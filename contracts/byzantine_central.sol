// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
import "./auction.sol";
import "./stratmod.sol";
import "./byzETH.sol";

contract ByzantineFinance is Ownable {
    AuctionContract public auction;
    StrategyModule public strategyModule;
    ByzETH public byzETH;

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
        byzETH = new ByzETH();
        console.log("Auction contract deployed at: ", address(auction));
        console.log("This contract deployed at: ", address(this));
    }

    // LIQUID STAKERS & BYZETH

    function depositEthForByzEth() payable external {
        require(msg.value > 0, "You need to send some ether");
        byzETH.mintByzEth(msg.value, msg.sender);
    }

    function withdrawthForByzEth(uint amountToWithdraw) external {
        require(byzETH.balanceOf(msg.sender) >= amountToWithdraw, "Insufficient byzETH balance");
        uint256 ethAmount = amountToWithdraw; // 1:1 Exchange
        require(address(this).balance >= ethAmount, "Insufficient ETH liquidity in contract");
        
        bool success = byzETH.burnByzEth(amountToWithdraw, msg.sender);
        require(success);
        payable(msg.sender).transfer(ethAmount);
    }


    // FULL STAKERS

    function createDedicatedModule() payable public onlyOwner {
        require(msg.value == 32 ether, "Exactly 32ETH are required. Please provide that amount.");
        address stratModOwner = msg.sender;
        createStratModule(stratModOwner, dvtClusterSize, address(auction));
    }


    // STRATEGY MODULE SETUP

    function createStratModule(address stratModOwner, uint8 _dvtClusterSize, address _auctionContract) public {
        strategyModule = new StrategyModule(_dvtClusterSize, stratModOwner, _auctionContract); // Create a new strategy module
        strategyModules[address(strategyModule)] = stratModDetails(stratModStatus.activating, stratModOwner); // Add this strategy module to our mapping to allow it to call for operators
        StrategyModule[] memory myStratMods = myStrategyModules[stratModOwner];
        myStratMods[myStratMods.length] = strategyModule;
        myStrategyModules[stratModOwner] = myStratMods;
    }

    function returnModuleStatus(address _strategyModule) public view returns(stratModStatus) {
        return(strategyModules[_strategyModule].status);
    }

    function exitStratModule(StrategyModule targetModule) public {
        require(msg.sender == strategyModules[address(targetModule)].stratModOwner);
        require(strategyModules[address(targetModule)].status == stratModStatus.activating || strategyModules[address(targetModule)].status == stratModStatus.activating);
        bool success = targetModule.exitRequest();
        require(success);
    }
}