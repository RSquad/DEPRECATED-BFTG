pragma ton-solidity >= 0.42.0;

struct JuryGroupPending {
    address addrJury;
    string tag;
}

interface IBftgRoot {
    function registerMemberJuryGroup(string tag, address addrMember) external;
}