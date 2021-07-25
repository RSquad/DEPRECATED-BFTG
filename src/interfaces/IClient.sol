pragma ton-solidity >= 0.36.0;


import './IProposal.sol';
import '../Glossary.sol';

interface IClient {
    function onProposalPassed(ProposalInfo proposalInfo) external;
    function onProposalDeploy(address addr, string proposalType, TvmCell specific) external;
}