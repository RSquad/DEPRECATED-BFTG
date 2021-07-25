pragma ton-solidity >= 0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import '../Padawan.sol';

contract PadawanResolver {
    TvmCell _codePadawan;

    function resolvePadawan(address owner) public view returns (address addrPadawan) {
        TvmCell state = _buildPadawanState(owner);
        uint256 hashState = tvm.hash(state);
        addrPadawan = address.makeAddrStd(0, hashState);
    }

    function _buildPadawanState(address owner) internal virtual view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Padawan,
            varInit: {_deployer: address(this), _owner: owner},
            code: _codePadawan
        });
    }
}