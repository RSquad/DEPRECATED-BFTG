pragma ton-solidity >= 0.36.0;

contract Voting {
    enum VoteType { Undefined, For, Abstain, Reject }

    struct Evaluation {
        uint8 entryId;
        VoteType voteType;
        uint8 score;
        string comment;
    }
    struct Mark {
        VoteType vt;
        uint8 score;
    }
    struct Comment {   
        string comment;
        uint32 ts;
    }
    struct HiddenVote {   
        uint8 entryId;
        uint hash;
        string encoded;
    }
    mapping (uint16 => Mark) public _marks;
    mapping (uint16 => Comment) public _comments;
    mapping (uint16 => HiddenVote) public _hiddenVotes;

    function voteHidden(HiddenVote hiddenVote) external {
        tvm.accept();
        // Здесь нужно правильные айдишники использовать. Сделал энтри для примера
        _hiddenVotes.add(hiddenVote.entryId, hiddenVote);
    }

    function revealHiddenVote(Evaluation evaluation) external {
        tvm.accept();
        uint hash = hashEvaluation(evaluation);
        if(hash == _hiddenVotes[evaluation.entryId].hash) {
            // Здесь нужно правильные айдишники использовать. Сделал энтри для примера
            _marks.add(evaluation.entryId, Mark(evaluation.voteType, _validateScore(evaluation)));
            _comments.add(evaluation.entryId, Comment(evaluation.comment, uint32(now)));
        }
    }

    function _validateScore(Evaluation evaluation) private pure returns (uint8 score) {
        score = evaluation.score;
        if (evaluation.voteType == VoteType.For) {
            if (score == 0) {
                score = 1;
            } else if (score > 10) {
                score = 10;
            }
        } else {
            score = 0;
        }
    }

    function hashEvaluation(Evaluation evaluation) public pure returns (uint hash) {
        TvmBuilder builder;
        builder.store(evaluation.entryId, uint8(evaluation.voteType), evaluation.score, evaluation.comment);
        TvmCell cell = builder.toCell();
        hash = tvm.hash(cell);
    }
}