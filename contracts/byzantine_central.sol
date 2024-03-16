// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
import "./auction.sol";
import "./stratmod.sol";

contract ByzantineFinance is Ownable {
    AuctionContract public auction;
    StrategyModule public strategyModule;

    uint8 dvtClusterSize = 4;

    enum stratModStatus {
        inactive,
        activating,
        active,
        exiting
    }

    struct stratModDetails {
        stratModStatus status;
        address stratModOwner;
    }

    mapping(address => stratModDetails) public strategyModules;
    mapping(address => StrategyModule[]) public myStrategyModules;

    constructor() Ownable(msg.sender) {
        auction = new AuctionContract();
        console.log("Auction contract deployed at: ", address(auction));
        console.log("This contract deployed at: ", address(this));
    }

    function returnModuleStatus(address _strategyModule) public view returns(stratModStatus) {
        return(strategyModules[_strategyModule].status);
    }

    function createDedicatedModule() payable public onlyOwner {
        require(msg.value == 32 ether, "Exactly 32ETH are required. Please provide that amount.");
        address stratModOwner = msg.sender;
        strategyModule = new StrategyModule(dvtClusterSize, stratModOwner, address(auction)); // Create a new strategy module
        strategyModules[address(strategyModule)] = stratModDetails(stratModStatus.activating, stratModOwner); // Add this strategy module to our mapping to allow it to call for operators
        StrategyModule[] memory myStratMods = myStrategyModules[stratModOwner];
        myStratMods[myStratMods.length] = strategyModule;
        myStrategyModules[stratModOwner] = myStratMods;
    }

    function exitModule(StrategyModule targetModule) public {
        require(msg.sender == strategyModules[address(targetModule)].stratModOwner);
        require(strategyModules[address(targetModule)].status == stratModStatus.activating || strategyModules[address(targetModule)].status == stratModStatus.activating);
        bool success = targetModule.exitRequest();
        require(success);
    }
}