pragma ton-solidity >= 0.45.0;

pragma AbiHeader expire;
pragma AbiHeader time;

import './interfaces/IProposalFactory.sol';
import '../crystal-smv/src/interfaces/ISmvRoot.sol';

import './Errors.sol';
import './Fees.sol';

contract ProposalFactory is IProposalFactory {
    address _addrSmvRoot;
    
    constructor(address addrSmvRoot) public {
        tvm.accept();
        // optional(TvmCell) optSalt = tvm.codeSalt(tvm.code());
        // require(optSalt.hasValue());
        // (address addrSmvRoot) = optSalt.get().toSlice().decode(address);
        _addrSmvRoot = addrSmvRoot;
    }

    function deployContestProposal(
        address client,
        string title,
        address[] whiteList,
        uint128 totalVotes,
        ContestProposalSpecific specific
    ) public override {
        require(msg.sender != address(0), Errors.INVALID_CALLER);
        require(msg.value >= Fees.DEPLOY_DEFAULT + Fees.PROCESS, Errors.INVALID_VALUE);
        TvmBuilder b;
        b.store(specific);
        TvmCell cellSpecific = b.toCell();
        ISmvRoot(_addrSmvRoot).deployProposal
            {value: Fees.DEPLOY_DEFAULT + Fees.PROCESS_SM, flag: 1, bounce: true}
            (
                client,
                title,
                totalVotes,
                whiteList,
                'contest',
                cellSpecific
            );

        // TODO
        // tvm.rawReserve(Fees.DEPLOY_DEFAULT, 4);
        // msg.sender.transfer(0, false, 128);
    }
}