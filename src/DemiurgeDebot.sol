pragma ton-solidity >=0.36.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "./interfaces/Debot.sol";
import "./interfaces/Terminal.sol";
import "./interfaces/Menu.sol";
import "./interfaces/Msg.sol";
import "./interfaces/ConfirmInput.sol";
import "./interfaces/AddressInput.sol";
import "./interfaces/Sdk.sol";
import "./interfaces/Upgradable.sol";
import "IDemiurge.sol";
//import "VotingDebot.sol";
import "VotingDebotStub.sol";
import "DemiurgeStub.sol";
import "DemiurgeStore.sol";

contract DemiurgeDebot is DemiurgeStore, Debot, Upgradable {

    // Debot context ids
    uint8 constant STATE_DEPLOY_VOTING_DEBOT_0 = 1;
    uint8 constant STATE_DEPLOY_VOTING_DEBOT_1 = 2;
    uint8 constant STATE_DEPLOY_VOTING_DEBOT_2 = 3;
    uint8 constant STATE_DEPLOY_VOTING_DEBOT_3 = 4;
    uint8 constant STATE_DEPLOY_VOTING_DEBOT_4 = 5;
    uint8 constant STATE_DEPLOY_DEMIURGE       = 6;
    uint8 constant STATE_TRANSFER              = 7;
    uint8 constant STATE_SET_DEMI              = 8;
    uint8 constant STATE_SUCCEEDED             = 9;

    uint128 constant MIN_DEBOT_BALANCE = 1 ton;
    /*
        Storage
    */

    TvmCell _votingDebotState;
    uint256 _deployKey;
    address _userDebotAddr;
    uint128 _userDebotBalance;
    TvmCell _demiState;
    address _demiurge;
    uint128 _balance;

    uint32 _retryId;

    uint256 _pub;
    uint256 _sec;

    // helper modifier
    modifier accept() {
        tvm.accept();
        _;
    }

    /*
     *   Init functions
     */

    constructor(address priceProv) public signed {
        priceProvider = priceProv;
    }

    function setDemiurgeAddress(address addr) public signed {
        _demiurge = addr;
    }

    function deployDemiurge(uint256 pubkey) public signed {
        uint256[] initialJury = [
            0x82c9fc3bf4a0afedc84e1a087807d31fbc5ebd4f3589172b983852af3622ca63,
            0x9ac54dc117413c19ed5759c4e183671edb32f078dd4b18ab46bea8e3a7abdb68,
            0xc1b17b2ca24349320d0e4617342c3775a5ff5b08e7761e181c96a099bdd89eb5
        ];
        TvmCell image = tvm.insertPubkey(images[uint8(ContractType.Demiurge)], pubkey);
        _demiurge = new Demiurge{stateInit: image, value: 30 ton, bounce: true}(address(this), initialJury);
    }

    function deployVotingDebot(address demi, uint256 pubkey) public signed {
        TvmCell image = tvm.insertPubkey(images[uint8(ContractType.VotingDebot)], pubkey);
        new VotingDebot{stateInit: image, value: 10 ton, bounce: true}(address(this), demi);
    }

    function getDemiurge() public view returns (address addr) {
        return _demiurge;
    }

    /*
     *  Overrided Debot functions
     */

    /// @notice Returns Metadata about DeBot.
    function getDebotInfo() public functionID(0xDEB) override view returns(
        string name, string version, string publisher, string key, string author,
        address support, string hello, string language, string dabi, bytes icon
    ) {
        name = "Demiurge Debot";
        version = "1.6.0";
        publisher = "RSquad";
        key = "Deploy SMV system and create personal voting debot.";
        author = "RSquad";
        support = address.makeAddrStd(0, 0x0);
        hello = "Hello, i am Demiurge Debot.";
        language = "en";
        dabi = m_debotAbi.get();
        icon = "";
    }

    function getRequiredInterfaces() public view override returns (uint256[] interfaces) {
        return [ Terminal.ID, Menu.ID, AddressInput.ID, ConfirmInput.ID ];
    }

    function start () public override {
        _pub = 0x042ba05fab575ae9488b5a4b49b293f07b885cad09a21292aaaa3c26ebba1c66;
        _sec = 0x14de59851748d1df1c986de13c4e6d52291e6b832524f67278935578f0b58305;
        Sdk.getBalance(tvm.functionId(setDemiBalance), _demiurge);
        Terminal.print(0, "Hello, user, i'm a Demiurge Debot.");
        Terminal.print(0, format("Current Demiurge: {}", _demiurge));
        Menu.select("What do you want to do?", "", [
            MenuItem("Deploy new demiurge", "", tvm.functionId(deployDemi)),
            MenuItem("Attach existed demiurge", "", tvm.functionId(attachDemi)),
            MenuItem("Deploy user voting debot", "", tvm.functionId(deployUser))
        ]);
    }

    function deployDemi(uint32 index) public {
        index = index;
        Terminal.print(0, "Please, generate seed phrase for new demiurge.");
        Terminal.input(tvm.functionId(setDemiKey), "Enter public key derived from this phrase:", false);
    }

    function attachDemi(uint32 index) public {
        index = index;
        AddressInput.get(tvm.functionId(setDemiAddress), "Enter Demiurge address:");
    }

    function deployUser(uint32 index) public {
        index = index;
        Terminal.print(0, "I'll guide you step by step to deploy your personal debot for voting.\nThis debot will help you create proposals, vote for proposals and also deposit and reclaim funds for voting.");
        Terminal.print(0, "Generate seed phrase for your personal debot. Keep it in secret because you will use it to control debot.");
        Terminal.input(tvm.functionId(setVotingKey), "Enter public key derived from seed phrase:", false);
    }

    function setVotingKey(string value) public {
        (uint256 key, bool res) = stoi("0x" + value);
        if (!res) return;
        _deployKey = key;

        _votingDebotState = tvm.insertPubkey(images[uint8(ContractType.VotingDebot)], _deployKey);
        _userDebotAddr = address.makeAddrStd(0, tvm.hash(_votingDebotState));
        Terminal.print(0, format("Voting debot address:\n{}", _userDebotAddr));
        ConfirmInput.get(tvm.functionId(callDeployVotingDebot), "Ready to deploy?");
    }

    function callDeployVotingDebot(bool value) public {
        if (!value) return;
        optional(uint256) pubkey = _pub;
        _retryId = tvm.functionId(callDeployVotingDebot);
        TvmCell message = tvm.buildExtMsg({
            abiVer: 2,
            dest: address(this),
            callbackId: tvm.functionId(onSuccessfulDeploy),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            sign: true,
            pubkey: pubkey,
            call: {DemiurgeDebot.deployVotingDebot, _demiurge, _deployKey}
        });
        Msg.sendWithKeypair(tvm.functionId(onSuccessfulDeploy), message, _pub, _sec);
    }

    function setDemiBalance(uint128 nanotokens) public {
        _balance = nanotokens;
        Terminal.print(0, format("Demiurge balance: {} nanotokens", nanotokens));
    }

    function setDemiKey(string value) public {
        (uint256 key, bool res) = stoi("0x" + value);
        if (!res) return;
        _deployKey = key;
        _demiState = tvm.insertPubkey(images[uint8(ContractType.Demiurge)], _deployKey);
        _demiurge = address.makeAddrStd(0, tvm.hash(_demiState));

        Terminal.print(0, format("New demiurge address:\n{}", _demiurge));
        ConfirmInput.get(tvm.functionId(callDeployDemiurge), "Ready to deploy?");
    }

    function callDeployDemiurge(bool value) public {
        if (!value) return;
        optional(uint256) pubkey = _pub;
        _retryId = tvm.functionId(callDeployDemiurge);
        TvmCell message = tvm.buildExtMsg({
            abiVer: 2,
            dest: address(this),
            callbackId: tvm.functionId(onSuccessfulDeploy),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            sign: true,
            pubkey: pubkey,
            call: {DemiurgeDebot.deployDemiurge, _deployKey}
        });
        Msg.sendWithKeypair(tvm.functionId(onSuccessfulDeploy), message, _pub, _sec);
    }

    function onSuccessfulDeploy() public pure {
        optional(uint256) none;
        this.getDemiurge{
            abiVer: 2,
            extMsg: true,
            callbackId: tvm.functionId(updateDemi),
            onErrorId: 0,
            time: 0,
            expire: 0,
            sign: false,
            pubkey: none
        }();
    }

    function updateDemi(address addr) public {
        _demiurge = addr;
        Terminal.print(tvm.functionId(Debot.start), "Deploy succeeded.");
    }

    function onSuccessfulSet() public {
        Terminal.print(tvm.functionId(Debot.start), "Succeeded.");
    }

    function onError(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, format("Deploy failed. Sdk error {}. Exit code {}.", sdkError, exitCode));
        ConfirmInput.get(_retryId, "Do you want to retry?");
    }

    function setDemiAddress(address value) public {
        _demiurge = value;
        optional(uint256) pubkey = _pub;
        _retryId = tvm.functionId(retrySetAddress);
        TvmCell message = tvm.buildExtMsg({
            abiVer: 2,
            dest: address(this),
            callbackId: tvm.functionId(onSuccessfulSet),
            onErrorId: tvm.functionId(onError),
            time: uint32(now),
            expire: 0,
            sign: true,
            pubkey: pubkey,
            call: {DemiurgeDebot.setDemiurgeAddress, _demiurge}
        });
        Msg.sendWithKeypair(tvm.functionId(onSuccessfulSet), message, _pub, _sec);
    }

    function retrySetAddress(bool value) public {
        if (!value) return;
        setDemiAddress(_demiurge);
    }

    /*
     *  Helpers
     */

    function tokens(uint128 nanotokens) private pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    }

    function onCodeUpgrade() internal override {
        tvm.resetStorage();
        _pub = 0x042ba05fab575ae9488b5a4b49b293f07b885cad09a21292aaaa3c26ebba1c66;
        _sec = 0x14de59851748d1df1c986de13c4e6d52291e6b832524f67278935578f0b58305;
        priceProvider = address.makeAddrStd(0, 0x9e9f912a67088341a9cd04330c40eff63300c52bf2fb4634e286a6d0d1e9a77c);
    }
}
