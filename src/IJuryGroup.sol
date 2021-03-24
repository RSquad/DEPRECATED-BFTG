pragma ton-solidity >= 0.36.0;

interface IJuryGroup {
    function getMembers() external;
    function registerMember(address addrMember, uint pkMember) external;
}
