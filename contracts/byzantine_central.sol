// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
import "./auction.sol";
import "./stratmod.sol";

contract ByzantineFinance is Ownable {
    AuctionContract public auction;
    StrategyModule public strategyModule;

    mapping(address => bool) public strategyModules;

    constructor() Ownable(msg.sender) {
        auction = new AuctionContract();
        console.log("Auction contract deployed at: ", address(auction));
        console.log("This contract deployed at: ", address(this));
    }

    function createModule() public onlyOwner {
        strategyModule = new StrategyModule();
        strategyModules[address(strategyModule)] = true;
    }
}