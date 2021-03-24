pragma ton-solidity >= 0.36.0;

interface ITokenWallet {
    function getBalance_InternalOwner(uint32 _answer_id) external functionID(0xD);
    function transfer(address dest, uint128 tokens, uint128 grams) external functionID(0xC);
}
