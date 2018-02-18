pragma solidity ^0.4.17;

import "./EtherbotsMigrations.sol";
import "./Battle.sol";
import "./Tournament.sol";

contract EtherbotsBattle is EtherbotsMigrations {

    // can never remove any of these contracts, can only add
    // once we publish a contract, you'll always be able to play by that ruleset
    // good for two player games which are non-susceptible to collusion
    // people can be trusted to choose the fairest outcome
    // fields which are vulnerable to collusion still have to be centrally controlled :(

    Battle[] approvedBattles;
    Tournament[] approvedTournaments;

    function addApprovedBattle(Battle _battle) external onlyOwner {
        approvedBattles.push(_battle);
    }

    function addApprovedTournament(Tournament _tournament) external onlyOwner {
        approvedTournaments.push(_tournament);
    }

    function _isApprovedTournament() internal view returns (bool) {
        for (uint8 i = 0; i < approvedTournaments.length; i++) {
            if (msg.sender == address(approvedTournaments[i])) {
                return true;
            }
        }
        return false;
    }

    function _isApprovedBattle() internal view returns (bool) {
        for (uint8 i = 0; i < approvedBattles.length; i++) {
            if (msg.sender == address(approvedBattles[i])) {
                return true;
            }
        }
        return false;
    }

    modifier onlyApprovedTournaments(){
        require(_isApprovedTournament());
        _;
    }

    modifier onlyApprovedBattles(){
        require(_isApprovedBattle());
        _;
    }

    struct Etherbot {
        uint[] partIds;
        Part[] parts;
    }
    // // only created during battles

    mapping(address => Reward[]) pendingRewards;

    struct Reward {
        uint blocknumber;
        int32 exp;
    }

    uint8 constant PART_CHANCE = 1;

    /*function claimRewards() external {
        uint[] storage pc = pendingCrates[msg.sender];
        require(pc.length > 0);
        uint8 count = 0;
        for (uint i = 0; i < pc.length; i++) {
            Reward storage reward = pc[i];
            // can't open on the same block
            require(block.number > reward.blocknumber);
            var hash = block.blockhash(reward.blocknumber);
            if (uint(hash) != 0) {
                // different results even on the same block/same user
                // randomness is already taken care of
                uint rand = uint(keccak256(hash, msg.sender, i));
                if (rand % 100 == 100 - PART_CHANCE) {
                    // crate drop time
                   //uint bot = rand % (10 ** 20);
                    // SHOULD CREATE AND TRANSFER A PART.
                   // _importRobot(bytes32ToString(bytes32(bot)));
                } else {
                    // shard drop time
                    //_dropShards(rand);
                }
            } else {
                // can't claim rewards after 256 blocks (~1 hour for now)
                break;
            }
        }
        CratesOpened(msg.sender, count);
        delete pendingCrates[msg.sender];
    }

    function _dropShards(uint rand) external {
        // bell curve distribution
        // have a number from 1 - 100 - PART_CHANCE
        //uint mid = (100 - PART_CHANCE) / 2;
        //uint sd = 10; // TODO: fixed

    }*/

    /*function _addUserReward(address user, int32 _exp) internal {
        // has already been scaled
        pendingRewards[user] = Reward({
            blocknumber: now,
            exp: _exp
        });

    }*/

    function addExperience(address user, uint[] parts, int16[] exps) external onlyApprovedBattles {
        require(parts.length == exps.length);
        int16 sum = 0;
        for (uint i = 0; i < exps.length; i++) {
            sum += _addPartExperience(parts[i], exps[i]);
        }
        _addUserExperience(user, sum);
    }

    // don't need to do any scaling
    // should already have been done by previous stages
    function _addUserExperience(address user, int16 exp) internal {
        // never allow exp to drop below 0
        User memory u = users[userID[user]];
        if (exp < 0 && uint16(int16(u.experience) + exp) > u.experience) {
            u.experience = 0;
        } else if (exp > 0) {
            // check for overflow
            require(uint16(int16(u.experience) + exp) > u.experience);
        }
        u.experience = uint16(int16(u.experience) + exp);
        //_addUserReward(user, exp);
    }

    function setExpScaling(int8 _scale) external onlyOwner {
        expScale = _scale;
    }

    function setExpStart(int8 _start) external onlyOwner {
        expStart = _start;
    }

    int8 public expScale;
    int8 public expStart;

   // exp will go from start
    function _scaleExp(uint32 _battleCount, int16 _exp) internal returns (int16) {
        return _exp * (-1 * int16(_battleCount * _battleCount) / expScale) + expStart;
    }


    function _addPartExperience(uint _id, int16 _baseExp) internal returns (int16) {
        // never allow exp to drop below 0
        Part storage p = parts[_id];
        if (now - p.battlesLastReset > 24 hours) {
            p.battlesLastReset = uint32(block.timestamp);
            p.battlesLastDay = 0;
        }
        int16 exp = _scaleExp(p.battlesLastDay, _baseExp);
        if (exp < 0 && uint16(int16(p.experience) + exp) > p.experience) {
            // check for wrap-around
            p.experience = 0;
        } else if (exp > 0) {
            // check for overflow
            require(uint16(int16(p.experience) + exp) > p.experience);
        }
        parts[_id].experience = uint16(int16(parts[_id].experience) + exp);
        return exp;
    }
    
    function _totalLevel(Etherbot _bot) internal returns (uint16) {
        uint16 total = 0;
        for (uint i = 0; i < _bot.parts.length; i++) {
            total += _getLevel(uint16(parts[_bot.partIds[i]].experience));
        }
        return total;
    }

    function _getLevel(uint16 _exp) internal returns(uint16) {
        return _exp / 1000;
    }

    function hasPartTypes(uint[] partIds, uint8[] types) external returns(bool) {
        if (partIds.length != types.length) {
            return false;
        }
        for (uint i = 0; i < partIds.length; i++) {
            if (parts[partIds[i]].partType != types[i]) {
                return false;
            }
        }
        return true;
    }

}
// }
