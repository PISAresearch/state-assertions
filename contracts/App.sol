pragma solidity ^0.5.0;

contract App {
    
    // Returns new state hash, coins for player1 to withdraw and coins for player2 to withdraw. 
    function transition(address payable signer, bytes memory oldstate, bytes memory input, uint command) public pure returns (bytes32 newhstate){
        // hash of "0xofff"
        newhstate = 0x0050c0bb1a7f44340fff58dc7250ec88a127ad18267a1cadbb0839d5d67566d8;
    } 

}
