pragma ton-solidity >= 0.36.0;

interface IJuror {

    function invite(uint32 expertId, uint32 contestId, uint8 newId) external;
}
