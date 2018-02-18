pragma solidity ^0.4.18;

import "./Base.sol";

// the contract which all battles must implement
// allows for different types of battles to take place
contract PerkTree is EtherbotsBase {
    // The perktree is represented in a uint8[32] representing a binary tree
    // see the number of perks active
    // buy a new perk
    // 0: Prestige level -> starts at 0;
    // next row of tree
    // 1: offensive moves 2: defensive moves
    // next row of tree
    // 3: melee attack 4: turret shooting 5: defend arm 6: body dodge
    // next row of tree
    // 7: mech melee 8: android melee 9: mech turret 10: android turret
    // 11: mech defence 12: android defence 13: mech body 14: android body
    //next row of tree
    // 15: melee electric 16: melee steel 17: melee fire 18: melee water
    // 19: turret electric 20: turret steel 21: turret fire 22: turret water
    // 23: defend electric 24: defend steel 25: defend fire 26: defend water
    // 27: body electric 28: body steel 29: body fire 30: body water
    //TODO ADD GOLD OR SHADOW AS A FINAL LEVEL
    function _leftChild(uint8 _i) internal pure returns (uint8) {
        return 2*_i + 1;
    }
    function _rightChild(uint8 _i) internal pure returns (uint8) {
        return 2*_i + 2;
    }
    function _parent(uint8 _i) internal pure returns (uint8) {
        return (_i-1)/2;
    }
    function _isValidPerkToAdd(uint8[32] _perks, uint8 _i) internal pure returns (bool) {
        // a previously unlocked perk is not a valid perk to add.
        if (_perks[_i] > 0) {
            return false;
        }
        while (_i > 0) {
            _i = _parent(_i);
            // a perk without all its parents unlocked is not valid
            if (_perks[_i] == 0) {
                return false;
            }
        }
        return true;
    }
    function _isValidPrestige(uint8[32] _perks) internal pure returns (bool) {
        uint256 allPerks = _sumActivePerks(_perks);
        allPerks -= _perks[0];
        if (allPerks == 30) {
            return true;
        }
        return false;
    }

    function _sumActivePerks(uint8[32] _perks) internal pure returns (uint256) {
        uint32 sum = 0;
        for ( uint8 i = 0; i < _perks.length ; i++ ) {
            sum += _perks[i];
        }
        return sum;
    }

    function choosePerk(uint8 _i) external {
        User storage currentUser = users[userID[msg.sender]];
        uint256 _numActivePerks = _sumActivePerks(currentUser.perks);
        require(_numActivePerks * _numActivePerks <= currentUser.userExperience);
        if (_i == 0 ) {
            require(_isValidPrestige(currentUser.perks));
        } else {
            require(_isValidPerkToAdd(currentUser.perks, _i));
        }
        currentUser.perks[_i]++;
        PerkChosen(msg.sender, _i);
    }

    event PerkChosen(address indexed upgradedUser, uint8 indexed perk);

}
