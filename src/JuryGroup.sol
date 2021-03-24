pragma ton-solidity >= 0.36.0;

import "IJuryGroup.sol";
import "IJuryGroupCallback.sol";

// 100 - sender is not deployer
// 101 - only inbound messages
// 200 - not enough value
// 201 - not enough value
// 202 - not enough balance to withdraw

contract JuryGroup is IJuryGroup {
    string static public _tag;
    address static public _deployer;

    mapping(address => Member) public _members;
    uint32 _membersCounter;

    constructor() public {
        require(_deployer == msg.sender, 100);
    }

    function registerMember(address addrMember, uint pkMember) public override {
        if(_members.exists(addrMember) == false) {
            _members[addrMember] = Member(_membersCounter, msg.value, addrMember, pkMember);
            _membersCounter++;
        } else {
            _members[addrMember].balance += msg.value;
        }
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