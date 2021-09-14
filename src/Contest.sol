pragma ton-solidity >= 0.47.0;

import './Checks.sol';
import './interfaces/IContest.sol';
import './interfaces/IBftgRoot.sol';
import './interfaces/IBftgRootStore.sol';
import './resolvers/JuryGroupResolver.sol';

contract Contest is JuryGroupResolver, IJuryGroupCallback, IBftgRootStoreCallback, Checks {

/* -------------------------------------------------------------------------- */
/*                                ANCHOR Checks                               */
/* -------------------------------------------------------------------------- */

    uint8 constant CHECK_JURY_GROUP_CODE = 1;

    function _createChecks() private inline {
        _checkList = CHECK_JURY_GROUP_CODE;
    }

/* -------------------------------------------------------------------------- */
/*                                 ANCHOR Init                                */
/* -------------------------------------------------------------------------- */

    uint32 static public _id;
    address public _addrBftgRoot;

    string[] public _tags;
    mapping(address => bool) _tagsPendings;

    mapping(address => Member) public _jury;
    uint128 _maxJuryStake;
    uint32 public _juryCount;
    uint128 public _juryStake;

    string public _description;
    uint128 public _prizePool;
    uint32 public _underwayDuration;
    uint32 public _underwayEnds;
    
    uint8 constant PERIOD_COEF = 3;

    constructor(
        address addrBftgRootStore,
        string[] tags,
        uint128 prizePool,
        uint32 underwayDuration,
        string description
    ) public {
        optional(TvmCell) oSalt = tvm.codeSalt(tvm.code());
        require(oSalt.hasValue());
        (address addrBftgRoot) = oSalt.get().toSlice().decode(address);
        require(msg.sender == addrBftgRoot);
        _addrBftgRoot = addrBftgRoot;

        _description = description;
        _tags = tags;
        _stage = ContestStage.New;
        _prizePool = prizePool;
        _underwayDuration = underwayDuration;
        IBftgRootStore(addrBftgRootStore).queryCode
            {value: 0.2 ton, bounce: true}
            (ContractCode.JuryGroup);
    }

    bool public _inited = false;

    function _onInit() private {
        if(_isCheckListEmpty() && !_inited) {
            _inited = true;
            for(uint8 i = 0; i < _tags.length; i++) {
                TvmCell state = _buildJuryGroupState(_tags[i], _addrBftgRoot);
                uint256 hashState = tvm.hash(state);
                address addrJuryGroup = address.makeAddrStd(0, hashState);
                _tagsPendings[addrJuryGroup] = true;
                IJuryGroup(addrJuryGroup).getMembers{
                    value: 0.2 ton,
                    flag: 1,
                    bounce: true
                }();
            }
        }
    }

    onBounce(TvmSlice) external {
        if(_tagsPendings.exists(msg.sender)) {
            delete _tagsPendings[msg.sender];
            if(_tagsPendings.empty()) {
                _changeStage(ContestStage.Underway);
            }
        }
    }

    function updateCode(ContractCode kind, TvmCell code) external override {
        if (kind == ContractCode.JuryGroup) {
            _codeJuryGroup = code;
            _passCheck(CHECK_JURY_GROUP_CODE);
        }
        _onInit();
    }

    function updateAddr(ContractAddr kind, address addr) external override {}

/* -------------------------------------------------------------------------- */
/*                               ANCHOR Members                               */
/* -------------------------------------------------------------------------- */

    function getMembersCallback(mapping(address => Member) members) external override {
        require(_tagsPendings.exists(msg.sender), 102);
        delete _tagsPendings[msg.sender];
        for((, Member member): members) {
            if(member.balance > 0) {
                if(member.balance >= _maxJuryStake) {
                    _maxJuryStake = member.balance;
                    uint128 threshold = member.balance - uint128(math.muldivr(member.balance, 9, 10));
                    optional(address, Member) oJuryMember = _jury.min();
                    while (oJuryMember.hasValue()) {
                        (address addr, Member member_) = oJuryMember.get();
                        if(member_.balance < threshold) {
                            delete _jury[addr];
                        }
                    }
                    _juryStake += member.balance;
                    _juryCount += 1;
                    _jury[member.addr] = member;
                } else {
                    uint128 threshold = _maxJuryStake - uint128(math.muldivr(_maxJuryStake, 9, 10));
                    if(member.balance >= threshold) {
                        _juryStake += member.balance;
                        _juryCount += 1;
                        _jury[member.addr] = member;
                    }
                }
            }
        }
        if(_tagsPendings.empty()) {
            _changeStage(ContestStage.Underway);
        }
    }

/* -------------------------------------------------------------------------- */
/*                                ANCHOR Stages                               */
/* -------------------------------------------------------------------------- */

    ContestStage public _stage;

    function _changeStage(ContestStage stage) private inline returns (ContestStage) {
        // require(_stage < stage, 103);
        if (stage == ContestStage.Underway) {
            _underwayEnds = uint32(now) + _underwayDuration;
        }
        _stage = stage;
    }

/* -------------------------------------------------------------------------- */
/*                            ANCHOR Underway stage                           */
/* -------------------------------------------------------------------------- */

    mapping(uint32 => Submission) public _submissions;
    uint32 _submissionsCounter;

    function submit(address addrPartisipant, string forumLink, string fileLink, uint hash) external {
        require(_stage == ContestStage.Underway, 104);
        _submissions[_submissionsCounter] = (Submission(_submissionsCounter, addrPartisipant, forumLink, fileLink, hash, uint32(now)));
        _submissionsCounter += 1;
        msg.sender.transfer(0, true, 64);
    }

/* -------------------------------------------------------------------------- */
/*                             ANCHOR Voting stage                            */
/* -------------------------------------------------------------------------- */

    mapping(address => mapping(uint32 => HiddenVote)) public _juryHiddenVotes;

    function vote(HiddenVote[] hiddenVotes) external {
        require(_stage == ContestStage.Voting, 104);
        require(_jury.exists(msg.sender), 105);
        for(uint8 i = 0; i < hiddenVotes.length; i++) {
            if(!_juryHiddenVotes[msg.sender].exists(hiddenVotes[i].submissionId)) {
                _juryHiddenVotes[msg.sender][hiddenVotes[i].submissionId] = hiddenVotes[i];
            }
        }
        msg.sender.transfer(0, true, 64);
    }

    function getHiddenVotesByAddress(address juryAddr) public view returns (mapping(uint32 => HiddenVote) hiddenVotes) {
        hiddenVotes = _juryHiddenVotes[juryAddr];
    }

/* -------------------------------------------------------------------------- */
/*                             ANCHOR Reveal stage                            */
/* -------------------------------------------------------------------------- */

    mapping(uint32 => Vote[]) public _submissionVotes;

    function reveal(RevealVote[] revealVotes) external {
        require(_stage == ContestStage.Reveal, 104);
        require(_jury.exists(msg.sender), 105);
        for(uint8 i = 0; i < revealVotes.length; i++) {
            uint oldHash = _juryHiddenVotes[msg.sender][revealVotes[i].submissionId].hash;
            uint newHash = hashVote(revealVotes[i].submissionId, revealVotes[i].score, revealVotes[i].comment);
            require(oldHash == newHash, 106);
            _submissionVotes[revealVotes[i].submissionId].push(Vote(msg.sender, revealVotes[i].score, revealVotes[i].comment));
        }
        msg.sender.transfer(0, true, 64);
    }

/* -------------------------------------------------------------------------- */
/*                            ANCHOR Slashing stage                           */
/* -------------------------------------------------------------------------- */


    mapping(address => uint128) _fishermen;
    mapping(uint32 => mapping(address => uint128)) _blames;

    function blame(uint32 submissionId, address addrJury) public {
        require(msg.sender != address(0));
        require(msg.value > 10 ton);
        _fishermen[msg.sender] += msg.value;
        _blames[submissionId][addrJury] += msg.value;
        if(_blames[submissionId][addrJury] >= _prizePool) {
            _slashing(submissionId, addrJury);
        }
    }

    function _slashing(uint32 submissionId, address addrJury) private {
        Vote[] sv = _submissionVotes[submissionId];
        uint8 sum;
        uint8 upper;
        uint8 mean;
        uint8 lower;
        uint8 score;
        for(uint8 i = 0; i < sv.length; i++) {
            if(sv[i].addrJury == addrJury) {
                score = sv[i].score;
            } else {
                sum += sv[i].score;
            }
        }
        mean = uint8(math.divr(sum, sv.length - 1));
        upper = mean + PERIOD_COEF > 10 ? 10 : mean + PERIOD_COEF;
        lower = mean - PERIOD_COEF < 0 ? 0 : mean - PERIOD_COEF;
        if(score < lower || score > upper) {
            optional(uint32, Vote[]) oSubmissionVotes = _submissionVotes.min();
            while (oSubmissionVotes.hasValue()) {
                (uint32 id, Vote[] submissionVotes) = oSubmissionVotes.get();
                for(uint8 i = 0; i < submissionVotes.length; i++) {
                    if(submissionVotes[i].addrJury == addrJury) {
                        delete _submissionVotes[submissionId][i];
                    }
                }
                oSubmissionVotes = _submissionVotes.next(id);
            }
        }
    }

/* -------------------------------------------------------------------------- */
/*                              ANCHOR Rank stage                             */
/* -------------------------------------------------------------------------- */

    uint128 _pointValue;
    mapping(address => Reward) public _rewards;

    function calcRewards() public {
        _calcPointValue();
        optional(uint32, Vote[]) optSubmissionVotes = _submissionVotes.min();
        while (optSubmissionVotes.hasValue()) {
            (uint32 id, Vote[] submissionVotes) = optSubmissionVotes.get();
            for(uint8 i = 0; i < submissionVotes.length; i++) {
                _rewards[_submissions[id].addrPartisipant].total += submissionVotes[i].score * _pointValue;
            }
            optSubmissionVotes = _submissionVotes.next(id);
        }
        _changeStage(ContestStage.Slashing);
    }

    function _calcPointValue() private inline {
        // TODO: change the formula
        _pointValue = _prizePool / (_submissionsCounter * 10);
    }

/* -------------------------------------------------------------------------- */
/*                             ANCHOR Reward stage                            */
/* -------------------------------------------------------------------------- */

    function claimPartisipantReward(uint128 amount) public {
        require(_rewards.exists(msg.sender), 107);
        require(_rewards[msg.sender].total - _rewards[msg.sender].paid >= amount, 108);
        _rewards[msg.sender].paid += amount;
        msg.sender.transfer(amount, true, 1);
    }

    function stakePartisipantReward(uint128 amount, string tag, address addrJury) public {
        require(_rewards.exists(msg.sender), 107);
        require(_rewards[msg.sender].total - _rewards[msg.sender].paid >= amount, 108);
        bool isTagExists = false;
        for(uint8 i = 0; i < _tags.length; i++) {
            if(_tags[i] == tag) isTagExists = true;
        }
        require(isTagExists, 108);
        _rewards[msg.sender].paid += amount;
        IBftgRoot(_addrBftgRoot).registerMemberJuryGroup
            {value: amount, bounce: true, flag: 2}
            (tag, addrJury == address(0) ? msg.sender : addrJury, _id);
        msg.sender.transfer(0, true, 64);
    }

/* -------------------------------------------------------------------------- */
/*                                ANCHOR Crypto                               */
/* -------------------------------------------------------------------------- */

    function hashVote(uint32 submissionId, uint8 score, string comment) public pure returns (uint hash) {
        TvmBuilder builder;
        builder.store(submissionId, score, comment);
        TvmCell cell = builder.toCell();
        hash = tvm.hash(cell);
    }

/* -------------------------------------------------------------------------- */
/*                              ANCHOR Test utils                             */
/* -------------------------------------------------------------------------- */

    function changeStage(ContestStage stage) external {
        tvm.accept();
        _stage = stage;
    }
}