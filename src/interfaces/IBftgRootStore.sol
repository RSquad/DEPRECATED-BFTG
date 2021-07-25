pragma ton-solidity >= 0.42.0;

enum ContractCode {
    JuryGroup,
    Contest
}

enum ContractAddr {
    empty
}

interface IBftgRootStore {
    function setJuryGroupCode(TvmCell code) external;
    function setContestCode(TvmCell code) external;
    function queryCode(ContractCode kind) external;
    function queryAddr(ContractAddr kind) external;
}

interface IBftgRootStoreCallback {
    function updateCode(ContractCode kind, TvmCell code) external;
    function updateAddr(ContractAddr kind, address addr) external;
}