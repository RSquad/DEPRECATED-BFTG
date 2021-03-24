pragma ton-solidity >= 0.36.0;

import "Proposal.sol";
import "Contest.sol";
import "DemiurgeStore.sol";
import "IInterestGroup.sol";
import "IInterestGroupClient.sol";
import "./interfaces/Upgradable.sol";
import "./interfaces/Destructable.sol";
import "JurorContract.sol";

abstract contract IClient {
    function updatePadawan(address addr) external {}
    function onProposalDeployed(uint32 id, address addr) external {}
    function onProposalCompletion(uint32 id, bool result) external {}
}

interface IContestDetails {
    function decode(uint32 duration, uint128 prizePool, string[] tags) external;
}

 /*
    Exception codes:
    101 Not authorized to administer contest
    102 ID is already taken
*/
contract Demiurge is Base, IDemiurge, IDemiurgeStoreCallback, IInfoCenter, IJuryGroupCallback, Upgradable, Destructable, IInterestGroupClient {

    uint16 constant ERROR_NOT_AUTHORIZED_WALLET =       300; // Only UserWallet can request padawans
    uint16 constant ERROR_PADAWAN_ALREADY_DEPLOYED =    301; // padawan is already deployed
    uint16 constant ERROR_PROPOSAL_ALREADY_DEPLOYED =   302; // proposal is already deployed
    uint16 constant ERROR_NOT_ALL_CHECKS_PASSED =       303;
    uint16 constant ERROR_INIT_ALREADY_COMPLETED =      304;

    uint16 constant DEFAULT_OPTIONS = 0;

    uint8 constant CHECK_PROPOSAL = 1;
    uint8 constant CHECK_PADAWAN = 2;
    uint8 constant CHECK_DEPOOLS = 4;
    uint8 constant CHECK_PRICE_PROVIDER = 8;
    uint8 constant CHECK_CONTEST = 16;
    uint8 constant CHECK_JURY_GROUP = 32;

    TvmCell _padawanSI;
    TvmCell _proposalSI;
    TvmCell public _contestSI;
    TvmCell public _juryGroupSI;
    TvmCell _jurorSI;

    address  public _priceProvider;
    address  public _infoCenter;

    mapping (uint => PadawanData) _deployedPadawans;
    mapping (address => uint32) _deployedProposals;
    mapping (address => uint32) _deployedContests;
    mapping (address => uint32) _interestGroups;

    mapping (uint32 => ProposalInfo) _proposalInfo;
    mapping (uint32 => ProposalData) _proposalData;

    mapping (uint32 => Brief) _radar;

    mapping(address => uint32) public _tagsPendings;

    struct Req {
        uint32 id;
        uint32 groupId;
        ReqStatus status;
        uint32 eid;
    }
    mapping (uint32 => Req) public _reqs;
    uint32 public _reqCounter;

    struct Draft {
        DomainOrder[] order;
        uint32[] reqs;
        uint16 left;
        address[] jury;
        ReqStatus overallStatus;
    }
    mapping (uint32 => Draft) public _quorum;

    VotingResults[] _votingResults;

    struct DomainOrder {
        string tag;
        uint16 count;
//        uint32 level;
//        uint32 budget;
    }
    uint32 _deployedPadawansCounter;
    uint32 _deployedProposalsCounter;
    uint32 _contestsCounter;
    uint16 _version = 2;

    // Address of Demiurge Store - smc where all tvc and abi are stored.
    address demiStore;

    uint8 _checkList;

    mapping(address => bool) _depools;

    /*
    *  Inline work with checklist
    */

    function _createChecks() private inline {
        _checkList = CHECK_PADAWAN | CHECK_PROPOSAL | CHECK_PRICE_PROVIDER | CHECK_DEPOOLS | CHECK_CONTEST | CHECK_JURY_GROUP;
    }

    function _passCheck(uint8 check) private inline {
        _checkList &= ~check;
    }

    function _allCheckPassed() private view inline returns (bool) {
        return (_checkList == 0);
    }

    modifier checksEmpty() {
        require(_allCheckPassed(), ERROR_NOT_ALL_CHECKS_PASSED);
        tvm.accept();
        _;
    }

    modifier signedAndChecksNotPassed() {
        /*
        require(tvm.pubkey() == msg.pubkey(), 100);
        require(!_allCheckPassed(), ERROR_INIT_ALREADY_COMPLETED);
        */
        tvm.accept();
        _;
    }

    /*
    * Initialization functions
    */
    uint256[] _initJuryKeys;
    constructor(address store, uint256[] initJuryKeys) public {
        if (msg.sender == address(0)) {
            require(msg.pubkey() == tvm.pubkey(), 101);
        }
        tvm.accept();
        _initJuryKeys = initJuryKeys;

        if (store != address(0)) {
            demiStore = store;
            DemiurgeStore(demiStore).queryImage{value: 0.2 ton, bounce: true}(ContractType.Juror);
            DemiurgeStore(demiStore).queryImage{value: 0.2 ton, bounce: true}(ContractType.Proposal);
            DemiurgeStore(demiStore).queryImage{value: 0.2 ton, bounce: true}(ContractType.Padawan);
            DemiurgeStore(demiStore).queryImage{value: 0.2 ton, bounce: true}(ContractType.Contest);
            DemiurgeStore(demiStore).queryImage{value: 0.2 ton, bounce: true}(ContractType.JuryGroup);
            DemiurgeStore(demiStore).queryDepools{value: 0.2 ton, bounce: true}();
            DemiurgeStore(demiStore).queryAddress{value: 0.2 ton, bounce: true}(ContractType.PriceProvider);
        }
        _deployedPadawansCounter = 0;
        _deployedProposalsCounter = 0;
        _contestsCounter = 0;

        _createChecks();
    }

    function updateImage(ContractType kind, TvmCell image) external override {
        require(msg.sender == demiStore);
        tvm.accept();
        if (kind == ContractType.Proposal) {
            _proposalSI = image;
            _passCheck(CHECK_PROPOSAL);
        } else if (kind == ContractType.Padawan) {
            _padawanSI = image;
            _passCheck(CHECK_PADAWAN);
        } else if (kind == ContractType.Contest) {
            _contestSI = image;
            _passCheck(CHECK_CONTEST);
        } else if (kind == ContractType.JuryGroup) {
            _juryGroupSI = image;
            _passCheck(CHECK_JURY_GROUP);
            _migrateInitialJuryGroups();
        } else if (kind == ContractType.Juror) {
            _jurorSI = image;
        }
    }

    function updateDepools(mapping(address => bool) depools) external override {
        require(msg.sender == demiStore);
        tvm.accept();
        _depools = depools;
        _passCheck(CHECK_DEPOOLS);
    }

    function updateAddress(ContractType kind, address addr) external override {
        require(msg.sender == demiStore);
        tvm.accept();
        if (kind == ContractType.PriceProvider) {
            _priceProvider = addr;
            _passCheck(CHECK_PRICE_PROVIDER);
        }
    }

    function updateABI(ContractType kind, string sabi) external override {
        require(false); kind; sabi;
    }

    /*
     * Public Deploy API
     */

    function deployPadawan(uint userKey) external override checksEmpty {
        require(!_deployedPadawans.exists(userKey), ERROR_PADAWAN_ALREADY_DEPLOYED);
        require(msg.value >= DEPLOY_FEE);
        TvmCell code = _padawanSI.toSlice().loadRef();
        TvmCell state = tvm.buildStateInit({
            contr: Padawan,
            varInit: {deployer: address(this)},
            pubkey: userKey,
            code: code
        });
        address addr = new Padawan {stateInit: state, value: START_BALANCE}();
        _deployedPadawans[userKey] = PadawanData(msg.sender, addr);
    }

    function onPadawanDeploy(uint key) external override {
        optional(PadawanData) opt = _deployedPadawans.fetch(key);
        require(opt.hasValue());
        PadawanData data = opt.get();
        require(msg.sender == data.addr);
        _deployedPadawansCounter++;
        Padawan(data.addr).initPadawan{value:0, flag: 64}
            (data.userWalletAddress, _priceProvider, _depools);
        IClient(data.userWalletAddress).updatePadawan(data.addr);
    }

    function _deployProposal(
        uint32 totalVotes,
        uint32 start,
        uint32 end,
        uint16 options,
        TvmCell specificData,
        string description,
        string text,
        VoteCountModel model,
        address[] voters
    ) private {
        uint32 key = _deployedProposalsCounter;
        require(msg.value >= DEPLOY_PROPOSAL_FEE);

        if (model == VoteCountModel.SoftMajority) {
            options |= PROPOSAL_VOTE_SOFT_MAJORITY;
        } else if (model == VoteCountModel.SuperMajority) {
            options |= PROPOSAL_VOTE_SUPER_MAJORITY;
        }

        ProposalInfo pi = ProposalInfo(key, start, end, options,
            totalVotes, description, text, voters, uint32(now), specificData);
        _proposalInfo[key] = pi;

        TvmCell code = _proposalSI.toSlice().loadRef();
        TvmCell state = tvm.buildStateInit({
            contr: Proposal,
            varInit: {_deployer: address(this)},
            pubkey: key,
            code: code
        });
        uint128 pledge = START_BALANCE;
        if (options & PROPOSES_CONTEST > 0) {
            pledge += DEPLOY_PAY;
        }
        address addr = new Proposal {stateInit: state, value: pledge}();
        _deployedProposals[addr] = key;
        _proposalData[key] = ProposalData(key, ProposalState.New, msg.sender, addr, uint32(now), 0);
    }

    function deployProposal(uint32 totalVotes, uint32 start, uint32 end,
        string description, string text, VoteCountModel model) external override checksEmpty {
        address[] noVoters;
        delete noVoters;
        TvmCell empty;
        _deployProposal(totalVotes, start, end, DEFAULT_OPTIONS, empty, description, text, model, noVoters);
    }

    function deployProposalWithWhitelist(uint32 totalVotes, uint32 start, uint32 end, string description,
            string text, VoteCountModel model, address[] voters) external override checksEmpty {
        TvmCell empty;
        _deployProposal(totalVotes, start, end, PROPOSAL_HAS_WHITELIST, empty, description, text, model, voters);
    }

    function deployProposalForContest(
        uint32 totalVotes,
        uint32 start,
        uint32 end,
        string description,
        string title,
        VoteCountModel model,
        uint32 contestDuration, // period of accepting submissions
        uint128 prizePool,
        string[] tags
    ) external override {
        address[] noVoters;
        TvmBuilder builder;
        builder.store(contestDuration, prizePool, tags);
        TvmCell specificProposalData = builder.toCell();
        _deployProposal(totalVotes, start, end, DEFAULT_OPTIONS | PROPOSES_CONTEST,
            specificProposalData, title, description, model, noVoters);
    }

    function onProposalDeploy() external override {
        optional(uint32) opt = _deployedProposals.fetch(msg.sender);
        require(opt.hasValue());
        uint32 key = opt.get();

        ProposalInfo pi = _proposalInfo[key];

        Proposal(msg.sender).initProposal{value: DEF_COMPUTE_VALUE}(pi, _padawanSI);

        ProposalData pd = _proposalData[key];
        IClient(pd.userWalletAddress).onProposalDeployed(key, pd.addr);

        _deployedProposalsCounter++;
    }

    function _registerContest(uint32 id, string title, string link, uint hashCode) private pure returns (ContestInfo) {
        return ContestInfo(id, title, link, hashCode);
    }

    function _scheduleContest(uint32 contestStarts, uint32 contestEnds, uint32 votingEnds) private pure returns (ContestTimeline) {
        return ContestTimeline(uint32(now), contestStarts, contestEnds, votingEnds);
    }

    function _setupContest(uint32 id, uint32 proposalId, uint8 groupId, uint128 budget, string[] tags) private pure returns (ContestSetup) {
        return ContestSetup(id, proposalId, 0, groupId, budget, uint32(now), tags);
    }

    function _deployContest(
        uint32 id,
        ContestInfo contestInfo,
        ContestTimeline contestTimeline,
        ContestSetup contestSetup
    ) private {
        TvmCell code = _contestSI.toSlice().loadRef();
        TvmCell state = tvm.buildStateInit({
            contr: Contest,
            varInit: {_deployer: address(this)},
            pubkey: id,
            code: code
        });

        address addr = new Contest {stateInit: state, value: START_BALANCE}
            (demiStore, contestInfo, contestTimeline, contestSetup);
        _deployedContests[addr] = id;
        _radar[id] = Brief(id, addr, Stage.New, contestSetup.tags, contestTimeline.contestStarts);
    }

    function deployContest(
        uint8 groupId,
        string title,
        string link,
        uint hashCode,
        uint32 start,
        uint32 end,
        uint32 vEnd,
        uint32[] rewards
    ) external checksEmpty {
        uint32 key = _contestsCounter++;
        ContestInfo info = _registerContest(key, title, link, hashCode);
        ContestTimeline timeline = _scheduleContest(start, end, vEnd);
        string[] tags;
        uint32 prizePool = 0;
        for (uint8 i = 0; i < rewards.length; i++) {
            prizePool += rewards[i];
        }
        ContestSetup setup = _setupContest(key, key, groupId, prizePool * uint128(1e9), tags);
        _deployContest(key, info, timeline, setup);
    }

    function getMembersCallback(mapping(address => Member) members) external override {
        require(_tagsPendings.exists(msg.sender), 200);
        uint32 contestId = _tagsPendings[msg.sender];
        mapping (address => Member) juryMembers;
        address[] juryAddresses;
        delete _tagsPendings[msg.sender];
        for((, Member member): members) {
            if(member.balance > 0) {
                juryMembers[member.addr] = member;
            }
        }

        if(_tagsPendings.empty()) {
            for((, Member member): juryMembers) {
                juryAddresses.push(member.addr);
            }
            Contest(_radar[contestId].addr).setJuryAddresses{value: 1 ton}(juryAddresses);
        }
    }

    function onContestDeploy(uint32 id) external override {
        require(_deployedContests.exists(msg.sender), 200);
        // check msg.sender == _radar[id].addr
        string[] tags = _radar[id].tags;
        resolveTags(id, tags);

//        Contest(msg.sender).setupContest{value: DEF_COMPUTE_VALUE}();
//        _deployedContestsCounter++;
        msg.sender.transfer(0, false, 64);
    }

    function resolveTags(uint32 id, string[] tags) private {
        for(uint8 i = 0; i < tags.length; i++) {
            TvmCell state = _buildJuryGroupState(tags[i]);
            uint256 hashState = tvm.hash(state);
            address addr = address.makeAddrStd(0, hashState);
            _tagsPendings[addr] = id;
            IJuryGroup(addr).getMembers{
                value: 0.5 ton,
                flag: 1,
                bounce: true
            }();
        }
    }

    function stateUpdated(Stage stage) external override {
        uint32 contestId = _deployedContests[msg.sender];
        _radar[contestId].stage = stage;
        // handle nextAt
    }

    function onStateUpdate(ProposalState state) external override {
        optional(uint32) opt = _deployedProposals.fetch(msg.sender);
        require(opt.hasValue());
        uint32 key = opt.get();
        _proposalData[key].state = state;
        msg.sender.transfer(0, false, 64);
    }

    function updateRoster(uint32 contestId, uint32 grId, uint32[] members) external override {
        uint32[] fit;
        mapping (uint32 => uint32) offers;

        for (uint32 rid: _quorum[contestId].reqs) {
            Req req = _reqs[rid];
            if ((req.groupId == grId) && (req.status >= ReqStatus.Query) && (req.status <= ReqStatus.Confirm)) {
                fit.push(rid);
            }
        }

        for (uint i = 0; i < fit.length; i++) {
            // i < members.length();
            uint32 rid = fit[i];
            _reqs[rid].eid = members[i];
            _reqs[rid].status = ReqStatus.Hire;
            offers[members[i]] = rid;
        }
        IInterestGroup(msg.sender).offer{value: DEF_COMPUTE_VALUE}(contestId, offers);
    }

    function confirm(uint32 contestId, mapping (uint32 => address) staff) external override {
        uint16 accepted = 0;
        for ((uint32 rid, address addr): staff) {
//            _reqs[rid].eid == members[i];    // check it
            _reqs[rid].status = ReqStatus.Confirm;
            _quorum[contestId].jury.push(addr);
            accepted++;
        }
        if (_quorum[contestId].left < accepted) {
            // assert
        } else {
            _quorum[contestId].left -= accepted;
        }
        if (_quorum[contestId].left == 0) {
            _quorum[contestId].overallStatus = ReqStatus.Confirm;
        }
    }

    function lapse(uint32 contestId, uint16 response) external override {
        // failed to assemble jury
    }

    function _groupId(string /*tag*/) private view returns (uint32, address) {
        for ((address addr, uint32 groupId) :_interestGroups) {
            return (groupId, addr);
        }
    }

    function _gatherJury(uint32 contestId, DomainOrder domain) private {
        uint32 counter = _reqCounter;
        (uint32 groupId, address addr) = _groupId(domain.tag);
        repeat (domain.count) {
            _reqs[counter] = Req(counter, groupId, ReqStatus.New, 0);
            _quorum[contestId].reqs.push(counter);
            counter++;
        }
        _reqCounter += domain.count;
        IInterestGroup(addr).inquire{value: DEF_COMPUTE_VALUE}(contestId, _quorum[contestId].reqs);
    }

    function assemble(uint32 contestId, string tag, uint16 quota) external {
        _gatherJury(contestId, DomainOrder(tag, quota));
    }

    function assembleAll(uint32 contestId, DomainOrder[] wishlist) external {
        _quorum[contestId].order = wishlist;
        for (DomainOrder domain: wishlist) {
            _gatherJury(contestId, domain);
        }
    }

    function reportResults(VotingResults results) external override {
        optional(uint32) opt = _deployedProposals.fetch(msg.sender);
        require(opt.hasValue());
        uint32 proposalId = opt.get();
        _votingResults.push(results);
        ProposalData data = _proposalData[proposalId];
        ProposalInfo info = _proposalInfo[proposalId];
        if ((info.options & PROPOSES_CONTEST) != 0) {
            TvmSlice slice = info.customData.toSlice();
            (uint32 duration, uint128 prizePool, string[] tags) = slice.decodeFunctionParams(IContestDetails.decode);
            uint32 contestId = _contestsCounter++;
            ContestInfo cinfo = _registerContest(contestId, info.description, info.text, 0);
            ContestTimeline timeline = _scheduleContest(uint32(now), uint32(now) + duration, 0);
            ContestSetup setup = _setupContest(contestId, proposalId, 1, prizePool, tags);
            _proposalData[proposalId].contestId = contestId;
            _deployContest(proposalId, cinfo, timeline, setup);
        }
        IClient(data.userWalletAddress).onProposalCompletion{value: DEF_COMPUTE_VALUE}(proposalId, results.passed);
    }

    /*
    *  Setters
    */

    function setProposalSI(TvmCell c) external signedAndChecksNotPassed {
        _proposalSI = c;
        _passCheck(CHECK_PROPOSAL);
    }

    function setPadawanSI(TvmCell c) external signedAndChecksNotPassed {
        _padawanSI = c;
        _passCheck(CHECK_PADAWAN);
    }

    function setContestSI(TvmCell c) external signedAndChecksNotPassed {
        _contestSI = c;
        _passCheck(CHECK_CONTEST);
    }

    function setJuryGroupSI(TvmCell c) external signedAndChecksNotPassed {
        _juryGroupSI = c;
        _passCheck(CHECK_JURY_GROUP);
    }

    function setPriceProvider(address addr) external signedAndChecksNotPassed {
        _priceProvider = addr;
        _passCheck(CHECK_PRICE_PROVIDER);
    }

    function setDePool(address addr) external signedAndChecksNotPassed {
        _depools[addr] = true;
        _passCheck(CHECK_DEPOOLS);
    }

    function setInfoCenter(address addr) external signed {
        _infoCenter = addr;
    }

    function grant(address addr, uint128 value) pure external signed {
        addr.transfer(value, false, 3);
    }

    function _migrateInitialJuryGroups() private {
        TvmCell state = _buildJuryGroupState('initial');
        TvmCell payload = tvm.encodeBody(JuryGroup);
        address addrJuryGroup = tvm.deploy(state, payload, 3 ton, 0);
        for (uint i = 0; i < _initJuryKeys.length; i++) {
            TvmCell stateJuror = tvm.insertPubkey(_jurorSI, _initJuryKeys[i]);
            address addrJuror = new JurorContract {stateInit: stateJuror, value: 1 ton, flag: 1}();
            IJuryGroup(addrJuryGroup).registerMember{value: 1 ton, bounce: false, flag: 1}(addrJuror, _initJuryKeys[i]);
        }
    }

    function _buildJuryGroupState(string tag) internal view returns (TvmCell) {
        TvmCell code = _juryGroupSI.toSlice().loadRef();
        return tvm.buildStateInit({
            contr: JuryGroup,
            varInit: {_tag: tag, _deployer: address(this)},
            code: code
        });
    }

    /*
    *   Get methods
    */

    function getImages() public view returns (TvmCell padawan, TvmCell proposal, TvmCell contest) {
        padawan = _padawanSI;
        proposal = _proposalSI;
        contest = _contestSI;
    }

    function getPartners() public view returns (address priceProvider, address[] depools, address infoCenter) {
        priceProvider = _priceProvider;
        infoCenter = _infoCenter;
        for ((address addr, bool flag): _depools) {
            if (flag)
                depools.push(addr);
        }
    }

    function getDeployed() public view returns (mapping (uint => PadawanData) padawans, mapping (address => uint32) proposals, mapping (address => uint32) contests) {
        padawans = _deployedPadawans;
        proposals = _deployedProposals;
        contests = _deployedContests;
    }

    function pulse() external view returns (mapping (uint32 => Brief) snapshot) {
        snapshot = _radar;
    }

    function getVotingResults() public view returns (VotingResults[] results) {
        results = _votingResults;
    }

    function getProposalInfo() external override view returns (mapping (uint32 => ProposalInfo) proposals) {
        proposals = _proposalInfo;
    }

    function getProposalData() external override view returns (mapping (uint32 => ProposalData) proposals) {
        proposals = _proposalData;
    }

    function getStats() public view returns (uint16 version, uint32 deployedPadawansCounter, uint32 deployedProposalsCounter, uint32 contestsCounter) {
        version = _version;
        deployedPadawansCounter = _deployedPadawansCounter;
        deployedProposalsCounter = _deployedProposalsCounter;
        contestsCounter = _contestsCounter;
    }

    function getPadawan(uint key) public view returns (PadawanData data) {
        data = _deployedPadawans[key];
    }

    function onCodeUpgrade() internal override {
        tvm.resetStorage();
        demiStore = address.makeAddrStd(0, 0x093810ee72d9550ee7a7ea245753803f4d4b0981f7143e1bcb1828b1e9b9cde6);
        DemiurgeStore(demiStore).queryImage{value: 0.2 ton, bounce: true}(ContractType.Proposal);
        DemiurgeStore(demiStore).queryImage{value: 0.2 ton, bounce: true}(ContractType.Padawan);
        DemiurgeStore(demiStore).queryImage{value: 0.2 ton, bounce: true}(ContractType.Contest);
        DemiurgeStore(demiStore).queryDepools{value: 0.2 ton, bounce: true}();
        DemiurgeStore(demiStore).queryAddress{value: 0.2 ton, bounce: true}(ContractType.PriceProvider);
    }

    function destruct() public override {
        tvm.accept();
        _destruct(demiStore);
    }

    function registerJuryMember(string tag, uint pk) external override {
        // TODO: add contest sender check
        require(msg.sender != address(0), 300);
        TvmCell stateJuryGroup = _buildJuryGroupState(tag);
        address addrJuryGroup = new JuryGroup{
            stateInit: stateJuryGroup,
            value: 1 ton,
            flag: 2,
            bounce: true
        }();

        TvmCell stateJuror = tvm.insertPubkey(_jurorSI, pk);
        address addrJuror = new JurorContract{
            stateInit: stateJuror,
            value: 1 ton,
            flag: 2,
            bounce: true
        }();

        IJuryGroup(addrJuryGroup).registerMember{
            value: msg.value - 2 ton,
            flag: 2,
            bounce: true
        }(addrJuror, pk);
        // _tagsPendings[addr] = Candidate(pk, tag, msg.value - 3 ton);
        // IJuryGroup(addr).getMembers{
        //     value: 1 ton,
        //     flag: 1,
        //     bounce: true
        // }();
    }

    function resolveJuryGroup(string tag) public view returns (address addr) {
        TvmCell state = _buildJuryGroupState(tag);
        uint256 hashState = tvm.hash(state);
        addr = address.makeAddrStd(0, hashState);
    }

    function resolveJuror(uint pk) public view returns (address addr) {
        TvmCell state = tvm.insertPubkey(_jurorSI, pk);
        uint256 hashState = tvm.hash(state);
        addr = address.makeAddrStd(0, hashState);
    }
}
