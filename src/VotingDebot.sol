pragma ton-solidity >=0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "./interfaces/Debot.sol";
import "./interfaces/Terminal.sol";
import "./interfaces/Menu.sol";
import "./interfaces/NumberInput.sol";
import "./interfaces/AmountInput.sol";
import "./interfaces/ConfirmInput.sol";
import "./interfaces/Sdk.sol";
import "./interfaces/Upgradable.sol";
import "./interfaces/Destructable.sol";
import "DemiurgeStore.sol";
import "Base.sol";
import "IBaseData.sol";
import "IDemiurge.sol";
import "IPadawan.sol";
import "IProposal.sol";
import "Contest.sol";

abstract contract DemiurgeClient is Base {

    address _demiurge;

    function requestPadawan(uint userKey) external view signed {
        IDemiurge(_demiurge).deployPadawan{value: DEPLOY_FEE, flag: 1}(userKey);
    }

    function requestProposal(
        uint32 totalVotes,
        uint32 start,
        uint32 end,
        string description,
        string text,
        VoteCountModel model
    ) external view signed {
        IDemiurge(_demiurge).deployProposal{value: DEPLOY_PROPOSAL_PAY, flag: 1}
            (totalVotes, start, end, description, text, model);
    }

    function requestProposalForContest(
        uint32 totalVotes,
        uint32 start,
        uint32 end,
        string description,
        string title,
        VoteCountModel model,
        uint32 duration, // period of accepting submissions
        uint128 prizePool,
        string[] tags
    ) external view signed {
        IDemiurge(_demiurge).deployProposalForContest{value: DEPLOY_PROPOSAL_PAY, flag: 1}
            (totalVotes, start, end, description, title, model, duration, prizePool, tags);
    }
}

abstract contract PadawanClient is Base {

    address _padawan;

    function updatePadawan(address addr) public virtual;

    function depositTons(uint32 tons) external view signed {
        IPadawan(_padawan).depositTons{value: uint64(tons) * 1 ton + 1 ton, bounce: true, flag: 1}(tons);
    }

    function depositTokens(address returnTo, uint256 tokenId, uint64 tokens) public view signed {
        IPadawan(_padawan).depositTokens{value: 1.5 ton, bounce: true, flag: 1}
            (returnTo, tokenId, tokens);
    }

    function reclaimDeposit(uint32 votes) public view signed {
        IPadawan(_padawan).reclaimDeposit{value: 1 ton, bounce: true, flag: 1}
            (votes);
    }

    function voteFor(address proposal, bool choice, uint32 votes) public view signed {
        IPadawan(_padawan).voteFor{value: 1 ton, bounce: true, flag: 1}
            (proposal, choice, votes);
        IProposal(proposal).wrapUp{value: 0.1 ton, flag: 1}();
    }

    function createTokenAccount(address root) public view signed {
        IPadawan(_padawan).createTokenAccount{value: 2 ton + /*just for tests*/ 2 ton, bounce: true, flag: 1}
            (root);
    }
}

