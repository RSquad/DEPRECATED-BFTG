pragma ton-solidity >= 0.36.0;

import "../Glossary.sol";

struct ProposalResults {
    uint32 id;
    bool passed;
    uint128 votesFor;
    uint128 votesAgainst;
    uint256 totalVotes;
    VoteCountModel model;
    uint32 ts;
}

struct ProposalInfo {
    uint32 start;
    uint32 end;
    string title;
    string proposalType;
    TvmCell specific;
    ProposalState state;
    uint128 votesFor;
    uint128 votesAgainst;
    uint128 totalVotes;
}

interface IProposal {
    function estimateVotes(uint128 votes, bool choice) external;
    function vote(address padawanOwner, bool choice, uint128 votes) external;
    
    function queryStatus() external;
    function wrapUp() external;
    function getCurrentVotes() external view returns (uint128 votesFor, uint128 votesAgainst);
    function getAll() external view returns (ProposalInfo info);
}

interface IEstimateVotesCallback {
    function onEstimateVotes(uint128 cost, uint128 votePrice, address voteProvider, uint128 votes, bool choice) external;
}