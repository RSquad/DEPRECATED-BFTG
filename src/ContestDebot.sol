pragma ton-solidity >=0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "./interfaces/Debot.sol";
import "./interfaces/Terminal.sol";
import "./interfaces/Menu.sol";
import "./interfaces/Msg.sol";
import "./interfaces/NumberInput.sol";
import "./interfaces/AmountInput.sol";
import "./interfaces/AddressInput.sol";
import "./interfaces/ConfirmInput.sol";
import "./interfaces/Sdk.sol";
import "./interfaces/Upgradable.sol";
import "DemiurgeStore.sol";
//import "Base.sol";
import "IBaseData.sol";
import "IDemiurge.sol";
import "JurorContract.sol";
import "Contest.sol";


contract ContestDebot is Debot, IBaseData, IContestData, Upgradable {
    struct ContestData {
        ContestSetup setup;
        ContestInfo info;
        ContestTimeline timeline;
        Stage stage;
    }

    struct ContestStats {
        ContenderInfo[] info;
        address[] juryAddresses;
        Stats[] allStats;
        mapping (uint16 => Mark) marks;
        mapping (uint16 => Comment) comments;
        mapping (uint16 => HiddenEvaluation) hiddens;
    }

    // 0 - demi, 1 - store, 2 - current contest
    mapping(uint8 => address) _addrs;

    struct Images {
        TvmCell jurorSI;
        TvmCell contestSI;
    }

    Images public _images;

    uint256 _jurorKey;
    address _jurorAddr;
    uint32 _retryId;

    Evaluation _eval;
    ContenderInfo _newContender;


    int64 _id;
    mapping(address => ContestData) _contests;
    mapping(address => ContestStats) _contestStats;
    address[] _list;

    mapping (uint32 => ProposalData) _data;
    mapping (uint32 => ProposalInfo) _info;

    struct Keypair {
        uint256 pub;
        uint256 sec;
    }

    Keypair _testKeys;

    mapping (uint8 => HiddenEvaluation) _hideval;

    constructor(address store, address demiurge, TvmCell jurorWallet) public {
        tvm.accept();
        _addrs[0] = demiurge;
        _addrs[1] = store;
        _images.jurorSI = jurorWallet;
        _testKeys.pub = 0xa05cf32c3c67c9ce6b1c82442656bf0b410c6db59f4ca912ee07e93c927d0077;
        _testKeys.sec = 0x9fda0e81f70fde751e07391f99740969013d6abdab49779e3469bd2825177d6d;
        DemiurgeStore(store).queryImage{value: 0.2 ton, bounce: true}(ContractType.Contest);
    }

    function updateImage(ContractType kind, TvmCell image) external {
        require(msg.sender == _addrs[1]);
        if (kind == ContractType.Contest) {
            _images.contestSI = image;
        }
    }

    function start() public override {
        printMainInfo();
    }

    /// @notice Returns Metadata about DeBot.
    function getDebotInfo() public functionID(0xDEB) override view returns(
        string name, string version, string publisher, string key, string author,
        address support, string hello, string language, string dabi, bytes icon
    ) {
        name = "Contest Debot";
        version = "0.2.0";
        publisher = "RSquad";
        key = "Create contest submissions and vote for them";
        author = "RSquad";
        support = address.makeAddrStd(0, 0x0);
        hello = "Hello, i am Contest Debot.";
        language = "en";
        dabi = m_debotAbi.get();
        icon = "";
    }

    function getRequiredInterfaces() public view override returns (uint256[] interfaces) {
        return [ Terminal.ID, Menu.ID, AddressInput.ID, ConfirmInput.ID ];
    }

    function printMainInfo() public {
        _getProposals();
        MenuItem[] items;
        items.push(MenuItem("View contests", "", tvm.functionId(viewContests)));
        items.push(MenuItem("Deploy juror wallet", "", tvm.functionId(deployJurorWallet)));
        Menu.select("What do you want to do?", "", items);
    }

    function deployJurorWallet(uint32 index) public {
        index = index;
        Terminal.input(tvm.functionId(setJurorKey), "Enter juror public key:", false);
    }

    function setJurorKey(string value) public {
        (_jurorKey, _jurorAddr) = _calcJurorAddr(value);
        ConfirmInput.get(
            tvm.functionId(deploy1),
            format("Send some tons to address {} and then continue. Ready to continue?", _jurorAddr)
        );
    }

    function _calcJurorAddr(string value) private view returns (uint256, address) {
        string number = format("0x{}", value);
        (uint256 pubkey, ) = stoi(number);
        TvmCell walletState = tvm.insertPubkey(_images.jurorSI, pubkey);
        address addr = address.makeAddrStd(0, tvm.hash(walletState));
        return (pubkey, addr);
    }

    function deploy1(bool value) public {
        if (!value) return;
        TvmCell walletState = tvm.insertPubkey(_images.jurorSI, _jurorKey);
        address addr = address.makeAddrStd(0, tvm.hash(walletState));
        _retryId = tvm.functionId(deploy1);

        TvmCell message = tvm.buildExtMsg({
            abiVer: 2,
            dest: addr,
            sign: true,
            callbackId: tvm.functionId(onDeploy),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            stateInit: walletState,
            call: {JurorContract}
        });

        tvm.sendrawmsg(message, 0);
    }

    function onDeploy() public {
        Terminal.print(tvm.functionId(Debot.start), "Wallet deployed");
    }

    function onError(uint32 sdkError, uint32 exitCode) public {
        ConfirmInput.get(_retryId, format("Transaction failed. sdk={}, code={}. Want to retry?", sdkError, exitCode));
    }

    function _getProposals() private view {
        IDemiurge(_addrs[0]).getProposalData{
            abiVer: 2,
            extMsg: true,
            sign: false,
            callbackId: tvm.functionId(setProposalData),
            onErrorId: 0,
            time: uint32(now)
        }();
        IDemiurge(_addrs[0]).getProposalInfo{
            abiVer: 2,
            extMsg: true,
            sign: false,
            callbackId: tvm.functionId(setProposalInfo),
            onErrorId: 0,
            time: uint32(now)
        }();
    }

    function setProposalData(mapping(uint32 => ProposalData) proposals) public {
        _data = proposals;
    }

    function setProposalInfo(mapping(uint32 => ProposalInfo) proposals) public {
        _info = proposals;
    }


    function viewContests(uint32 index) public {
        index = index;
        _id = -1;
        getContest();
    }

    function getContest() public {
        optional(uint32, ProposalData) opt = _data.next(_id);
        if (opt.hasValue()) {
            (uint32 id, ProposalData data) = opt.get();
            if (data.state == ProposalState.Passed) {
                TvmCell code = _images.contestSI.toSlice().loadRef();
                TvmCell state = tvm.buildStateInit({
                    contr: Contest,
                    varInit: {_deployer: _addrs[0]},
                    pubkey: uint256(id),
                    code: code
                });
                _id = id;
                _addrs[2] = address.makeAddrStd(0, tvm.hash(state));

                optional(uint256) testKey = _testKeys.pub;
                TvmCell message = tvm.buildExtMsg({
                    abiVer: 2,
                    dest: _addrs[2],
                    sign: true,
                    callbackId: tvm.functionId(stub),
                    onErrorId: 0,
                    time: 0,
                    expire: 0,
                    pubkey: testKey,
                    call: {IContest.next}
                });
                Msg.sendWithKeypair(tvm.functionId(stub), message, _testKeys.pub, _testKeys.sec);

                optional(uint256) pubkey;
                IContest(_addrs[2]).getContest{
                    abiVer: 2,
                    extMsg: true,
                    sign: false,
                    callbackId: tvm.functionId(setContest),
                    onErrorId: 0,
                    time: uint32(now),
                    expire: 0,
                    pubkey: pubkey
                }();
                IContest(_addrs[2]).getCurrentData{
                    abiVer: 2,
                    extMsg: true,
                    sign: false,
                    callbackId: tvm.functionId(setContestData),
                    onErrorId: 0,
                    time: uint32(now),
                    expire: 0,
                    pubkey: pubkey
                }();
            }
        } else {
            printContests();
        }
    }

    function stub() public {}

    function setContest(
        ContestInfo contestInfo,
        ContestTimeline timeline,
        ContestSetup setup,
        Stage stage
    ) public {
        _contests[_addrs[2]] = ContestData(setup, contestInfo, timeline, stage);
    }

    function setContestData(
        ContenderInfo[] info,
        address[] juryAddresses,
        Stats[] allStats,
        mapping (uint16 => Mark) marks,
        mapping (uint16 => Comment) comments,
        mapping (uint16 => HiddenEvaluation) hiddens
    ) public {
        ContestStats stats = ContestStats(info, juryAddresses, allStats);
        stats.marks = marks;
        stats.comments = comments;
        stats.hiddens = hiddens;
        _contestStats[_addrs[2]] = stats;
        this.getContest();
    }

    function printContests() public {
        delete _list;
        MenuItem[] items;
        for((address addr, ContestData data) : _contests) {
            items.push(MenuItem(data.info.title, "", tvm.functionId(printContest)));
            _list.push(addr);
        }
        items.push(MenuItem("To main", "", tvm.functionId(toMain)));
        Menu.select("List of contests:", "", items);

    }

    function toMain(uint32 index) public {
        index = index;
        Terminal.print(tvm.functionId(Debot.start), "Back to start");
    }

    function printContest(uint32 index) public {
        MenuItem[] items;
        address addr = _list[index];
        _addrs[2] = addr;
        ContestData data = _contests[addr];
        ContestStats stats = _contestStats[addr];
        string tags;
        for (uint i = 0; i < data.setup.tags.length; i++) {
            tags.append(format("#{} ", data.setup.tags[i]));
        }

        Terminal.print(0, format(
            "ID{} \"{}\"\nStatus: {}\nAddress: {}\nCreated at: {}, ends at: {}\nPrize pool: {}\nTags: {}",
            data.setup.id, data.info.title, _decodeStage(data.stage), addr, data.timeline.contestStarts, data.timeline.contestEnds,
            formatTokens(data.setup.budget), tags
        ));

        Terminal.print(0, "\nSubmissions:\n");
        for (uint i = 0; i < stats.info.length; i++) {
            ContenderInfo inf = stats.info[i];
            Terminal.print(0,
            format("ID{}\nWallet address: {}\nForum link: {}\nFile link: {}\nApplied at: {}\n",
            i, inf.addr, inf.forumLink, inf.fileLink, inf.appliedAt));
        }

        Terminal.print(0, "\nJury:\n");
        for (uint i = 0; i < stats.juryAddresses.length; i++) {
            address j = stats.juryAddresses[i];
            Terminal.print(0, format("ID{} Address: {}", i, j));
        }

        if (data.stage == Stage.Contend) {
            items.push(MenuItem("Add submission", "", tvm.functionId(createSubmission)));
        }
        if (data.stage == Stage.Vote) {
            items.push(MenuItem("Vote for submission", "", tvm.functionId(vote)));
        }
        if (data.stage == Stage.Reveal) {
            items.push(MenuItem("Reveal vote for submission", "", tvm.functionId(reveal)));
        }
        if (stats.info.length > 0) {
            items.push(MenuItem("View submission marks", "", tvm.functionId(viewMarks)));
        }
        items.push(MenuItem("Return to contest list", "", tvm.functionId(toContests)));
        Menu.select("Options:", "", items);
    }

    function _decodeStage(Stage stage) private pure returns (string) {
        if (stage < Stage.Contend) {
            return "Setup";
        }
        if (stage == Stage.Contend) {
            return "Accepting submissions";
        }
        if (stage == Stage.Vote) {
            return "Jury voting";
        }
        if (stage == Stage.Reveal) {
            return "Revealing votes";
        }
        if (stage > Stage.Reveal) {
            return "Finalizing";
        }
        return "unknown";
    }

    function viewMarks(uint32 index) public {
        index = index;
        address addr = _addrs[2];
        ContestStats stats = _contestStats[addr];
        NumberInput.get(tvm.functionId(submissionMarks), "enter submission id:", 0, int256(stats.info.length));
    }

    function submissionMarks(int256 value) public {
        ContestStats stats = _contestStats[_addrs[2]];
        uint16 entryId = uint16(value);
        uint8 jid = 0;

        Terminal.print(0, "Revealed Marks:");
        optional(uint16, Mark) next = stats.marks.min();
        while (next.hasValue()) {
            (uint16 id, Mark m) = next.get();
            if (((id & 0x00FF) == entryId) && (uint8(id >> 8) >= jid)) {
                jid = uint8(id >> 8);
                Comment c = stats.comments[id];
                Terminal.print(0, format("Juror {}: {}\nComment: {}", jid, m.score, c.comment));
            }
            next = stats.marks.next(id);
        }

        Terminal.print(tvm.functionId(printContests), "Back to contests");
    }

    function toContests(uint32 index) public {
        index = index;
        printContests();
    }

    function createSubmission(uint32 index) public {
        index = index;
        AddressInput.get(tvm.functionId(setParticipantAddress), "Enter your Free TON wallet address:");
        Terminal.input(tvm.functionId(setForumLink), "Enter link to submission pdf:", false);
        Terminal.input(tvm.functionId(setFileLink), "Enter forum link for discussion:", false);
        ConfirmInput.get(tvm.functionId(submit1), "Sign and submit?");
    }

    function submit1(bool value) public {
        if (!value) return;
        _retryId = tvm.functionId(submit1);
        optional(uint256) pubkey = 0;
        IContest(_addrs[2]).submit{
            abiVer: 2,
            extMsg: true,
            sign: true,
            callbackId: tvm.functionId(onSubmit),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            pubkey: pubkey
        }(_newContender.addr, _newContender.forumLink, _newContender.fileLink, _newContender.hashCode, _newContender.contact);
    }

    function onSubmit() public {
        Terminal.print(tvm.functionId(printMainInfo), "Submission added.");
    }

    function setParticipantAddress(address value) public {
        _newContender.addr = value;
        _newContender.contact = address(0);
    }

    function setForumLink(string value) public {
        _newContender.forumLink = value;
    }

    function setFileLink(string value) public {
        _newContender.fileLink = value;
        _newContender.hashCode = 0;
    }

    function vote(uint32 index) public {
        index = index;
        ContestStats stats = _contestStats[_addrs[2]];
        int256 max = stats.info.length == 0 ? 0 : int256(stats.info.length) - 1;
        Terminal.input(tvm.functionId(calcJurorAddress), "Enter juror pubkey:", false);
        NumberInput.get(tvm.functionId(setEntryId), "Enter submission id:", 0, max);
        NumberInput.get(tvm.functionId(setMark), "Enter score:", 0, 10);
        Terminal.input(tvm.functionId(setComment), "Enter comment:", true);
        Terminal.input(tvm.functionId(setPwd), "Enter encryption key:", false);
    }

    function setEntryId(int256 value) public {
        _eval.entryId = uint8(value);
    }

    function setMark(int256 value) public {
        _eval.score = uint8(value);
        if (_eval.score == 0) {
            _eval.voteType = VoteType.Abstain;
        } else {
            _eval.voteType = VoteType.For;
        }
    }

    function setComment(string value) public {
        _eval.comment = value;
    }

    uint256 _encryptKey;
    function setPwd(string value) public {
        string number = format("0x{}", value);
        (_encryptKey, ) = stoi(number);
        bytes nonce = "JurorEncrypt";
        Sdk.chacha20(tvm.functionId(setEncodedComment), _eval.comment, nonce, _encryptKey);
        Sdk.chacha20(tvm.functionId(setEncodedScore), format("{}", _eval.score), nonce, _encryptKey);
        Sdk.chacha20(tvm.functionId(setEncodedVoteType), format("{}", uint8(_eval.voteType)), nonce, _encryptKey);

        _hideval[0].entryId = _eval.entryId;
        _hideval[0].hash = hashEvaluation(_eval);
    }

    function setEncodedComment(bytes output) public {
        _hideval[0].comment = output;
    }
    function setEncodedScore(bytes output) public {
        _hideval[0].score = output;
    }
    function setEncodedVoteType(bytes output) public {
        _hideval[0].voteType = output;
        ConfirmInput.get(tvm.functionId(record1), "Sign and record vote?");
    }

    function reveal2(uint8 jurorId) public {
        ContestStats stats = _contestStats[_addrs[2]];
        uint16 entryId = uint16(_eval.entryId);

        optional(HiddenEvaluation) eval = stats.hiddens.fetch((uint16(jurorId) << 8) | entryId);
        if (eval.hasValue()) {
            _hideval[0] = eval.get();

            bytes nonce = "JurorEncrypt";
            Sdk.chacha20(tvm.functionId(setDecComment), _hideval[0].comment, nonce, _encryptKey);
            Sdk.chacha20(tvm.functionId(setDecScore), _hideval[0].score, nonce, _encryptKey);
            Sdk.chacha20(tvm.functionId(setDecVoteType), _hideval[0].voteType, nonce, _encryptKey);
        }
    }

    function setDecComment(bytes output) public {
        _eval.comment = string(output);
    }
    function setDecScore(bytes output) public {
        (uint256 num,) = stoi(string(output));
        _eval.score = uint8(num);
    }
    function setDecVoteType(bytes output) public {
        (uint256 num,) = stoi(string(output));
        _eval.voteType = VoteType(uint8(num));

        Terminal.print(tvm.functionId(reveal3), format("Decrypted:\ncomment: {}\nscore: {}\nvote: {}", _eval.comment, _eval.score, uint8(_eval.voteType)));
    }

    function record1(bool value) public view {
        if (!value) return;

        JurorContract(_jurorAddr).recordVote{
            abiVer: 2,
            extMsg: true,
            sign: true,
            callbackId: tvm.functionId(onRecord),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0
        }(_addrs[2], _hideval[0]);
    }

    function onRecord() public {
        Terminal.print(tvm.functionId(Debot.start), "Vote recorded");
    }

    function hashEvaluation(Evaluation evaluation) private pure returns (uint hash) {
        TvmBuilder builder;
        builder.store(evaluation.entryId, uint8(evaluation.voteType), evaluation.score, evaluation.comment);
        TvmCell cell = builder.toCell();
        hash = tvm.hash(cell);
    }

    function calcJurorAddress(string value) public {
        (_jurorKey, _jurorAddr) = _calcJurorAddr(value);
        Terminal.print(0, format("Juror wallet address: {}", _jurorAddr));
    }

    function reveal(uint32 index) public {
        index = index;
        ContestStats stats = _contestStats[_addrs[2]];
        int256 max = stats.info.length == 0 ? 0 : int256(stats.info.length) - 1;
        Terminal.input(tvm.functionId(calcJurorAddress), "Enter juror pubkey:", false);
        NumberInput.get(tvm.functionId(setEntryId), "Enter submission id:", 0, max);
        Terminal.input(tvm.functionId(revealPwd), "Enter encryption key:", false);
    }

    function revealPwd(string value) public {
        string number = format("0x{}", value);
        (_encryptKey, ) = stoi(number);
        optional(uint256) pubkey;
        IContest(_addrs[2]).getJurorId{
            abiVer: 2,
            extMsg: true,
            sign: false,
            callbackId: tvm.functionId(reveal2),
            onErrorId: 0,
            time: uint32(now),
            expire: 0,
            pubkey: pubkey
        }(_addrs[2]);
    }

    function reveal3() public view {
        JurorContract(_jurorAddr).revealVote{
            abiVer: 2,
            extMsg: true,
            sign: true,
            callbackId: 0,
            onErrorId: 0,
            time: uint32(now),
            expire: 0
        }(_addrs[2], _eval);
    }

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

    function onCodeUpgrade() internal override {
        tvm.resetStorage();
    }
}