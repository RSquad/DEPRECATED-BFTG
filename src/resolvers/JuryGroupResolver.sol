pragma ton-solidity >= 0.42.0;

import '../JuryGroup.sol';

contract JuryGroupResolver {
    TvmCell _codeJuryGroup;

    function resolveJuryGroup(
        string tag,
        address deployer
    ) public view returns (address addrJuryGroup) {
        TvmCell state = _buildJuryGroupState(tag, deployer);
        uint256 hashState = tvm.hash(state);
        addrJuryGroup = address.makeAddrStd(0, hashState);
    }

    function _buildJuryGroupCode(address deployer) internal virtual view returns (TvmCell) {
        TvmBuilder salt;
        salt.store(deployer);
        return tvm.setCodeSalt(_codeJuryGroup, salt.toCell());
    }
    
    function _buildJuryGroupState(
        string tag,
        address deployer
    ) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: JuryGroup,
            varInit: {
                _tag: tag
            },
            code: _buildJuryGroupCode(deployer)
        });
    }
}