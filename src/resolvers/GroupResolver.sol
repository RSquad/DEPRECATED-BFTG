pragma ton-solidity >= 0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import '../Group.sol';

contract GroupResolver {
    TvmCell _codeGroup;

    function resolveGroup(string name) public view returns (address group) {
        TvmCell state = _buildGroupState(name);
        uint256 hashState = tvm.hash(state);
        group = address.makeAddrStd(0, hashState);
    }

    function _buildGroupState(string name) internal virtual view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Group,
            varInit: {_name: name},
            code: _codeGroup
        });
    }
}