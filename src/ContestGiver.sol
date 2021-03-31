pragma ton-solidity >= 0.36.0;

// 100 - sender is not deployer

contract ContestGiver {
    address static public _deployer;

    constructor() public {
        require(_deployer == msg.sender, 100);
    }

    function give(address addrMember, uint128 amount) public view {
        require(_deployer == msg.sender, 100);
        addrMember.transfer(amount, true, 1);
    }
}