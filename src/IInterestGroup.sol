pragma ton-solidity >= 0.36.0;

interface IInterestGroup {
    function inquire(uint32 contestId, uint32[] reqs) external;
    function offer(uint32 contestId, mapping (uint32 => uint32) offers) external;
}