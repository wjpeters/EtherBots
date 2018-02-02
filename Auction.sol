pragma solidity ^0.4.18;

import "./ERC721.sol";
// import "./Base.sol";
// Auction contract, facilitating statically priced sales, as well as 
// inflationary and deflationary pricing for items.
// Relies heavily on the ERC721 interface and so most of the methods
// are tightly bound to that implementation

contract NFTAuctionBase is ERC {

    ERC721 public nftContract;
    uint256 public ownerCut;
    uint public minDuration;
    uint public maxDuration;

    // Represents an auction on an NFT (in this case, Robot part)
    struct Auction {
        // address of part owner
        address seller;
        // wei price of listing
        uint256 startPrice;
        // wei price of floor
        uint256 endPrice;
        // duration of sale in seconds.
        uint64 duration;
        // Time when sale started
        // Reset to 0 after sale concluded
        uint64 start;
    }

    function NFTAuctionBase() public {
        minDuration = 1 minutes;
        maxDuration = 30 days; // arbitrary
    }

    // map of all tokens and their auctions
    mapping (uint256 => Auction) tokenIdToAuction;

    event AuctionCreated(uint256 tokenId, uint256 startPrice, uint256 endPrice, uint256 duration);
    event AuctionSuccessful(uint256 tokenId, uint256 totalPrice, address winner);
    event AuctionCancelled(uint256 tokenId);

    // returns true if the token with id _partId is owned by the _claimant address
    function _owns(address _claimant, uint256 _partId) internal view returns (bool) {
        return ownerOf(_partId) == _claimant;
    }

   // returns false if start == 0
    function _isActiveAuction(Auction _auction) internal returns (bool) {
        return _auction.start > 0;
    }
    
    // assigns ownership of the token with id = _partId to this contract
    // must have already been approved
    function _escrow(address _owner, uint256 _partId) internal {
        // throws on transfer fail
        transferFrom(_owner, this, _partId);
    }

    // transfer the token with id = _partId to buying address
    function _transfer(address _bidder, uint256 _partId) internal {
        // throws on transfer fail
        transfer(_bidder, _partId);
    }

    // creates
    function _newAuction(uint256 _partId, Auction _auction) internal {

        require(_auction.duration >= minDuration);

        tokenIdToAuction[_partId] = _auction;

        AuctionCreated(uint256(_partId),
            uint256(_auction.startPrice),
            uint256(_auction.endPrice),
            uint256(_auction.duration)
        );
    }

    function setMinDuration(uint _duration) external onlyOwner {
        minDuration = _duration;
    }

    function setMaxDuration(uint _duration) external onlyOwner {
        maxDuration = _duration;
    }

    /// Removes auction from public view, returns token to the seller
    function _cancelAuction(uint256 _partId, address _seller) internal {
        _removeAuction(_partId);
        _transfer(_seller, _partId);
        AuctionCancelled(_partId);
    }

    // Calculates price and transfers bid to owner. Part is NOT transferred to bidder.
    function _bid(uint256 _partId, uint256 _bidAmount) internal returns (uint256) {

        Auction storage auction = tokenIdToAuction[_partId];

        // check that this token is being auctioned
        require(_isActiveAuction(auction));

        // enforce bid >= the current price
        uint256 price = _currentPrice(auction);
        require(_bidAmount >= price);

        // Store seller before we delete auction.
        address seller = auction.seller;

        // Valid bid. Remove auction to prevent reentrancy.
        _removeAuction(_partId);

        // Transfer proceeds to seller (if there are any!)
        if (price > 0) {
            
            // Calculate and take fee from bid

            uint256 auctioneerCut = _computeFee(price);
            uint256 sellerProceeds = price - auctioneerCut;

            // Pay the seller
            seller.transfer(sellerProceeds);
        }

        // Calculate excess funds and return to bidder.
        uint256 bidExcess = _bidAmount - price;

        // Return any excess funds. Reentrancy again prevented by deleting auction.
        msg.sender.transfer(bidExcess);

        AuctionSuccessful(_partId, price, msg.sender);

        return price;
    }

    // returns the current price of the token being auctioned in _auction
    function _currentPrice(Auction storage _auction) internal view returns (uint256) {
        uint256 secsElapsed = now - _auction.start;
        return _computeCurrentPrice(
            _auction.startPrice,
            _auction.endPrice,
            _auction.duration,
            secsElapsed
        );
    }

    // Checks if NFTPart is currently being auctioned.
    function _isBeingAuctioned(Auction storage _auction) internal view returns (bool) {
        return (_auction.start > 0);
    }

    // removes the auction of the part with id _partId
    function _removeAuction(uint256 _partId) internal {
        delete tokenIdToAuction[_partId];
    }

    // computes the current price of an deflating-price auction 
    function _computeCurrentPrice( uint256 _startPrice, uint256 _endPrice, uint256 _duration, uint256 _secondsPassed ) internal pure returns (uint256) {
        
        if (_secondsPassed >= _duration) {
            // Has been up long enough to hit endPrice.
            // Return this price floor.
            return _endPrice;
            // this is a statically price sale. Just return the price.
        } else if (_startPrice == _endPrice) {
            return _startPrice;
        } else {
            // This auction contract supports auctioning from any valid price to any other valid price.
            // This means the price can dynamically increase upward, or downard.
            int256 priceDifference = int256(_endPrice) - int256(_startPrice);
            int256 currentPriceDifference = priceDifference * (int256(_secondsPassed) / int256(_duration));
            int256 currentPrice = int256(_startPrice) + currentPriceDifference;

            return uint256(currentPrice);
        }
    }

    // Compute percentage fee of transaction

    function _computeFee (uint256 _price) internal view returns (uint256) {
        return _price * ownerCut / 10000; 
    }

}

