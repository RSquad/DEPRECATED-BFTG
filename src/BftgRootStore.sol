pragma ton-solidity >=0.47.0;

pragma AbiHeader expire;
pragma AbiHeader time;

import './interfaces/IBftgRootStore.sol';

import './Errors.sol';

contract BftgRootStore is IBftgRootStore {

    mapping(uint8 => address) public _addrs;
    mapping(uint8 => TvmCell) public _codes;

    function setJuryGroupCode(TvmCell code) public override {
        require(msg.pubkey() == tvm.pubkey(), Errors.INVALID_CALLER);
        tvm.accept();
        _codes[uint8(ContractCode.JuryGroup)] = code;
    }

    function setContestCode(TvmCell code) public override {
        require(msg.pubkey() == tvm.pubkey(), Errors.INVALID_CALLER);
        tvm.accept();
        _codes[uint8(ContractCode.Contest)] = code;
    }
    
    function queryCode(ContractCode kind) external override {
        TvmCell code = _codes[uint8(kind)];
        IBftgRootStoreCallback(msg.sender).updateCode{value: 0, flag: 64, bounce: false}(kind, code);
    }

    function queryAddr(ContractAddr kind) external override {
        address addr = _addrs[uint8(kind)];
        IBftgRootStoreCallback(msg.sender).updateAddr{value: 0, flag: 64, bounce: false}(kind, addr);
    }
}