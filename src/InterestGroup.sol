pragma ton-solidity >= 0.36.0;

import "Group.sol";
import "IInterestGroup.sol";
import "IInterestGroupClient.sol";

contract InterestGroup is IInterestGroup, Group {

    uint32 public _id;
    string public _tag;
    bool public _isOccupied;

    uint16 constant BLUNDER = 1;
    uint16 constant LACK = 2;
    uint16 constant SHORTAGE = 3;

    struct MemberData {
        bool isAvailable;
        uint32 reqId;
        address addr;
        uint32 ts;
    }

    mapping (uint32 => MemberData) public _statusQuo; // hide later

    function inquire(uint32 contestId, uint32[] reqs) external override {
        uint32[] fit;
        for (uint32 rid: reqs) {
            // examine the reqs. i.e. check that groupId matches, req is open etc.
//            if ((req.groupId == grId) && (req.status >= ReqStatus.Query) && (req.status <= ReqStatus.Confirm)) {
                fit.push(rid);
//            }
        }

        if (_membersCounter < fit.length) {
            IInterestGroupClient(msg.sender).lapse{value: DEF_RESPONSE_VALUE}(contestId, LACK);
        }
        uint32[] ids;
        for ((uint32 memberId, MemberData memberData): _statusQuo) {
            if (memberData.isAvailable) {
                ids.push(memberId);
            }
        }
        if (ids.length < fit.length) {
            IInterestGroupClient(msg.sender).lapse{value: DEF_RESPONSE_VALUE}(contestId, SHORTAGE);
        }
        IInterestGroupClient(msg.sender).updateRoster{value: DEF_COMPUTE_VALUE}(contestId, _id, ids);
    }

    function setTag(string tag) external {
        _tag = tag;
    }

    function setId(uint32 id) external {
        _id = id;
    }

    function offer(uint32 contestId, mapping (uint32 => uint32) offers) external override {
        mapping (uint32 => address) staff;
        for ((uint32 eid, uint32 rid): offers) {
            _statusQuo[eid].isAvailable = false;
            _statusQuo[eid].reqId = rid;
            staff[rid] = _statusQuo[eid].addr;
            _statusQuo[eid].ts = uint32(now);
        }
        IInterestGroupClient(msg.sender).confirm{value: DEF_COMPUTE_VALUE}(contestId, staff);
    }

}