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

contract Token {
  /// @return total amount of tokens
  function totalSupply() constant returns (uint256 supply) {}

  /// @param _owner The address from which the balance will be retrieved
  /// @return The balance
  function balanceOf(address _owner) constant returns (uint256 balance) {}

  /// @notice send `_value` token to `_to` from `msg.sender`
  /// @param _to The address of the recipient
  /// @param _value The amount of token to be transferred
  /// @return Whether the transfer was successful or not
  function transfer(address _to, uint256 _value) returns (bool success) {}

  /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
  /// @param _from The address of the sender
  /// @param _to The address of the recipient
  /// @param _value The amount of token to be transferred
  /// @return Whether the transfer was successful or not
  function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {}

  /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
  /// @param _spender The address of the account able to transfer the tokens
  /// @param _value The amount of wei to be approved for transfer
  /// @return Whether the approval was successful or not
  function approve(address _spender, uint256 _value) returns (bool success) {}

  /// @param _owner The address of the account owning tokens
  /// @param _spender The address of the account able to transfer the tokens
  /// @return Amount of remaining tokens allowed to spent
  function allowance(address _owner, address _spender) constant returns (uint256 remaining) {}

  event Transfer(address indexed _from, address indexed _to, uint256 _value);
  event Approval(address indexed _owner, address indexed _spender, uint256 _value);

  uint public decimals;
  string public name;
}

contract StandardToken is Token {

  function transfer(address _to, uint256 _value) returns (bool success) {
    //Default assumes totalSupply can't be over max (2^256 - 1).
    //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
    //Replace the if with this one instead.
    if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
    //if (balances[msg.sender] >= _value && _value > 0) {
      balances[msg.sender] -= _value;
      balances[_to] += _value;
      Transfer(msg.sender, _to, _value);
      return true;
    } else { return false; }
  }

  function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
    //same as above. Replace this line with the following if you want to protect against wrapping uints.
    if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
    //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
      balances[_to] += _value;
      balances[_from] -= _value;
      allowed[_from][msg.sender] -= _value;
      Transfer(_from, _to, _value);
      return true;
    } else { return false; }
  }

  function balanceOf(address _owner) constant returns (uint256 balance) {
    return balances[_owner];
  }

  function approve(address _spender, uint256 _value) returns (bool success) {
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

  function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
    return allowed[_owner][_spender];
  }

  mapping(address => uint256) balances;

  mapping (address => mapping (address => uint256)) allowed;

  uint256 public totalSupply;
}

// this is used for testing only. simple little minting scheme.
contract ReserveToken is StandardToken, SafeMath {
  address public minter;
  function ReserveToken() {
    minter = msg.sender;
  }
  function create(address account, uint amount) public {
    require(msg.sender == minter);
    balances[account] = safeAdd(balances[account], amount);
    totalSupply = safeAdd(totalSupply, amount);
  }
  function destroy(address account, uint amount) public {
    require(msg.sender == minter);
    require(balances[account] >= amount);
    balances[account] = safeSub(balances[account], amount);
    totalSupply = safeSub(totalSupply, amount);
  }
}



