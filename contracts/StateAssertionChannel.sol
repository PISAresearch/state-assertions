pragma solidity ^0.5.0;

contract App {
    // Returns new state hash, coins for player1 to withdraw and coins for player2 to withdraw. 
    function transition(address signer, bytes memory oldstate, bytes memory input, uint command) public pure returns (bytes32 newhstate); 
}

contract StateAssertionChannel {
    bool turnParity;
    bool bondParty1;
    bool bondParty2;
    Status public status;
    uint deadline;

    address payable[] public plist; // list of parties in our channel 
    mapping (address => uint) public balance; // List of bonds to be refunded

    // address public turn; 
    enum Status {DEPOSIT, ON, DISPUTE } 

    uint256 public bestRound = 0;
    bytes32 public channelHash;
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

    // TODO: balance
    // Both parties need to deposit coins. 
    // Equal value turns on channel. 
    function deposit() public payable onlyplayers {
        balance[msg.sender] = balance[msg.sender] + msg.value;
        if(balance[plist[0]] == balance[plist[1]]) {
            status = Status.ON; 
        }
    }

    // Set latest agreed state off-chain (can cancel commands in process)
    function setstate(uint256[] memory _sigs, 
        uint256 _i, 
        bool _turnParity, 
        bytes32 _hstate
        ) public {
        require(_i > bestRound);

        // Commitment to signed message for new state hash.
        bytes32 h = keccak256(abi.encodePacked(_hstate, _i, _turnParity, address(this)));
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
        turnParity = _turnParity;

        // clear the assertion states
        channelHash = keccak256(abi.encodePacked(_hstate, bytes32(0x00)));

        // Refund everyone
        refundAllBonds(); 

        // Tell the world about the new state!
        emit EventEvidence(bestRound, _hstate);
    }

    // Trigger the dispute
    // Missing _prevhstate as we'll use the one already in the contract
    function triggerdispute() onlyplayers payable public {
        // Make sure dispute process is not already active
        require( status == Status.ON );
        status = Status.DISPUTE;
        deadline = block.number + disputePeriod; 
    }

    // Party in the channel can assert a new state. 
    // TODO: tidy up the _args
    function assertState(bytes32 _hstate, 
            bytes32 _assertedState, 
            bytes memory _input,  
            uint _command,
            
            
            bytes32 currenthstate,
            address currentAsserter,
            bytes32 currentInputHash,
            uint256 currentCommand,
            bytes32 currentAssertedState

            ) onlyplayers payable public {
        // 1000
        require(status == Status.DISPUTE);
        require((turnParity && (msg.sender == plist[0])) || (!turnParity && (msg.sender == plist[1])));
        
        // is there an assertion set?
        if(channelHash == keccak256(abi.encodePacked(currenthstate, bytes32(0x00)))) {
            // no
            require(currenthstate == _hstate);
        } else {
            // yes
            require(channelHash == keccak256(abi.encodePacked(currenthstate, keccak256(abi.encodePacked(currentAsserter, currentInputHash, currentCommand, currentAssertedState)))));
            require(currentAssertedState == _hstate);
        }

        // We can confirm we always have the bond from sender. 
        // We'll refund all bonds after dispute is resolved. 

        // is this party1 or two
        bool bondValue;
        uint playerIndex;
        if(plist[0] == msg.sender) {
            bondValue = bondParty1;
            playerIndex = 0;
        }
        else if(plist[1] == msg.sender) { 
            bondValue = bondParty2; 
            playerIndex = 1;
        }
        
        // 1000
        require((msg.value == bond && !bondValue)
            || (msg.value == 0 && bondValue));

        
        // 5000
        if(msg.value != 0) { 
            if(playerIndex == 0) bondParty1 = true; 
            else if(playerIndex == 1) bondParty2 = true;
        }

        // update channel info
        // 6000
        channelHash = keccak256(abi.encodePacked(_hstate, keccak256(abi.encodePacked(msg.sender, keccak256(abi.encodePacked(_input)), _command, _assertedState))));

        // New deadline 
        // 5000
        deadline = block.number + disputePeriod;
        // 5000
        turnParity = !turnParity; // Cannot assert two states in a row. 
        
        
        emit EventAssert(msg.sender, _hstate, _assertedState, _command, _input);
    }

    // TODO: hstate is not set correctly in assertstate
    // TODO: update turn taker in assertstate
    // TODO: asserter != msg.sender (should checkCallerTurn()) 
    // TODO: checkh in challengeAssertion

     
    // Send old state, and the index for submitted command. 
    // This is not PISA friendly. Ideally PISA will have a signed message from the honest party with PISA's address in it.
    // i.e. to stop front-running attacks. 
    // Can easily be fixed (note: this means no more state privacy for PISA)
    function challengeCommand(bytes memory _oldstate, bytes memory _input, 
        bytes32 currenthstate,
        bytes32 currentAssertionHash,
        address currentAsserter,
        bytes32 currentInputHash,
        uint256 currentCommand,
        bytes32 currentAssertedState
    
    ) onlyplayers public {
        require(status == Status.DISPUTE);
        // Asserter cannot challenge their own command
        require((turnParity && (msg.sender == plist[0])) || (!turnParity && (msg.sender == plist[1])));
        // hstate is either accepted by all parties, or it was 
        // extended as "correct" by the asserter 
        if(currentAssertionHash != 0) {
            require(currentAssertionHash == keccak256(abi.encodePacked(currentAsserter, currentInputHash, currentCommand, currentAssertedState)));
        }
        require(channelHash == keccak256(abi.encodePacked(keccak256(abi.encodePacked(_oldstate)), currentAssertionHash)));
        require(currentInputHash == keccak256(abi.encodePacked(_input)));

        // Fetch us new state 
        // Note: we assume the input includes a digital signature 
        // from the party executing this command 
        bytes32 newhstate;
        (newhstate) = app.transition(currentAsserter, _oldstate, _input, currentCommand);
        
        // Is this really the new state?
        // Can the user really withdraw this amount? 
        if(newhstate != currentAssertedState) {
            // send all funds (including bonds) in the contract to other player
            msg.sender.transfer(address(this).balance);
        }
    }

    // The app has reached the terminal state. Its state should just be a balance. 
    function resolve(uint balance1, uint balance2,
        bytes32 currenthstate,
        bytes32 currentAssertionHash,
        address currentAsserter,
        bytes32 currentInputHash,
        uint256 currentCommand,
        bytes32 currentAssertedState
    ) onlyplayers public {
        // If the final state was reached via dispute process,
        // Make sure the counterparty accepts it (i.e. the one who didnt do an assertion)
        require(channelHash == keccak256(abi.encodePacked(currenthstate, currentAssertionHash)));
        bytes32 balanceHash;
        if(currentAssertionHash != 0) {
            // Must be accepted by the counterparty 
            require(currentAssertionHash == keccak256(abi.encodePacked(currentAsserter, currentInputHash, currentCommand, currentAssertedState)));
            require((turnParity && (msg.sender == plist[0])) || (!turnParity && (msg.sender == plist[1])));

            // finalise the hstate to be the asserted one
            balanceHash = currentAssertedState;
        }
        else {
            require(status == Status.ON);
            balanceHash = currenthstate;
        }

        // In the app - the final state is "balance1,balance2". 
        require(balanceHash == keccak256(abi.encodePacked(balance1, balance2))); 
        
        // There was no response from a party
        // i.e. both parties need to use "setstate" or finish protocol via state assertions. 
        plist[0].transfer(balance1);
        plist[1].transfer(balance2);
        refundAllBonds();
        channelHash = keccak256(abi.encodePacked(balanceHash, bytes32(0x00)));

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
        if(turnParity) otherPlayer = plist[1];
        else if(!turnParity) otherPlayer = plist[0];
        otherPlayer.transfer(address(this).balance);

        emit EventTimeout(bestRound);
    }
    
    // Refund all bonds - only callable when resolving dispute 
    function refundAllBonds() internal {
        bool toSend1 = bondParty1;
        if(toSend1) {
            bondParty1 = false;
            plist[0].transfer(bond);
        }


        bool toSend2 = bondParty2;
        if(toSend2) {
            bondParty2 = false;
            plist[1].transfer(bond);
        }
    }
        
    // Helper function to verify signatures
    function verifySignature(address pub, bytes32 h, uint8 v, bytes32 r, bytes32 s) public pure {
        address _signer = ecrecover(h,v,r,s);
        if (pub != _signer) revert();
    }
    
    
}
