pragma ton-solidity >= 0.36.0;

interface IInterestGroupClient {
    function updateRoster(uint32 contestId, uint32 groupId, uint32[] members) external;
    function confirm(uint32 contestId, mapping (uint32 => address) staff) external;
    function lapse(uint32 contestId, uint16 response) external;
}