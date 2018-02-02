pragma solidity ^0.4.18;

import "./ERC721.sol";

// the contract which all battles must implement
// allows for different types of battles to take place

contract Battle is EtherbotsBase {

    // This struct does not exist outside the context of a battle
    struct Etherbot {
        uint meleeArmId;   // visually right arm
        uint defenceArmId; // visually left arm
        uint turretId;
        uint bodyId;
    }

    // create an array of battle contracts
    // you can only add contracts, never remove, and you can make calls to any of them
    // this means that if the devs implement a rule change
    // and the community doesn't like it, they can just stay on the old contract
    // once a contract is up and registered, you will ALWAYS be able to use that 'version' of the game
    // provided enough people will play with you, of course
    address[] battleContracts;

    function newBattleContract (address bContract) onlyOwner public {
        battleContracts.push(Battle(bContract));
    }

    function getBattleContract(uint index) returns (address) {
        return battleContracts[index];
    }

    // the name of the battle type
    function name() public view returns (string name);
    // the number of robots currently battling
    function playerCount() external view returns (uint count);
    // creates a new battle, with a submitted user string for initial input/
    function createBattle(Etherbot battler, bytes32 commit, uint64 duration) public;
    // cancels the battle at battleID
    function cancelBattle(uint battleID) external;

    event BattleCreated(uint indexed battleID, address indexed starter);
    event BattleEnded(uint indexed battleID, address indexed winner);
    event BattleConcluded(uint indexed battleID);
}

