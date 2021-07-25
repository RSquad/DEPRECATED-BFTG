pragma ton-solidity >= 0.36.0;

interface IGroup {
    function getMembers() external;
}

interface IGroupCallback {
    function onGetMembers(string name, address[] members) external;
}