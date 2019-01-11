pragma solidity ^0.5.0;

contract App {
    // Returns new state hash, coins for player1 to withdraw and coins for player2 to withdraw. 
    function transition(address payable signer, bytes memory oldstate, bytes memory input, uint command) public pure returns (bytes32 newhstate); 
}

contract StateAssertionChannel {
    address payable[] public plist; // list of parties in our channel 
    mapping (address => uint) public bonds; // List of bonds to be refunded
    mapping (address => uint) public balance; // List of bonds to be refunded

    uint deadline;
    address asserter;
    bytes32 futurehstate;
    bytes32 inputHash;
    uint256 command;
    bool assertion;
    address public turn; 

    enum Status {DEPOSIT, ON, DISPUTE, PAYOUT} 
    
    Status public status;

    uint256 public bestRound = 0;
    bytes32 public hstate;
    uint256 public disputePeriod; 
    
    // Why is bond important? 
    // An honest user should always be refudnded for  challenging. Even if they get all coins in the app. 
    uint256 public bond; 
    
    // address of contract app 
    App public app;

    event EventAssert (address asserter, bytes32 prevhstate, bytes32 hstate, uint command, bytes input);
    event EventTimeout (uint256 indexed bestround);
    event EventEvidence (uint256 indexed bestround, bytes32 hstate);
    event EventClose (uint256 indexed bestround, bytes32 hstate);

    modifier onlyplayers { if (plist[0] == msg.sender || plist[1] == msg.sender) _; else revert(); }
     
    // The application creates this state channel and updates it with the list of players.
    // Also sets a fixed dispute period.
    // We assume the app is keeping track of each party's balance (and it is holding their coins).
    // --> This can be tweaked so the state channel holds the coins, and app tracks the balance, 
    // --> channel must instantatiate app - too much work for demo. 
    constructor(address payable party1, address payable party2, uint _disputePeriod, address _app, uint _bond) public {
        plist.push(party1);
        plist.push(party2);

        status = Status.DEPOSIT;

        disputePeriod = _disputePeriod;
        app = App(_app); 
        bond = _bond; 
    }

    // Both parties need to deposit coins. 
    // Equal value turns on channel. 
    function deposit() public payable onlyplayers {
        balance[msg.sender] = balance[msg.sender] + msg.value;
        if(balance[plist[0]] == balance[plist[1]]) {
            status = Status.ON; 
        }
    }

    function clearAssertionState() internal {
        asserter = address(0x00);
        futurehstate = 0x00;
        inputHash = 0x00;
        command = 0;
        assertion = false;
    }
    
    // Set latest agreed state off-chain (can cancel commands in process)
    function setstate(uint256[] memory _sigs, uint256 _i, address _turn, bytes32 _hstate) public {
        require(_i > bestRound);

        // Commitment to signed message for new state hash.
        bytes32 h = keccak256(abi.encodePacked(_hstate, _i, _turn, address(this)));
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        h = keccak256(abi.encodePacked(prefix, h));

        // Check all parties in channel have signed it.
        for (uint i = 0; i < plist.length; i++) {
            uint8 V = uint8(_sigs[i*3+0])+27;
            bytes32 R = bytes32(_sigs[i*3+1]);
            bytes32 S = bytes32(_sigs[i*3+2]);
            verifySignature(plist[i], h, V, R, S);
        }

        // Cancel dispute
        status = Status.ON; 
        
        // Store new state!
        bestRound = _i;
        hstate = _hstate;
        turn = _turn;

        // clear the assertion states
        clearAssertionState();

        // Refund everyone
        refundAllBonds(); 

        // Tell the world about the new state!
        emit EventEvidence(bestRound, hstate);
    }

    // Trigger the dispute
    // Missing _prevhstate as we'll use the one already in the contract
    function triggerdispute() onlyplayers payable public {
        // Make sure dispute process is not already active
        require( status == Status.ON );
        status = Status.DISPUTE;
        // Dummy assertion - overwritten in AssertState

        // address payable otherParty;
        // if(turn == plist[0]) otherParty = plist[1];
        // else otherParty = plist[0];
        // TODO: do we still need to do this
        //assertion = Assertion(otherParty, 0,hstate,"",0);

        deadline = block.number + disputePeriod; 
    }


    // change the next turn
    function changeTurn() internal {
        if(plist[0] == turn) turn = plist[1];
        else if(plist[1] == turn) turn = plist[0];
    }
    
    // Party in the channel can assert a new state. 
    function assertState(bytes32 _hstate, bytes32 _assertedState, bytes memory _input,  uint _command) onlyplayers payable public {
        require(status == Status.DISPUTE);
        require(turn == msg.sender); 
        changeTurn(); // Cannot assert two states in a row. 
        if(!assertion) {
            assertion = true;
            require(hstate == _hstate);
        } else {
            require(futurehstate == _hstate);
        }

        // We can confirm we always have the bond from sender. 
        // We'll refund all bonds after dispute is resolved. 
        require((msg.value == bond && bonds[msg.sender] == 0)
            || (msg.value == 0 && bonds[msg.sender] == bond));        
        if(msg.value != 0) bonds[msg.sender] = bonds[msg.sender] + msg.value;

        // update assertion data
        asserter = msg.sender;
        inputHash = keccak256(_input);
        command = _command;
        hstate = _hstate;
        futurehstate = _assertedState;

        // New deadline 
        deadline = block.number + disputePeriod;
        
        emit EventAssert(asserter, hstate, futurehstate, command, _input);
    }

    // TODO: hstate is not set correctly in assertstate
    // TODO: update turn taker in assertstate
    // TODO: asserter != msg.sender (should checkCallerTurn()) 
    // TODO: checkh in challengeAssertion

     
    // Send old state, and the index for submitted command. 
    // This is not PISA friendly. Ideally PISA will have a signed message from the honest party with PISA's address in it.
    // i.e. to stop front-running attacks. 
    // Can easily be fixed (note: this means no more state privacy for PISA)
    function challengeCommand(bytes memory _oldstate, bytes memory _input) onlyplayers public {
        require(status == Status.DISPUTE);
        // Asserter cannot challenge their own command
        require(turn == msg.sender); 
        require(assertion);
        // hstate is either accepted by all parties, or it was 
        // extended as "correct" by the asserter 
        require(hstate == keccak256(abi.encodePacked(_oldstate))); 
        require(inputHash == keccak256(_input));

        // Fetch us new state 
        // Note: we assume the input includes a digital signature 
        // from the party executing this command 
        bytes32 newhstate;

        (newhstate) = app.transition(msg.sender, _oldstate, _input, command);
        
        // Is this really the new state?
        // Can the user really withdraw this amount? 
        if(newhstate != futurehstate) {
            // send all funds (including bonds) in the contract to other player
            msg.sender.transfer(address(this).balance);
        }
    }

    // The app has reached the terminal state. Its state should just be a balance. 
    function resolve(uint balance1, uint balance2) onlyplayers public {
        
        // If the final state was reached via dispute process,
        // Make sure the counterparty accepts it (i.e. the one who didnt do an assertion)
        if(assertion) {
            // Must be accepted by the counterparty 
            require(turn == msg.sender); 
            // finalise the hstate to be the asserted one
            hstate = futurehstate;
        }
        else {
            require(status == Status.ON); 
        }
        
        // In the app - the final state is "balance1,balance2". 
        require(hstate == keccak256(abi.encodePacked(balance1, balance2))); 
        
        // There was no response from a party
        // i.e. both parties need to use "setstate" or finish protocol via state assertions. 
        plist[0].transfer(balance1);
        plist[1].transfer(balance2);
        refundAllBonds();

        emit EventTimeout(bestRound);
    }

    function timeout() onlyplayers public {
        require(block.number >= deadline); 
        require(status == Status.DISPUTE);
        
        // There was no response from a party
        // i.e. both parties need to use "setstate" or finish protocol via state assertions. 
        // if we timeout penalise whoever's turn it is by sending everything 
        // in the contract to the other player
        address payable otherPlayer;
        if(plist[0] == turn) otherPlayer = plist[1];
        else if(plist[1] == turn) otherPlayer = plist[0];
        otherPlayer.transfer(address(this).balance);

        emit EventTimeout(bestRound);
    }
    
    // Refund all bonds - only callable when resolving dispute 
    function refundAllBonds() internal {
                
        // Refund all bonds 
        for(uint k=0; k<plist.length; k++) {
            
            // How much do we send? 
            uint toSend = bonds[plist[k]]; 
            bonds[plist[k]] = 0;
            
            // Send it! 
            if(toSend != 0) plist[k].transfer(toSend); //throws if bad 
        }
    
        // Delete last stored command
        delete assertion;
    }
        
    // Helper function to verify signatures
    function verifySignature(address pub, bytes32 h, uint8 v, bytes32 r, bytes32 s) public pure {
        address _signer = ecrecover(h,v,r,s);
        if (pub != _signer) revert();
    }
    
    
}
