pragma ton-solidity >= 0.36.0;

interface IPrizeGiver {
    function requestPrizePool(uint128 amount) external;
}

interface IGiverCallback {
    function receivePrizePool() external;
}