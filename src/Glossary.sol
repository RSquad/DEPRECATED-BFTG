pragma ton-solidity >= 0.36.0;

enum VoteCountModel {
    Undefined,
    Majority,
    SoftMajority,
    SuperMajority,
    Other,
    Reserved,
    Last
}

enum ProposalType {
    Undefined,
    SetCode,
    Reserve,
    SetOwner,
    SetRootOwner
}

enum ProposalState {
    Undefined,
    New,
    OnVoting,
    Ended,
    Passed,
    NotPassed,
    Finalized,
    Distributed,
    Reserved,
    Last
}