contract MyEtherMarket is SafeMath {

    struct Bid {
        // bids automatically have tokenGet as address, know tokenGive is ether
        //address token; Dont need token, mapped to book with token known
        uint amountGive; // in terms of ether
        uint rate; // token price [eth/token * 1 ether]
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
        uint rate; // token price [eth/token * 1 ether]
        uint nonce;
        bool exists;
        address user;
        // required for data structures
        bytes32 bookNext;
        bytes32 bookPrev;
    }
    
    address public admin;
    // mappings of orders. key is order hash
    mapping (bytes32 => Bid) bids;
    mapping (bytes32 => Ask) asks;
    // order books connect to book root only. key is [tokenAddr].
    mapping (address => bytes32) bookBidRoot;
    mapping (address => bytes32) bookAskRoot;
    // MyEtherMarket wallet balances. keys are [tokenAddr][userAddr]; (token=0 means Ether)
    mapping (address => mapping (address => uint)) public walletBalance;
    // this is the minimum size, in wei that an order can have
    uint minOrderSizeWei;
    uint feeTake;
    
    // constructor, can only be ran on initial contract upload
    // note the feeTake is always divided by 1 ether
    function MyEtherMarket(uint minOrderSizeWei_, uint thisFeeTake_) {
        admin = msg.sender;
        minOrderSizeWei = minOrderSizeWei_;
        feeTake = thisFeeTake_;
    }
    
    // This can be called by the admin to change the minimum order size as the price of ether goes to the moon
    function changeMinOrderSize(uint MinOrderSizeWei_) public {
        require(msg.sender == admin);
        minOrderSizeWei = MinOrderSizeWei_;
    }
    
    // This can be called by the admin to reduce the make fee. No increases allowed that would screw users.
    function changefeeTake(uint feeTake_) public {
        require(msg.sender == admin);
        require(feeTake_ < feeTake);
        feeTake = feeTake_;
    }
    
    // ---------------------------   DEPOSIT/WITHDRAWAL    -------------------------
    // ETHER
    function deposit() payable public {
        walletBalance[0][msg.sender] = safeAdd(walletBalance[0][msg.sender], msg.value);
    }
    function withdraw(uint amount) public {
        require(walletBalance[0][msg.sender] >= amount);
        walletBalance[0][msg.sender] = safeSub(walletBalance[0][msg.sender], amount);
        if (!msg.sender.call.value(amount)()) {
            require(false); // throw
        }
    }
    // TOKENS
    function depositToken(address token, uint amount) public {
        //remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
        require(token != 0);
        require(Token(token).transferFrom(msg.sender, this, amount));
        walletBalance[token][msg.sender] = safeAdd(walletBalance[token][msg.sender], amount);
    }
    function withdrawToken(address token, uint amount) public {
        if(token==0) {
            require(false);
        }
        require(walletBalance[token][msg.sender] >= amount);
        walletBalance[token][msg.sender] = safeSub(walletBalance[token][msg.sender], amount);
        if (!Token(token).transfer(msg.sender, amount)) {
            require(false);
        }
    }
    
    // ---------------------------------   BIDS    ---------------------------------
    // this would be called by the user to offer a new bid
    function newBid(address token, uint amountGive, uint rate, uint nonce) public returns (bytes32 hash){
        require(amountGive >= minOrderSizeWei);
        // Creates new struct and saves in storage. We leave out the mapping type.
        hash = sha256(msg.sender, token, amountGive, rate, nonce);
        // safely deduct funds from user's MEM walletBalance
        walletBalance[0][msg.sender] = safeSub(walletBalance[0][msg.sender], amountGive);
        // check for duplicates, then claim hash. irreversable.
        require(!bids[hash].exists);
        // create struct - dummy hashes for the struct
        bids[hash] = Bid(amountGive, rate, nonce, true, msg.sender, 0, 0);
        // insert into book
        insertBookBid(token, hash, rate);
    }
    
    // this is called internally to insert a new bid into the book
    // assumes the order has already been created
    function insertBookBid(address token, bytes32 hash, uint thisRate) private {
        // books are linked lists
        // check the priceline
        while (bookAskRoot[token] != 0 && thisRate >= asks[bookAskRoot[token]].rate && bids[hash].amountGive > 0) {
            // there is an ask to fill
            fillAsk(bookAskRoot[token], hash, safeMul(asks[bookAskRoot[token]].amountGive, asks[bookAskRoot[token]].rate) / (1 ether), token, safeMul(bids[hash].amountGive, (1 ether)) / asks[bookAskRoot[token]].rate);
        }
        // if there is any left to give, place in the book
        if (bids[hash].amountGive > 0) {
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
    }
    
    // this is called by a user to cancel their bid and reclaim their funds
    function cancelBid(address token, bytes32 hash) public {
        // only a user can cancel their own order
        require(bids[hash].user == msg.sender);
        // require the order to be active
        require(bids[hash].amountGive > 0);
        // remove the order from the book
        removeBookBid(token, hash);
        // return the eth to the user
        walletBalance[0][msg.sender] = safeAdd(walletBalance[0][msg.sender], bids[hash].amountGive);
        // fully close out to prevent repeat cancellation
        bids[hash].amountGive = 0;
    }
    
    // this is called internally to remove a bid from the book
    // note this makes no state changes to the actual order. must set amountGive to zero elsewhere, but efficient to have as reference so not changed here.
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
    
    // this is called internally to fill a bid in the book
    function fillBid(bytes32 makerHash, bytes32 takerHash, uint amountTokensNeededToFillBid, address token, uint maxTakeAmountEth) private {
       // descriptive: if (amountTokensMyAskCanFill >= amountTokensNeededToFillBid) {
        if (asks[takerHash].amountGive >= amountTokensNeededToFillBid) {// comparing in tokens
            // maker gets their order removed and their amount needed to fill
            removeBookBid(token, makerHash);
            // maker is a bidder, they get tokens
            walletBalance[token][bids[makerHash].user] = safeAdd(walletBalance[token][bids[makerHash].user], amountTokensNeededToFillBid);
            // taker reduces his amount given and then gets his ether
            asks[takerHash].amountGive = safeSub(asks[takerHash].amountGive, amountTokensNeededToFillBid);
            // taker gets all remainnig eth from the maker, minus the fee
            walletBalance[0][msg.sender] = safeAdd(walletBalance[0][msg.sender], safeSub(bids[makerHash].amountGive, safeMul(bids[makerHash].amountGive, feeTake) / (1 ether)));
            // pay the fee
            walletBalance[0][admin] = safeAdd(walletBalance[0][admin], safeMul(bids[makerHash].amountGive, feeTake) / (1 ether));
            // fully close the maker's order (to prevent post-trade cancellation)
            bids[makerHash].amountGive = 0;
        } else {
            // maker gets their amountGive reduced by the taker's available amountGive
            // maker gets all the tokens from the taker
            walletBalance[token][bids[makerHash].user] = safeAdd(walletBalance[token][bids[makerHash].user], asks[takerHash].amountGive);
            // maker must reduce amountGive at makers rate. This should be less than the remaining amountGive.
            // if it is not less, it is between rounding tolerance, so clear both orders
            if (maxTakeAmountEth >= bids[makerHash].amountGive) { // comparing in wei
                // we are also clearing the ask order due to rounding
                removeBookBid(token, makerHash);
                // taker gets all remainnig eth from the maker, minus the fee
                walletBalance[0][msg.sender] = safeAdd(walletBalance[0][msg.sender], safeSub(bids[makerHash].amountGive, safeMul(bids[makerHash].amountGive, feeTake) / (1 ether)));
                // pay the fee
                walletBalance[0][admin] = safeAdd(walletBalance[0][admin], safeMul(bids[makerHash].amountGive, feeTake) / (1 ether));
                // fully close the maker's order (to prevent post-trade cancellation)
                bids[makerHash].amountGive = 0;
            } else {
                // subtract appropriate amount of tokens from the maker's order
                bids[makerHash].amountGive = safeSub(bids[makerHash].amountGive, maxTakeAmountEth);
                // taker gets those eth from the maker, minus the fee
                // defined in memory to save gas: uint maxTakeAmountEth = safeMul(asks[takerHash].amountGive, bids[makerHash].rate) / (1 ether);
                walletBalance[0][msg.sender] = safeAdd(walletBalance[0][msg.sender], safeSub(maxTakeAmountEth, safeMul(maxTakeAmountEth, feeTake) / (1 ether)));
                // pay the fee
                walletBalance[0][admin] = safeAdd(walletBalance[0][admin], safeMul(maxTakeAmountEth, feeTake) / (1 ether));
            }
            // taker was cleared out
            asks[takerHash].amountGive = 0;
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
    function newAsk(address token, uint amountGive, uint rate, uint nonce) public returns (bytes32 hash){
        require(safeMul(amountGive, rate) / (1 ether) > minOrderSizeWei);
        // Creates new struct and saves in storage. We leave out the mapping type.
        hash = sha256(this, token, amountGive, rate, nonce);
        // safely deduct funds from user's MEM walletBalance
        walletBalance[token][msg.sender] = safeSub(walletBalance[token][msg.sender], amountGive);
        // check for duplicates, then claim hash. irreversable.
        require(!asks[hash].exists);
        // create struct - dummy hashes for the struct
        asks[hash] = Ask(amountGive, rate, nonce, true, msg.sender, 0, 0);
        // insert into book
        insertBookAsk(token, hash, rate);
    }
    
    // this is called internally to insert a new bid into the book
    function insertBookAsk(address token, bytes32 hash, uint thisRate) private {
        // books are linked lists
        // check the priceline
        while (bookBidRoot[token] != 0 && thisRate <= bids[bookBidRoot[token]].rate && asks[hash].amountGive > 0) {
            // there is a bid to fill
            fillBid(bookBidRoot[token], hash, safeMul(bids[bookBidRoot[token]].amountGive, (1 ether)) / bids[bookBidRoot[token]].rate, token, safeMul(asks[hash].amountGive, bids[bookBidRoot[token]].rate) / (1 ether));
        }
        // if there is any left to give, place in the book
        if (asks[hash].amountGive > 0) {
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
    }
    
    // this is called by a user to cancel their ask and reclaim their funds
    function cancelAsk(address token, bytes32 hash) public {
        // only a user can cancel their own order
        require(asks[hash].user == msg.sender);
        // require the order to be active
        require(asks[hash].amountGive > 0);
        // remove the order from the book
        removeBookAsk(token, hash);
        // return the tokens to the user
        walletBalance[token][msg.sender] = safeAdd(walletBalance[token][msg.sender], bids[hash].amountGive);
        // fully close out the order to prevent repeat cancellation
        asks[hash].amountGive = 0;
    }
    
    // this is called internally to remove a bid from the book
    // note this makes no state changes to the actual order. must set amountGive to zero elsewhere, but efficient to have as reference so not changed here.
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
    
    // this is called internally to fill an ask in the book
    // assumes the rate check has already occured. uses maker's rate.
    function fillAsk(bytes32 makerHash, bytes32 takerHash, uint amountNeededToFillAsk, address token, uint maxTakeAmountTokens) private {
        // descriptive: if (amountToTake >= amountNeededToFillAsk) {
        if (bids[takerHash].amountGive >= amountNeededToFillAsk) {// comparing in wei
            // maker gets their order removed and their amount needed to fill
            removeBookAsk(token, makerHash);
            walletBalance[0][asks[makerHash].user] = safeAdd(walletBalance[0][asks[makerHash].user], amountNeededToFillAsk);
            // taker reduces his amount given and then gets his tokens
            bids[takerHash].amountGive = safeSub(bids[takerHash].amountGive, amountNeededToFillAsk);
            // take all the tokens, minus the fees
            walletBalance[token][msg.sender] = safeAdd(walletBalance[token][msg.sender], safeSub(asks[makerHash].amountGive, safeMul(asks[makerHash].amountGive, feeTake) / (1 ether)));
            // pay the fee
            walletBalance[token][admin] = safeAdd(walletBalance[token][admin], safeMul(asks[makerHash].amountGive, feeTake) / (1 ether));
            // fully close the maker's order (to prevent post-trade cancellation)
            asks[makerHash].amountGive = 0;
        } else {
            // maker gets their amountGive reduced by the taker's available amountGive
            // maker gets all the ether from the taker
            walletBalance[0][asks[makerHash].user] = safeAdd(walletBalance[0][asks[makerHash].user], bids[takerHash].amountGive);
            // maker must reduce amountGive at makers rate. This should be less than the remaining amountGive.
            // if it is not less, it is between rounding tolerance, so clear both orders
            if (maxTakeAmountTokens >= asks[makerHash].amountGive) {
                // we are also clearing the ask order due to rounding
                removeBookAsk(token, makerHash);
                // take all the tokens, minus the fees
                walletBalance[token][msg.sender] = safeAdd(walletBalance[token][msg.sender], safeSub(asks[makerHash].amountGive, safeMul(asks[makerHash].amountGive, feeTake) / (1 ether)));
                // pay the fee
                walletBalance[token][admin] = safeAdd(walletBalance[token][admin], safeMul(asks[makerHash].amountGive, feeTake) / (1 ether));
                // fully close the maker's order (to prevent post-trade cancellation)
                asks[makerHash].amountGive = 0;
            } else {
                // subtract appropriate amount of tokens from the maker's order
                asks[makerHash].amountGive = safeSub(asks[makerHash].amountGive, maxTakeAmountTokens);
                // taker gets those tokens from the maker
                walletBalance[token][msg.sender] = safeAdd(walletBalance[token][msg.sender], safeSub(maxTakeAmountTokens, safeMul(maxTakeAmountTokens, feeTake) / (1 ether)));
                walletBalance[token][admin] = safeAdd(walletBalance[token][admin], safeMul(maxTakeAmountTokens, feeTake) / (1 ether));
            }
            // taker was cleared out
            bids[takerHash].amountGive = 0;
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