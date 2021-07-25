pragma ton-solidity >= 0.42.0;

import "../Proposal.sol";

interface ISmvRoot {
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
    ) external;
}