contract VotingDebot is Debot, PadawanClient, DemiurgeClient, IBaseData, Upgradable, Destructable {

    struct TipAccount {
        address addr;
        uint256 walletKey;
        uint32 createdAt;
        uint128 balance;
    }

    struct CurrentToken {
        TipAccount info;
        uint256 id;
        address returnTo;
        address root;
    }

    struct VoteInfo {
        // Number of votes requested to reclaim
        uint32 reqVotes;
        // Total number of votes available to user.
        uint32 totalVotes;
        // Number of votes that cannot be reclaimed until finish of one of active proposals.
        uint32 lockedVotes;
    }

    uint8 constant ABI_PROPOSAL = 1;
    uint8 constant ABI_DEMIURGE = 2;
    uint8 constant ABI_PADAWAN = 3;
    mapping(uint8 => string) _abis;

    //
    //  Storage
    //

    struct NewProposal {
        uint32 id;
        uint32 start;
        uint32 end;
        uint16 options;
        uint32 totalVotes;
        string description;
        string title;
        uint32 duration;
        uint128 prizePool;
        string[] tags;
    }

    uint128 _myBalance;
    uint128 _padawanBalance;
    address _demiDebot;
    uint256 _ballotId;

    VoteInfo _padawanInfo;
    uint32 _proposalId;
    bool _yesNo;
    uint32 _retryId;
    NewProposal _newprop;

    uint32 _tons;
    uint64 _tokens;
    uint32 _votes;

    uint32 _proposalCount;
    mapping(address => uint32) _activeProposals;
    mapping (uint32 => ProposalData) _data;
    mapping (uint32 => ProposalInfo) _info;

    mapping (address => TipAccount) _tokenAccounts;
    CurrentToken _currToken;

    modifier contractOnly() {
        require(msg.sender != address(0), 100);
        _;
    }

    function getData() public view returns (address padawan) {
        padawan = _padawan;
    }

    function updatePadawan(address addr) public override {
        tvm.accept();
        _padawan = addr;
    }

    //
    //   Init functions
    //

    constructor(address demiDebot, address demiurge) public {
        require(msg.sender != address(0), 101);
        _demiurge = demiurge;
        _demiDebot = demiDebot;
        _init();
    }

    function _init() private view {
        DemiurgeStore(_demiDebot).queryABI{value: 0.2 ton, bounce: true}(ContractType.VotingDebot);
    }

    function updateABI(ContractType kind, string sabi) external {
        require(msg.sender == _demiDebot);
        if (kind == ContractType.Demiurge) {
            _abis[ABI_DEMIURGE] = sabi;
        } else if (kind == ContractType.Proposal) {
            _abis[ABI_PROPOSAL] = sabi;
        } else if (kind == ContractType.Padawan) {
            _abis[ABI_PADAWAN] = sabi;
        } else if (kind == ContractType.VotingDebot) {
            m_debotAbi = sabi;
            m_options |= DEBOT_ABI;
        }
    }

    //
    // DeBot functions
    //

    function start() public override {
        optional(uint256) none;
        this.getData{
            abiVer: 2,
            extMsg: true,
            sign: false,
            callbackId: tvm.functionId(updateData),
            onErrorId: 0,
            time: uint32(now),
            expire: 0,
            pubkey: none
        }();

        Terminal.print(0, "Hello, i'm your personal Voting Debot!");
        Sdk.getBalance(tvm.functionId(setMyBalance), address(this));
    }

    function updateData(address padawan) public {
        _padawan = padawan;
        if (_padawan == address(0)) {
            ConfirmInput.get(tvm.functionId(deploy), "You don't have a padawan contract yet.\nReady to deploy?");
        } else {
            Sdk.getBalance(tvm.functionId(setPadawanBalance), _padawan);
            _getProposals();
            _getPadawanInfo();
            this.printMainInfo();
        }
    }

    function setMyBalance(uint128 nanotokens) public {
        _myBalance = nanotokens;
        Terminal.print(0, format("My balance: {} tons", formatTokens(nanotokens)));
    }

    function setPadawanBalance(uint128 nanotokens) public {
        _padawanBalance = nanotokens;
    }

    function deploy(bool value) public {
        if (!value) {
            return;
        }
        Sdk.genRandom(tvm.functionId(setRandom), 32);
    }

    function setRandom(bytes buffer) public accept {
        _ballotId = buffer.toSlice().decode(uint256);
        (uint64 decimal, uint64 float) = tokens(DEPLOY_FEE);
        Terminal.print(tvm.functionId(deploy2), format("Deploy fee is {}.{} tons", decimal, float));
    }

    function retryDeploy(bool value) public {
        if (!value) {
            return;
        }
        deploy2();
    }

    function deploy2() public {
        optional(uint256) pubkey = tvm.pubkey();
        _retryId = tvm.functionId(retryDeploy);
        this.requestPadawan{
            abiVer: 2,
            extMsg: true,
            sign: true,
            callbackId: tvm.functionId(onDeploySuccess),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            pubkey: pubkey
        }(_ballotId);
    }

    function onDeploySuccess() public {
        Terminal.print(0, "Transaction succeeded. Please, wait for a few seconds and restart debot.");
    }

    function _getProposals() private view {
        IDemiurge(_demiurge).getProposalData{
            abiVer: 2,
            extMsg: true,
            sign: false,
            callbackId: tvm.functionId(setProposalData),
            onErrorId: 0,
            time: uint32(now)
        }();
        IDemiurge(_demiurge).getProposalInfo{
            abiVer: 2,
            extMsg: true,
            sign: false,
            callbackId: tvm.functionId(setProposalInfo),
            onErrorId: 0,
            time: uint32(now)
        }();
    }

    function _getPadawanInfo() private view {
        IPadawan(_padawan).getVoteInfo{
            abiVer: 2,
            extMsg: true,
            sign: false,
            callbackId: tvm.functionId(setVoteInfo),
            onErrorId: 0,
            time: uint32(now)
        }();
        IPadawan(_padawan).getActiveProposals{
            abiVer: 2,
            extMsg: true,
            sign: false,
            callbackId: tvm.functionId(setActiveProps),
            onErrorId: 0,
            time: uint32(now)
        }();
    }

    function printMainInfo() public {
        string printStr = format(
            "You voted for {} proposals.\nYour total votes: {}\nLocked votes: {}\nUnused votes: {}\nPadawan address: {}",
            _proposalCount, _padawanInfo.totalVotes, _padawanInfo.lockedVotes,
            _padawanInfo.totalVotes - _padawanInfo.lockedVotes, _padawan
        );
        Terminal.print(0, printStr);
        _printMainMenu();
    }

    function _printMainMenu() private {
        MenuItem[] items;
        items.push(MenuItem("Acquire votes", "", tvm.functionId(acquireVotes)));
        if (_padawanInfo.totalVotes != 0) {
            items.push(MenuItem("Reclaim votes", "", tvm.functionId(reclaimVotes)));
        }
        items.push(MenuItem("Create new contest proposal", "", tvm.functionId(createProposal)));
        items.push(MenuItem("View all proposals", "", tvm.functionId(viewAllproposals)));
        items.push(MenuItem("Vote for proposal", "", tvm.functionId(voteForProposal)));
        if (!_activeProposals.empty()) {
            items.push(MenuItem("View proposals you voted", "", tvm.functionId(viewMyVotingProposals)));
        }
        items.push(MenuItem("View contests", "", tvm.functionId(viewContests)));
        items.push(MenuItem("Update info", "", tvm.functionId(gotoStart)));
        Menu.select("What do you want to do?", "", items);
    }

    function viewContests(uint32 index) public {
        index = index;
        Terminal.print(0, "Run Contest Debot to view all running contests.");
    }

    function gotoStart(uint32 index) public {
        index = index;
        Terminal.print(tvm.functionId(Debot.start), "Updating...");
    }

    function acquireVotes(uint32 index) public {
        index = index;
        Menu.select("How do you want to get votes?", "", [
            MenuItem("Deposit tons", "", tvm.functionId(deposit1))
        ]);
    }

    function reclaimVotes(uint32 index) public {
        index = index;
        NumberInput.get(tvm.functionId(enterVotes), "Enter number of votes:", 1, _padawanInfo.totalVotes);
        ConfirmInput.get(tvm.functionId(reclaim) , "Sign and reclaim?");
    }

    function createProposal(uint32 index) public {
        index = index;
        delete _newprop.tags;
        NumberInput.get(tvm.functionId(enterMaxVotes), "Enter total votes:", 3, 1000000);
        NumberInput.get(tvm.functionId(enterStart), "Enter unixtime when voting for proposal should start:", uint32(now), 0xFFFFFFFF);
        NumberInput.get(tvm.functionId(enterEnd), "Enter duration of voting period for contest proposal (in seconds):", 1, 31536000);
        Terminal.input(tvm.functionId(enterProposalTitle), "Enter title:", false);
        Terminal.input(tvm.functionId(enterDesc), "Enter description:", true);
        Menu.select("Choose voting model:", "", [
            MenuItem("Super majority", "", tvm.functionId(setModel)),
            MenuItem("Soft majority", "", tvm.functionId(setModel))
        ]);
        AmountInput.get(tvm.functionId(enterPrize), "Enter contest prize pool (in tons):", 9, 1e9, 1000000e9);
        NumberInput.get(tvm.functionId(enterDuration), "Enter contest duration (in seconds):", 1, 31536000);

        enterTag(true);
    }

    function enterPrize(uint128 value) public {
        _newprop.prizePool = value;
    }

    function enterDuration(int256 value) public {
        _newprop.duration = uint32(value);
    }

    function enterTag(bool value) public {
        if (!value) {
            ConfirmInput.get(
                tvm.functionId(sendRequestProposal),
                format("Creation fee: {} tons.\nSign and create proposal?", formatTokens(DEPLOY_FEE))
            );
        } else {
            Terminal.input(tvm.functionId(pushTag), "Enter contest tag:", false);
        }

    }

    function pushTag(string value) public {
        _newprop.tags.push(value);
        ConfirmInput.get(tvm.functionId(enterTag), "Add one more tag?");
    }

    function setModel(uint32 index) public {
        if (index == 0) {
            _newprop.options |= PROPOSAL_VOTE_SUPER_MAJORITY;
        } else {
            _newprop.options |= PROPOSAL_VOTE_SOFT_MAJORITY;
        }
    }

    function sendRequestProposal(bool value) public {
        if (!value) {
            return;
        }
        NewProposal prop = _newprop;
        VoteCountModel model;
        if (prop.options & PROPOSAL_VOTE_SOFT_MAJORITY != 0) {
            model = VoteCountModel.SoftMajority;
        } else {
            model = VoteCountModel.SuperMajority;
        }

         optional(uint256) pubkey = tvm.pubkey();
        _retryId = tvm.functionId(sendRequestProposal);
        this.requestProposalForContest{
            abiVer: 2,
            extMsg: true,
            sign: true,
            callbackId: tvm.functionId(onSuccess),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            pubkey: pubkey
        }(prop.totalVotes,
            prop.start,
            prop.end,
            prop.description,
            prop.title,
            model,
            prop.duration,
            prop.prizePool,
            prop.tags);

    }

    function viewAllproposals(uint32 index) public {
        index = index;
        Terminal.print(0, "List of proposals:");
        _printProposals();
        Terminal.print(tvm.functionId(Debot.start), "Back to start");
    }

    function viewMyVotingProposals(uint32 index) public {
        index = index;
        Terminal.print(0, "List of voted proposals:");
        _printActiveProposals();
        Terminal.print(tvm.functionId(Debot.start), "Back to start");
    }

    function voteForProposal(uint32 index) public {
        index = index;
        NumberInput.get(tvm.functionId(enterProposalId), "Enter proposal id:", 0, 0xFFFFFFFF);
        NumberInput.get(tvm.functionId(enterVotes), "Enter votes count:", 0, _padawanInfo.totalVotes);
        Menu.select("How to vote?", "", [
            MenuItem("Vote \"Yes\"", "", tvm.functionId(sendVoteFor)),
            MenuItem("Vote \"No\"", "", tvm.functionId(sendVoteFor))
        ]);
    }

    function reclaim(bool value) public {
        if (!value) {
            return;
        }
        _retryId = tvm.functionId(reclaim);
        optional(uint256) pubkey = tvm.pubkey();
        PadawanClient(address(this)).reclaimDeposit{
            abiVer: 2,
            extMsg: true,
            sign: true,
            callbackId: tvm.functionId(onSuccess),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            pubkey: pubkey
        }(_votes);
    }

    function onSuccess() public {
        Terminal.print(tvm.functionId(Debot.start), "Transaction succeeded.");
    }

    function onError(uint32 sdkError, uint32 exitCode) public {
        ConfirmInput.get(_retryId, format("Transaction failed. sdk={}, code={}.Want to retry?", sdkError, exitCode));
    }

    function deposit1(uint32 index) public {
        index = index;
        NumberInput.get(tvm.functionId(deposit2), "Enter a number of tons:", 1, _myBalance / 1 ton);
    }

    function deposit2(uint128 value) public {
        _tons = uint32(value);
        ConfirmInput.get(tvm.functionId(retryDeposit), "Sign and deposit?");
    }

    function retryDeposit(bool value) public {
        if (!value) {
            return;
        }
        _retryId = tvm.functionId(retryDeposit);
        optional(uint256) pubkey = tvm.pubkey();
        this.depositTons{
            abiVer: 2,
            extMsg: true,
            sign: true,
            callbackId: tvm.functionId(onSuccess),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 1,
            pubkey: pubkey
        }(_tons);
    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "Personal Voting DeBot";
        semver = (1 << 16) |(2 << 8) | 0;
    }

    /*
     *  Helpers
     */


    function tokens(uint128 nanotokens) private pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    }

    function formatTokens(uint128 amount) private pure returns (string) {
        (uint64 dec, uint64 float) = tokens(amount);
        string floatStr = format("{}", float);
        while (floatStr.byteLength() < 9) {
            floatStr = "0" + floatStr;
        }
        return format("{}.{}", dec, floatStr);
    }

    function setVoteInfo(uint32 reqVotes, uint32 totalVotes, uint32 lockedVotes) public accept {
        _padawanInfo.reqVotes = reqVotes;
        _padawanInfo.totalVotes = totalVotes;
        _padawanInfo.lockedVotes = lockedVotes;
    }

    function setActiveProps(mapping(address => uint32) activeProposals) public accept {
        _activeProposals = activeProposals;
        optional(address, uint32) prop = _activeProposals.min();
        uint32 count = 0;
        while (prop.hasValue()) {
            (address addr, ) = prop.get();
            count += 1;
            prop = _activeProposals.next(addr);
        }
        _proposalCount = count;
    }

    function setProposalData(mapping(uint32 => ProposalData) proposals) public {
        _data = proposals;
    }

    function setProposalInfo(mapping(uint32 => ProposalInfo) proposals) public {
        _info = proposals;
    }

    function _printProposals() private inline {
        for((uint32 id, ) : _data) {
            _printProp(id);
        }
    }

    function _printProp(uint32 id) private inline {
        ProposalInfo info = _info[id];
        ProposalData data = _data[id];
        uint16 options = info.options;
        string opt = "";
        if (options & PROPOSAL_VOTE_SOFT_MAJORITY != 0) {
            opt = opt + "\"soft majority\"";
        } else if (options & PROPOSAL_VOTE_SUPER_MAJORITY != 0) {
            opt = opt + "\"super majority\"";
        }

        string fmt = format(
            "\nID {}. \"{}\"\nStatus: {}\nStart: {}, End: {}\nTotal votes: {}, options: {}\nAddress: {}\ncreator: {}\n",
            id, info.description, _stateToString(data.state), info.start, info.end, info.totalVotes,
            opt, data.addr, data.userWalletAddress
        );
        Terminal.print(0, fmt);
    }

    function _stateToString(ProposalState state) inline private pure returns (string) {
        if (state <= ProposalState.New) {
            return "New";
        }
        if (state == ProposalState.OnVoting) {
            return "Voting";
        }
        if (state == ProposalState.Ended) {
            return "Ended";
        }
        if (state == ProposalState.Passed) {
            return "Passed";
        }
        if (state == ProposalState.Failed) {
            return "Failed";
        }
        if (state == ProposalState.Finalized) {
            return "Finalized";
        }
        if (state == ProposalState.Distributed) {
            return "Distributed";
        }
        return "unknown";
    }

    function _printActiveProposals() private {
        if (_activeProposals.empty()) {
            Terminal.print(0, "No active proposals");
            return;
        }
        for ((address addr, uint32 votes) : _activeProposals) {
            uint32 id = _findProposal(addr);
            _printProp(id);
            Terminal.print(0, format("You sent {} votes for it.", votes));
        }
    }

    function _findProposal(address findAddr) private view returns (uint32) {
        optional(uint32, ProposalData) prop = _data.min();
        while (prop.hasValue()) {
            (uint32 id, ProposalData pd) = prop.get();
            if (pd.addr == findAddr) {
                return id;
            }
            prop = _data.next(id);
        }
        return 0;
    }

    function enterProposalId(int256 value) public {
        _proposalId = uint32(value);
    }

    function enterVotes(int256 value) public {
        _votes = uint32(value);
    }

    function enterTons(uint32 tons) public {
        _tons = tons;
    }

    function enterTokens(uint64 value) public {
        _tokens = value;
    }

    function enterReturnTo(address returnTo) public {
        _currToken.returnTo = returnTo;
    }

    function enterRootAddress(address root) public {
        _currToken.root = root;
    }

    function enterMaxVotes(int256 value) public {
        _newprop.totalVotes = uint32(value);
    }

    function enterStart(int256 value) public {
        _newprop.start = uint32(value);
    }

    function enterEnd(int256 value) public {
        _newprop.end = uint32(int256(_newprop.start) + value);
    }

    function enterDesc(string value) public {
        _newprop.description = value;
    }

    function enterProposalTitle(string value) public {
        _newprop.title = value;
    }

    function sendVoteFor(uint32 index) public {
        _yesNo = index == 0;
        ConfirmInput.get(tvm.functionId(retryVoteFor), "Sign and send votes?");
    }

    function retryVoteFor(bool value) public {
        if (!value) {
            return;
        }
        _retryId = tvm.functionId(retryVoteFor);
        address propAddr = _data[_proposalId].addr;
        optional(uint256) pubkey = tvm.pubkey();
        this.voteFor{
            abiVer: 2,
            extMsg: true,
            sign: true,
            callbackId: tvm.functionId(onSuccess),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            pubkey: pubkey
        }(propAddr, _yesNo, _votes);
    }

    function onCodeUpgrade() internal override {
        tvm.resetStorage();
        //_demiurge = address.makeAddrStd(0, 0xd3b2385abb7a0a9cc3d8f89f4e0950e04b09d2c516dceb0084f14bb566451e13);
        //_demiDebot = address.makeAddrStd(0, 0x093810ee72d9550ee7a7ea245753803f4d4b0981f7143e1bcb1828b1e9b9cde6);
        _demiurge = address.makeAddrStd(0, 0x823a4d0ea109dabb0417bfead600b4460495cc355edb7fe8b623daf6009c9df7);
        _demiDebot = address.makeAddrStd(0, 0xd1eec5ed21a557484e19652de5c3273db3a708899352d69d10f20b75efa6a674);

        _init();
        updatePadawan(address.makeAddrStd(0, 0x1b66654e5beb5b91fcc0273fd8273b1d7e868caf880b87c890b6f46078ef2308));
    }

    function destruct() public override {
        tvm.accept();
        _destruct(_demiDebot);
    }
}