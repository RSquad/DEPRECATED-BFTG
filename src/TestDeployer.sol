pragma ton-solidity >= 0.36.0;

import "./JuryGroup.sol";
import "./Contest.sol";
import "./IContestData.sol";
import "./DemiurgeStore.sol";

contract TestDeployer {
  address _addrStore;
  TvmCell public _imageJuryGroup;
  TvmCell public _imageContest;

  constructor(address addrStore) public {
    tvm.accept();
    _addrStore = addrStore;

    DemiurgeStore(_addrStore).queryImage{
      value: 0.2 ton, bounce: true
    }(ContractType.JuryGroup);
    DemiurgeStore(_addrStore).queryImage{
      value: 0.2 ton, bounce: true
    }(ContractType.Contest);
  }

  function deployJuryGroup(string tag) public view returns (address addrJuryGroup){
    tvm.accept();
    TvmCell state = _buildJuryGroupState(tag);
    TvmCell payload = tvm.encodeBody(JuryGroup);
    addrJuryGroup = tvm.deploy(state, payload, 10 ton, 0);
  }

  function deployContest(
    address store,
    ContestInfo contestInfo,
    ContestTimeline contestTimeline,
    ContestSetup setup
  ) public view returns (address addrContest){
    tvm.accept();
    TvmCell state = _buildContestState();
    TvmCell payload = tvm.encodeBody(Contest, store, contestInfo, contestTimeline, setup);
    addrContest = tvm.deploy(state, payload, 10 ton, 0);
  }

  function updateImage(ContractType kind, TvmCell image) external {
    if (kind == ContractType.JuryGroup) {
      _imageJuryGroup = image;
    }
    if (kind == ContractType.Contest) {
      _imageContest = image;
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

  function _buildContestState() internal view returns (TvmCell) {
    TvmCell code = _imageContest.toSlice().loadRef();
    return tvm.buildStateInit({
      contr: Contest,
      varInit: {_deployer: address(this)},
      code: code
    });
  }
}