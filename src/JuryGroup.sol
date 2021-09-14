pragma ton-solidity >= 0.36.0;

import "./interfaces/IJuryGroup.sol";

contract JuryGroup is IJuryGroup {
    modifier onlyDeployer() {
        require(msg.sender == _deployer, 100);
        _;
    }

    string static public _tag;
    address _deployer;

    mapping(address => Member) public _members;
    uint32 _membersCounter;

    constructor(address[] initialMembers) public {
        optional(TvmCell) optSalt = tvm.codeSalt(tvm.code());
        require(optSalt.hasValue(), 102);
        (address deployer) = optSalt.get().toSlice().decode(address);
        require(msg.sender == deployer, 100);
        _deployer = deployer;
        for(uint8 i = 0; i < initialMembers.length; i++) {
            _addMember(initialMembers[i], 10);
        }
    }

    function registerMember(address addrMember) public override onlyDeployer {
        if(_members.exists(addrMember) == false) {
            _addMember(addrMember, msg.value);
        } else {
            _members[addrMember].balance += msg.value;
        }
    }

    function _addMember(address addrMember, uint128 value) private inline {
        _members[addrMember] = Member(_membersCounter, value, addrMember);
        _membersCounter++;
    }

    function withdraw(uint128 amount) public {
        require(msg.sender != address(0), 101);
        require(_members[msg.sender].balance >= 0 ton, 201);
        require(_members[msg.sender].balance < amount, 202);
        msg.sender.transfer(amount, true, 1);
        _members[msg.sender].balance -= amount;
    }

    function getMembers() public override {
        IJuryGroupCallback(msg.sender).getMembersCallback{value: 0, flag: 64, bounce: false}(_members);
    }
}