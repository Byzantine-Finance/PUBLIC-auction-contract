// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./auction.sol";

contract StrategyModule {
    address payable owner;
    address byzHQ;

    constructor(address stratModOwner) {
        owner = payable(stratModOwner);
        byzHQ = msg.sender;
    }

    // MAKE THIS GUY REQUEST OPERATORS





    function exitRequest() public onlyHQorOwner returns(bool success) {
        // Exit DVT, close down everything, etc.
        // Will get a lot more complicated as soon as things get spicy

        (bool exitSuccess, ) = owner.call{ value: address(this).balance }("");

        return(exitSuccess);
    }

    modifier onlyHQorOwner() {
        require(msg.sender == owner || msg.sender == byzHQ);
        _;
    }
}