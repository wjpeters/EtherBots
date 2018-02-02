pragma solidity ^0.4.18;
import "./Base.sol";

// This contract implements both the original ERC-721 standard and
// the proposed 'deed' standard of 841
// I don't know which standard will eventually be adopted - support both
// TODO: there must be a better way of expressing all this
// TODO: add ERC165 or ERC820 support (won't take long)

/// @title Interface for contracts conforming to ERC-721: Deed Standard
/// @author William Entriken (https://phor.net), et. al.
/// @dev Specification at https://github.com/ethereum/eips/XXXFinalUrlXXX
contract ERC is EtherbotsBase {

    // COMPLIANCE WITH ERC-165 (DRAFT) /////////////////////////////////////////

    /// @dev ERC-165 (draft) interface signature for itself
    // bytes4 internal constant INTERFACE_SIGNATURE_ERC165 = // 0x01ffc9a7
    //     bytes4(keccak256('supportsInterface(bytes4)'));

    /// @dev ERC-165 (draft) interface signature for ERC721
    // bytes4 internal constant INTERFACE_SIGNATURE_ERC721 = // 0xda671b9b
    //     bytes4(keccak256('ownerOf(uint256)')) ^
    //     bytes4(keccak256('countOfDeeds()')) ^
    //     bytes4(keccak256('countOfDeedsByOwner(address)')) ^
    //     bytes4(keccak256('deedOfOwnerByIndex(address,uint256)')) ^
    //     bytes4(keccak256('approve(address,uint256)')) ^
    //     bytes4(keccak256('takeOwnership(uint256)'));

    /// @notice Query a contract to see if it supports a certain interface
    /// @dev Returns `true` the interface is supported and `false` otherwise,
    ///  returns `true` for INTERFACE_SIGNATURE_ERC165 and
    ///  INTERFACE_SIGNATURE_ERC721, see ERC-165 for other interface signatures.
    function supportsInterface(bytes4 _interfaceID) external pure returns (bool);

    // PUBLIC QUERY FUNCTIONS //////////////////////////////////////////////////

    /// @notice Find the owner of a deed
    /// @param _deedId The identifier for a deed we are inspecting
    /// @dev Deeds assigned to zero address are considered invalid, and
    ///  queries about them do throw.
    /// @return The non-zero address of the owner of deed `_deedId`, or `throw`
    ///  if deed `_deedId` is not tracked by this contract
    function ownerOf(uint256 _deedId) public view returns (address _owner);

    /// @notice Count deeds tracked by this contract
    /// @return A count of valid deeds tracked by this contract, where each one of
    ///  them has an assigned and queryable owner not equal to the zero address
    function countOfDeeds() external view returns (uint256 _count);

    /// @notice Count all deeds assigned to an owner
    /// @dev Throws if `_owner` is the zero address, representing invalid deeds.
    /// @param _owner An address where we are interested in deeds owned by them
    /// @return The number of deeds owned by `_owner`, possibly zero
    function countOfDeedsByOwner(address _owner) external view returns (uint256 _count);

    /// @notice Enumerate deeds assigned to an owner
    /// @dev Throws if `_index` >= `countOfDeedsByOwner(_owner)` or if
    ///  `_owner` is the zero address, representing invalid deeds.
    /// @param _owner An address where we are interested in deeds owned by them
    /// @param _index A counter less than `countOfDeedsByOwner(_owner)`
    /// @return The identifier for the `_index`th deed assigned to `_owner`,
    ///   (sort order not specified)
    function deedOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256 _deedId);

    // TRANSFER MECHANISM //////////////////////////////////////////////////////

    /// @dev This event emits when ownership of any deed changes by any
    ///  mechanism. This event emits when deeds are created (`from` == 0) and
    ///  destroyed (`to` == 0). Exception: during contract creation, any
    ///  transfers may occur without emitting `Transfer`. At the time of any transfer,
    ///  the "approved taker" is implicitly reset to the zero address.
    event Transfer(address indexed from, address indexed to, uint256 indexed deedId);

    /// @dev The Approve event emits to log the "approved taker" for a deed -- whether
    ///  set for the first time, reaffirmed by setting the same value, or setting to
    ///  a new value. The "approved taker" is the zero address if nobody can take the
    ///  deed now or it is an address if that address can call `takeOwnership` to attempt
    ///  taking the deed. Any change to the "approved taker" for a deed SHALL cause
    ///  Approve to emit. However, an exception, the Approve event will not emit when
    ///  Transfer emits, this is because Transfer implicitly denotes the "approved taker"
    ///  is reset to the zero address.
    event Approval(address indexed owner, address indexed approved, uint256 indexed deedId);

    /// @notice Set the "approved taker" for your deed, or revoke approval by
    ///  setting the zero address. You may `approve` any number of times while
    ///  the deed is assigned to you, only the most recent approval matters. Emits
    ///  an Approval event.
    /// @dev Throws if `msg.sender` does not own deed `_deedId` or if `_to` ==
    ///  `msg.sender` or if `_deedId` is not a valid deed.
    /// @param _deedId The deed for which you are granting approval
    function approve(address _to, uint256 _deedId) external payable;

    /// @notice Become owner of a deed for which you are currently approved
    /// @dev Throws if `msg.sender` is not approved to become the owner of
    ///  `deedId` or if `msg.sender` currently owns `_deedId` or if `_deedId is not a
    ///  valid deed.
    /// @param _deedId The deed that is being transferred
    function takeOwnership(uint256 _deedId) external payable;
}

