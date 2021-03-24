pragma ton-solidity >= 0.36.0;
import "Glossary.sol";
import "IVote.sol";
/* General contest information */
struct ContestInfo {
    uint32 gid;         // Contract global ID
    string title;       // Title of the contract
    string link;        // Link to the document location
    uint hashCode;      // Hash of the proposal
}

struct Expert {
    uint32 id;
    string tag;
    ReqStatus status;
    uint32 rating;
    uint32 rate;
    uint key;           // Juror's public key
    address addr;       // Juror's address
}

/* Timeline of the contest */
struct ContestTimeline {
    uint32 createdAt;     // Contest contract creation
    uint32 contestStarts; // Accepts contest entries
    uint32 contestEnds;   // End of the acceptance period
    uint32 votingEnds;    // End of the voting period
}

struct ContestSetup {
    uint32 id;
    uint32 proposalId;
    uint16 tag;
    uint8 groupId;
    uint128 budget;
    uint32 createdAt;
    string[] tags;
}

struct ContestStage {
    uint32 mask;
    uint32 notifyAt;
}

struct Brief {
    uint32 id;
    address addr;
    Stage stage;
    string[] tags;
    uint32 nextAt;
}

/* Individual contest entry */
struct ContenderInfo {
    address addr;       // Rewards go there
    string forumLink;   // forum post link
    string fileLink;    // PDF document link
    uint hashCode;          // hash of the PDF
    address contact;    // Surf address contact (optional)
    uint32 appliedAt;   // Timestamp of the entry arrival
}

struct Stats {
    uint8 id;           // Entry or juror id
    uint16 totalRating; // Sum of all marks given
    uint16 avgRating;   // Sum of all marks multiplied by 100 and divided by the number of votes for
    uint8 votesFor;     // Votes "for"
    uint8 abstains;     // Votes "abstain"
    uint8 rejects;      // Votes "reject"
}

// Actively used
struct Mark {
    VoteType vt;
    uint8 score;
}

// Just stored
struct Comment {
    string comment;
    uint32 ts;
}

interface IContestData {

}