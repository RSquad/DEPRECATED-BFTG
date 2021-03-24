pragma ton-solidity >= 0.36.0;

import "Base.sol";
import "IDemiurge.sol";
import "IPadawan.sol";
import "IProposal.sol";

interface IDePool {
    function addOrdinaryStake(uint64 stake) external;
    function transferStake(address dest, uint64 amount) external;
}

contract UserWallet is Base {

    address _deployer;

    uint32 _tokens;
    address _padawan;
    mapping (address => uint32) _proposals;
    mapping (uint32 => address) public _wins;
    mapping (uint32 => address) public _losses;

    constructor() public {
        tvm.accept();
    }

    function setTargetAddress(address target) public accept {
        _deployer = target;
    }

    function deployPadawan(uint userKey) external view accept {
        IDemiurge(_deployer).deployPadawan{value: DEPLOY_PAY}(userKey);
    }

    function deployProposal(uint32 totalVotes, uint32 start, uint32 end, string description,
                                string text, VoteCountModel model) external view accept {
        IDemiurge(_deployer).deployProposal{value: DEPLOY_PROPOSAL_PAY}(totalVotes, start, end, description, text, model);
    }

    function requestProposalWithWhitelist(uint32 totalVotes, uint32 start, uint32 end, string description, string text,
                                            VoteCountModel model, address[] voters) external view accept {
        IDemiurge(_deployer).deployProposalWithWhitelist{value: DEPLOY_PROPOSAL_PAY}(totalVotes, start, end, description, text, model, voters);
    }

    function requestProposalForContest(uint32 totalVotes, uint32 start, uint32 end, string description, string title, VoteCountModel model,
        uint32 contestDuration, uint128 prizePool, string[] tags) external view accept {
        IDemiurge(_deployer).deployProposalForContest{value: DEPLOY_PROPOSAL_PAY + DEPLOY_PAY + prizePool + START_BALANCE}
        (totalVotes, start, end, description, title, model, contestDuration, prizePool, tags);
    }

    /* Callbacks */

    function updatePadawan(address addr) external {
        _padawan = addr;
    }

    function onProposalDeployed(uint32 id, address addr) external {
        _proposals[addr] = id;
    }

    function onProposalCompletion(uint32 id, bool result) external {
        uint32 fin = 0;
        address loc;
        for ((address addr, uint32 pid): _proposals) {
            if (pid == id) {
                (loc, fin) = (addr, pid);
            }
        }
        if (fin == 0) {
            // Not found
            return;
        }

        if (result) {
            _wins[fin] = loc;
        } else {
            _losses[fin] = loc;
        }
        delete _proposals[loc];
    }


    function depositTons(uint32 tons) public view accept {
        IPadawan(_padawan).depositTons{value: uint64(tons) * 1 ton + DEPOSIT_TONS_PAY, bounce: true}(tons);
    }

    function depositTokens(address returnTo, uint256 tokenId, uint64 tokens) public view accept {
        IPadawan(_padawan).depositTokens{value: DEPOSIT_TOKENS_PAY, bounce: true}
            (returnTo, tokenId, tokens);
    }

    function reclaimDeposit(uint32 votes) public view accept {
        IPadawan(_padawan).reclaimDeposit{value: DEPOSIT_TONS_PAY, bounce: true}
            (votes);
    }

    function voteFor(address proposal, bool choice, uint32 votes) public view accept {
        IPadawan(_padawan).voteFor{value: 1 ton, bounce: true}
            (proposal, choice, votes);
    }

    function createTokenAccount(address root) public view accept {
        IPadawan(_padawan).createTokenAccount{value: TOKEN_ACCOUNT_PAY + /*just for tests*/ 2 ton, bounce: true}
            (root);
    }

    function wrapUp(address proposal) public pure accept {
        IProposal(proposal).wrapUp{value: 0.2 ton}();
    }

    /*
    * DePool interface
    */

    function addOrdinaryStake(address depool, uint64 stake) public pure accept {
        IDePool(depool).addOrdinaryStake{value: 0.5 ton + stake}(stake);
    }

    function transferStake(address depool, address dest, uint64 amount) public pure accept {
        IDePool(depool).transferStake{value: 0.5 ton}(dest, amount);
    }


    /*
    *  Groups API
    */

    function applyToGroup(address group, string name) public view accept {
        IPadawan(_padawan).applyToGroup(group, name);
    }

    function removeFromGroup(address group, uint32 id, address addr) public view accept {
        IPadawan(_padawan).removeFromGroup(group, id, addr);
    }

     /* Receiving interface */

    /* Plain transfers */
    receive() external {
    }

    function transferFunds(address to, uint128 val) external pure signed {
        to.transfer(val, true, 1);
    }

    function getInfo() public view returns (uint32 tokens, address padawan) {
        tokens = _tokens;
        padawan = _padawan;
    }

    function getDeployed() public view returns (address deployer, mapping (address => uint32) proposals) {
        deployer = _deployer;
        proposals = _proposals;
    }

}