/// @title Metadata extension to ERC-721 interface
/// @author William Entriken (https://phor.net)
/// @dev Specification at https://github.com/ethereum/eips/issues/XXXX
contract ERC721Metadata is ERC {

    /// @dev ERC-165 (draft) interface signature for ERC721
    // bytes4 internal constant INTERFACE_SIGNATURE_ERC721Metadata = // 0x2a786f11
    //     bytes4(keccak256('name()')) ^
    //     bytes4(keccak256('symbol()')) ^
    //     bytes4(keccak256('deedUri(uint256)'));

    /// @notice A descriptive name for a collection of deeds managed by this
    ///  contract
    /// @dev Wallets and exchanges MAY display this to the end user.
    function name() public pure returns (string n);

    /// @notice An abbreviated name for deeds managed by this contract
    /// @dev Wallets and exchanges MAY display this to the end user.
    function symbol() public pure returns (string s);

    /// @notice A distinct URI (RFC 3986) for a given token.
    /// @dev If:
    ///  * The URI is a URL
    ///  * The URL is accessible
    ///  * The URL points to a valid JSON file format (ECMA-404 2nd ed.)
    ///  * The JSON base element is an object
    ///  then these names of the base element SHALL have special meaning:
    ///  * "name": A string identifying the item to which `_deedId` grants
    ///    ownership
    ///  * "description": A string detailing the item to which `_deedId` grants
    ///    ownership
    ///  * "image": A URI pointing to a file of image/* mime type representing
    ///    the item to which `_deedId` grants ownership
    ///  Wallets and exchanges MAY display this to the end user.
    ///  Consider making any images at a width between 320 and 1080 pixels and
    ///  aspect ratio between 1.91:1 and 4:5 inclusive.
    function deedUri(uint256 _deedId) external view returns (string _uri);
}

/// @title Enumeration extension to ERC-721 interface
/// @author William Entriken (https://phor.net)
/// @dev Specification at https://github.com/ethereum/eips/issues/XXXX
contract ERC721Enumerable is ERC721Metadata {

    /// @dev ERC-165 (draft) interface signature for ERC721
    // bytes4 internal constant INTERFACE_SIGNATURE_ERC721Enumerable = // 0xa5e86824
    //     bytes4(keccak256('deedByIndex()')) ^
    //     bytes4(keccak256('countOfOwners()')) ^
    //     bytes4(keccak256('ownerByIndex(uint256)'));

    /// @notice Enumerate active deeds
    /// @dev Throws if `_index` >= `countOfDeeds()`
    /// @param _index A counter less than `countOfDeeds()`
    /// @return The identifier for the `_index`th deed, (sort order not
    ///  specified)
    function deedByIndex(uint256 _index) external view returns (uint256 _deedId);

    /// @notice Count of owners which own at least one deed
    /// @return A count of the number of owners which own deeds
    function countOfOwners() external view returns (uint256 _count);

    /// @notice Enumerate owners
    /// @dev Throws if `_index` >= `countOfOwners()`
    /// @param _index A counter less than `countOfOwners()`
    /// @return The address of the `_index`th owner (sort order not specified)
    function ownerByIndex(uint256 _index) external view returns (address _owner);
}

contract ERC721Original {
    // Core functions
    function implementsERC721() public pure returns (bool);
    function totalSupply() public view returns (uint256 _totalSupply);
    function balanceOf(address _owner) public view returns (uint256 _balance);
    function ownerOf(uint _tokenId) public view returns (address _owner);
    function approve(address _to, uint _tokenId) external payable;
    function transferFrom(address _from, address _to, uint _tokenId) public;
    function transfer(address _to, uint _tokenId) public;

    // Optional functions
    function name() public pure returns (string _name);
    function symbol() public pure returns (string _symbol);
    function tokenOfOwnerByIndex(address _owner, uint _index) external view returns (uint _tokenId);
    function tokenMetadata(uint _tokenId) public view returns (string _infoUrl);

    // Events
    event Transfer(address indexed _from, address indexed _to, uint256 _tokenId);
    event Approval(address indexed _owner, address indexed _approved, uint256 _tokenId);
}


