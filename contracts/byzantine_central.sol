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
    uint liquidityRequirement = 10; // Liquidity reserve that should be kept
    uint newModuleCounter;
    uint liquidityCounter;

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
        newModuleCounter += msg.value;
        createPoolModule();
    }

    function withdrawthForByzEth(uint amountToWithdraw) external {
        require(byzETH.balanceOf(msg.sender) >= amountToWithdraw, "Insufficient byzETH balance");
        uint256 ethAmount = amountToWithdraw; // 1:1 Exchange
        require(address(this).balance >= ethAmount, "Insufficient ETH liquidity in contract");
        
        if(newModuleCounter >= amountToWithdraw) {
            newModuleCounter -= amountToWithdraw;
        } else if (newModuleCounter + liquidityCounter >= amountToWithdraw) {
            liquidityCounter -= amountToWithdraw - newModuleCounter;
            newModuleCounter = 0;
        } else {
            revert("Withdrawals are currently paused.");
        }

        bool success = byzETH.burnByzEth(amountToWithdraw, msg.sender);
        require(success);
        payable(msg.sender).transfer(ethAmount);

    }

    function getContractETHBalance() external view returns(uint256) {
        return address(this).balance;
    }

    function createPoolModule() private {
        if(newModuleCounter >= 32 ether * liquidityRequirement / 100) {
            createStratModule(address(this), dvtClusterSize, address(auction));
            liquidityCounter += (newModuleCounter - 32 ether);
            newModuleCounter = 0;
            
        }
    }


    // FULL STAKERS

    function createDedicatedModule() payable public {
        require(msg.value == 32 ether, "Exactly 32ETH are required. Please provide that amount.");
        console.log("a special cluster for a special boy");
        address stratModOwner = msg.sender;
        address myNewModule = createStratModule(stratModOwner, dvtClusterSize, address(auction));
        console.log(myNewModule);
    }


    // STRATEGY MODULE SETUP

    function createStratModule(address stratModOwner, uint8 _dvtClusterSize, address _auctionContract) public returns(address) {
        console.log("time to create");
        
        // Create strategy module
        strategyModule = (new StrategyModule){value: 32 ether}(_dvtClusterSize, stratModOwner, _auctionContract); // Create a new strategy module
        console.log("completed stratmod");

        // Update strat mod status
        strategyModules[address(strategyModule)] = stratModDetails(stratModStatus.activating, stratModOwner);
        
        console.log("a special cluster for a special boy");
        // Tell strat mod to go get operators
        strategyModule.seekOperators();

        // Add strat mod to owner's portfolio
        StrategyModule[] storage myStratMods = myStrategyModules[stratModOwner];
        myStratMods.push(strategyModule);
        myStrategyModules[stratModOwner] = myStratMods;
        return(address(strategyModule));
    }

    function returnModuleStatus(address _strategyModule) public view returns(stratModStatus) {
        return(strategyModules[_strategyModule].status);
    }

    function exitStratModule(StrategyModule targetModule) public {
        require(msg.sender == strategyModules[address(targetModule)].stratModOwner, "You're not allowed to do that!");
        require(strategyModules[address(targetModule)].status == stratModStatus.activating || strategyModules[address(targetModule)].status == stratModStatus.active, "That request can't be acted on.");
        console.log("1");
        bool success = targetModule.exitRequest();
        require(success);
    }
}