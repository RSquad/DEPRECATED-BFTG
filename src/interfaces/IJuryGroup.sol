pragma ton-solidity >= 0.43.0;

struct Member {
    uint32 id;
    uint128 balance;
    address addr;
}

interface IJuryGroup {
    function getMembers() external;
    function registerMember(address addrMember) external;
}

interface IJuryGroupCallback {
    function getMembersCallback(mapping(address => Member) members) external;
}