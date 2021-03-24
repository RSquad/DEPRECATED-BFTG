pragma ton-solidity >= 0.36.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

contract BatchGiver {
    struct Target {
        address dest;
        uint64 amount;
    }
    constructor() public {
        tvm.accept();
    }

    function send(Target[] targets) public pure {
        tvm.accept();
        for(uint i = 0; i < targets.length; i++) {
            targets[i].dest.transfer(targets[i].amount, false, 3);
        }
    }
}