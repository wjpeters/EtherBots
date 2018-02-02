pragma solidity ^0.4.18;

import "./AccessControl.sol";
// import "./contracts/CratePreSale.sol";
// Central collection of storage on which all other contracts depend.
// Contains structs for parts, users and functions which control their
// transferrence.
contract EtherbotsBase is EtherbotsPrivileges {
    /*** EVENTS ***/

    ///  Forge fires when a new part is created - 4 times when a crate is opened,
    /// and once when a battle takes place. Also has fires when
    /// parts are combined in the furnace.
    event Forge(address owner, uint256 partID, uint32[8] blueprint);

    ///  Transfer event as defined in ERC721.
    event Transfer(address from, address to, uint256 tokenId);

    /*** DATA TYPES ***/
    ///  The main struct representation of a robot. Each robot in Etherbots is represented by four copies
    ///  of this structure, one for each of the four parts comprising it:
    /// 1. Right Arm (Melee),
    /// 2. Left Arm (Defence),
    /// 3. Head (Turret),
    /// 4. Body.
    struct Part {
        // Could actually pull the whole part type + rarity + element into
        // the uint32 in the first space and access via bitshifting, but as there
        // is a lot of space, may as well go for readability.
        // Blueprint represents details of the part:
        // [0] part type (representing, i.e., "turret"),
        // [1] part ID (representing, i.e., "missile launcher")
        // [2] part level (experience),
        // [3] rarity status, (representing, i.e., "gold") -> 1 = common, 2 = shadow, 3 = gold
        // [4] elemental type, (i.e., "water")
        // // 1 - steel, 2 - electric, 3 - fire, 4 - water
        // [5-7] spare storage
        uint32[8] blueprint;

        // The timestamp from the block when this part came into existence.
        uint64 forgeTime;

        // Keep track of how many battles this part has been engaged in within
        // the last day
        uint16 battlesLastDay;
    }

    // Store a user struct
    // in order to keep track of experience and perk choices.
    // This perk tree is a binary tree, efficiently encodable as an array.
    // 0 reflects no perk selected. 1 is first choice. 2 is second. 3 is both.
    // Each choice costs experience (deducted from user struct).

    /*** ~~~~~ROBOT PERKS~~~~~ ***/
    // PERK 1: ATTACK vs DEFENCE PERK CHOICE.
    // Choose
    // PERK 2: MECH vs ELEMENTAL PERK CHOICE ---
    // Choose steel and electric (Mech path), or water and fire (Elemetal path)
    // (... will the mechs win the war for Ethertopia? or will the androids
    // be deluged in flood and fire? ...)
    // PERK 3: Commit to a specific elemental pathway:
    // 1. the path of steel: the iron sword; the burning frying pan!
    // 2. the path of electricity: the deadly taser, the fearsome forcefield
    // 3. the path of water: high pressure water blasters have never been so cool
    // 4. the path of fire!: we will hunt you down, Aang...
    // PERK 4: choose to enhance common parts, or special ones.
    // common ones will make your everyday robot stronger...
    // but a special enhancement can make your legendary Etherbot unstoppable.


    struct User {
        address userAddress;
        uint32 userExperience;
        uint16[16] perks;
    }

    //Maintain an array of all users.
    User[] users;

    // Store a map of the address to a uint representing index of User within users
    // we check if a user exists at multiple points, every time they acquire
    // via a crate or the market. Users can also manually register their address.
    mapping ( address => uint ) userID;

    // An approximation of currently how many seconds are in between blocks.
    uint256 public secondsPerBlock = 15;

    // store a seed for use in randomizations
    uint256 _seed;

    // STORAGE

    // Array containing the structs of all parts in existence. The ID
    // of each part is an index into this array.
    Part[] parts;

    // Mapping from part IDs to to owning address. Should always exist.
    mapping (uint256 => address) public partIndexToOwner;

    //  A mapping from owner address to count of tokens that address owns.
    //  Used internally inside balanceOf() to resolve ownership count. REMOVE?
    mapping (address => uint256) addressToTokensOwned;

    // Mapping from Part ID to an address approved to call transferFrom().
    // maximum of one approved address for transfer at any time.
    mapping (uint256 => address) public partIndexToApproved;

    // Arrays to store contracts
    // can only ever be added to, not removed from
    // once a ruleset is published, you will ALWAYS be able to use that contract
    // TODO: actually implement this (call by index etc)
    address[] auctions;
    address[] battles;

    function addAuction(address _newAuction) external onlyOwner {
        auctions.push(_newAuction);
    }

    function addBattle(address _newBattle) external onlyOwner {
        battles.push(_newBattle);
    }

    //  Transfer a part to an address
    function _transfer(address _from, address _to, uint256 _tokenId) internal {
        // No cap on number of parts
        // Very unlikely to ever be 2^256 parts owned by one account
        // Shouldn't waste gas checking for overflow
        // no point making it less than a uint --> mappings don't pack
        addressToTokensOwned[_to]++;
        // transfer ownership
        partIndexToOwner[_tokenId] = _to;
        // New parts are transferred _from 0x0, but we can't account that address.
        if (_from != address(0)) {
            addressToTokensOwned[_from]--;
            // clear any previously approved ownership exchange
            delete partIndexToApproved[_tokenId];
        }
        // Emit the transfer event.
        Transfer(_from, _to, _tokenId);
    }

    ///  An internal method that creates a new part and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is known to be valid. Will generate both a Forge event
    ///  and a Transfer event.
    function _createPart(uint32[8] _blueprint, address _owner) internal returns (uint) {
        Part memory _part = Part({
            blueprint: _blueprint,
            forgeTime: uint64(now),
            battlesLastDay: 0
        });
        uint256 newPartId = parts.push(_part) - 1;


        // emit the FORGING!!!
        Forge(_owner, newPartId, _part.blueprint);

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        _transfer(0, _owner, newPartId);

        return newPartId;
    }


    // ELEMENT CONSTANTS
    // 1 - steel, 2 - electric, 3 - fire, 4 - water
    string private BODY_ELEMENT_BY_ID = "212343114234111";
    string private TURRET_ELEMENT_BY_ID = "12434133214";
    string private MELEE_ELEMENT_BY_ID = "31323422111144";
    string private DEFENCE_ELEMENT_BY_ID = "43212113434";

    function substring(string str, uint startIndex, uint endIndex) internal constant returns (string) {
      bytes memory strBytes = bytes(str);
      bytes memory result = new bytes(endIndex-startIndex);
      for(uint i = startIndex; i < endIndex; i++) {
          result[i-startIndex] = strBytes[i];
      }
      return string(result);
    }
  // helper functions adapted from  Jossie Calderon on stackexchange
  function stringToUint32(string s) internal constant returns (uint32) {
      bytes memory b = bytes(s);
      uint result = 0;
      for (uint i = 0; i < b.length; i++) { // c = b[i] was not needed
          if (b[i] >= 48 && b[i] <= 57) {
              result = result * 10 + (uint(b[i]) - 48); // bytes and int are not compatible with the operator -.
          }
      }
      return uint32(result); // this was missing
  }

  function uintToString(uint v) internal constant returns (string) {
      uint maxlength = 100;
      bytes memory reversed = new bytes(maxlength);
      uint i = 0;
      while (v != 0) {
          uint remainder = v % 10;
          v = v / 10;
          reversed[i++] = byte(48 + remainder);
      }
      bytes memory s = new bytes(i); // i + 1 is inefficient
      for (uint j = 0; j < i; j++) {
          s[j] = reversed[i - j - 1]; // to avoid the off-by-one error
      }
      string memory str = string(s);
      return str;
  }
}
