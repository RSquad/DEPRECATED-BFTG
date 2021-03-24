pragma ton-solidity >=0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;

enum ContractType { Demiurge, Proposal, Padawan, VotingDebot, DemiurgeDebot, PriceProvider, Contest, JuryGroup, Juror, ContestGiver }

interface IDemiurgeStoreCallback {
    function updateABI(ContractType kind, string sabi) external;
    function updateDepools(mapping(address => bool) depools) external;
    function updateImage(ContractType kind, TvmCell image) external;
    function updateAddress(ContractType kind, address addr) external;
}

contract DemiurgeStore {

    /*struct ABI {
        string votingDebotAbi;
        string padawanAbi;
        string proposalAbi;
        string demiurgeAbi;
    }*/

    mapping(uint8 => string) public abis;

    /*struct Images {
        TvmCell proposalImage;
        TvmCell padawanImage;
        TvmCell votingDebotImage;
        TvmCell demiurgeImage;
    }*/

    mapping(uint8 => TvmCell) public images;

    mapping(address => bool) public depools;

    address public priceProvider;

    modifier signed() {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        _;
    }

    function setVotingDebotABI(string sabi) public signed {
        abis[uint8(ContractType.VotingDebot)] = sabi;
    }

    function setPadawanABI(string sabi) public signed {
        abis[uint8(ContractType.Padawan)] = sabi;
    }

    function setDemiurgeABI(string sabi) public signed {
        abis[uint8(ContractType.Demiurge)] = sabi;
    }

    function setProposalABI(string sabi) public signed {
        abis[uint8(ContractType.Proposal)] = sabi;
    }

    function setPadawanImage(TvmCell image) public signed {
        images[uint8(ContractType.Padawan)] = image;
    }

    function setProposalImage(TvmCell image) public signed {
        images[uint8(ContractType.Proposal)] = image;
    }

    function setContestImage(TvmCell image) public signed {
        images[uint8(ContractType.Contest)] = image;
    }

    function setVotingDebotImage(TvmCell image) public signed {
        images[uint8(ContractType.VotingDebot)] = image;
    }

    function setDemiurgeImage(TvmCell image) public signed {
        images[uint8(ContractType.Demiurge)] = image;
    }

    function setJuryGroupImage(TvmCell image) public signed {
        images[uint8(ContractType.JuryGroup)] = image;
    }

    function setJurorImage(TvmCell image) public signed {
        images[uint8(ContractType.Juror)] = image;
    }

    function setContestGiver(TvmCell image) public signed {
        images[uint8(ContractType.ContestGiver)] = image;
    }

    function addDepools(address[] addresses) public signed {
        uint len = addresses.length;
        for(uint i = 0; i < len; i++) {
            depools[addresses[i]] = true;
        }
    }

    function setPriceProvider(address addr) public signed {
        priceProvider = addr;
    }

    /*
     *  Query Store functions
     */

    function queryABI(ContractType kind) public view {
        string sabi = abis[uint8(kind)];
        IDemiurgeStoreCallback(msg.sender).updateABI{value: 0, flag: 64, bounce: false}(kind, sabi);
    }

    function queryDepools() public view {
        IDemiurgeStoreCallback(msg.sender).updateDepools{value: 0, flag: 64, bounce: false}(depools);
    }

    function queryImage(ContractType kind) public view {
        TvmCell image = images[uint8(kind)];
        IDemiurgeStoreCallback(msg.sender).updateImage{value: 0, flag: 64, bounce: false}(kind, image);
    }

    function queryAddress(ContractType kind) public view {
        address addr;
        if (kind == ContractType.PriceProvider) {
            addr = priceProvider;
        }
        IDemiurgeStoreCallback(msg.sender).updateAddress{value: 0, flag: 64, bounce: false}(kind, addr);
    }

}