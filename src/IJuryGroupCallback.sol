pragma ton-solidity >= 0.36.0;

struct Member {
    uint32 id;
    uint128 balance;
    address addr;
    uint pk;
}

interface IJuryGroupCallback {
    function getMembersCallback(mapping(address => Member) members) external;
}
