pragma ton-solidity >= 0.42.0;

contract Checks {
    uint8 _checkList;

    function _passCheck(uint8 check) internal inline {
        _checkList &= ~check;
    }
    function _isCheckListEmpty() internal view inline returns (bool) {
        return (_checkList == 0);
    }
    modifier checksEmpty() {
        require(_isCheckListEmpty(), 100); //Errors.NOT_ALL_CHECKS_PASSED);
        tvm.accept();
        _;
    }
}