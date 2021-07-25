pragma ton-solidity >= 0.42.0;

import '../ProposalFactory.sol';

contract ProposalFactoryResolver {
    TvmCell _codeProposalFactory;

    function resolveProposalFactory(address deployer) public view returns (address addrProposalFactory) {
        TvmCell state = _buildProposalFactoryState(deployer);
        uint256 hashState = tvm.hash(state);
        addrProposalFactory = address.makeAddrStd(0, hashState);
    }
    
    function _buildProposalFactoryState(address deployer) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: ProposalFactory,
            varInit: {_deployer: deployer},
            code: _codeProposalFactory
        });
    }
}