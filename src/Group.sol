pragma ton-solidity >= 0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import "./Base.sol";
import "./Errors.sol";
import "./interfaces/IGroup.sol";

contract Group is Base, IGroup {

    string static _name;
    address[] _members;


    constructor(address[] initialMembers) public onlyContract {
        _members = initialMembers;
    }

    function getMembers() override public onlyContract {
        IGroupCallback(msg.sender).onGetMembers
            {value: 0, flag: 64, bounce: true}
            (_name, _members);
    }

    function addMember(uint128 idProposal, address member) public onlyContract {
        idProposal;
        _members.push(member);
    }

    function removeMember(uint128 idProposal, address member) public onlyContract {
        idProposal;
        address[] members;
        for(uint32 index = 0; index < _members.length; index++) {
            if(_members[index] != member) {
                members.push(_members[index]);
            }
        }
        _members = members;
    }
}