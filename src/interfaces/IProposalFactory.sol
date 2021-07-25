pragma ton-solidity >= 0.45.0;

struct ContestProposalSpecific {
    uint32 duration;
    string description;
}
struct AddMemberProposalSpecific {
    string nonce;
    address member;
}
struct RemoveMemberProposalSpecific {
    string nonce;
    address member;
}


interface IProposalFactory {
    function deployContestProposal(
        address client,
        string title,
        address group,
        ContestProposalSpecific specific
    ) external;
}