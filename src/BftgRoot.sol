pragma ton-solidity >=0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import './Base.sol';
import './Checks.sol';
import './Errors.sol';
import './interfaces/IBftgRoot.sol';
import './resolvers/ContestResolver.sol';
import './resolvers/JuryGroupResolver.sol';

contract BftgRoot is Base, IBftgRoot, IBftgRootStoreCallback, ContestResolver, JuryGroupResolver, Checks {

/* -------------------------------------------------------------------------- */
/*                                ANCHOR Checks                               */
/* -------------------------------------------------------------------------- */

    uint8 constant CHECK_CONTEST_CODE = 1;
    uint8 constant CHECK_JURY_GROUP_CODE = 2;

    function _createChecks() private inline {
        _checkList = CHECK_CONTEST_CODE | CHECK_JURY_GROUP_CODE;
    }

/* -------------------------------------------------------------------------- */
/*                                 ANCHOR Init                                */
/* -------------------------------------------------------------------------- */

    modifier onlyStore() {
        require(msg.sender == _addrBftgRootStore, Errors.ONLY_STORE);
        _;
    }

    address _addrBftgRootStore;

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
    ) external override onlyStore {
        if (kind == ContractCode.Contest) {
            _codeContest = code;
            _passCheck(CHECK_CONTEST_CODE);
        }
        if (kind == ContractCode.JuryGroup) {
            _codeJuryGroup = code;
            _passCheck(CHECK_JURY_GROUP_CODE);
        }
        _onInit();
    }

    function updateAddr(ContractAddr kind, address addr) external override {}

/* -------------------------------------------------------------------------- */
/*                                ANCHOR Bounce                               */
/* -------------------------------------------------------------------------- */

    onBounce(TvmSlice) external {
        if(_juryGroupPendings.exists(msg.sender)) {
            address[] _;
            deployJuryGroup(_juryGroupPendings[msg.sender].tag, _);
            this.registerMemberJuryGroup
                {value: 0, bounce: false, flag: 64}
                (_juryGroupPendings[msg.sender].tag, _juryGroupPendings[msg.sender].addrJury);
            delete _juryGroupPendings[msg.sender];
        }
    }

/* -------------------------------------------------------------------------- */
/*                               ANCHOR Contest                               */
/* -------------------------------------------------------------------------- */

    function deployContest(string[] tags, uint128 prizePool, uint32 underwayDuration) external view {
        tvm.accept();
        TvmCell state = _buildContestState(address(this));
        new Contest
            {stateInit: state, value: 1 ton}
            (_addrBftgRootStore, tags, prizePool, underwayDuration);
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

    function registerMemberJuryGroup(string tag, address addrMember) public override {
        address addrContest = resolveContest(address(this));
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