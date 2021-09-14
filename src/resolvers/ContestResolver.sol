pragma ton-solidity >= 0.47.0;

pragma AbiHeader expire;
pragma AbiHeader time;

import '../Contest.sol';

contract ContestResolver {
    TvmCell _codeContest;

    function resolveContest(
        address addrBftgRoot,
        uint32 id
    ) public view returns (address addrContest) {
        TvmCell state = _buildContestState(addrBftgRoot, id);
        uint256 hashState = tvm.hash(state);
        addrContest = address.makeAddrStd(0, hashState);
    }

    function _buildContestState(
        address addrBftgRoot,
        uint32 id
    ) internal view inline returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Contest,
            varInit: {_id: id},
            code: _buildContestCode(addrBftgRoot)
        });
    }

    function _buildContestCode(
        address addrBftgRoot
    ) internal view inline returns (TvmCell) {
        TvmBuilder salt;
        salt.store(addrBftgRoot);
        return tvm.setCodeSalt(_codeContest, salt.toCell());
    }
}