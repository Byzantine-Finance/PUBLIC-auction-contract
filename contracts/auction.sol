// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
import "./byzantine_central.sol"; // Assurez-vous que le chemin d'importation est correct

contract AuctionContract {
    uint public expectedValidatorReturn = uint256(1.2 ether) / 365;
    uint8 public maxDiscountRate = 10; // The highest possible discount rate a node op can set (in %)
    uint8 public minDuration = 30; // Minimum duration a node op has to bid for

    ByzantineFinance public owner;

    constructor() {
        owner = ByzantineFinance(msg.sender);
    }

    event NewBid(address indexed bidder, Bid bid);
    event OpJustJoined(address indexed operator);
    event OpJustLeft(address indexed operator);

    struct Bid {
        // Desired duration of activity (in days)
        uint128 durationInDays;

        // Price per validation credit. Calculated as (expected return at bid time) x (1 - discount rate)
        // NOTE: Does not factor in DVT sizes yet.
        uint256 dailyVcPrice;

        // The desired DVT cluster size
        uint8 clusterSize;

        // Especially calculated score for ranking our darling node operators
        uint256 auctionScore;
    }

    enum OperatorStatus {
        untouched, // Not a member
        inAuctionSet, // Bond given, no bid set yet
        seekingWork, // Bond given, bid set
        pendingForDvt, // In process to join DVT cluster
        activeInDvt // Hard at work earning that sweet, sweet internet money
    }

    struct OperatorDetails {
        OperatorStatus opStat;
        Bid bid;
        address assignedToStrategyModule;
        uint lastDvtKick;
    }

    mapping(address => OperatorDetails) public operatorDetails;

    function joinAuctionSet() payable external {
        require(msg.value == 1 ether, "Wrong bond value");
        operatorDetails[msg.sender].opStat = OperatorStatus.inAuctionSet;
        emit OpJustJoined(msg.sender);
    }

    function leaveAuctionSet() external {
        require(operatorDetails[msg.sender].opStat == OperatorStatus.inAuctionSet || operatorDetails[msg.sender].opStat == OperatorStatus.seekingWork, "Can't perform this action with your current status");
        if(operatorDetails[msg.sender].opStat == OperatorStatus.seekingWork) {
            (bool success, ) = msg.sender.call{value: getOperatorEscrowBalance(msg.sender)}("");
            require(success);
        }
        operatorDetails[msg.sender].opStat = OperatorStatus.untouched;
        emit OpJustLeft(msg.sender);
    }

    function setBid(uint128 duration, uint discountRate/*, uint8 clusterSize*/) payable external {

        // Make sure that the parameters are nice and good
        require(duration >= minDuration, "Duration too short");
        require(discountRate >= 0 && discountRate <= maxDiscountRate, "That's a weird discount rate.");

        // Put expected return into memory because we call it a few times
        uint256 expectedReturn = expectedValidatorReturn;

        // Calculate what the bid should be and then make sure that exactly this amount was received
        uint8 clusterSize = 1; // This one needs to be updated later
        uint256 dailyVcPrice = expectedReturn * (1 - discountRate);

        if (operatorDetails[msg.sender].opStat == OperatorStatus.seekingWork) {
            
            // Do something for someone that already has a bid set.
            uint oldPrice = calculateBidPrice(operatorDetails[msg.sender].bid.durationInDays, operatorDetails[msg.sender].bid.dailyVcPrice, operatorDetails[msg.sender].bid.clusterSize);
            int priceToPay = int(calculateBidPrice(duration, dailyVcPrice, clusterSize) - oldPrice);

            if(priceToPay > 0) {
                // They pay us
                require(msg.value == calculateBidPrice(duration, dailyVcPrice, clusterSize), "That is not the right payment amount.");
            } else {
                // We pay them
                (bool success, ) = msg.sender.call{value: uint(-priceToPay)}("");
                require(success, "Payment failed!");
            }
            // If all goes well, then we note down the bid of the operators
            Bid memory myBid = Bid(duration, dailyVcPrice, clusterSize, calculateAuctionScore(duration, dailyVcPrice, clusterSize));
            operatorDetails[msg.sender].bid = myBid;
            emit NewBid(msg.sender, myBid);

        } else if (operatorDetails[msg.sender].opStat == OperatorStatus.inAuctionSet) {

            // Do something for someone that has no bid yet.
            require(msg.value == calculateBidPrice(duration, dailyVcPrice, clusterSize), "That is not the right payment amount.");

            // If all goes well, then we note down the bid of the operators
            Bid memory myBid = Bid(duration, dailyVcPrice, clusterSize, calculateAuctionScore(duration, dailyVcPrice, clusterSize));
            operatorDetails[msg.sender].opStat = OperatorStatus.seekingWork;
            operatorDetails[msg.sender].bid = myBid;
            emit NewBid(msg.sender, myBid);

        } else {
            revert();
        }
    }

    function getOperatorDetails(address operator) public view returns(OperatorDetails memory) {
        return(operatorDetails[operator]);
    }

    function getMyStatus() public view returns(OperatorStatus) {
        return(operatorDetails[msg.sender].opStat);
    }

    function getOperatorEscrowBalance(address operator) public view returns(uint) {
        Bid memory operatorBid = operatorDetails[operator].bid;
        return(calculateBidPrice(operatorBid.durationInDays, operatorBid.dailyVcPrice, operatorBid.clusterSize));
    }

    function calculateBidPrice(uint duration, uint dailyVcPrice, uint8 clusterSize) internal pure returns(uint) {
        return(duration * dailyVcPrice / clusterSize);
    }
    
    function calculateAuctionScore(uint duration, uint dailyVcPrice, uint8 clusterSize) internal pure returns(uint) {
        return(duration * dailyVcPrice / clusterSize * ((1001^duration) / (1000^duration)));
    }

    function requestOperators(uint numberOfOps) public onlyStrategyModule() returns(address[] memory operators) {
        address[] memory operatorsToReturn = new address[](numberOfOps);
/*
- requestOperators
    - Rank operators
    - Do NOT slot in ops marked as "recently inactive" (we have the "lastDvtKick" property for that
        */


        for(uint i = 0; i <= operatorsToReturn.length; i++) {
            require(operatorDetails[operatorsToReturn[i]].opStat == OperatorStatus.seekingWork);
            operatorDetails[operatorsToReturn[i]].assignedToStrategyModule = msg.sender;
            operatorDetails[operatorsToReturn[i]].opStat = OperatorStatus.pendingForDvt;
        }

        return(operatorsToReturn);
    }



    function failedToSign(address offendingOperator) onlyStrategyModule() onlyParentStrategyModule(offendingOperator) public {
        // A function that gets called whenever some operator was selected for a DVT cluster but did not sign

        operatorDetails[offendingOperator].lastDvtKick = block.timestamp;
        (bool success, ) = offendingOperator.call{value: getOperatorEscrowBalance(offendingOperator)}("");
        require(success);
        operatorDetails[offendingOperator].opStat = OperatorStatus.inAuctionSet;
        operatorDetails[offendingOperator].bid = Bid(0, 0, 0, 0);
    }

    function processOperatorBids(address[] calldata operators) onlyStrategyModule() external view {
        for(uint i = 0; i <= operators.length; i++) {
            processOperatorBid(operators[i]);
        }
    }

    function processOperatorBid(address operator) onlyParentStrategyModule(operator) private view {
    /*
- processOperatorBids
    - If release:
        - Send money to vault and extract our fees
        - Set operator as "active"
        - Delete operator bid
    - If return:
        - Send money back to operators
        - Deactivate operator bid and mark operator as "recently inactive"
        */
    }

    error BadPermissions();

    modifier onlyStrategyModule() {
        require(owner.strategyModules(msg.sender) == true);
        _;
    }

    modifier onlyParentStrategyModule(address operator) {
        require(operatorDetails[operator].assignedToStrategyModule == msg.sender, "You're not allowed to do that. Naughty naught.");
        _;
    }
}

/*

- Rank node operators in a useful way
- Process node operator payment
- Handle payment regularisation
    - 
- Gas optimisation

*/