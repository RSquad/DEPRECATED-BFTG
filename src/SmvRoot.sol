pragma ton-solidity >= 0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import "./resolvers/PadawanResolver.sol";
import "./resolvers/ProposalResolver.sol";
import "./resolvers/GroupResolver.sol";
import "./resolvers/ProposalFactoryResolver.sol";
import "./Proposal.sol";
import "./Group.sol";
import "./SmvRootStore.sol";
import "./interfaces/IProposal.sol";
import "./interfaces/IClient.sol";
import './Glossary.sol';
import './ProposalFactory.sol';
import './Checks.sol';
import './interfaces/ISmvRootStore.sol';
import './interfaces/ISmvRoot.sol';

import {Errors} from './Errors.sol';

contract SmvRoot is
    Base,
    ISmvRoot,
    ISmvRootStoreCallback,
    PadawanResolver,
    ProposalResolver,
    GroupResolver,
    ProposalFactoryResolver,
    Checks {

/* -------------------------------------------------------------------------- */
/*                                ANCHOR Checks                               */
/* -------------------------------------------------------------------------- */

    uint8 constant CHECK_PROPOSAL = 1;
    uint8 constant CHECK_PADAWAN = 2;
    uint8 constant CHECK_GROUP = 4;
    uint8 constant CHECK_PROPOSAL_FACTORY = 8;
    uint8 constant CHECK_BFTG_ROOT_ADDRESS = 16;

    function _createChecks() private inline {
        _checkList =
            CHECK_PROPOSAL |
            CHECK_PADAWAN |
            CHECK_GROUP |
            CHECK_PROPOSAL_FACTORY |
            CHECK_BFTG_ROOT_ADDRESS;
    }

/* -------------------------------------------------------------------------- */
/*                                 ANCHOR Init                                */
/* -------------------------------------------------------------------------- */

    address _addrSmvRootStore;
    address _addrBftgRoot;
    address _addrProposalFactory;

    modifier onlyStore() {
        require(msg.sender == _addrSmvRootStore, Errors.ONLY_STORE);
        _;
    }

    constructor(address addrSmvRootStore) public {
        if (msg.sender == address(0)) {
            require(msg.pubkey() == tvm.pubkey(), Errors.ONLY_SIGNED);
        }
        require(addrSmvRootStore != address(0), Errors.STORE_UNDEFINED);
        tvm.accept();
        
        _addrSmvRootStore = addrSmvRootStore;
        ISmvRootStore(_addrSmvRootStore).queryCode
            {value: 0.2 ton, bounce: true}
            (ContractCode.Proposal);
        ISmvRootStore(_addrSmvRootStore).queryCode
            {value: 0.2 ton, bounce: true}
            (ContractCode.Padawan);
        ISmvRootStore(_addrSmvRootStore).queryCode
            {value: 0.2 ton, bounce: true}
            (ContractCode.Group);
        ISmvRootStore(_addrSmvRootStore).queryCode
            {value: 0.2 ton, bounce: true}
            (ContractCode.ProposalFactory);
        ISmvRootStore(_addrSmvRootStore).queryAddr
            {value: 0.2 ton, bounce: true}
            (ContractAddr.BftgRoot);

        _createChecks();
    }

    bool public _inited = false;

    function _onInit() private {
        if(_isCheckListEmpty() && !_inited) {
            _inited = true;
            TvmCell state = _buildProposalFactoryState(address(this));
            _addrProposalFactory = new ProposalFactory
                {stateInit: state, value: 0.2 ton}
                ();
        }
    }

    function updateCode(
        ContractCode kind,
        TvmCell code
    ) external override onlyStore {
        if (kind == ContractCode.Proposal) {
            _codeProposal = code;
            _passCheck(CHECK_PROPOSAL);
        } else if (kind == ContractCode.Padawan) {
            _codePadawan = code;
            _passCheck(CHECK_PADAWAN);
        } else if (kind == ContractCode.Group) {
            _codeGroup = code;
            _passCheck(CHECK_GROUP);
        } else if (kind == ContractCode.ProposalFactory) {
            _codeProposalFactory = code;
            _passCheck(CHECK_PROPOSAL_FACTORY);
        }
        _onInit();
    }

    function updateAddr(ContractAddr kind, address addr) external override onlyStore {
        require(addr != address(0));
        if (kind == ContractAddr.BftgRoot) {
            _addrBftgRoot = addr;
            _passCheck(CHECK_BFTG_ROOT_ADDRESS);
        }
        _onInit();
    }

    uint32 _deployedPadawansCounter;
    
    function deployPadawan(address owner) external onlyContract {
        require(msg.value >= DEPLOY_FEE);
        require(owner != address(0));
        TvmCell state = _buildPadawanState(owner);
        new Padawan{stateInit: state, value: START_BALANCE + 2 ton}();
    }

    uint32 _deployedProposalsCounter;

    function deployProposal(
        address client,
        string title,
        uint128 votePrice,
        uint128 voteTotal,
        address voteProvider,
        address group,
        address[] whiteList,
        string proposalType,
        TvmCell specific
    ) external override onlyContract {
        require(msg.sender == _addrProposalFactory);
        require(msg.value >= DEPLOY_PROPOSAL_FEE);
        TvmBuilder b;
        b.store(specific);
        TvmCell cellSpecific = b.toCell();
        _beforeProposalDeploy(
            client,
            title,
            votePrice,
            voteTotal,
            voteProvider,
            group,
            whiteList,
            proposalType,
            cellSpecific
        );
    }

    function _beforeProposalDeploy(
        address client,
        string title,
        uint128 votePrice,
        uint128 voteTotal,
        address voteProvider,
        address group,
        address[] whiteList,
        string proposalType,
        TvmCell specific
    ) private view {
        TvmCell state = _buildProposalState(_deployedProposalsCounter);
        uint256 hashState = tvm.hash(state);
        address proposal = address.makeAddrStd(0, hashState);
        // IClient(_addrDensRoot).onProposalDeploy
        //     {value: 1 ton, bounce: true}
        //     (proposal, proposalType, specific);
        this._deployProposal
            {value: 4 ton}
            (client, title, votePrice, voteTotal, voteProvider, group, whiteList, proposalType, specific);
    }

    function _deployProposal(
        address client,
        string title,
        uint128 votePrice,
        uint128 voteTotal,
        address voteProvider,
        address group,
        address[] whiteList,
        string proposalType,
        TvmCell specific
    ) public onlyMe {
        TvmCell state = _buildProposalState(_deployedProposalsCounter);
        new Proposal {stateInit: state, value: START_BALANCE}(
            client,
            title,
            votePrice,
            voteTotal,
            voteProvider,
            group,
            whiteList,
            proposalType,
            specific,
            _codePadawan
        );
        _deployedProposalsCounter++;
    }

    function deployGroup(string name, address[] initialMembers) public onlyContract {
        TvmCell state = _buildGroupState(name);
        new Group
            {stateInit: state, value: START_BALANCE}
            (initialMembers);
    }

    // Getters

    function getStored() public view returns (
        TvmCell codePadawan,
        TvmCell codeProposal,
        TvmCell codeGroup,
        TvmCell codeProposalFactory,
        address addrBftgRoot,
        address proposalFactory
    ) {
        codePadawan = _codePadawan;
        codeProposal = _codeProposal;
        codeGroup = _codeGroup;
        codeProposalFactory = _codeProposalFactory;
        addrBftgRoot = _addrBftgRoot;
        proposalFactory = _addrProposalFactory;
    }

    function getStats() public view returns (uint32 deployedPadawansCounter, uint32 deployedProposalsCounter) {
        deployedPadawansCounter = _deployedPadawansCounter;
        deployedProposalsCounter = _deployedProposalsCounter;
    }
}