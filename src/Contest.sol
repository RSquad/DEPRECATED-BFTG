pragma ton-solidity >= 0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import "IVote.sol";
import "IJuror.sol";
import "IInfoCenter.sol";
import "IContest.sol";
import "DemiurgeStore.sol";
import "JuryGroup.sol";
import "./interfaces/Upgradable.sol";

contract Contest is IVote, IContest, IJuryGroupCallback, Upgradable {

    /*    Exception codes:   */
    uint16 constant NOT_AUTHORIZED      = 101; // Not authorized to administer contest
    uint16 constant INVALID_JUROR_KEY   = 102; // Message requires a jury member signature
    uint16 constant ALREADY_VOTED       = 103; // This juror has already voted for this entry
    uint16 constant INVALID_ENTRY       = 104; // Entry not found
    uint16 constant CONTEST_CLOSED      = 105; // Contest does not accept entries at this time
    uint16 constant VOTING_CLOSED       = 106; // Votes are not accepted at this time
    uint16 constant REVEAL_CLOSED       = 107; // Vote reveals are not accepted at this time
    uint16 constant DIFFERENT_CALLER    = 111; // Caller is not the contract itself
    uint16 constant NON_NATIVE_CALLER   = 112; // Caller is not the one which deployed it
    uint16 constant RESTRICTED_CALLER   = 113; // Caller is not the contract and not the deployer
    uint16 constant NOT_FINALIZED       = 114; // Final results are not available at this time
    uint16 constant INVALID_TIMELINE    = 120; // Contest end date can't precede contest start date
    uint16 constant INVALID_SETUP       = 121; // Contest has not been started yet
    uint16 constant WRONG_SCORE         = 124; // Mark should be in 1 to 10 range
    uint16 constant ADVANCE_AHEAD       = 130; // Already at this stage or further
    uint16 constant ADVANCE_START       = 131; // Too early to start the contest
    uint16 constant ADVANCE_END         = 132; // Too early to end the contest
    uint16 constant ADVANCE_VOTE_END    = 133; // Too early to end the voting period
    uint16 constant ADVANCE_REVEAL_END  = 134; // Too early to end the reveal period
    uint16 constant NO_CONTEST_PRIZE    = 140; // Not eligible to claim a contest prize
    uint16 constant NO_JUROR_REWARD     = 141; // Not eligible to claim a juror reward
    uint16 constant WRONG_CLAIM_TIME    = 142; // Not the right time to claim rewards
    uint16 constant ALREADY_CLAIMED     = 143; // Reward already claimed
    uint16 constant TOO_POOR_TO_JUDGE   = 145; // Not enough prized funds to become a juror

    /* Contest data */

    ContestInfo _contestInfo;    // Contest reference information
    ContestTimeline _timeline;   // Contest timeline
    ContestSetup _setup;

    address static _deployer;   // Deployer contract
    address _peer;              // Peer contract

    mapping (uint256 => uint8) public _jurors;  // Juror ID by public key
    mapping (Stage => uint32) _actualTimeline;  // Actual timeline of the contest (as opposed to the planned)

    uint16 constant DEFAULT_SCORE_THRESHOLD = 100; // Average score of 1 and below are dismissed by default

    uint32 constant JURY_COEFFICIENT = 5;  // percentage of the contest budget as a jury reward
    uint128 constant DEF_COMPUTE = 2e8;     // default value for computation-heavy operations
    uint128 constant MAX_COMPUTE = 1e9;     // maximal value for computation-heavy operations

    ContenderInfo[] public _entries;        // Entries submitted to compete
    Stage public _stage;                    // Current contest stage

    /* Internal processing of the assessments - broken down into two structures for efficiency */
    mapping (uint16 => Mark) public _marks;
    mapping (uint16 => Comment) public _comments;
    mapping (uint16 => HiddenEvaluation) _hiddens;

    /* Final contest results and jury stats */
    Stats[] public _contestResults;
    Stats[] public _juryStatistics;

    enum PayStatus { Undefined, New, Due, Requested, Sent, Confirmed, Failed, Reserved, Last}

    struct Payout {
        uint8 id;           // Entry or juror id
        uint16 rating;      // Rating (multiplied by 100)
        uint128 reward;     // reward (in nanotons)
        PayStatus status;   // status of the payment
        uint32 updatedAt;   // status update timestamp
    }

    /* Payouts due on the contest completion */
    mapping (address => Payout) public _contestPayouts;
    mapping (address => Payout) public _juryPayouts;

    /*** new options ****/
    uint128 _prizePool;
    uint16 _scoreThreshold = DEFAULT_SCORE_THRESHOLD;

    address[] public _juryAddresses;
    mapping (address => uint8) _jurorList;

    /* Modifiers */

    // Accept messages from this contract only
    modifier mine {
        require(msg.sender == address(this), DIFFERENT_CALLER);
        _;
    }

    // Restricted to the messages from deployer or from the contract itself
    modifier restricted {
        require(msg.sender == address(this) || msg.sender == _deployer, RESTRICTED_CALLER);
        _;
    }

    // Can be called only after contest results have been finalized
    modifier finals {
        require(_stage >= Stage.Finalize, NOT_FINALIZED);
        _;
    }

    /* Contest setup */
    TvmCell public _imageJuryGroup;
    mapping(address => bool) public _tagsPendings;
    mapping(address => Member) public _juryMembers;

    constructor(address store, ContestInfo contestInfo, ContestTimeline contestTimeline, ContestSetup setup) public {
        _contestInfo = contestInfo;
        _timeline = _computeTimeline(contestTimeline);
        _setup = setup;
        _stage = Stage.Setup;
        IInfoCenter(_deployer).onContestDeploy{value: DEF_COMPUTE}(contestInfo.gid);
        DemiurgeStore(store).queryImage{value: 0.2 ton, bounce: true}(ContractType.JuryGroup);
    }

    function _computeTimeline(ContestTimeline ctl) private pure returns (ContestTimeline timeline) {
        /* Old school */
//        timeline = ctl;
        /* New way */
        timeline.createdAt = ctl.createdAt;     //  Preserve the creation date
        timeline.contestStarts = uint32(now);   // Start ASAP
        timeline.contestEnds = timeline.contestStarts + ctl.contestEnds - ctl.contestStarts;    // shift the start moment, keep the duration
        timeline.votingEnds = timeline.contestEnds + _computeVotingTime();  // Voting ends as required by contest regulations
    }

    function updateImage(ContractType kind, TvmCell image) external {
        if (kind == ContractType.JuryGroup) {
            _imageJuryGroup = image;
            resolveTags();
        }
    }

    function resolveTags() private {
        for(uint8 i = 0; i < _setup.tags.length; i++) {
            TvmCell state = _buildJuryGroupState(_setup.tags[i]);
            uint256 hashState = tvm.hash(state);
            address addr = address.makeAddrStd(0, hashState);
            _tagsPendings[addr] = true;
            IJuryGroup(addr).getMembers{
                value: 0.5 ton,
                flag: 1,
                bounce: true
            }();
        }
    }

    function getMembersCallback(mapping(address => Member) members) external override {
        require(_tagsPendings.exists(msg.sender), 200);
        delete _tagsPendings[msg.sender];
        for((, Member member): members) {
            if(member.balance > 0) {
                _juryMembers[member.addr] = member;
            }
        }
        if(_tagsPendings.empty()) {
            calcJuryAddresses();
        }
    }

    onBounce(TvmSlice) external {
        if(_tagsPendings.exists(msg.sender)) {
            delete _tagsPendings[msg.sender];
            if(_tagsPendings.empty()) {
                calcJuryAddresses();
            }
        }
    }

    function calcJuryAddresses() private {
        // TODO: improve the algorithm of selection of jury members
        address[] juryAddresses;
        uint8 i;
        for((, Member member): _juryMembers) {
            juryAddresses.push(member.addr);
            _jurorList[member.addr] = i++;
        }
        _juryAddresses = juryAddresses;
        _timeline.contestStarts = uint32(now);
        advanceTo(Stage.Contend);
    }

    function setJuryAddresses(address[] juryAddresses) external restricted {
        for (uint8 i = 0; i < juryAddresses.length; i++) {
            _jurorList[juryAddresses[i]] = i;
        }
        _juryAddresses = juryAddresses;
        _timeline.contestStarts = uint32(now);
        advanceTo(Stage.Contend);
    }

    function _next(Stage s) private inline pure returns (Stage) {
        if (s == Stage.Undefined) {
            return Stage.Setup;
        } else if (s == Stage.Setup) {
            return Stage.Contend;
        } else if (s == Stage.Contend) {
            return Stage.Vote;
        } else if (s == Stage.Vote) {
            return Stage.Reveal;
        } else if (s == Stage.Reveal) {
            return Stage.Finalize;
        } else if (s == Stage.Finalize) {
            return Stage.Rank;
        } else if (s == Stage.Rank) {
            return Stage.Reward;
        } else if (s == Stage.Reward) {
            return Stage.Finish;
        } else if (s == Stage.Finish) {
            return Stage.Finish;
        } else if (s == Stage.Reserve) {
            return Stage.Last;
        }
    }

    function next() external override view {
        tvm.accept(); // remove this before release
        this.advanceTo{value: MAX_COMPUTE}(_next(_stage));
    }

    /* To be called to advance to the next stage, provided the requirements are met */
    // TODO: temporarily removed restricted, since the callback
    // from the JuryGroup cannot be reached
    function advanceTo(Stage s) public /* restricted */{
        require(_stage < s, ADVANCE_AHEAD);

        if (s == Stage.Contend) {
            require(now >= _timeline.contestStarts, ADVANCE_START);
        } else if (s == Stage.Vote) {
            require(now >= _timeline.contestEnds, ADVANCE_END);
        } else if (s == Stage.Reveal) {
            // Commented for debug purposes only
//            require(now >= _timeline.votingEnds, ADVANCE_VOTE_END);
        } else if (s == Stage.Finalize) {
            require(now >= _timeline.votingEnds + 1 days, ADVANCE_REVEAL_END);
            this.finalizeResults{value: MAX_COMPUTE}();
        } else if (s == Stage.Rank) {
            this.rank{value: MAX_COMPUTE}();
        } else if (s == Stage.Reserve) {
            s = Stage.Undefined;
        }
        _stage = s;
        _actualTimeline[s] = uint32(now);
        IInfoCenter(_deployer).stateUpdated{value: DEF_COMPUTE}(s);
    }

    /* Can be computed using any complicated formula of your choice */
    function _computeVotingTime() private pure returns (uint32) {
        return 1 weeks;
    }

    /* Record contest entries submitted by contenders */
    function submit(address participant, string forumLink, string fileLink, uint hash, address contact) external override {
        require(_stage == Stage.Contend, CONTEST_CLOSED);
        tvm.accept();
        _entries.push(ContenderInfo(participant, forumLink, fileLink, hash, contact, uint32(now)));
    }

    /* Combine juror and entry IDs to index the mark */
    function _markId(uint8 jurorId, uint8 entryId) private inline pure returns (uint16 markId) {
        markId = uint16(jurorId * (1 << 8) + entryId);
    }

    /* Break down combined ID into components - juror and entry IDs */
    function _jurorEntryIds(uint16 markId) private pure returns (uint8 jurorId, uint8 entryId) {
        jurorId = uint8(markId >> 8);      // 8 upper bits
        entryId = uint8(markId & 0xFF);    // 8 lower bits
    }

    /* Accept voting messages only with a current jury member signature, and only when the time is right */
    function _checkVote() private inline view returns (uint8) {
        require(_stage == Stage.Vote, VOTING_CLOSED);
        uint8 jurorId = _jurors.at(msg.pubkey()); // Check if there's a juror with this public key
        tvm.accept();
        return jurorId;
    }

    /* Enforce score being in range 1 to 10 for regular votes and 0 for abstains and rejects */
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

    /* store a single vote */
    function _recordVote(uint8 jurorId, Evaluation evaluation) private inline {
        uint16 markId = _markId(jurorId, evaluation.entryId);
        _marks.add(markId, Mark(evaluation.voteType, _validateScore(evaluation)));
        _comments.add(markId, Comment(evaluation.comment, uint32(now)));
    }

    function _recordHiddenVote(uint8 jurorId, HiddenEvaluation evaluation) private inline {
        uint16 markId = _markId(jurorId, evaluation.entryId);
        _hiddens.add(markId, evaluation);
    }

    /* Process mass votes */
    function voteAll(Evaluation[] evaluations) external {
        uint8 jurorId = _checkVote();
        for (uint8 i = 0; i < evaluations.length; i++) {
            _recordVote(jurorId, evaluations[i]);
        }
    }

    /* Process a single vote */
    function vote(Evaluation evaluation) external {
        uint8 jurorId = _checkVote(); // Check if there's a juror with this public key
        _recordVote(jurorId, evaluation);
    }

    function revealVote(Evaluation evaluation) external override {
        require(_stage == Stage.Reveal, REVEAL_CLOSED);
        optional(uint8) jurorIdOpt = _jurorList.fetch(msg.sender);
        require(jurorIdOpt.hasValue(), 400);
        uint8 jurorId = jurorIdOpt.get();
        _recordVote(jurorId, evaluation);
    }

    function revealVotes(Evaluation[] evaluations) external {
        require(_stage == Stage.Reveal, REVEAL_CLOSED);
        optional(uint8) jurorIdOpt = _jurorList.fetch(msg.sender);
        require(jurorIdOpt.hasValue(), 400);
        uint8 jurorId = jurorIdOpt.get();
        for (uint8 i = 0; i < evaluations.length; i++) {
            _recordVote(jurorId, evaluations[i]);
        }
    }

    function recordVote(HiddenEvaluation evaluation) external override {
        require(_stage == Stage.Vote, VOTING_CLOSED);
        optional(uint8) jurorIdOpt = _jurorList.fetch(msg.sender);
        require(jurorIdOpt.hasValue(), 400);
        uint8 jurorId = jurorIdOpt.get();
        _recordHiddenVote(jurorId, evaluation);
    }

    /* Process the results and form the final set of raw data */
    function finalizeResults() external mine {
        for (uint8 i = 0; i < _entries.length; i++) {
            /* compute stats necessary to evaluate the entries based on the contest rules */
            _contestResults.push(_computeStatsFor(i, true));
        }
        for (uint8 i = 0; i < _juryAddresses.length; i++) {
            /* compute jury activity stats */
            _juryStatistics.push(_computeStatsFor(i, false));
        }
        advanceTo(Stage.Rank);
    }

    /* Common routine for computing stats for entries and jurors */
    function _computeStatsFor(uint8 id, bool isEntry) private view returns (Stats stats) {
        uint16 totalRating;
        uint8 votesFor;
        uint8 abstains;
        uint8 rejects;
        uint16 avgRating;

        uint8 cap = isEntry ? uint8(_juryAddresses.length) : uint8(_entries.length);

        for (uint8 i = 0; i < cap; i++) {
            uint16 mid = isEntry ? _markId(i, id) : _markId(id, i);
            if (_marks.exists(mid)) {
                Mark m = _marks[mid];
                if (m.vt == VoteType.For) {
                    votesFor++;
                    totalRating += m.score;
                } else if (m.vt == VoteType.Reject) {
                    rejects++;
                } else if (m.vt == VoteType.Abstain) {
                    abstains++;
                }
            }
        }
        avgRating = votesFor > 0 ? uint16(totalRating * 100 / votesFor) : 0;
        stats = Stats(id, totalRating, avgRating, votesFor, abstains, rejects);
    }

    /*
     * Assess the entries quality and the jurors' performance according to the specified metrics and criteria
     */
    function rank() external mine {
        uint128 contestBudget;
        (_contestPayouts, contestBudget) = _rankContenders();
        _juryPayouts = _rankJurors(contestBudget);
        advanceTo(Stage.Reward);
    }

    /* Rank contenders according to the evaluations submitted by jury */
    function _rankContenders() private inline view returns (mapping (address => Payout) contestPayouts, uint128 contestBudget) {
        mapping (uint24 => bool) scores;
        uint8 ns;
        // Sort entries from highest average rating to lowest
        for (uint8 i = 0; i < _entries.length; i++) {
            Stats st = _contestResults[i];
            /* 50%+ of jurors rejects disqualifies */
            if (st.rejects <= st.votesFor + st.abstains) {
                uint24 key = uint24(st.avgRating) * (1 << 8) + i;
                if (st.avgRating >= _scoreThreshold) {
                    scores[key] = true;
                    ns++;
                }
            }
        }

        /*
         * Compose a payout table according to the formula
         */
        uint128 pp = _prizePool;
        optional(uint24, bool) maxScore = scores.max();
        (uint24 key,) = maxScore.get();
        uint16 hs = uint16(key >> 8);
        uint16 base = hs * 2 / 3 / 10;
        uint32 square = base * base;
        uint32 sub = hs * 100 - square;
        uint32 denom = ns * sub;
        uint128 pv = pp / denom;

        uint128 prize;

        optional(uint24, bool) curScore = maxScore;
        uint8 k = 0;
        while (curScore.hasValue()) {
            (key,) = curScore.get();
            uint16 rating = uint16(key >> 8);
            uint8 entryId = uint8(key & 0xFF);
            prize = rating * pv * 1e7;
            contestPayouts[_entries[entryId].addr] = Payout(entryId, rating, prize, PayStatus.New, uint32(now));
            contestBudget += prize;
            k++;
            curScore = scores.prev(key);
        }
        // k == ns
    }

    /* Rank jurors according to their contribution to the assessment. Compute due payouts based on the specified formulae */
    function _rankJurors(uint128 contestBudget) private inline view returns (mapping (address => Payout) juryPayouts) {

        /* calculate jury performance metrics */
        mapping (uint24 => uint8) scores;
        uint16 totalVotes;
        uint8 ns = 0;
        for (uint8 i = 0; i < _juryAddresses.length; i++) {
            Stats st = _juryStatistics[i];
            /* Mandatory contribution as a sum of votes for and rejects. Affects payout sum */
            uint8 contribution = _jurorContribution(st);
            if (contribution > 0) {
                uint16 rating = uint16(contribution);
                uint24 key = uint24(rating * (1 << 8) + i);
                totalVotes += contribution;
                scores[key] = contribution;
                ns++;
            }
        }

        uint128 votePrice = contestBudget * JURY_COEFFICIENT / totalVotes;

        /*
         * Compose a payout table based on participation metric
         */
        optional(uint24, uint8) curScore = scores.max();
        while (curScore.hasValue()) {
            (uint24 key, uint8 done) = curScore.get();
            uint16 rating = uint16(key >> 8);
            uint8 jurorId = uint8(key & 0xFF);
            uint128 reward = votePrice * done / 100;
            juryPayouts[_juryAddresses[jurorId]] = Payout(jurorId, rating, reward, PayStatus.New, uint32(now));
            curScore = scores.prev(key);
        }

    }

    /* Assess juror's contribution */
    function _jurorContribution(Stats st) private inline view returns (uint8) {
        uint8 done = st.votesFor + st.rejects;
        /* Half of the meaningful votes makes eligible for rewards */
        return (done >= _entries.length / 2) ? done : 0;
    }

    function _buildJuryGroupState(string tag) internal view returns (TvmCell) {
        TvmCell code = _imageJuryGroup.toSlice().loadRef();
        return tvm.buildStateInit({
            contr: JuryGroup,
            varInit: {_tag: tag, _deployer: _deployer},
            code: code
        });
    }

    function _due(bool isContender) private view returns (uint128) {
        require(_stage == Stage.Reward, WRONG_CLAIM_TIME);
        address from = msg.sender;
        Payout due = isContender ? _contestPayouts[from] : _juryPayouts[from];
        require (due.status <= PayStatus.Sent, ALREADY_CLAIMED);
        return due.reward;
    }

    function claimContestReward() external override {
        address from = msg.sender;
        from.transfer(_due(true), true, 0);
        _contestPayouts[from].status = PayStatus.Sent;
        _contestPayouts[from].updatedAt = uint32(now);
    }

    function claimJurorReward() external override {
        address from = msg.sender;
        from.transfer(_due(false), true, 0);
        _juryPayouts[from].status = PayStatus.Sent;
        _juryPayouts[from].updatedAt = uint32(now);
    }

    function claimContestRewardAndBecomeJuror(uint128[] amount, string[] tag, uint pk) external override {
        address from = msg.sender;
        uint128 total = _due(true);
        uint8 i = 0;
        for (uint128 val: amount) {
            require(val < total, TOO_POOR_TO_JUDGE);
            IInfoCenter(_deployer).registerJuryMember{value: val}(tag[i], pk);
            total -= val;
        }
        from.transfer(total, true, 0);
        _contestPayouts[from].status = PayStatus.Sent;
        _contestPayouts[from].updatedAt = uint32(now);
    }

    /* Stats for an entry */
    function getEntryStats(uint8 entryId) public view returns (Stats entryStats) {
        entryStats = _computeStatsFor(entryId, true);
    }

    /* Stats for a juror */
    function getJurorStats(uint8 jurorId) public view returns (Stats jurorStats) {
        jurorStats = _computeStatsFor(jurorId, false);
    }

    /*
     * Overall contest statistics:
     *      total points awarded by all jurors combined
     *      total number of votes
     *      average score (multiplied by 100)
     *      number of entries submitted
     *      unique jurors voted
     */
    function contestStatistics() public view returns (uint16 pointsAwarded, uint16 totalVotes, uint16 avgScore, uint8 entries, uint8 jurorsVoted) {
        uint16 totalVotesFor;
        entries = uint8(_entries.length);

        for (uint8 i = 0; i < _entries.length; i++) {
            Stats entryStats = _computeStatsFor(i, true);
            pointsAwarded += entryStats.totalRating;
            totalVotesFor += entryStats.votesFor;
            totalVotes += entryStats.votesFor + entryStats.abstains + entryStats.rejects;
        }

        for (uint8 i = 0; i < _juryAddresses.length; i++) {
            optional(uint16, Mark) nextPair = _marks.nextOrEq(_markId(i, 0));
            if (nextPair.hasValue()) {
                (uint16 nextKey, ) = nextPair.get();
                if (nextKey < _markId(i + 1, 0)) {
                    jurorsVoted++;
                }
            }
        }

        avgScore = totalVotesFor > 0 ? uint16(pointsAwarded * 100 / totalVotesFor) : 0;
    }

    /* Snapshot of the contest data */
    function getCurrentData() external override view returns (
        ContenderInfo[] info, address[] juryAddresses, Stats[] allStats, mapping (uint16 => Mark) marks, mapping (uint16 => Comment) comments, mapping (uint16 => HiddenEvaluation) hiddens
    ) {
        info = _entries;
        juryAddresses = _juryAddresses;
        for (uint8 i = 0; i < _entries.length; i++) {
            allStats.push(_computeStatsFor(i, true));
        }
        marks = _marks;
        comments = _comments;
        hiddens = _hiddens;
    }

    /* Resulting contest data */
    function getFinalData() public view returns (Stats[] contestResults, Stats[] juryStatistics, mapping (address => Payout) contestPayouts,
                mapping (address => Payout) juryPayouts, ContestTimeline timeline) {
        contestResults = _contestResults;
        juryStatistics = _juryStatistics;
        contestPayouts = _contestPayouts;
        juryPayouts = _juryPayouts;
        timeline = _timeline;
    }

    function getJurorId(address addr) external view override returns (uint8 jurorId) {
        jurorId = _jurorList[addr];
    }

    function getContestInfo() external override returns (ContestInfo contestInfo) {
        contestInfo = _contestInfo;
    }

    function getContestTimeline() external override returns (ContestTimeline timeline) {
        timeline = _timeline;
    }

    function getContestSetup() external override returns (ContestSetup setup) {
        setup = _setup;
    }

    function getContest() external view override returns (
        ContestInfo contestInfo, ContestTimeline timeline, ContestSetup setup, Stage stage
    ) {
        contestInfo = _contestInfo;
        timeline = _timeline;
        setup = _setup;
        stage = _stage;
    }

    function onCodeUpgrade() internal override {
        tvm.resetStorage();
    }
}
