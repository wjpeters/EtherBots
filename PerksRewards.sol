pragma solidity ^0.4.17;

import "./EtherbotsAuction.sol";

contract PerksRewards is EtherbotsAuction {
	    ///  An internal method that creates a new part and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is known to be valid. Will generate both a Forge event
    ///  and a Transfer event.
   function _createPart(uint8[4] _partArray, address _owner) internal returns (uint) {
        uint32 newPartId = uint32(parts.length);
        assert(newPartId == parts.length);

        Part memory _part = Part({
            tokenId: newPartId,
            partType: _partArray[0],
            partSubType: _partArray[1],
            rarity: _partArray[2],
            element: _partArray[3],
            battlesLastDay: 0,
            experience: 0,
            forgeTime: uint32(now), // TODO: check whether we need uint64
            battlesLastReset: uint32(now)
        });

        
        assert(newPartId == parts.push(_part) - 1);


        // emit the FORGING!!!
        Forge(_owner, newPartId, _part);

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        _transfer(0, _owner, newPartId);

        return newPartId;
    }

}
