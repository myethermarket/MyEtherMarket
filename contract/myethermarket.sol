pragma solidity ^0.4.0;

contract SafeMath {
    // updated to use native solidity assert function due to depreciated throw
    // updated with pure keyword to indicate no access of contract storage
  function safeMul(uint a, uint b) internal pure returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) internal pure returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) internal pure returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

}

contract MyEtherMarket {

    struct Bid {
        // bids automatically have tokenGet as address, know tokenGive is ether
        //address token; Dont need token, mapped to book with token known
        uint amountGive; // in terms of ether
        uint rate; // token price in wei
        uint nonce;
        bool exists;
        address user;
        // required for data structures
        bytes32 bookNext;
        bytes32 bookPrev;
    }
    
    struct Ask {
        // bids automatically have tokenGet as address, know tokenAsk is ether
        //address token; Dont need token, mapped to book with token known
        uint amountGive; // in terms of token
        uint rate; // token price in wei
        uint nonce;
        bool exists;
        address user;
        // required for data structures
        bytes32 bookNext;
        bytes32 bookPrev;
    }
    
    address admin;
    // mappings of orders. key is order hash
    mapping (bytes32 => Bid) bids;
    mapping (bytes32 => Ask) asks;
    //mapping (bytes32 => bool) orders; // prevents any possible duplicate orders
    // order books connect to book root only. key is [tokenAddr].
    mapping (address => bytes32) bookBidRoot;
    mapping (address => bytes32) bookAskRoot;

    // constructor, can only be ran on initial contract upload
    function MyEtherMarket() {
        admin = msg.sender;
    }
    
    // ---------------------------------   BIDS    ---------------------------------
    // this would be called by the user to offer a new bid
    // TODO: likely create a minimum order threshhold in eth, probably a dynamic variable controlled by admin. This would be to economically prevent book spam attacks.
    function newBid(address token, uint amountGive, uint rate, uint nonce) public returns (bytes32 hash){
        // Creates new struct and saves in storage. We leave out the mapping type.
        hash = sha256(msg.sender, token, amountGive, rate, nonce);
        // check for duplicates, then claim hash. irreversable.
        require(!bids[hash].exists);
        // create struct - dummy hashes for the struct
        bids[hash] = Bid(amountGive, rate, nonce, true, msg.sender, 0, 0);
        // insert into book
        insertBookBid(token, hash, rate);
    }
    
    // this is called internally to insert a new bid into the book
    function insertBookBid(address token, bytes32 hash, uint thisRate) private {
        // book is a linked list
        // decreasing order for bids, so check if we are greater than
        if (bookBidRoot[token] == 0) {
            bookBidRoot[token] = hash;
        } else {
            if (bids[bookBidRoot[token]].rate < thisRate) {
                // special case: we go at the front of the book
                bids[hash].bookNext = bookBidRoot[token];
                bids[bookBidRoot[token]].bookPrev = hash;
                bookBidRoot[token] = hash;
            } else {
                bytes32 current = bookBidRoot[token];
                // decreasing order for bids (highest first)
                while (bids[current].bookNext != 0 && bids[bids[current].bookNext].rate >= thisRate) {
                    current = bids[current].bookNext;
                }
                if (bids[current].bookNext != 0) {
                    // my next is current's next, my new next's previous is me
                    bids[hash].bookNext = bids[current].bookNext;
                    bids[bids[hash].bookNext].bookPrev = hash;
                }
                // my previous is current, current's next is me
                bids[hash].bookPrev = current;
                bids[current].bookNext = hash;
            }
        }
    }
    
    // this is called internally to remove a bid from the book
    function removeBookBid(address token, bytes32 hash) private {
        if (bookBidRoot[token] == hash) {
            bookBidRoot[token] = bids[hash].bookNext;
        } else {
            // we know we have a previous. safe to access bids.
            bids[bids[hash].bookPrev].bookNext = bids[hash].bookNext;
        }
        if (bids[hash].bookNext != 0) {
            bids[bids[hash].bookNext].bookPrev = bids[hash].bookPrev;
        }
    }
    
    function getBid(bytes32 hash) public constant returns (uint amountGive, uint rate, uint nonce, address user, bytes32 bookNext, bytes32 bookPrev){
        // Creates new struct and saves in storage. We leave out the mapping type.
        amountGive = bids[hash].amountGive;
        rate = bids[hash].rate;
        nonce = bids[hash].nonce;
        user = bids[hash].user;
        bookNext = bids[hash].bookNext;
        bookPrev = bids[hash].bookPrev;
    }
    
    // ---------------------------------   ASKS    ---------------------------------
    
    // this would be called by the user to offer a new ask
    // TODO: likely create a minimum order threshhold in eth, probably a dynamic variable controlled by admin. This would be to economically prevent book spam attacks.
    function newAsk(address token, uint amountGive, uint rate, uint nonce) public returns (bytes32 hash){
        // Creates new struct and saves in storage. We leave out the mapping type.
        hash = sha256(this, token, amountGive, rate, nonce);
        // check for duplicates, then claim hash. irreversable.
        require(!asks[hash].exists);
        // create struct - dummy hashes for the struct
        asks[hash] = Ask(amountGive, rate, nonce, true, msg.sender, 0, 0);
        // insert into book
        insertBookAsk(token, hash, rate);
    }
    
    // this is called internally to insert a new bid into the book
    function insertBookAsk(address token, bytes32 hash, uint thisRate) private {
        // book is a linked list
        // increasing order for asks, so check if we are less than
        if (bookAskRoot[token] == 0) {
            bookAskRoot[token] = hash;
        } else {
            if (asks[bookAskRoot[token]].rate > thisRate) {
                // special case: we go at the front of the book
                asks[hash].bookNext = bookAskRoot[token];
                asks[bookAskRoot[token]].bookPrev = hash;
                bookAskRoot[token] = hash;
            } else {
                bytes32 current = bookAskRoot[token];
                // increasing order for asks (lowest first)
                while (asks[current].bookNext != 0 && asks[asks[current].bookNext].rate <= thisRate) {
                    current = asks[current].bookNext;
                }
                if (asks[current].bookNext != 0) {
                    // my next is current's next, my new next's previous is me
                    asks[hash].bookNext = asks[current].bookNext;
                    asks[asks[hash].bookNext].bookPrev = hash;
                }
                // my previous is current, current's next is me
                asks[hash].bookPrev = current;
                asks[current].bookNext = hash;
            }
        }
    }
    
    // this is called internally to remove a bid from the book
    function removeBookAsk(address token, bytes32 hash) private {
        if (bookAskRoot[token] == hash) {
            bookAskRoot[token] = asks[hash].bookNext;
        } else {
            // we know we have a previous. safe to access asks.
            asks[asks[hash].bookPrev].bookNext = asks[hash].bookNext;
        }
        if (asks[hash].bookNext != 0) {
            asks[asks[hash].bookNext].bookPrev = asks[hash].bookPrev;
        }
    }
    
    function getAsk(bytes32 hash) public constant returns (uint amountGive, uint rate, uint nonce, address user, bytes32 bookNext, bytes32 bookPrev){
        // Creates new struct and saves in storage. We leave out the mapping type.
        amountGive = asks[hash].amountGive;
        rate = asks[hash].rate;
        nonce = asks[hash].nonce;
        user = asks[hash].user;
        bookNext = asks[hash].bookNext;
        bookPrev = asks[hash].bookPrev;
    }
}