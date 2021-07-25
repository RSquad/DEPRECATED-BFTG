pragma ton-solidity >= 0.43.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import '../Contest.sol';

contract ContestResolver {
    TvmCell _codeContest;

    function resolveContest(address deployer) public view returns (address addrContest) {
        TvmCell state = _buildContestState(deployer);
        uint256 hashState = tvm.hash(state);
        addrContest = address.makeAddrStd(0, hashState);
    }

    function _buildContestState(address deployer) internal virtual view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Contest,
            varInit: {_deployer: deployer},
            code: _codeContest
        });
    }
}