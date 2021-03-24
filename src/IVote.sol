pragma ton-solidity >= 0.36.0;

enum VoteType { Undefined, For, Abstain, Reject }

/* Incoming vote */
struct Evaluation {
    uint8 entryId;      // entry being evaluated
    VoteType voteType;  // kind of vote: for, abstain or reject
    uint8 score;        // a mark from 1 to 10, 0 for abstain or reject
    string comment;     // juror's evaluation in the text form
}

struct HiddenEvaluation {
    uint8 entryId;
    uint hash;
    bytes comment;
    bytes score;
    bytes voteType;
}

interface IVote {
    function revealVote(Evaluation evaluation) external;
    function recordVote(HiddenEvaluation evaluation) external;
}
