pragma ton-solidity >= 0.36.0;
import "DemiurgeStore.sol";

contract StoreStub is DemiurgeStore {
    
    function getImages() public view returns (TvmCell demiurge, TvmCell padawan, TvmCell proposal/*, TvmCell contest*/) {
        demiurge = images[uint8(ContractType.Demiurge)];
        padawan = images[uint8(ContractType.Padawan)];
        proposal = images[uint8(ContractType.Proposal)];
//        contest = images[uint8(ContractType.Contest)];
    }
}