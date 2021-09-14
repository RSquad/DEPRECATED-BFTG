pragma ton-solidity >= 0.45.0;

library Fees {
    uint128 constant PROCESS_SM = 0.2 ton;
    uint128 constant PROCESS = 0.4 ton;

    uint128 constant DEPLOY_DEFAULT = 3 ton;
    uint128 constant DEPLOY_WALLET = 2 ton;

    uint128 constant START = 1 ton;
}