contract EtherbotsNFT is ERC721Enumerable, ERC721Original {

    function name() public pure returns (string _name) {
      return "Etherbots";
    }

    function symbol() public pure returns (string _smbol) {
      return "ETHBOT";
    }

    // total supply of parts --> as no parts are ever deleted, this is simply
    // the total supply of parts ever created
    function totalSupply() public view returns (uint) {
        return parts.length;
    }

    /// @notice Returns the total number of deeds currently in existence.
    /// @dev Required for ERC-721 compliance.
    function countOfDeeds() external view returns (uint256) {
        return totalSupply();
    }

    /// internal function    which checks whether the token with id (_tokenId)
    /// is owned by the (_claimant) address
    function _owns(address _owner, uint256 _tokenId) internal view returns (bool) {
        return partIndexToOwner[_tokenId] == _owner;
    }

    function _approvedFor(address _newOwner, uint256 _tokenId) internal view returns (bool) {
        return partIndexToApproved[_tokenId] == _newOwner;
    }

    function ownerByIndex(uint256 _index) external view returns (address _owner){
        return partIndexToOwner[_index];
    }

    // returns the NUMBER of tokens owned by (_owner)
    function balanceOf(address _owner) public view returns (uint256 count) {
        return addressToTokensOwned[_owner];
    }

    function countOfDeedsByOwner(address _owner) external view returns (uint256) {
        return balanceOf(_owner);
    }

    // transfers a part to another account
    function transfer(address _to, uint256 _tokenId) public whenNotPaused {

        // Safety checks to prevent accidental transfers to common accounts
        require(_to != address(0));
        require(_to != address(this));
        // can't transfer parts to any of the auction contracts directly
        for (uint i = 0; i < auctions.length; i++){
            require(_to != auctions[i]);
        }
        // can't transfer parts to any of the battle contracts directly
        for (uint j = 0; j < battles.length; j++){
            require(_to != battles[j]);
        }

        // Cannot send tokens you don't own
        require(_owns(msg.sender, _tokenId));

        // perform state changes necessary for transfer
        _transfer(msg.sender, _to, _tokenId);
    }

    // transfers a part to another account
    function transferMany(address _to, uint256[] _tokenIds) external whenNotPaused {

        // Safety checks to prevent accidental transfers to common accounts
        require(_to != address(0));
        require(_to != address(this));
        // can't transfer parts to any of the auction contracts directly
        // require(_to != address(saleAuction));
        for (uint i = 0; i < auctions.length; i++){
            require(_to != auctions[i]);
        }
        // can't transfer parts to any of the battle contracts directly
        for (uint j = 0; j < auctions.length; j++){
            require(_to != battles[j]);
        }

        for (uint256 k = 0; k < _tokenIds.length; k++) {
            uint256 _tokenId = _tokenIds[k];

            // Cannot send tokens you don't own
            require(_owns(msg.sender, _tokenId));

            // perform state changes necessary for transfer
            _transfer(msg.sender, _to, _tokenId);
        }

    }

    // approves the (_to) address to use the transferFrom function on the token with id (_tokenId)
    // if you want to clear all approvals, simply pass the zero address
    function approve(address _to, uint256 _deedId) external whenNotPaused payable {
        // payable for ERC721 --> don't actually send eth @_@
        require(msg.value == 0);

        // Cannot approve the transfer of tokens you don't own
        require(_owns(msg.sender, _deedId));

        // Store the approval (can only approve one at a time)
        partIndexToApproved[_deedId] = _to;

        Approval(msg.sender, _to, _deedId);
    }

    // approves many token ids
    function approveMany(address _to, uint256[] _tokenIds) external whenNotPaused {

        for (uint i = 0; i < _tokenIds.length; i++){
            uint _tokenId = _tokenIds[i];

            // Cannot approve the transfer of tokens you don't own
            require(_owns(msg.sender, _tokenId));

            // Store the approval (can only approve one at a time)
            partIndexToApproved[_tokenId] = _to;
        }

        Approval(msg.sender, _to, _tokenId);
    }
    function _transferFrom(address _from, address _to, uint256 _tokenId) internal whenNotPaused {
        // Safety checks to prevent accidents
        require(_to != address(0));
        require(_to != address(this));

        // sender must be approved
        require(partIndexToApproved[_tokenId] == msg.sender);
        // from must currently own the token
        require(_owns(_from, _tokenId));

        // Reassign ownership (also clears pending approvals and emits Transfer event).
        _transfer(_from, _to, _tokenId);
    }

    // transfer the part with id (_tokenId) from (_from) to (_to)
    // (_to) must already be approved for this (_tokenId)
    function transferFrom(address _from, address _to, uint256 _tokenId) public whenNotPaused {

        // Safety checks to prevent accidents
        require(_to != address(0));
        require(_to != address(this));

        // sender must be approved
        require(partIndexToApproved[_tokenId] == msg.sender);
        // from must currently own the token
        require(_owns(_from, _tokenId));

        // Reassign ownership (also clears pending approvals and emits Transfer event).
        _transfer(_from, _to, _tokenId);
    }

    // returns the current owner of the token with id = _tokenId
    function ownerOf(uint256 _tokenId) public view returns (address owner) {
        owner = partIndexToOwner[_tokenId];
        // must result false if index key not found
        require(owner != address(0));
    }

    // returns a dynamic array of the ids of all tokens which are owned by (_owner)
    // Looping through every possible part and checking it against the owner is
    // actually much more efficient than storing a mapping or something, because
    // it won't be executed as a transaction
    function tokensOfOwner(address _owner) external view returns(uint256[] ownerTokens) {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory result = new uint256[](tokenCount);

        uint256 totalParts = totalSupply();
        uint256 resultIndex = 0;

        for (uint partId = 0; partId < totalParts; partId++) {
            if (partIndexToOwner[partId] == _owner) {
                result[resultIndex] = partId;
                resultIndex++;
            }
        }
        return result; // will have 0 elements if tokenCount == 0
    }

    // have one internal function which lets us implement the divergent interfaces
    function _metadata(uint256 _tokenId) internal returns(string){
        return "";
    }

    /// @notice A distinct URI (RFC 3986) for a given token.
    /// @dev If:
    ///  * The URI is a URL
    ///  * The URL is accessible
    ///  * The URL points to a valid JSON file format (ECMA-404 2nd ed.)
    ///  * The JSON base element is an object
    ///  then these names of the base element SHALL have special meaning:
    ///  * "name": A string identifying the item to which `_deedId` grants
    ///    ownership
    ///  * "description": A string detailing the item to which `_deedId` grants
    ///    ownership
    ///  * "image": A URI pointing to a file of image/* mime type representing
    ///    the item to which `_deedId` grants ownership
    ///  Wallets and exchanges MAY display this to the end user.
    ///  Consider making any images at a width between 320 and 1080 pixels and
    ///  aspect ratio between 1.91:1 and 4:5 inclusive.
    function deedUri(uint256 _deedId) external view returns (string _uri){
        return _metadata(_deedId);
    }

    /// returns a metadata URI
    // TODO: implement this.
    function tokenMetadata(uint256 _tokenId, string _preferredTransport) external view returns (string infoUrl) {
        return _metadata(_tokenId);
    }

    function takeOwnership(uint256 _deedId) external payable {
        // payable for ERC721 --> don't actually send eth @_@
        require(msg.value == 0);

        address _from = partIndexToOwner[_deedId];

        require(_approvedFor(msg.sender, _deedId));

        _transferFrom(_from, msg.sender, _deedId);
    }

    // parts are stored sequentially
    function deedByIndex(uint256 _index) external view returns (uint256 _deedId){
        return _index;
    }

    function countOfOwners() external view returns (uint256 _count){
        // TODO: implement this
        return 0;
    }

    function tokenOfOwnerByIndex(address _owner, uint _index) external view returns (uint _tokenId){
        // The index should be valid.
        require(_index < balanceOf(_owner));

        // can loop through all without
        uint256 seen = 0;
        uint256 totalTokens = totalSupply();

        for (uint i = 0; i < totalTokens; i++) {
            if (partIndexToOwner[i] == _owner) {
                if (seen == _index) {
                    return i;
                }
                seen++;
            }
        }
    }

    function _tokenOfOwnerByIndex(address _owner, uint _index) private view returns (uint _tokenId){
        // The index should be valid.
        require(_index < balanceOf(_owner));

        // can loop through all without
        uint256 seen = 0;
        uint256 totalTokens = totalSupply();

        for (uint i = 0; i < totalTokens; i++) {
            if (partIndexToOwner[i] == _owner) {
                if (seen == _index) {
                    return i;
                }
                seen++;
            }
        }
    }

    function deedOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256 _deedId){
        return _tokenOfOwnerByIndex(_owner, _index);
    }

}
