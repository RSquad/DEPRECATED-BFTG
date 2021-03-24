pragma ton-solidity >= 0.36.0;

interface IGroup {
    function applyFor(string name) external;
    function unseat(uint32 id, address addr) external;
}