pragma ton-solidity >= 0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import "./Base.sol";
import "./Errors.sol";
import "./resolvers/PadawanResolver.sol";
import "./resolvers/GroupResolver.sol";
import "./interfaces/IClient.sol";
import "./interfaces/IProposal.sol";
import "./interfaces/IPadawan.sol";
import "./interfaces/IGroup.sol";

contract Proposal is Base, PadawanResolver, GroupResolver, IProposal, IGroupCallback {
    address static _deployer;
    uint32 static _id;
    
    address _client;

    uint128 _votePrice;
    uint128 _voteTotal;
    address _voteProvider;

    address[] _whiteList;
    bool _openProposal = false;

    ProposalInfo _proposalInfo;

    ProposalResults _results;
    VoteCountModel _voteCountModel;

    constructor(
        address client,
        string title,
        uint128 votePrice,
        uint128 voteTotal,
        address voteProvider,
        address group,
        address[] whiteList,
        string proposalType,
        TvmCell specific,
        TvmCell codePadawan
    ) public {
        require(_deployer == msg.sender);

        _client = client;

        _votePrice = votePrice;
        _voteTotal = voteTotal;
        _voteProvider = voteProvider;

        _proposalInfo.title = title;
        _proposalInfo.start = uint32(now);
        _proposalInfo.end = uint32(now + 60 * 60 * 24 * 7);
        _proposalInfo.proposalType = proposalType;
        _proposalInfo.specific = specific;
        _proposalInfo.state = ProposalState.New;
        _proposalInfo.totalVotes = voteTotal;

        _codePadawan = codePadawan;

        if(group != address(0)) {
            _getGroupMembers(group);
        } else if (!whiteList.empty()) {
            _whiteList = whiteList;
        } else  {
            _openProposal = true;
        }

        _voteCountModel = VoteCountModel.SoftMajority;
    }

    function wrapUp() external override {
        _wrapUp();
        msg.sender.transfer(0, false, 64);
    }

    function estimateVotes(uint128 votes, bool choice) external override {
        IEstimateVotesCallback(msg.sender).onEstimateVotes
            {value: 0, flag: 64, bounce: true}
            (votes * _votePrice, _votePrice, _voteProvider, votes, choice);
    }

    function vote(address padawanOwner, bool choice, uint128 votes) external override {
        address addrPadawan = resolvePadawan(padawanOwner);
        uint16 errorCode = 0;

        require(_openProposal || _findInWhiteList(padawanOwner), Errors.INVALID_CALLER);

        if (addrPadawan != msg.sender) {
            errorCode = Errors.NOT_AUTHORIZED_CONTRACT;
        } else if (now < _proposalInfo.start) {
            errorCode = Errors.VOTING_NOT_STARTED;
        } else if (now > _proposalInfo.end) {
            errorCode = Errors.VOTING_HAS_ENDED;
        }

        if (errorCode > 0) {
            IPadawan(msg.sender).rejectVote{value: 0, flag: 64, bounce: true}(votes, errorCode);
        } else {
            IPadawan(msg.sender).confirmVote{value: 0, flag: 64, bounce: true}(votes, _votePrice, _voteProvider);
            if (choice) {
                _proposalInfo.votesFor += votes;
            } else {
                _proposalInfo.votesAgainst += votes;
            }
        }

        _wrapUp();
    }

    function _finalize(bool passed) private {
        _results = ProposalResults(
            uint32(0),
            passed,
            _proposalInfo.votesFor,
            _proposalInfo.votesAgainst,
            _voteTotal,
            _voteCountModel,
            uint32(now)
        );

        ProposalState state = passed ? ProposalState.Passed : ProposalState.NotPassed;

        _changeState(state);

        IClient(address(_client)).onProposalPassed{value: 1 ton} (_proposalInfo);
    }

    function _tryEarlyComplete(
        uint128 yes,
        uint128 no
    ) private view returns (bool, bool) {
        (bool completed, bool passed) = (false, false);
        if (yes * 2 > _voteTotal) {
            completed = true;
            passed = true;
        } else if(no * 2 >= _voteTotal) {
            completed = true;
            passed = false;
        }
        return (completed, passed);
    }

    function _wrapUp() private {
        (bool completed, bool passed) = (false, false);

        if (now > _proposalInfo.end) {
            completed = true;
            passed = _calculateVotes(_proposalInfo.votesFor, _proposalInfo.votesAgainst);
        } else {
            (completed, passed) = _tryEarlyComplete(_proposalInfo.votesFor, _proposalInfo.votesAgainst);
        }

        if (completed) {
            _changeState(ProposalState.Ended);
            _finalize(passed);
        }
    }

    function _calculateVotes(
        uint128 yes,
        uint128 no
    ) private view returns (bool) {
        bool passed = false;
        passed = _softMajority(yes, no);
        return passed;
    }

    function _softMajority(
        uint128 yes,
        uint128 no
    ) private view returns (bool) {
        bool passed = false;
        passed = yes >= 1 + (_voteTotal / 10) + (no * ((_voteTotal / 2) - (_voteTotal / 10))) / (_voteTotal / 2);
        return passed;
    }

    function _changeState(ProposalState state) private inline {
        _proposalInfo.state = state;
    }

    function _buildPadawanState(address owner) internal view override returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Padawan,
            varInit: {_deployer: _deployer, _owner: owner},
            code: _codePadawan
        });
    }

    function queryStatus() external override {
        IPadawan(msg.sender).updateStatus
            {value: 0, flag: 64, bounce: true}
            (_proposalInfo.state);
    }

    // Getters

    function getAll() public view override returns (ProposalInfo info) {
        info = _proposalInfo;
    }

    function getVotingResults() public view returns (ProposalResults vr) {
        require(_proposalInfo.state > ProposalState.Ended, Errors.VOTING_HAS_NOT_ENDED);
        vr = _results;
    }

    function getInfo() public view returns (ProposalInfo info) {
        info = _proposalInfo;
    }

    function getCurrentVotes() external override view returns (uint128 votesFor, uint128 votesAgainst) {
        return (_proposalInfo.votesFor, _proposalInfo.votesAgainst);
    }

    /*
    * Groups
    */

    function onGetMembers(string name, address[] members) public override onlyContract { name;
        _whiteList = members;
    }

    function _findInWhiteList(address padawanOwner) view private returns (bool) {
        for(uint32 index = 0; index < _whiteList.length; index++) {
            if(_whiteList[index] == padawanOwner) {
                return true;
            }
        }
        return false;
    }

    function _getGroupMembers(address group) view private {
        IGroup(group).getMembers();
    }

}
