pragma ton-solidity >= 0.45.0;

pragma AbiHeader expire;
pragma AbiHeader time;

import './Base.sol';
import './Glossary.sol';
import './interfaces/IProposalFactory.sol';
import './interfaces/ISmvRoot.sol';

import {Errors} from './Errors.sol';

contract ProposalFactory is Base {
    address static _deployer;
    
    constructor() public onlyContract {
        require(_deployer == msg.sender, Errors.ONLY_DEPLOYER);
    }

    function deployContestProposal(
        address client,
        string title,
        address group,
        ContestProposalSpecific specific
    ) external view onlyContract {
        require(msg.value >= DEPLOY_PROPOSAL_PAY + 1 ton);
        TvmBuilder b;
        b.store(specific);
        TvmCell cellSpecific = b.toCell();
        address[] arr;
        ISmvRoot(_deployer).deployProposal
            {value: 0, flag: 64, bounce: true}
            (
                client,
                title,
                1 ton,
                1000000000,
                address(0),
                group,
                arr,
                'contest',
                cellSpecific
            );
    }

    function deployRemoveMemberProposal(
        address client,
        string title,
        uint128 votePrice,
        uint128 voteTotal,
        address voteProvider,
        address group,
        address[] whiteList,
        RemoveMemberProposalSpecific specific
    ) external view onlyContract {
        require(msg.value >= DEPLOY_PROPOSAL_PAY + 1 ton);
        TvmBuilder b;
        b.store(specific);
        TvmCell cellSpecific = b.toCell();
        ISmvRoot(_deployer).deployProposal
            {value: 0, flag: 64, bounce: true}
            (
                client,
                title,
                votePrice,
                voteTotal,
                voteProvider,
                group,
                whiteList,
                'remove-member',
                cellSpecific
            );
    }

    function deployAddMemberProposal(
        address client,
        string title,
        uint128 votePrice,
        uint128 voteTotal,
        address voteProvider,
        address group,
        address[] whiteList,
        AddMemberProposalSpecific specific
    ) external view onlyContract {
        require(msg.value >= DEPLOY_PROPOSAL_PAY + 1 ton);
        TvmBuilder b;
        b.store(specific);
        TvmCell cellSpecific = b.toCell();
        ISmvRoot(_deployer).deployProposal
            {value: 0, flag: 64, bounce: true}
            (
                client,
                title,
                votePrice,
                voteTotal,
                voteProvider,
                group,
                whiteList,
                'add-member',
                cellSpecific
            );
    }
}