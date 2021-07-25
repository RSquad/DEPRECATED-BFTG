pragma ton-solidity >= 0.42.0;

enum ContestStage {
    Undefined,
    New,
    Underway,
    Voting,
    Reveal,
    Rank,
    Reward,
    Finish,
    Last
}

struct Submission {
  uint32 id;
  address addrPartisipant;
  string forumLink;
  string fileLink;
  uint hash;
  uint32 createdAt;
}

struct HiddenVote {
    uint32 submissionId;
    uint hash;
    bytes hiddenComment;
    bytes hiddenScore;
}

struct RevealVote {
    uint32 submissionId;
    uint8 score;
    bytes comment;
}

struct Vote {
    address addrJury;
    uint8 score;
    bytes comment;
}

struct Reward {
    uint128 total;
    uint128 paid;
}