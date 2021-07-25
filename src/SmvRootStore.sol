pragma ton-solidity >=0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import './Base.sol';
import './interfaces/ISmvRootStore.sol';

contract SmvRootStore is Base, ISmvRootStore {

    mapping(uint8 => address) public _addrs;
    mapping(uint8 => TvmCell) public _codes;

    function setPadawanCode(TvmCell code) public override signed {
        _codes[uint8(ContractCode.Padawan)] = code;
    }
    function setProposalCode(TvmCell code) public override signed {
        _codes[uint8(ContractCode.Proposal)] = code;
    }
    function setGroupCode(TvmCell code) public override signed {
        _codes[uint8(ContractCode.Group)] = code;
    }
    function setProposalFactoryCode(TvmCell code) public override signed {
        _codes[uint8(ContractCode.ProposalFactory)] = code;
    }

    function setBftgRootAddr(address addr) public override signed {
        require(addr != address(0));
        _addrs[uint8(ContractAddr.BftgRoot)] = addr;
    }

    function queryCode(ContractCode kind) external override {
        TvmCell code = _codes[uint8(kind)];
        ISmvRootStoreCallback(msg.sender).updateCode{value: 0, flag: 64, bounce: false}(kind, code);
    }

    function queryAddr(ContractAddr kind) external override {
        address addr = _addrs[uint8(kind)];
        ISmvRootStoreCallback(msg.sender).updateAddr{value: 0, flag: 64, bounce: false}(kind, addr);
    }
}