// Clock auction for NFTParts.
// Only timed when pricing is dynamic (i.e. startPrice != endPrice).
// Else, this becomes an infinite duration statically priced sale,
// resolving when succesfully bid for or cancelled.

contract ClockAuction is EtherbotsPrivileges, NFTAuctionBase {

    // The ERC-165 interface signature for ERC-721.

    bytes4 constant InterfaceSignature_ERC721 = bytes4(0x9a20483d);

    // Constructor references NFTAuctionBase. 
    function ClockAuction(address _nftAddress, uint256 _fee) public {
        require(_fee <= 10000);
        ownerCut = _fee;

        ERC721 candidateContract = ERC721(_nftAddress);
        require(candidateContract.supportsInterface(InterfaceSignature_ERC721));
        nftContract = candidateContract;
    }

    // Remove all ether from the contract. This will be marketplace fees.
    // Transfers to the NFT contract. 
    // Can be called by owner or NFT contract.

    function withdrawBalance() external {
        address nftAddress = address(nftContract);

        require(msg.sender == owner || msg.sender == nftAddress);

        nftAddress.transfer(this.balance);
    }

    // Creates an auction and lists it.
    function createAuction( uint256 _partId, uint256 _startPrice, uint256 _endPrice, uint256 _duration, address _seller ) external whenNotPaused {
        // Sanity check that no inputs overflow how many bits we've allocated
        // to store them in the auction struct.
        require(_startPrice == uint256(uint128(_startPrice)));
        require(_endPrice == uint256(uint128(_endPrice)));
        require(_duration == uint256(uint64(_duration)));

        require(_owns(msg.sender, _partId));
        _escrow(msg.sender, _partId);
        Auction memory auction = Auction(
            _seller,
            uint128(_startPrice),
            uint128(_endPrice),
            uint64(_duration),
            uint64(now)
        );
        _newAuction(_partId, auction);
    }

    // bids on open auction
    // will transfer ownership is successful
    
    function bid(uint256 _partId) external payable whenNotPaused {
        // _bid will throw if the bid or funds transfer fails
        _bid(_partId, msg.value);
        _transfer(msg.sender, _partId);
    }

    // Allows a user to cancel an auction before it's resolved.
    // Returns the part to the seller.

    function cancelAuction(uint256 _partId) external {
        Auction storage auction = tokenIdToAuction[_partId];
        require(_isBeingAuctioned(auction));
        address seller = auction.seller;
        require(msg.sender == seller);
        _cancelAuction(_partId, seller);
    }

    // returns the current price of the auction of a token with id _partId
    function getCurrentPrice(uint256 _partId) external view returns (uint256) {
        Auction storage auction = tokenIdToAuction[_partId];
        require(_isActiveAuction(auction));
        return _currentPrice(auction);
    }

    //  Returns the details of an auction from its _partId.
    function getAuction(uint256 _partId) external view returns ( address seller, uint256 startPrice, uint256 endPrice, uint256 duration, uint256 startedAt ) {
        Auction storage auction = tokenIdToAuction[_partId];
        require(_isBeingAuctioned(auction));
        return ( auction.seller, auction.startPrice, auction.endPrice, auction.duration, auction.start);
    }

    // Allows owner to cancel an auction.
    // ONLY able to be used when contract is paused,
    // in the case of emergencies.
    // Parts returned to seller as it's equivalent to them 
    // calling cancel.
    function cancelAuctionWhenPaused(uint256 _partId) whenPaused onlyOwner external {
        Auction storage auction = tokenIdToAuction[_partId];
        require(_isBeingAuctioned(auction));
        _cancelAuction(_partId, auction.seller);
    }

}

// Wrapper function for ClockAuction
contract PartAuction is ClockAuction {
    // Auction auction;
    /// @dev Sets the reference to the sale auction.
    /// @param _address - Address of sale contract.
    ClockAuction auction;
    function setAuctionAddress(address _address) external onlyOwner {
        ClockAuction candidateContract = ClockAuction(_address);

        // require(candidateContract.isSaleClockAuction());
        // Set the new contract address
        auction = candidateContract;
    }

    // list a part for auction.

    function createAuction( uint256 _partId, uint256 _startPrice, uint256 _endPrice, uint256 _duration ) external whenNotPaused {

        // user must have current control of the part
        // will lose control if they delegate to the auction
        // therefore no duplicate auctions!
        require(_owns(msg.sender, _partId));

        // _approve(_partId, saleAuction);

        // will throw if inputs are invalid
        // will clear transfer approval
        auction.createAuction(_partId,_startPrice,_endPrice,_duration,msg.sender);
    }

    // transfer balance back to core contract
    function withdrawAuctionBalance() external onlyOwner {
        auction.withdrawBalance();
    }
}