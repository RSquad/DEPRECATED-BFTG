pragma ton-solidity >= 0.36.0;

import "Base.sol";
import "IProposal.sol";
import "IDemiurge.sol";
import "Padawan.sol";
import "IInfoCenter.sol";

contract Proposal is Base, IProposal, IBaseData {

    uint16 constant ERROR_NOT_AUTHORIZED_VOTER  =   302; // Only ProposalInitiatorWallet cal create proposals
    uint16 constant ERROR_TOO_EARLY_FOR_RECLAIM =   303; // Can't return deposit before proposal expiration

//    uint16 constant ERROR_NOT_AUTHORIZED_VOTER  = 250; // Votes are not accepted at this time
    uint16 constant ERROR_VOTING_NOT_STARTED    = 251;   // Votes are not accepted at this time
    uint16 constant ERROR_VOTING_HAS_ENDED      = 252;  // Votes are not accepted at this time
    uint16 constant ERROR_VOTER_IS_NOT_ELIGIBLE = 253;  // Voter is not eligible to vote for this proposal

    ProposalInfo _info;
    address static _deployer;

    bool _hasWhitelist;
    mapping (address => bool) _voters;
    TvmCell _padawanSI;

    struct ProposalStatus {
        ProposalState state;
        uint32 votesFor;
        uint32 votesAgainst;
    }

    VotingResults _results;

    ProposalStatus _state;
    VoteCountModel _voteCountModel;

    event ProposalFinalized(VotingResults results);

    constructor() public {
        require(_deployer == msg.sender);
        _state.state = ProposalState.New;
        IInfoCenter(_deployer).onProposalDeploy{value: DEF_RESPONSE_VALUE}();
    }

    function initProposal(ProposalInfo pi, TvmCell padawanSI) external {
        _info = pi;
        _padawanSI = padawanSI;
        _voteCountModel = VoteCountModel.Majority;

        if (_info.options & PROPOSAL_VOTE_SOFT_MAJORITY > 0) {
            _voteCountModel = VoteCountModel.SoftMajority;
        } else if (_info.options & PROPOSAL_VOTE_SUPER_MAJORITY > 0) {
            _voteCountModel = VoteCountModel.SuperMajority;
        }

        _hasWhitelist = (_info.options & PROPOSAL_HAS_WHITELIST > 0) ? true : false;
        if (_hasWhitelist) {
            for (address addr : _info.voters) {
                _voters[addr] = true;
            }
        }

        _state.state = ProposalState.OnVoting;
    }

    function _canVote() private inline pure returns (bool) {
        return (msg.sender != address(0));
    }

    function wrapUp() external override {
        _wrapUp();
        msg.sender.transfer(0, false, 64);
    }

    /* Implements SMV algorithm and has vote function to receive ‘yes’ or ‘no’ votes from Voting Wallet. */
    function voteFor(uint256 key, bool choice, uint32 deposit) external override {
        TvmCell code = _padawanSI.toSlice().loadRef();
        TvmCell state = tvm.buildStateInit({
            contr: Padawan,
            varInit: {deployer: _deployer},
            pubkey: key,
            code: code
        });
        address padawanAddress = address.makeAddrStd(0, tvm.hash(state));
        uint16 ec = 0;
        address from = msg.sender;

        if (padawanAddress != from) {
            ec = ERROR_NOT_AUTHORIZED_VOTER;
        } else if (now < _info.start) {
            ec = ERROR_VOTING_NOT_STARTED;
        } else if (now > _info.end) {
            ec = ERROR_VOTING_HAS_ENDED;
        } else if (_hasWhitelist) {
            if (!_voters.exists(from)) {
                ec = ERROR_VOTER_IS_NOT_ELIGIBLE;
            }
        }

        if (ec > 0) {
            IPadawan(from).rejectVote{value: 0, flag: 64, bounce: true}(_info.id, deposit, ec);
        } else {
            IPadawan(from).confirmVote{value: 0, flag: 64, bounce: true}(_info.id, deposit);
            if (choice) {
                _state.votesFor += deposit;
            } else {
                _state.votesAgainst += deposit;
            }
        }

        _wrapUp();
    }

    function finalize(bool passed) external me {
        tvm.accept();

        _results = VotingResults(_info.id, passed, _state.votesFor,
            _state.votesAgainst, _info.totalVotes, _voteCountModel, uint32(now));
        ProposalState state = passed ? ProposalState.Passed : ProposalState.Failed;
        _transit(state);
        emit ProposalFinalized(_results);
        // Make sure balance is sufficient to fun the proposal results processing
        uint128 bondValue = 1 ton;
        if (_info.options & PROPOSES_CONTEST > 0) {
            bondValue += DEPLOY_PAY;
        }
        IInfoCenter(_deployer).reportResults{value: bondValue}(_results);
    }

    function _calculateVotes(
        uint32 yes,
        uint32 no,
        uint32 total,
        VoteCountModel model
    ) private inline pure returns (bool) {
        bool passed = false;
        if (model == VoteCountModel.Majority) {
            passed = (yes > no);
        } else if (model == VoteCountModel.SoftMajority) {
            passed = (yes * total * 10 >= total * total + no * (8 * total  + 20));
        } else if (model == VoteCountModel.SuperMajority) {
            passed = (yes * total * 3 >= total * total + no * (total + 6));
        } else if (model == VoteCountModel.Other) {
            //
        }
        return passed;
    }

    function _tryEarlyComplete(
        uint32 yes,
        uint32 no,
        uint32 total,
        VoteCountModel model
    ) private inline pure returns (bool, bool) {
        (bool completed, bool passed) = (false, false);
        if (model == VoteCountModel.Majority) {
            (completed, passed) = (2*yes > total) ? (true, true) : ((2*no >= total) ? (true, false) : (false, false));
        } else if (model == VoteCountModel.SoftMajority) {
            (completed, passed) = (2*yes > total) ? (true, true) : ((2*no >= total) ? (true, false) : (false, false));
        } else if (model == VoteCountModel.SuperMajority) {
            (completed, passed) = (3*yes > 2*total) ? (true, true) : ((3*no > total) ? (true, false) : (false, false));
        } else if (model == VoteCountModel.Other) {
            //
        }
        return (completed, passed);
    }

    function _transit(ProposalState state) private inline {
        _state.state = state;
        IInfoCenter(_deployer).onStateUpdate{value: 0.2 ton, bounce: true}(state);
    }

    function _wrapUp() private {
        (bool completed, bool passed) = (false, false);
        if (now > _info.end) {
            completed = true;
            passed = _calculateVotes(_state.votesFor, _state.votesAgainst, _info.totalVotes, _voteCountModel);
        } else {
            (completed, passed) = _tryEarlyComplete(
                _state.votesFor, _state.votesAgainst, _info.totalVotes, _voteCountModel);
        }

        if (completed) {
            _transit(ProposalState.Ended);
            this.finalize{value: DEF_COMPUTE_VALUE}(passed);
        }
    }

    function queryStatus() external override {
        IPadawan(msg.sender).updateStatus(_info.id, _state.state);
    }

    /*
    *   Get Methods
    */

    function getId() public view returns (uint256 id) {
        id = tvm.pubkey();
    }

    function getVotingResults() public view returns (VotingResults vr) {
        require(_state.state > ProposalState.Ended);
        vr = _results;
    }

    function getInfo() public view returns (ProposalInfo info) {
        info = _info;
    }

    function getCurrentVotes() public view returns (uint32 votesFor, uint32 votesAgainst) {
        return (_state.votesFor, _state.votesAgainst);
    }

    function getProposalData() public view returns (ProposalInfo info, ProposalStatus status) {
        return (_info, _state);
    }

}
