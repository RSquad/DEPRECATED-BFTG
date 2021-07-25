pragma ton-solidity >= 0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import "./Base.sol";
import "./Errors.sol";
import "./interfaces/IProposal.sol";
import "./interfaces/IPadawan.sol";
import "./interfaces/ITokenRoot.sol";
import "./interfaces/ITokenWallet.sol";

struct PadawanData {
    address ownerAddress;
    address addr;
}
struct Balance {
    uint128 total;
    uint128 locked;
}
struct ActiveProposal {
    address voteProvider;
    uint128 votePrice;
    uint128 votes;
}
struct Reclaim {
    address balanceProvider;
    uint128 amount;
    address returnTo;
}

contract Padawan is Base, IEstimateVotesCallback {
    address static _deployer;
    address static _owner;

    mapping(address => Balance) public _balances;
    mapping(address => address) public _tokenAccounts;
    mapping(address => ActiveProposal) public _activeProposals;
    uint32 _activeProposalsLength;

    Reclaim public _reclaim;

    // Helpers

    modifier onlyOwner() {
        require(msg.sender == _owner, Errors.NOT_AUTHORIZED_CONTRACT);
        _;
    }

    constructor() public onlyContract {
        require(_deployer == msg.sender, Errors.ONLY_DEPLOYER);
    }

    function vote(address proposal, bool choice, uint128 votes) external onlyOwner {
        require(msg.value >= VOTE_FEE, Errors.MSG_VALUE_TOO_LOW);
        IProposal(proposal).estimateVotes
            {value: 0, flag: 64, bounce: true}
            (votes, choice);
    }

    function onEstimateVotes(
        uint128 cost,
        uint128 votePrice,
        address voteProvider,
        uint128 votes,
        bool choice)
    external override onlyContract {
        optional(ActiveProposal) optActiveProposal = _activeProposals.fetch(msg.sender);
        ActiveProposal activeProposal = optActiveProposal.hasValue() ? optActiveProposal.get() : ActiveProposal(voteProvider, votePrice, 0);
        if(!optActiveProposal.hasValue()) {
            _activeProposals[msg.sender] = activeProposal;
        }
        optional(Balance) optBalance;
        if(voteProvider == address(0)) {
            optBalance = _balances.fetch(voteProvider);
        } else {
            optional(address) optAccount = _tokenAccounts.fetch(voteProvider);
            require(optAccount.hasValue(), 115);
            optBalance = _balances.fetch(optAccount.get());
        }
        require(optBalance.hasValue(), 113);
        require(optBalance.get().total >= (activeProposal.votes * votePrice) + cost, 114);
        _activeProposals[msg.sender].votes += votes;
        _activeProposalsLength += 1;
        IProposal(msg.sender).vote
            {value: 0, flag: 64, bounce: true}
            (_owner, choice, votes);
    }

    function confirmVote(
        uint128 votes,
        uint128 votePrice,
        address voteProvider)
    external onlyContract { votes;
        optional(ActiveProposal) optActiveProposal = _activeProposals.fetch(msg.sender);
        require(optActiveProposal.hasValue(), 111);
        uint128 activeProposalVotes = optActiveProposal.get().votes;

        address balanceProvider = voteProvider == address(0) ? voteProvider : _tokenAccounts[voteProvider];

        if(_balances[balanceProvider].locked < (activeProposalVotes) * votePrice) {
            _balances[balanceProvider].locked = (activeProposalVotes) * votePrice;
        }
        _owner.transfer(0, false, 64);
    }

    function rejectVote(uint128 votes, uint16 errorCode) external onlyContract { votes; errorCode;
        optional(ActiveProposal) optActiveProposal = _activeProposals.fetch(msg.sender);
        require(optActiveProposal.hasValue(), 112);
        ActiveProposal activeProposal = optActiveProposal.get();
        activeProposal.votes -= votes;
        if (activeProposal.votes == 0) {
            delete _activeProposals[msg.sender];
            _activeProposalsLength -= 1;
        }
        _owner.transfer(0, false, 64);
    }

    function reclaimDeposit(address voteProvider, uint128 amount, address returnTo) external onlyOwner {
        require(_reclaim.amount == 0, 130);
        require(msg.value >= QUERY_STATUS_FEE * _activeProposalsLength + 1 ton, Errors.MSG_VALUE_TOO_LOW);
        address balanceProvider = address(0);
        if(voteProvider != address(0)) {
            optional(address) optAccount = _tokenAccounts.fetch(voteProvider);
            require(optAccount.hasValue(), 117);
            balanceProvider = optAccount.get();
        }
        optional(Balance) optBalance = _balances.fetch(balanceProvider);
        require(optBalance.hasValue(), 131);
        Balance balance = optBalance.get();
        require(amount <= balance.total, Errors.NOT_ENOUGH_VOTES);
        require(returnTo != address(0), 132);

        _reclaim = Reclaim(balanceProvider, amount, returnTo);

        if (amount <= balance.total - balance.locked) {
            _doReclaim();
        }

        optional(address, ActiveProposal) optActiveProposal = _activeProposals.min();
        while (optActiveProposal.hasValue()) {
            (address addrActiveProposal,) = optActiveProposal.get();
            IProposal(addrActiveProposal).queryStatus
                {value: QUERY_STATUS_FEE, bounce: true, flag: 1}
                ();
            optActiveProposal = _activeProposals.next(addrActiveProposal);
        }
    }

    function updateStatus(ProposalState state) external onlyContract {
        optional(ActiveProposal) optActiveProposal = _activeProposals.fetch(msg.sender);
        require(optActiveProposal.hasValue());
        ActiveProposal activeProposal = optActiveProposal.get();

        if (state >= ProposalState.Ended) {
            address balanceProvider = address(0);
            if(activeProposal.voteProvider != address(0)) {
                optional(address) optAccount = _tokenAccounts.fetch(activeProposal.voteProvider);
                require(optAccount.hasValue(), 117);
                balanceProvider = optAccount.get();
            }
            Balance balance = _balances[balanceProvider];
            if(balance.locked <= activeProposal.votes * activeProposal.votePrice) {
                delete _activeProposals[msg.sender];
                uint128 max;
                optional(address, ActiveProposal) optActiveProposal2 = _activeProposals.min();
                while (optActiveProposal2.hasValue()) {
                    (address addrActiveProposal, ActiveProposal activeProposal2) = optActiveProposal2.get();
                    if(activeProposal2.votes * activeProposal2.votePrice > max && activeProposal2.voteProvider == activeProposal.voteProvider) {
                        max = activeProposal2.votes * activeProposal2.votePrice;
                    }
                    optActiveProposal2 = _activeProposals.next(addrActiveProposal);
                }
                _balances[balanceProvider].locked = max;
            } else {
                delete _activeProposals[msg.sender];
            }
            _activeProposalsLength -= 1;
            if(_reclaim.amount != 0) {
                balance = _balances[_reclaim.balanceProvider];
                if (_reclaim.amount <= balance.total - balance.locked) {
                    _doReclaim();
                }
            }
        }
    }

    /*
    *   Private functions
    */

    function _doReclaim() private inline {
        if(_reclaim.balanceProvider == address(0)) {
            _reclaim.returnTo.transfer(_reclaim.amount, true, 1);
        } else {
            ITokenWallet(_reclaim.balanceProvider).transfer
                {value: 0.2 ton} // refactor
                (_reclaim.returnTo, _reclaim.amount, 0.1 ton);
        }
        _balances[_reclaim.balanceProvider].total -= _reclaim.amount;
        delete _reclaim;
        _owner.transfer(0, false, 64);
    }

    function depositTons(uint128 tons) external onlyOwner {
        require(msg.value >= tons + 1 ton);
        _balances[address(0)].total += tons;
        // _owner.transfer(0, false, 64);
    }

    function depositTokens(address tokenRoot) external onlyOwner {
        require(msg.value >= DEFAULT_FEE, Errors.MSG_VALUE_TOO_LOW);
        optional(address) optTokenAccount = _tokenAccounts.fetch(tokenRoot);
        require(optTokenAccount.hasValue(), Errors.ACCOUNT_DOES_NOT_EXIST);

        address tokenAccount = optTokenAccount.get();

        ITokenWallet(tokenAccount).getBalance_InternalOwner
            {value: 0, flag: 64, bounce: true}
            (tvm.functionId(onTokenWalletGetBalance));
    }

    function onTokenWalletGetBalance(uint128 balance) public onlyContract {
        optional(Balance) optBalance = _balances.fetch(msg.sender);
        require(optBalance.hasValue(), Errors.NOT_AUTHORIZED_CONTRACT);
        _balances[msg.sender].total += balance;
    }

    function createTokenAccount(address tokenRoot) external onlyOwner {
        require(msg.value >= DEFAULT_FEE, Errors.MSG_VALUE_TOO_LOW);
        require(!_tokenAccounts.exists(tokenRoot));

        ITokenRoot(tokenRoot).deployEmptyWallet
            {value: 0, flag: 64, bounce: true}
            (tvm.functionId(onTokenWalletDeploy), 0, 0, address(this).value, 1 ton);
    }

    function onTokenWalletDeploy(address account) public {
        require(!_tokenAccounts.exists(msg.sender), Errors.INVALID_CALLER);
        _tokenAccounts[msg.sender] = account;
        _balances[account] = Balance(0, 0);
        _owner.transfer(0, false, 64);
    }
}
