pragma solidity ^0.4.17;

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
    event Forge(address owner, uint256 partID, Part part);

    ///  Transfer event as defined in ERC721.
    event Transfer(address from, address to, uint256 tokenId);

    /*** DATA TYPES ***/
    ///  The main struct representation of a robot part. Each robot in Etherbots is represented by four copies
    ///  of this structure, one for each of the four parts comprising it:
    /// 1. Right Arm (Melee),
    /// 2. Left Arm (Defence),
    /// 3. Head (Turret),
    /// 4. Body.
    // store token id on this? 
     struct Part {
        uint32 tokenId; 
        uint8 partType;
        uint8 partSubType;
        uint8 rarity;
        uint8 element;
        uint32 battlesLastDay;
        uint32 experience;
        uint32 forgeTime; // TODO: check whether we need uint64
        uint32 battlesLastReset;
    }

    // Store a user struct
    // in order to keep track of experience and perk choices.
    // This perk tree is a binary tree, efficiently encodable as an array.
    // 0 reflects no perk selected. 1 is first choice. 2 is second. 3 is both.
    // Each choice costs experience (deducted from user struct).

    /*** ~~~~~ROBOT PERKS~~~~~ ***/
    // PERK 1: ATTACK vs DEFENCE PERK CHOICE.
    // Choose
    // PERK TWO ATTACK/ SHOOT, or DEFEND/DODGE
    // PERK 2: MECH vs ELEMENTAL PERK CHOICE ---
    // Choose steel and electric (Mech path), or water and fire (Elemetal path)
    // (... will the mechs win the war for Ethertopia? or will the androids
    // be deluged in flood and fire? ...)
    // PERK 3: Commit to a specific elemental pathway:
    // 1. the path of steel: the iron sword; the burning frying pan!
    // 2. the path of electricity: the deadly taser, the fearsome forcefield
    // 3. the path of water: high pressure water blasters have never been so cool
    // 4. the path of fire!: we will hunt you down, Aang...


    struct User {
        address userAddress;
        uint32 experience;
        uint8[32] perks;
    }

    //Maintain an array of all users.
    User[] public users;

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

    // function _randomPartArray(uint _rand) internal returns (uint8[4] blueprint) {

    // }    
    
    function getPartById(uint _id) external view returns (
       uint8 partType,
       uint8 partSubType,
        uint8 rarity,
        uint8 element,
        uint32 battlesLastDay,
        uint32 experience,
        uint32 forgeTime,
        uint32 battlesLastReset
    ) {
        Part memory p = parts[_id];
        return (p.partType, p.partSubType, p.rarity, p.element, p.battlesLastDay, p.experience, p.forgeTime, p.battlesLastReset);
    } 


    // ELEMENT CONSTANTS
    // 1 - steel, 2 - electric, 3 - fire, 4 - water
    string private BODY_ELEMENT_BY_ID = "212343114234111";
    string private TURRET_ELEMENT_BY_ID = "12434133214";
    string private MELEE_ELEMENT_BY_ID = "31323422111144";
    string private DEFENCE_ELEMENT_BY_ID = "43212113434";

    function substring(string str, uint startIndex, uint endIndex) internal pure returns (string) {
      bytes memory strBytes = bytes(str);
      bytes memory result = new bytes(endIndex-startIndex);
      for(uint i = startIndex; i < endIndex; i++) {
          result[i-startIndex] = strBytes[i];
      }
      return string(result);
    }
  // helper functions adapted from  Jossie Calderon on stackexchange
  function stringToUint32(string s) internal pure returns (uint32) {
      bytes memory b = bytes(s);
      uint result = 0;
      for (uint i = 0; i < b.length; i++) { // c = b[i] was not needed
          if (b[i] >= 48 && b[i] <= 57) {
              result = result * 10 + (uint(b[i]) - 48); // bytes and int are not compatible with the operator -.
          }
      }
      return uint32(result); // this was missing
  }
  
  function stringToUint8(string s) internal pure returns (uint8) {
      bytes memory b = bytes(s);
      uint result = 0;
      for (uint i = 0; i < b.length; i++) { // c = b[i] was not needed
          if (b[i] >= 48 && b[i] <= 57) {
              result = result * 10 + (uint(b[i]) - 48); // bytes and int are not compatible with the operator -.
          }
      }
      return uint8(result); // this was missing
  }

  function uintToString(uint v) internal pure returns (string) {
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
