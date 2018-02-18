pragma solidity ^0.4.17;

import "./EtherbotsBattle.sol";
import "./Battle.sol";
import "./Base.sol";
import "./AccessControl.sol";

contract TwoPlayerCommitRevealBattle is Battle, Ownable {

    EtherbotsBattle _base;

    function TwoPlayerCommitRevealBattle(EtherbotsBattle base) public {
        _base = base;
    }

    function name() external view returns (string) {
        return "2PCR";
    }

    function playerCount() external view returns (uint) {
        return duelingPlayers;
    }

    enum DuelStatus {
        Open, Exhausted, Completed, Cancelled
    }

    // TODO: packing?
    struct Duel {
        uint feeRemaining;
        uint[] defenderParts;
        bytes32 defenderCommit;
        uint64 maxAcceptTime;
        address defenderAddress;
        Attacker[] attackers;
        DuelStatus status;
    }

    struct Attacker {
        uint[] parts;
        uint8[] moves;
    }

    // ID maps to index in battles array.
    // TODO: do we need this?
    // TODO: don't think we ever update it
    // if we want to find all the duels for a user, just use external view
    mapping (address => uint[]) public addressToDuels;
    Duel[] public duels;
    uint public duelingPlayers;

    /*
    =========================
    OWNER CONTROLLED FIELDS
    =========================
    */

    uint8 public maxAttackers = 16;

    function setMaxAttackers(uint8 _max) external onlyOwner {
        BattlePropertyChanged("Defender Fee", uint(maxAttackers), uint(_max));
        maxAttackers = _max;
    }

    // centrally controlled fields
    // CONSIDER: can users ever change these (e.g. different time per battle)
    // CONSIDER: how do we incentivize users to fight 'harder' bots
    uint public maxRevealTime;
    uint public attackerFee;
    uint public defenderFee;
    uint public attackerRefund;
    uint public defenderRefund;

    function setDefenderFee(uint _fee) external onlyOwner {
        BattlePropertyChanged("Defender Fee", defenderFee, _fee);
        defenderFee = _fee;
    }

    function setAttackerFee(uint _fee) external onlyOwner {
        BattlePropertyChanged("Attacker Fee", attackerFee, _fee);
        attackerFee = _fee;
    }

    function setAttackerRefund(uint _refund) external onlyOwner {
        BattlePropertyChanged("Attacker Refund", attackerRefund, _refund);
        attackerRefund = _refund;
    }

    function setDefenderRefund(uint _refund) external onlyOwner {
        BattlePropertyChanged("Defender Refund", defenderRefund, _refund);
        defenderRefund = _refund;
    }

    function _makePart(uint _id) internal returns(EtherbotsBase.Part) {
        var (pt, pst, rarity, element, bld, exp, forgeTime, blr) = _base.getPartById(_id);
        return EtherbotsBase.Part({
            partType: pt,
            partSubType: pst,
            rarity: rarity,
            element: element,
            battlesLastDay: bld,
            experience: exp,
            forgeTime: forgeTime,
            battlesLastReset: blr
        });
    }

    /*
    =========================
    EXTERNAL BATTLE FUNCTIONS
    =========================
    */

    // commit should be in the form of:
    // uint[8]|random string
    function defenderCommitMoves(uint[] partIds, bytes32 _movesCommit) external payable {

        // will fail if the user doesn't own any of the parts
        // no need for a owns all
        _base.transferAll(msg.sender, this, partIds);

        require(_movesCommit != "");

        require(msg.value >= defenderFee);

        // check parts
        uint8[] memory types = [0, 1, 2, 3];
        require(_base.hasPartTypes(partIds, types));

        // is this the way of balancing the benefit of attacking?
        // should we have a max number of people who can attack one defender if we're going down this route?
        Duel memory _duel = Duel({
            defenderAddress: msg.sender,
            defenderParts: partIds,
            defenderCommit: _movesCommit,
            maxAcceptTime: uint64(now + maxRevealTime),
            status: DuelStatus.Open,
            attackers: new Attacker[](0),
            feeRemaining: msg.value
        });
        // TODO: -1 here?
        uint256 newDuelId = duels.push(_duel) - 1;
        duelingPlayers++; // doesn't matter if we overcount
        addressToDuels[msg.sender].push(newDuelId);
        BattleCreated(newDuelId, msg.sender);
    }

    function attack(uint _duelId, uint[] parts, uint8[] _moves) external payable returns(bool) {

        // check that it's your robot
        require(_base.ownsAll(msg.sender, parts));

        // check that the moves are readable
        require(_isValidMoves(_moves));

        Duel storage duel = duels[_duelId];
        // the duel must be open
        require(duel.status == DuelStatus.Open);
        require(duel.attackers.length < maxAttackers);
        require(msg.value >= attackerFee);

        // checks part independence and timing
        require(_canAttack(duel, parts));

        if (duel.feeRemaining < attackerFee) {
            // just do a return - no need to punish the attacker
            // mark as exhaused
            duel.status = DuelStatus.Exhausted;
            return false;
        }
        duel.feeRemaining -= defenderFee;

        // already guaranteed
        Attacker memory a = Attacker({
            attackerParts: parts,
            moves: _moves
        });

        duel.attackers.push(a);

        // increment those battling
        duelingPlayers++;
        return true;
    }

    function _canAttack(Duel _duel, uint[] parts) internal returns(bool) {
        // short circuit if trying to attack yourself
        // obviously can easily get around this, but may as well check
        if (_duel.defender == msg.sender) {
            return false;
        }
        // the same part cannot attack the same bot at the same time
        for (uint i = 0; i < _duel.attackers.length; i++) {
            for (uint j = 0; j < _duel.attackers[i].parts.length; j++) {
                if (_duel.attackers[i].partIds[j] == parts[j]) {
                    return false;
                }
            }
        }
        return true;
    }

    uint8 constant MOVE_LENGTH = 8;

    function _isValidMoves(uint8[] _moves) internal returns(bool) {
        if (_moves.length != MOVE_LENGTH) {
            return false;
        }
        for (uint i = 0; i < MOVE_LENGTH; i++) {
            if (_moves[i] < MOVE_COUNT) {
                return false;
            }
        }
        return true;
    }

    function defenderRevealMoves(uint _duelId, uint8[] _moves, bytes32 _seed) external returns(bool) {

        Duel storage _duel = duels[_duelId];

        require(_duel.defender.owner == msg.sender);

        // require(bytes(_moves).length == 8);
        if (_duel.defenderCommit != keccak256(_moves, _seed)) {
            // InvalidAction("Moves did not match move commit");
            return false;
        }
        // after the defender has revealed their moves, perform all the duels
        for (uint i = 0; i < _duel.attackers.length; i++) {
            Attacker memory tempA = _duel.attackers[i];
            // TODO: gas limit?
            _executeMoves(_duelId, _duel, _moves, tempA);
        }
        duelingPlayers -= (_duel.attackers.length + 1);
        // give back an extra fees
        _refundDuelFee();
        // send back ownership of parts
        _base.transferAll(this, _duel.defender.owner, _duel.defender.parts);
        _duel.status = DuelStatus.Completed;
        return true;
    }

    // should only be used where the defender has forgotten their moves
    // forfeits every battle
    function cancelDuel(uint _duelId) external {

        Duel storage _duel = duels[_duelId];

        // can only be called by the defender
        require(msg.sender == _duel.defender);

        for (uint i = 0; i < _duel.attackers.length; i++) {
            Attacker memory tempA = _duel.attackers[i];
            _winBattle(_duel.defender);
        }
        // no gas refund for cancelling
        // encourage people to battle rather than cancel
        _refundDuelFee();
        _base.transferAll(this, _duel.defender.owner, _duel.defender.partIds);
        _duel.status = DuelStatus.Cancelled;
    }

    // after the time limit has elapsed, anyone can claim victory for all the attackers
    // have to pay gas cost for all
    // todo: how much will this cost for 256 attackers?
    function claimTimeVictory(uint _duelId) external {
        Duel storage _duel = duels[_duelId];
        // let anyone claim it to stop boring iteration
        require(now > _duel.maxRevealTime);
        for (uint i = 0; i < _duel.attackers.length; i++) {
            Attacker memory tempA = _duel.attackers[i];
            _winBattle(tempA.attacker, _duel.defender);
        }
        _refundAttacker(_duel.attackers.length);
        // refund the defender
        _refundDuelFee();
        _base.transferAll(this, _duel.defender.owner, _duel.defender.parts);
        _duel.status = DuelStatus.Completed;
    }

    function _refundDefender(uint _count) internal {
        uint refund = (_count * defenderFee);
        if (refund > 0) {
            msg.sender.transfer(refund);
        }
    }

    function _refundAttacker(uint _count) internal {
        // they have paid for everyone else to win
        // could be quite expensive
        uint refund = (_count * attackerFee);
        if (refund > 0) {
            msg.sender.transfer(refund);
        }
    }

    function _refundDuelFee(Duel _duel) internal {
        if (_duel.feeRemaining > 0) {
            uint a = _duel.feeRemaining;
            _duel.feeRemaining = 0;
            _duel.defender.transfer(_duel.feeRemaining);
        }
    }

    uint16 constant EXP_BASE = 100;
    uint16 constant WINNER_EXP = 3;
    uint16 constant LOSER_EXP = 1;

    uint8 constant BONUS_PERCENT = 5;
    uint8 constant ALL_BONUS = 5;

    // Parts reminder: Blueprint represents details of the part:
    // [2] part level (experience),
    // [3] rarity status, (representing, i.e., "gold")
    // [4] elemental type, (i.e., "water")

    function getPartBonus(uint movingPart, EtherbotsBattle.Etherbot bot) internal returns (uint8) {
        uint8 typ = movingPart.rarity;
        // apply bonuses
        uint8 matching = 0;
        for (uint8 i = 0; i < bot.parts.length; i++) {
            if (bot.parts[i].rarity == typ) {
                matching++;
            }
        }
        // matching will never be less than 1
        uint8 bonus = (matching - 1) * BONUS_PERCENT;
        return bonus;
    }

    uint8 constant PERK_BONUS = 5;
    uint8 constant PRESTIGE_INC = 1;
    // level 0
    uint8 constant PT_PRESTIGE_INDEX = 0;
    // level 1
    uint8 constant PT_OFFENSIVE = 1;
    uint8 constant PT_DEFENSIVE = 2;
    // level 2
    uint8 constant PT_MELEE = 3;
    uint8 constant PT_TURRET = 4;
    uint8 constant PT_DEFEND = 5;
    uint8 constant PT_BODY = 6;
    // level 3
    uint8 constant PT_MELEE_MECH = 7;
    uint8 constant PT_MELEE_ANDROID = 8;
    uint8 constant PT_TURRET_MECH = 9;
    uint8 constant PT_TURRET_ANDROID = 10;
    uint8 constant PT_DEFEND_MECH = 11;
    uint8 constant PT_DEFEND_ANDROID = 12;
    uint8 constant PT_BODY_MECH = 13;
    uint8 constant PT_BODY_ANDROID = 14;
    // level 4
    uint8 constant PT_MELEE_ELECTRIC = 15;
    uint8 constant PT_MELEE_STEEL = 16;
    uint8 constant PT_MELEE_FIRE = 17;
    uint8 constant PT_MELEE_WATER = 18;
    uint8 constant PT_TURRET_ELECTRIC = 19;
    uint8 constant PT_TURRET_STEEL = 20;
    uint8 constant PT_TURRET_FIRE = 21;
    uint8 constant PT_TURRET_WATER = 22;
    uint8 constant PT_DEFEND_ELECTRIC = 23;
    uint8 constant PT_DEFEND_STEEL = 24;
    uint8 constant PT_DEFEND_FIRE = 25;
    uint8 constant PT_DEFEND_WATER = 26;
    uint8 constant PT_BODY_ELECTRIC = 27;
    uint8 constant PT_BODY_STEEL = 28;
    uint8 constant PT_BODY_FIRE = 29;
    uint8 constant PT_BODY_WATER = 30;

    uint8 constant DODGE = 0;
    uint8 constant DEFEND = 1;
    uint8 constant MELEE = 2;
    uint8 constant TURRET = 3;

    uint8 constant FIRE = 0;
    uint8 constant WATER = 1;
    uint8 constant STEEL = 2;
    uint8 constant ELECTRIC = 3;

    // TODO: might be a more efficient way of doing this
    // read: almost definitely is
    // would destroy legibility tho?
    // will get back to it --> pretty gross rn
    function _applyBonusTree(uint8 move, EtherbotsBattle.Etherbot bot, uint8[32] tree) internal returns (uint8 bonus) {
        uint8 prestige = tree[PT_PRESTIGE_INDEX];
        if (move == DEFEND || move == DODGE) {
            if (hasPerk(tree, PT_DEFENSIVE)) {
                bonus = _applyPerkBonus(bonus, prestige);
                if (move == DEFEND && hasPerk(tree, PT_DEFEND)) {
                    bonus = _applyPerkBonus(bonus, prestige);
                    if (hasPerk(tree, PT_DEFEND_MECH)) {
                        bonus = _applyPerkBonus(bonus, prestige);
                        if (getMoveType(bot, move) == ELECTRIC && hasPerk(tree, PT_DEFEND_ELECTRIC)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        } else if (getMoveType(bot, move) == STEEL && hasPerk(tree, PT_DEFEND_STEEL)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        }
                    } else if (hasPerk(tree, PT_DEFEND_ANDROID)) {
                        bonus = _applyPerkBonus(bonus, prestige);
                        if (getMoveType(bot, move) == FIRE && hasPerk(tree, PT_DEFEND_FIRE)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        } else if (getMoveType(bot, move) == WATER && hasPerk(tree, PT_DEFEND_WATER)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        }
                    }
                } else if (move == DODGE && hasPerk(tree, PT_BODY)) {
                    bonus = _applyPerkBonus(bonus, prestige);
                    bonus = _applyPerkBonus(bonus, prestige);
                    if (hasPerk(tree, PT_BODY_MECH)) {
                        bonus = _applyPerkBonus(bonus, prestige);
                        if (getMoveType(bot, move) == ELECTRIC && hasPerk(tree, PT_BODY_ELECTRIC)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        } else if (getMoveType(bot, move) == STEEL && hasPerk(tree, PT_BODY_STEEL)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        }
                    } else if (hasPerk(tree, PT_BODY_ANDROID)) {
                        bonus = _applyPerkBonus(bonus, prestige);
                        if (getMoveType(bot, move) == FIRE && hasPerk(tree, PT_BODY_FIRE)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        } else if (getMoveType(bot, move) == WATER && hasPerk(tree, PT_BODY_WATER)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        }
                    }
                }
            }
        } else {
            if (hasPerk(tree, PT_OFFENSIVE)) {
                bonus = _applyPerkBonus(bonus, prestige);
                if (move == MELEE && hasPerk(tree, PT_MELEE)) {
                    bonus = _applyPerkBonus(bonus, prestige);
                    if (hasPerk(tree, PT_MELEE_MECH)) {
                        bonus = _applyPerkBonus(bonus, prestige);
                        if (getMoveType(bot, move) == ELECTRIC && hasPerk(tree, PT_MELEE_ELECTRIC)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        } else if (getMoveType(bot, move) == STEEL && hasPerk(tree, PT_MELEE_STEEL)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        }
                    } else if (hasPerk(tree, PT_MELEE_ANDROID)) {
                        bonus = _applyPerkBonus(bonus, prestige);
                        if (getMoveType(bot, move) == FIRE && hasPerk(tree, PT_MELEE_FIRE)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        } else if (getMoveType(bot, move) == WATER && hasPerk(tree, PT_MELEE_WATER)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        }
                    }
                } else if (move == TURRET && hasPerk(tree, PT_TURRET)) {
                    bonus = _applyPerkBonus(bonus, prestige);
                    bonus = _applyPerkBonus(bonus, prestige);
                    if (hasPerk(tree, PT_TURRET_MECH)) {
                        bonus = _applyPerkBonus(bonus, prestige);
                        if (getMoveType(bot, move) == ELECTRIC && hasPerk(tree, PT_TURRET_ELECTRIC)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        } else if (getMoveType(bot, move) == STEEL && hasPerk(tree, PT_TURRET_STEEL)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        }
                    } else if (hasPerk(tree, PT_TURRET_ANDROID)) {
                        bonus = _applyPerkBonus(bonus, prestige);
                        if (getMoveType(bot, move) == FIRE && hasPerk(tree, PT_TURRET_FIRE)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        } else if (getMoveType(bot, move) == WATER && hasPerk(tree, PT_TURRET_WATER)) {
                            bonus = _applyPerkBonus(bonus, prestige);
                        }
                    }
                }
            }
        }
    }

    function getMoveType(EtherbotsBattle.Etherbot _bot, uint8 _move) internal returns(uint8) {
        return _bot.parts[_move].element;
    }

    function hasPerk(uint8[32] tree, uint8 perk) internal returns(bool) {
        return tree[perk] > 0;
    }

    uint8 constant PRESTIGE_BONUS = 1;

    function _applyPerkBonus(uint8 bonus, uint8 prestige) internal returns (uint8) {
        return bonus + (PERK_BONUS + (prestige * PRESTIGE_BONUS));
    }

   function getPerkBonus(uint8 move, EtherbotsBattle.Etherbot bot) internal returns (uint8) {
       var t = _base.getPerkTree(msg.sender);
       return _applyBonusTree(move, bot, t);
   }

   uint constant EXP_BONUS = 1;
   uint constant EVERY_X_LEVELS = 2;

   function getExpBonus(uint8 move, EtherbotsBattle.Etherbot bot) internal returns (uint8) {
       return (_base._totalLevel(bot.parts) * EXP_BONUS) / EVERY_X_LEVELS;
   }

   uint8 constant SHADOW_BONUS = 5;
   uint8 constant GOLD_BONUS = 10;

    // allow for more rarities
    // might never implement: undroppable rarities
    // 5 gold parts can be forged into a diamond
    // assumes rarity as follows: standard = 0, shadow = 1, gold = 2
    // shadow gives base 5% boost, gold 10% ...
   function getRarityBonus(uint8 move, EtherbotsBattle.Part[] parts) internal returns (uint8) {
        // bonus applies per part (but only if you're using the rare part in this move)
        uint rarity = parts[move].rarity;
        uint count = 0;
        if (rarity == 0) {
            // standard rarity, no bonus
            return 0;
        }
        for (uint8 i = 0; i < parts.length; i++) {
            if (parts[i].rarity == rarity) {
                count++;
            }
        }
        uint8 bonus = count * BONUS_PERCENT;
        return bonus;
   }

   function _applyBonuses(uint8 move, EtherbotsBattle.Etherbot bot, uint16 _dmg) internal returns(uint16) {
       // perks only land if you won the move
       uint16 _bonus = getPerkBonus(move, bot);
       _bonus += getPartBonus(move, bot);
       _bonus += getExpBonus(move, bot);
       _bonus += getRarityBonus(move, bot);
       _dmg += (_dmg * _bonus) / 100;
       return _dmg;
   }

   // what about collusion - can try to time the block?
   // obviously if colluding could just pick exploitable moves
   // this is random enough for two non-colluding parties
   function randomSeed(uint8[] defenderMoves, uint8[] attackerMoves) internal returns (uint) {
       return uint(defenderMoves ^ attackerMoves);
   }

   // when using a move of a type, you get a bonus based on
   function _executeMoves(uint _duelId, EtherbotsBattle.Etherbot defender, EtherbotsBattle.Etherbot attacker) internal {
       uint seed = randomSeed(defender.moves, attacker.moves);
       var totalAttackerDamage = 0;
       var totalDefenderDamage = 0;
       // works just the same for draws
       for (uint i = 0; i < MOVE_LENGTH; i++) {
           // TODO: check move for validity?
           var attackerMove = attacker.moves[i];
           var defenderMove = defender.moves[i];

           var (attackerDamage, defenderDamage) = _calculateBaseDamage(attackerMove, defenderMove);

           attackerDamage = _applyBonuses(attackerMove, attacker, attackerDamage);
           defenderDamage = _applyBonuses(defenderMove, defender, defenderDamage);

           attackerDamage = _applyRandomness(seed, attackerDamage);
           defenderDamage = _applyRandomness(seed, defenderDamage);

           if (attackerDamage == defenderDamage) {
               // no draws lads
               if (seed % 2 == 0) {
                   attackerDamage++;
               } else {
                   defenderDamage++;
               }
           }

           totalAttackerDamage += attackerDamage;
           totalDefenderDamage += defenderDamage;

           if (attackerDamage > defenderDamage) {
               // stage win for the winner
               // do them here rather than lots of intermediate calls
               BattleStage(_duelId);
           } else if (defenderDamage < attackerDamage) {
               BattleStage(_duelId);
           }
       }
       if (totalAttackerDamage == totalDefenderDamage) {
           // no draws ladettes
           if (seed % 2 == 0) {
               attackerDamage++;
           } else {
               defenderDamage++;
           }
       }
       if (totalAttackerDamage > totalDefenderDamage) {
           _base.winBattle(_duelId, attacker.owner, totalAttackerDamage, defender.owner, totalDefenderDamage);
       } else {
           _base.winBattle(_duelId, defender.owner, totalDefenderDamage, attacker.owner, totalAttackerDamage);
       }
   }

   uint constant RANGE = 40;

   function _applyRandomness(uint seed, uint16 _dmg) internal returns (uint16) {
       // damage can be modified between 1 - (RANGE/2) and 1 + (RANGE/2)
       // keep things interesting!
       _dmg = 0;
       seed = seed % RANGE;
       if (seed > (RANGE / 2)) {
           // seed is 21 or above
           _dmg += (_dmg * (seed / 2)) / 100;
       } else {
           // seed is 20 or below
           // this way makes 0 better than 20 --> who cares
           _dmg -= (_dmg * seed) / 100;
       }
       return _dmg;
   }

   // every move
   uint16 constant BASE_DAMAGE = 1000;
   uint8 constant WINNER_SPLIT = 3;
   uint8 constant LOSER_SPLIT = 1;

   function _calculateBaseDamage(uint8 a, uint8 d) internal returns(uint16, uint16) {
       if (a == d) {
           // even split
           return (BASE_DAMAGE / 2, BASE_DAMAGE / 2);
       }
       if (defeats(a, d)) {
           // 3 - 1 split
           return ((BASE_DAMAGE / (WINNER_SPLIT + LOSER_SPLIT)) * WINNER_SPLIT,
               (BASE_DAMAGE / (WINNER_SPLIT + LOSER_SPLIT)) * LOSER_SPLIT);
       } else if (defeats(d, a)) {
           // 3 - 1 split
           return ((BASE_DAMAGE / (WINNER_SPLIT + LOSER_SPLIT)) * LOSER_SPLIT,
               (BASE_DAMAGE / (WINNER_SPLIT + LOSER_SPLIT)) * WINNER_SPLIT);
       } else {
           return (BASE_DAMAGE / 2, BASE_DAMAGE / 2);
       }
   }
   // defence > attack
   // attack > body
   // body > turret
   // turret > defence

   /* move after it beats it
   uint8 constant DEFEND = 0;
   uint8 constant ATTACK = 1;
   uint8 constant BODY = 2;
   uint8 constant TURRET = 3;
   */

   uint8 constant MOVE_COUNT = 4;

   // defence > attack
   // attack > body
   // body > turret
   // turret > defence

   // don't hardcode this
   function defeats(uint8 a, uint8 b) internal returns(bool) {
       return (a + 1) % MOVE_COUNT == b;
   }

   // Experience-related functions/fields

   function _winBattle(EtherbotsBattle.Etherbot winner, EtherbotsBattle.Etherbot loser) internal {
        var (winnerExpBase, loserExpBase) = _calculateExpSplit(winner, loser);

        int32 winnerUserExp = _allocateExperience(winner, winnerExpBase);
        int32 loserUserExp = _allocateExperience(loser, loserExpBase);

        _base.addUsersExperience([winner.owner, loser.owner], [winnerUserExp, loserUserExp]);
    }

   uint8 constant BASE_EXP = 1000;
    uint8 constant EXP_MIN = 100;
    uint8 constant EXP_MAX = 1000;

    // this is a very important function in preventing collusion
    // works as a sort-of bell curve distribution
    // e.g. big bot attacks and defeats small bot (75exp, 25exp) = 100 total
    // e.g. big bot attacks and defeats big bot (750exp, 250exp) = 1000 total
    // e.g. small bot attacks and defeats big bot (1000exp, -900exp) = 100 total
    // huge incentive to play in the middle of the curve
    // makes collusion only slightly profitable (maybe -EV considering battle fees)

    function _calculateExpSplit(EtherbotsBattle.Etherbot winner, EtherbotsBattle.Etherbot loser) internal returns (int32, int32) {
        uint16 totalWinnerLevel = _base._totalLevel(winner);
        uint16 totalLoserLevel = _base._totalLevel(loser);
        // TODO: do we care about gold parts/combos etc
        // gold parts will naturally tend to higher levels anyway
        int32 total = _calculateTotalExperience(totalWinnerLevel, totalLoserLevel);
        return _calculateSplits(total, totalWinnerLevel, totalLoserLevel);
    }

    int32 constant WMAX = 1000;
    int32 constant WMIN = 75;
    int32 constant LMAX = 250;
    int32 constant LMIN = -900;

    uint8 constant WS = 3;
    uint8 constant LS = 1;

    function _calculateSplits(int32 total, uint16 wl, uint16 ll) pure internal returns (int32, int32) {
        int32 winnerSplit = max(WMIN, min(WMAX, ((total * WS) * (ll / wl)) / (WS + LS)));
        int32 loserSplit = total - winnerSplit;
        return (loserSplit, winnerSplit);
    }

    int32 constant BMAX = 1000;
    int32 constant BMIN = 100;
    int32 constant RATIO = BMAX / BMIN;

    // total exp generated follows a weird curve
    // 100 plays 1, wins: 75/25      -> 100
    // 50 plays 50, wins: 750/250    -> 1000
    // 1 plays 1, wins: 750/250      -> 1000
    // 1 plays 100, wins: 1000, -900 -> 100
    function _calculateTotalExperience(uint16 wl, uint16 ll) pure internal returns (int32) {
        uint16 diff = (wl - ll);
        return max(BMIN, BMAX - max(-RATIO * diff, RATIO * diff));
    }

    function max(int32 a, int32 b) pure internal returns (int32) {
        if (a > b) {
            return a;
        }
        return b;
    }

    function min(int32 a, int32 b) pure internal returns (int32) {
        if (a > b) {
            return b;
        }
        return a;
    }

    // allocates experience based on how many times a part was used in battle
    function _allocateExperience(uint[] parts, uint8[] moves, uint32 exp) internal returns(int32) {
        int32[] memory exps = new int32[](parts.length);
        int32 sum = 0;
        int32 each = exp / MOVE_COUNT;
        for (uint i = 0; i < MOVE_COUNT; i++) {
            exps[moves[i]] += each;
            sum += each;
        }
        _base.addExperienceToParts(parts, exps);
        return sum;
    }

}

