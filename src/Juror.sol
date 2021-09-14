pragma ton-solidity >= 0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;
import "Base.sol";
import "IVote.sol";

contract Juror is Base {

    function recordVote(address contest, HiddenEvaluation hiddenVote) external pure signed {
        IVote(contest).recordVote{value: 0.2 ton, flag: 1}(hiddenVote);
    }

    function revealVote(address contest, Evaluation evaluation) external pure signed {
        IVote(contest).revealVote{value: 0.2 ton, flag: 1}(evaluation);
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

    /* Combine juror and entry IDs to index the mark */
    function _markId(uint8 jurorId, uint8 entryId) private inline pure returns (uint16 markId) {
        markId = uint16(jurorId * (1 << 8) + entryId);
    }

    function _recordVote(uint8 jurorId, Evaluation evaluation) private pure inline {
    }

}

