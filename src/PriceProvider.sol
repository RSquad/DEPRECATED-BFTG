pragma ton-solidity >= 0.36.0;

import "IPriceProvider.sol";

contract PriceProvider is IPriceProvider {
    
    uint64 constant TON_PER_VOTE = 1 ton;
    uint64 constant TIP_PER_VOTE = 1;

    function queryTonsPerVote(uint32 queryId) external override {
        IPriceProviderCallback(msg.sender).updateTonsPerVote{value: 0, flag: 64}(queryId, TON_PER_VOTE);
    }

    function queryTipsPerVote(uint32 queryId, address tokenRoot) external override {
        tokenRoot = tokenRoot;
        IPriceProviderCallback(msg.sender).updateTipsPerVote{value: 0, flag: 64}(queryId, TIP_PER_VOTE);
    }
}