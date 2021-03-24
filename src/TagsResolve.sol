pragma ton-solidity >= 0.36.0;

import "./JuryGroup.sol";

struct Setup {
    string[] tags;
}

contract TagsResolve is IJuryGroupCallback {
  TvmCell _imageJuryGroup;
  mapping(address => bool) public _tagsPendings;
  Member[] public _members;
  Setup _setup;

  constructor(Setup setup, TvmCell imageJuryGroup) public {
    tvm.accept();
    _imageJuryGroup = imageJuryGroup;
    _setup = setup;
  }

  function deployJuryGroup() public view returns (address addrJuryGroup){
    tvm.accept();
    TvmCell state = _buildJuryGroupState(_setup.tags[0]);
    TvmCell payload = tvm.encodeBody(JuryGroup);
    addrJuryGroup = tvm.deploy(state, payload, 10 ton, 0);
  }

  function resolveJuryGroups() public {
    tvm.accept();
    for(uint8 i = 0; i < _setup.tags.length; i++) {
      TvmCell state = _buildJuryGroupState(_setup.tags[i]);
      uint256 hashState = tvm.hash(state);
      address addr = address.makeAddrStd(0, hashState);
      _tagsPendings[addr] = true;
      IJuryGroup(addr).getMembers{
        value: 1 ton,
        flag: 64,
        bounce: true
      }();
    }
  }

  function getMembersCallback(mapping(address => Member) members) external override {
    require(_tagsPendings.exists(msg.sender), 101);
    delete _tagsPendings[msg.sender];
    for((, Member member): members) {
        _members.push(member);
    }
  }

  onBounce(TvmSlice) external {
    if(_tagsPendings.exists(msg.sender)) {
      delete _tagsPendings[msg.sender];
    }
  }

  function _buildJuryGroupState(string tag) internal view returns (TvmCell) {
    TvmCell code = _imageJuryGroup.toSlice().loadRef();
    return tvm.buildStateInit({
      contr: JuryGroup,
      varInit: {_tag: tag, _deployer: address(this)},
      code: code
    });
  }
}