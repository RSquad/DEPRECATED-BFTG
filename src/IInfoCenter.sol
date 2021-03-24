pragma ton-solidity >= 0.36.0;
import "Glossary.sol";
import "IBaseData.sol";

interface IInfoCenter is IBaseData {
    function onContestDeploy(uint32 id) external;
    function onProposalDeploy() external;
    function stateUpdated(Stage stage) external;
    function onStateUpdate(ProposalState state) external;
    function reportResults(VotingResults results) external;
    function registerJuryMember(string tag, uint pk) external;
}