contract TwoPlayerCommitRevealDuel is Battle {

    function name() public view returns (string name) {
        return "2PCR";
    }

    function playerCount() external view returns (uint) {
        return duelingPlayers;
    }

    // TODO: packing?
    struct Duel {
        Etherbot defenderBot;
        bytes32 defenderCommit;
        uint64 maxAcceptTime;
        Attacker[] attackers;
        address defenderAddress;
    }

    struct Attacker {
        Etherbot attackerBot;
        // no need to encode this
        bytes32 moves;
        uint64 maxRevealTime;
        address attackerAddress;
    }

    //ID maps to index in battles array.
    // TODO: do we need this?
    // TODO: don't think we ever update it
    // if we want to find all the duels for a user, just use external view
    mapping (address => uint[]) addressToDuels;
    Duel[] duels;
    uint public duelingPlayers;

    // centrally controlled fields
    // CONSIDER: can users ever change these (e.g. different time per battle)
    // CONSIDER: how do we incentivize users to fight 'harder' bots
    uint public maxRevealTime;
    uint public duelFee;
    uint public minDuelDuration;
    uint public maxDuelDuration;
    uint public winnerExpReward;
    uint public winnerExpMultiplier;
    uint public moveStringLength;

    // moves should be in the form of:
    // movelength|movestring|random seed
    function defenderCommitMoves(Etherbot _bot, bytes32 _movesCommit, uint64 _duration) external payable {

        // have to keep the window open for a certain number of moves automatically
        // not very restrictive - can always cancel
        // limit the max so that people don't 'set and forget'
        // not very fun for other players
        require(_duration >= minDuelDuration && _duration <= maxDuelDuration);

        // require the user to have sent moves
        // require(_movesCommit.length == 8);

        // check parts and ownership
        require(_isValidRobot(_bot));

        // check the fee has been paid (if there is a fee)
        // TO CHCECK - this seems like one defender duelFee can have multiple duels, whereas one attacker duelFee is only one
        // is this the way of balancing the benefit of attacking?
        // should we have a max number of people who can attack one defender if we're going down this route?
        require(msg.value >= duelFee);
        uint64 _maxAcceptTime = uint64(now + _duration);
        Duel memory _duel = Duel({
            defenderAddress: msg.sender,
            defenderBot: _bot,
            defenderCommit: keccak256(_movesCommit),
            maxAcceptTime: _maxAcceptTime,
            attackers: new Attacker[](0)
            // attackers:
        });
        // TODO: -1 here?
        uint256 newDuelId = duels.push(_duel) - 1;
        duelingPlayers++;
        addressToDuels[msg.sender].push(newDuelId);
        BattleCreated(newDuelId, msg.sender);
    }

    // moves should be in the form of:
    // movelength|movestring|random seed
    function attack(uint _duelId, Etherbot _bot, bytes32 _moves) {
        // checks that all the parts are of the right type and owned by the sender
        require(_isValidRobot(_bot));

        Duel storage duel = duels[_duelId];

        // checks part independence and timing
        require(canAttack(duel, _bot));
        uint64 _maxRevealTime = uint64(now + maxRevealTime);
        Attacker memory a;
        a  = Attacker({
            attackerBot: _bot,
            moves: _moves,
            maxRevealTime: _maxRevealTime,
            attackerAddress: msg.sender
        });

        duel.attackers.push(a);

        // increment those battling
        duelingPlayers++;

    }

    function defenderRevealMoves(uint _duelId, bytes32 _moves) external returns(bool){
        Duel storage _duel = duels[_duelId];
        // all parts will have the same owner, can just check one
                // TO CHECK : are we sure about this, need to make sure we can't sell a dueling bot then
        // require(msg.sender == _duel.defenderBot.body.owner);
        // require(bytes(_moves).length == 8);
        if (_duel.defenderCommit != keccak256(_moves)) {
            // InvalidAction("Moves did not match move commit");
            return false;
        }
        // after the defender has revealed their moves, perform all the duels
        for (uint i = 0; i < _duel.attackers.length; i++) {
            Attacker memory tempA =   _duel.attackers[i];
            _executeMoves(_duelId, _duel, _moves, tempA);
        }
        return true;
    }

    // can be called if the defender hasn't replace
        // TO CHECK: how does the attacker know/ access the duel id? we are not saving it for them
    function claimTimeVictory(uint _duelId) external {
        Duel storage _duel = duels[_duelId];
        // go through all the
        // check if the defender failed to reveal their string
        // require(now > duel.maxRevealTime && duel.maxRevealTime != 0);
        // require(msg.sender == duel.attackerBot.body.owner);
        // if (TODO: - TIMEUP) {
            for (uint i = 0; i < _duel.attackers.length; i++) {
            Attacker memory tempA =   _duel.attackers[i];
            _rewardParticipants(_duelId, _duel, tempA, true);
            }
        // }
    }

    function _randomFightResult(string _attackerMoves, string _defenderMoves) private returns (uint256 randomNumber) {
        _seed = uint256(keccak256(
            _seed,
            block.blockhash(block.number - 1),
            _attackerMoves,
            _defenderMoves
            ));
        return _seed;
  }

  function bytes32ToString(bytes32 x) private constant returns (string) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }

    function _executeMoves(uint _duelId, Duel _duel, bytes32 _defenderMoves, Attacker _attacker ) private {
        // Random num from keccak(seed,block,defMoves,attackMoves) -> number between 0 and 100
        string memory _defenderMovesString = bytes32ToString(_defenderMoves);
        string memory _attackerMovesString = bytes32ToString(_attacker.moves);
        uint _rand100 = _randomFightResult(_attackerMovesString, _defenderMovesString) % 2000;
        // Threshold -> starts at 1000. Is modified by robot stats, perks and moves.
        // this represents the chance chance the defender has of winning
        // increasing the threshold makes it easier for the defender to win
        uint _threshold = 1000 - 1;
        // Threshold modified by experience level of parts compared for +-200
        Part[4] memory attackerParts = [
            parts[_attacker.attackerBot.turretId],
            parts[_attacker.attackerBot.meleeArmId],
            parts[_attacker.attackerBot.defenceArmId],
            parts[_attacker.attackerBot.bodyId]
        ];
        Part[4] memory defenderParts = [
            parts[_duel.defenderBot.turretId],
            parts[_duel.defenderBot.meleeArmId],
            parts[_duel.defenderBot.defenceArmId],
            parts[_duel.defenderBot.bodyId]
        ];
        // Parts reminder: Blueprint represents details of the part:
        // [2] part level (experience),
        // [3] rarity status, (representing, i.e., "gold")
        // [4] elemental type, (i.e., "water")

        // Parts are compared by type. A part can gain up to 5 threshold points (% win chance)
        uint32 diff = 0;
        for (uint i = 0; i < 4; i++) {
            if (attackerParts[i].blueprint[2] > defenderParts[i].blueprint[2]) {
                diff = attackerParts[i].blueprint[2] - defenderParts[i].blueprint[2];
                if (diff > 50) {
                    diff = 50;
                }
                // attacker is better. deduct to the defence threshold.
                _threshold -= diff;
            } else {
                diff = defenderParts[i].blueprint[2] - attackerParts[i].blueprint[2];
                if (diff > 50) {
                    diff = 50;
                }
                //defender is better. add to the defence threshold.
                _threshold += diff;
            }
            diff = 0;
        }
        // Threshold modified by UserExp + perks for +-100
        User attackingUser = users[userID[_attacker.attackerAddress]];
        User defendingUser = users[userID[_duel.defenderAddress]];
        // Experience difference has been set to have the same effect as one part difference
        if (attackingUser.userExperience > defendingUser.userExperience) {
            diff = attackingUser.userExperience - defendingUser.userExperience;
            if (diff > 50) {
                diff = 50;
            }
            // attacking User is better. deduct to the defence threshold.
            _threshold -= diff;
        } else {
            diff = defendingUser.userExperience - attackingUser.userExperience;
            if (diff > 50) {
                diff = 50;
            }
            // defending User is better. add to the defence threshold.
            _threshold -= diff;
        }
        diff = 0;
        // Threshold modified by gold and shadow. + all gold + all shadow. + all element.
        // blueprint[3] = rarity
        // blueprint [4] = element 
        if (attackerParts[0].blueprint[3] == 3) {
            bool isAttackerAllGold = true;
            // check all Legendary Gold;
            for (i = 0; i < 4; i++ ) {
                if (attackerParts[i].blueprint[3] != 3) {
                    isAttackerAllGold = false;
                } else {
                    _threshold -= 10;
                }
            }
        } else if (attackerParts[0].blueprint[3] == 2) {
            // check all Rare Shadow;
            bool isAttackerAllShadow = true;
            for (i = 0; i < 4; i++ ) {
                if (attackerParts[i].blueprint[3] != 2) {
                    isAttackerAllShadow = false;
                } else {
                    // attacker is better. deduct to the defence threshold.
                    _threshold -= 5;
                }
            }
        }
        if (defenderParts[0].blueprint[3] == 3) {
            bool isDefenderAllGold = true;
            // check all Legendary Gold;
            for (i = 0; i < 4; i++ ) {
                if (defenderParts[i].blueprint[3] != 3) {
                    isDefenderAllGold = false;
                } else {
                    _threshold += 10;
                }
            }
        } else if (defenderParts[0].blueprint[3] == 2) {
            // check all Rare Shadow;
            bool isDefenderAllShadow = true;
            for (i = 0; i < 4; i++ ) {
                if (defenderParts[i].blueprint[3] != 2) {
                    isDefenderAllShadow = false;
                } else {
                    // defender is better. add to the defence threshold.
                    _threshold += 5;
                }
            }
        }
        if (isAttackerAllGold) {
            _threshold -= 30;
        } else if (isAttackerAllShadow) {
            _threshold -= 15;
        }
        if (isDefenderAllGold) {
            _threshold += 30;
        } else if (isDefenderAllShadow) {
            _threshold += 15;
        }
       
        //TODO rest of the perk tree. Perks can give + - 50.
        // Threshold modified by moves for +- 160
        // Attack (1) > Move (2) > Shoot (3) > defend (4) > attack (1)
        // All other types are draws e.g. Attack vs shoot, and Move vs defend.
        bytes32 _attackerMoves = bytes32(_attacker.moves);
        _defenderMoves = bytes32(_defenderMoves);
        for (i = 0; i < 8; i++) {
            if (keccak256(_attackerMoves[i]) == keccak256("1") && keccak256(_defenderMoves) == keccak256("2")) {
                //attacker wins
                _threshold -=20;
            } else if (keccak256(_attackerMoves[i]) == keccak256("2") && keccak256(_defenderMoves) == keccak256("3")) {
                //attacker wins
                _threshold -=20;
            } else if (keccak256(_attackerMoves[i]) == keccak256("3") && keccak256(_defenderMoves) == keccak256("4")) {
                //attacker wins
                _threshold -=20;
            } else if (keccak256(_attackerMoves[i]) == keccak256("4") && keccak256(_defenderMoves) == keccak256("1")) {
                //attacker wins
                _threshold -=20;
            }

            if (keccak256(_defenderMoves[i]) == keccak256("1") && keccak256(_attackerMoves) == keccak256("2")) {
                //defender wins
                _threshold +=20;
            } else if (keccak256(_defenderMoves[i]) == keccak256("2") && keccak256(_attackerMoves) == keccak256("3")) {
                //defender wins
                _threshold +=20;
            } else if (keccak256(_defenderMoves[i]) == keccak256("3") && keccak256(_attackerMoves) == keccak256("4")) {
                //defender wins
                _threshold +=20;
            } else if (keccak256(_defenderMoves[i]) == keccak256("4") && keccak256(_attackerMoves) == keccak256("1")) {
                //defender wins
                _threshold +=20;
            }
        }
        // Attack + Shoot = Draw. Body + Shoot = Draw. Therefore don't need to deal with those situations

        bool _isAttackerWinner;
        if (_rand100 > _threshold) {
            _isAttackerWinner = true;
        } else {
            _isAttackerWinner = false;
        }
        _rewardParticipants(_duelId, _duel, _attacker, _isAttackerWinner);
    }

    // function _winDuel(uint _duelId, Etherbot bot){
    function _rewardParticipants(uint _duelId, Duel _duel, Attacker _attacker, bool _isAttackerWinner) private {
        
        // THIS AREA IS UNDER CONSTRUCTION,
        // AS WE ARE STILL FINE TUNING THE REWARDS TO ENSURE THAT THERE IS LOTS OF REPLAYABILITY
        // AND NOT TOO MUCH PARTS INFLATION

        address _winner;
        if (_isAttackerWinner) {
            _winner = _attacker.attackerAddress;
        } else {
            _winner = _duel.defenderAddress;
        }

        BattleEnded(_duelId, _winner);
    }
    // TO DO - might want to let people cancel duels
    // function cancelDuel(uint _duelId) external {
    //     Duel duel = duels[_duelId];
    //     // can't cancel a duel that's already over
    //     // require(duel.maxRevealTime > now);

    //     // have to forfeit all duels with an attacker
    //     for (uint i = 0; i < duel.attackers.length; i++) {
    //         _rewardParticipants(_duelId, duel.defenderBot, duel.attackers[i].attackerBot, false);
    //     }

    //     // prevent the contract from accepting new duels
    //     duel.maxAcceptTime = uint64(now);

    //     BattleConcluded(_duelId);
    // }

    function setMaxRevealTime(uint _maxReveal) onlyOwner {
        maxRevealTime = _maxReveal;
    }

    // TODO: consider removing
    function setDuelFee(uint _fee) onlyOwner {
        duelFee = _fee;
    }

    function setMinDuelDuration(uint _duration) onlyOwner {
        minDuelDuration = _duration;
    }

    function setMaxDuelDuration(uint _duration) onlyOwner {
        maxDuelDuration = _duration;
    }

    function setExpReward(uint _reward) onlyOwner {
        winnerExpReward = _reward;
    }

    function setWinnerExpMultiplier(uint _multiplier) onlyOwner {
        winnerExpMultiplier = _multiplier;
    }

    function setMoveStringLength(uint _length) onlyOwner {
        moveStringLength = _length;
    }

    function _isValidRobot(Etherbot _bot) internal view returns (bool) {
        //reuse implemenation from core
    //   if (_bot.body.blueprint[0] != 0) {
    //     return false;
    //   } else
    //   if (_bot.meleeArm.blueprint[0] != 1) {
    //     return false;
    //   } else if (_bot.defenceArm.blueprint[0] != 2) {
    //     return false;
    //   } else if (_bot.turret.blueprint[0] != 3) {
    //     return false;
    //   }
      // check that the owner owns all the parts
      address partOwner = partIndexToOwner[_bot.bodyId];
      if (partIndexToOwner[_bot.meleeArmId] != partOwner) {
          return false;
      } else if (partIndexToOwner[_bot.defenceArmId] != partOwner){
          return false;
      } else if (partIndexToOwner[_bot.turretId] != partOwner){
          return false;
      }
      return true;
    }

    function canAttack(Duel _duel, Etherbot _attacker) internal view returns(bool) {
        // check to see whether this part is already attacking this robot
        for (uint p = 0; p < _duel.attackers.length; p++) {
            Attacker memory a;
            // if (a.meleeArm == _attacker.meleeArm) {
            // a = _duel.attackers[p];
            //     return false;
            // }
            // if (a.defenceArm == _attacker.defenceArm) {
            //     return false;
            // }
            // if (a.meleeArm == _attacker.meleeArm) {
            //     return false;
            // }
            // if (a.body == _attacker.body) {
            //     return false;
            // }
        }
        // A Robot can't battle itself... only emotionally.
        // if (_duel.defender.meleeArm == _attacker.meleeArm) {
        //     return false;
        // }
        // if (_duel.defender.defenceArm == _attacker.defenceArm) {
        //     return false;
        // }
        // if (_duel.defender.meleeArm == _attacker.meleeArm) {
        //     return false;
        // }
        // if (_duel.defender.body == _attacker.body) {
        //     return false;
        // }
        // return true;
    }

}