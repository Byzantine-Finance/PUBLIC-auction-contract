// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
import "./auction.sol";
import "./stratmod.sol";

contract ByzantineFinance {
    AuctionContract public auction;
    StrategyModule public strategyModule;

    mapping(address => bool) public strategyModules;

    constructor() {
        auction = new AuctionContract();
    }

    function createModule() public {
        strategyModule = new StrategyModule();
        strategyModules[address(strategyModule)] = true;
    }
}