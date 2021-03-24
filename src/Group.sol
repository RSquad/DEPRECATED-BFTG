pragma ton-solidity >= 0.36.0;

import "Base.sol";
import "IDemiurge.sol";
import "IGroup.sol";

contract Group is Base, IGroup {

    enum Topic { Undefined, Generic, Recruit, Revoke, Other, Reserved, Last }

    /* Group-wide settings */

    uint32 _totalVotes;
    uint32 _startIn;

    struct Template {
        uint32 votingWindow;
        string description;
        string proposal;
        VoteCountModel model;
    }

    mapping (Topic => Template) _tl; // Templates library

    struct Member {
        uint32 id;
        string nick;
        uint pubkey;
        address addr;
        uint32 candidateId;
        uint32 ts;
    }

//    mapping (address => Member) _members;
    mapping (address => uint32) _members;

    struct Candidate {
        uint32 id;
        uint pubkey;
        address contact;
        address application;
        uint32 proposalId;
        uint32 ts;
    }

    uint32 _membersCounter;
    uint32 _candidatesCounter;

//    mapping (address => Candidate) _candidates;

    mapping (address => uint32) _candidates;
    address _deployer;

    struct OnVoting {
        uint32 id;
        address proposalAddr;
        Topic topic;
        address subject;
    }

    OnVoting _current;

    mapping (uint32 => OnVoting) _active;

    function initGroup(address deployer) external accept {
        _deployer = deployer;
        _totalVotes = 100;
        _startIn = 1 minutes;
        initGroupTemplates();
    }

    function setDeployer(address addr) external accept {
        _deployer = addr;
    }

    function setInitialMembers(address[] addrs) external accept {
        for (address a : addrs) {
            this.addMember(_membersCounter, a);
            _membersCounter++;
        }
    }

    function initGroupTemplates() public accept {
        _tl[Topic.Generic] = Template(1 hours, "<TITLE> ", "<BODY>", VoteCountModel.Majority);
        _tl[Topic.Recruit] = Template(1 hours, "Add ", "Request to add a member to the group", VoteCountModel.SoftMajority);
        _tl[Topic.Revoke]  = Template(3 hours, "Remove ", "Request to remove a member from the group", VoteCountModel.SuperMajority);
    }

    function _submitProposal(Topic topic, string toHeader, string toBody) private inline {
        Template t = _tl[topic];
        uint32 tnow = uint32(now);
        uint32 start = tnow + _startIn;
        uint32 end = start + t.votingWindow;
        string header = t.description + toHeader;
        string body = t.proposal + toBody;
        address[] voters;
        for ((address a, ) : _members) {
            voters.push(a);
        }
        IDemiurge(_deployer).deployProposalWithWhitelist{value: DEPLOY_FEE}(_totalVotes, start, end, header, body, t.model, voters);
        _current.id = _candidatesCounter;
        _current.topic = topic;
    }

    /* deploy a proposal to vote for adding a member */
    function applyFor(string name) external override {
        _current.subject = msg.sender;
        _submitProposal(Topic.Recruit, name, name/* + format("{}", msg.sender)*/);
    }

    function resign() external pure {
        /* remove a member by one's own will. Does not require voting  */
        this.removeMember(msg.sender);
    }

    /* deploy a proposal to vote for removing a member*/
    function unseat(uint32 id, address addr) external override {
        _current.subject = addr;
        id = id;
//          _submitProposal(Topic.Revoke, string(id), string(id) /*, format("{}", msg.sender)*/);
    }

    function addMember(uint32 id, address addr) external me {
        _members[addr] = id;
    }

    function removeMember(address addr) external me {
        delete _members[addr];
    }

    /* callbacks */
    function onProposalDeployed(uint32 id, address addr) external {
        _current.proposalAddr = addr;
        _active[id] = _current;
        delete _current;
        _candidatesCounter++;
    }

    function onProposalCompletion(uint32 id, bool result) external {
        if (!result) {
            // archive this
            delete _active[id];
            return;
        }

        OnVoting voted = _active[id];
        Topic s = voted.topic;
        address subject = voted.subject;

        if (s == Topic.Recruit) {
            this.addMember(_membersCounter, subject);
            _membersCounter++;

        } else if (s == Topic.Revoke) {
            this.removeMember(subject);
        }
    }

    function getMembers() public view returns (mapping (address => uint32) members) {
        members = _members;
    }

    function getActive() public view returns (mapping (uint32 => OnVoting) active) {
        active = _active;
    }

    function getCandidates() public view returns (mapping (address => uint32) candidates) {
        candidates = _candidates;
    }


}