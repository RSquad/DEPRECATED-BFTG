pragma ton-solidity >= 0.47.0;

struct ContestProposalSpecific {
    string[] tags;
    uint32 underwayDuration;
    uint128 prizePool;
    string description;
}

interface IProposalFactory {
    function deployContestProposal(
        address client,
        string title,
        address[] whiteList,
        uint128 totalVotes,
        ContestProposalSpecific specific
    ) external;
}