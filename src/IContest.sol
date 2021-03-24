pragma ton-solidity >= 0.36.0;
import "IContestData.sol";

interface IContest {
    function getContestInfo() external returns (ContestInfo contestInfo);
    function getContestTimeline() external returns (ContestTimeline timeline);
    function getContestSetup() external returns (ContestSetup setup);
    function getContest() external view returns (
        ContestInfo contestInfo, ContestTimeline timeline,
        ContestSetup setup, Stage stage
    );
    function getCurrentData() external view returns (
        ContenderInfo[] info, address[] juryAddresses, Stats[] allStats,
        mapping (uint16 => Mark) marks, mapping (uint16 => Comment) comments,
        mapping (uint16 => HiddenEvaluation) hiddens
    );

    function getJurorId(address addr) external view returns (uint8 jurorId);

    function submit(address participant, string forumLink, string fileLink, uint hash, address contact) external;
    function next() external view;

    function claimContestReward() external;
    function claimJurorReward() external;
    function claimContestRewardAndBecomeJuror(uint128[] amount, string[] tag, uint pk) external;
}
