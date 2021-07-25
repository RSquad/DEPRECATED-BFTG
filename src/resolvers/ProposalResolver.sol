pragma ton-solidity >= 0.42.0;

import '../Proposal.sol';

contract ProposalResolver {
    TvmCell _codeProposal;

    function resolveProposal(uint32 id) public view returns (address addrProposal) {
        TvmCell state = _buildProposalState(id);
        uint256 hashState = tvm.hash(state);
        addrProposal = address.makeAddrStd(0, hashState);
    }
    
    function _buildProposalState(uint32 id) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Proposal,
            varInit: {_deployer: address(this), _id: id},
            code: _codeProposal
        });
    }
}