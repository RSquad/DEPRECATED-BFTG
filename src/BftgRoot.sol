pragma ton-solidity >=0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import './Base.sol';
import './Checks.sol';
import './Errors.sol';

import './interfaces/IBftgRoot.sol';
import './interfaces/IBftgRootStore.sol';
import './interfaces/IProposalFactory.sol';
import '../crystal-smv/src/interfaces/IClient.sol';
import '../crystal-smv/src/interfaces/IProposal.sol';

import './resolvers/ContestResolver.sol';
import './resolvers/JuryGroupResolver.sol';

contract BftgRoot is
    IBftgRoot,
    IBftgRootStoreCallback,
    IClient,
    ContestResolver,
    JuryGroupResolver,
    Checks {

/* -------------------------------------------------------------------------- */
/*                                ANCHOR Checks                               */
/* -------------------------------------------------------------------------- */

    uint8 constant CHECK_CONTEST = 1;
    uint8 constant CHECK_JURY_GROUP = 2;

    function _createChecks() private inline {
        _checkList = CHECK_CONTEST | CHECK_JURY_GROUP;
    }

/* -------------------------------------------------------------------------- */
/*                                 ANCHOR Init                                */
/* -------------------------------------------------------------------------- */

    address _addrBftgRootStore;
    uint32 _deployedContest;

    constructor(address addrBftgRootStore) public {
        if (msg.sender == address(0)) {
            require(msg.pubkey() == tvm.pubkey(), Errors.ONLY_SIGNED);
        }
        require(addrBftgRootStore != address(0), Errors.STORE_UNDEFINED);
        tvm.accept();

        _addrBftgRootStore = addrBftgRootStore;
        IBftgRootStore(addrBftgRootStore).queryCode
            {value: 0.2 ton, bounce: true}
            (ContractCode.Contest);
        IBftgRootStore(addrBftgRootStore).queryCode
            {value: 0.2 ton, bounce: true}
            (ContractCode.JuryGroup);

        _createChecks();
    }

    bool public _inited = false;

    function _onInit() private {
        if(_isCheckListEmpty() && !_inited) {
            _inited = true;
        }
    }

    function updateCode(
        ContractCode kind,
        TvmCell code
    ) external override {
        require(msg.sender == _addrBftgRootStore, Errors.INVALID_CALLER);
        if (kind == ContractCode.Contest) {
            _codeContest = code;
            _passCheck(CHECK_CONTEST);
        }
        if (kind == ContractCode.JuryGroup) {
            _codeJuryGroup = code;
            _passCheck(CHECK_JURY_GROUP);
        }
        _onInit();
    }

    function updateAddr(ContractAddr kind, address addr) external override {
        require(msg.sender == _addrBftgRootStore, Errors.INVALID_CALLER);
    }

/* -------------------------------------------------------------------------- */
/*                                ANCHOR Bounce                               */
/* -------------------------------------------------------------------------- */

    onBounce(TvmSlice) external {
        if(_juryGroupPendings.exists(msg.sender)) {
            address[] _;
            deployJuryGroup(_juryGroupPendings[msg.sender].tag, _);
            this.registerMemberJuryGroup
                {value: 0, bounce: false, flag: 64}
                (_juryGroupPendings[msg.sender].tag, _juryGroupPendings[msg.sender].addrJury, _deployedContest);
            delete _juryGroupPendings[msg.sender];
        }
    }

/* -------------------------------------------------------------------------- */
/*                               ANCHOR Proposals                             */
/* -------------------------------------------------------------------------- */

    function onProposalNotPassed(ProposalData data, ProposalResults results) external override { data; results; }
    function onProposalPassed(ProposalData data, ProposalResults results) external override {
        // TODO: add check
        if(data.proposalType == 'contest') {
            TvmSlice slice = data.specific.toSlice();
            (ContestProposalSpecific specific) = slice.decode(ContestProposalSpecific);
            _deployContest(specific.tags, specific.prizePool, specific.underwayDuration, specific.description);
        }
    }
    function onProposalDeployed(ProposalData data) external override {  data;  }

/* -------------------------------------------------------------------------- */
/*                               ANCHOR Contest                               */
/* -------------------------------------------------------------------------- */

    function _deployContest(
        string[] tags,
        uint128 prizePool,
        uint32 underwayDuration,
        string description
    // commented for test purposes: ) private inline {
    ) public {
        TvmCell state = _buildContestState(address(this), _deployedContest);
        new Contest
            {stateInit: state, value: 0.8 ton}
            (_addrBftgRootStore, tags, prizePool, underwayDuration, description);
        _deployedContest++;
    }

/* -------------------------------------------------------------------------- */
/*                              ANCHOR JuryGroup                              */
/* -------------------------------------------------------------------------- */

    mapping(address => JuryGroupPending) _juryGroupPendings;

    function deployJuryGroup(string tag, address[] initialMembers) public view {
        require(address(0) != msg.sender);
        TvmCell state = _buildJuryGroupState(tag, address(this));
        new JuryGroup
            {stateInit: state, value: 0.3 ton}
            (initialMembers);
    }

    function registerMemberJuryGroup(string tag, address addrMember, uint32 contestId) public override {
        address addrContest = resolveContest(address(this), contestId);
        address addrJuryGroup = resolveJuryGroup(tag, address(this));
        require(msg.sender == addrContest || address(this) == msg.sender, 105);
        _juryGroupPendings[addrJuryGroup] = JuryGroupPending(addrMember, tag);
        IJuryGroup(addrJuryGroup).getMembers
            {value: 0, bounce: true, flag: 64}
            ();
    }

    function getMembersCallback(mapping(address => Member) members) public {
        require(_juryGroupPendings.exists(msg.sender) || address(this) == msg.sender, 106);
        IJuryGroup(msg.sender).registerMember
            {value: 0 ton, bounce: true, flag: 64}
            (_juryGroupPendings[msg.sender].addrJury);
        delete _juryGroupPendings[msg.sender];
    }

/* -------------------------------------------------------------------------- */
/*                               ANCHOR Getters                               */
/* -------------------------------------------------------------------------- */

    function getStored() public view returns (
        TvmCell codeContest,
        TvmCell codeJuryGroup
    ) {
        codeContest = _codeContest;
        codeJuryGroup = _codeJuryGroup;
    }
}