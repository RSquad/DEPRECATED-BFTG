pragma ton-solidity >= 0.47.0;

pragma AbiHeader expire;
pragma AbiHeader time;

struct ContestProposalSpecific {
    string[] tags;
    uint32 underwayDuration;
    uint128 prizePool;
    string description;
}

contract TestDecode {
    ContestProposalSpecific public _specificDecoded;
    TvmCell public _specificEncoded;

    constructor() public {
      tvm.accept();
    }

    function encode(
      ContestProposalSpecific specific
    ) public {
        tvm.accept();
        TvmBuilder b;
        b.store(specific);
        _specificEncoded = b.toCell();
    }

    function decode() public {
        tvm.accept();
        TvmSlice slice = _specificEncoded.toSlice();
        (ContestProposalSpecific specific) = slice.decode(ContestProposalSpecific);
        _specificDecoded = specific;
    }
}