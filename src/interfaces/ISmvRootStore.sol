pragma ton-solidity >= 0.42.0;

enum ContractCode {
    Padawan,
    Proposal,
    Group,
    ProposalFactory
}

enum ContractAddr {
    BftgRoot
}

interface ISmvRootStore {
    function setPadawanCode(TvmCell code) external;
    function setProposalCode(TvmCell code) external;
    function setGroupCode(TvmCell code) external;
    function setProposalFactoryCode(TvmCell code) external;

    function setBftgRootAddr(address addr) external;

    function queryCode(ContractCode kind) external;
    function queryAddr(ContractAddr kind) external;
}

interface ISmvRootStoreCallback {
    function updateAddr(ContractAddr kind, address addr) external;
    function updateCode(ContractCode kind, TvmCell code) external;
}


