// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
import "./byzantine_central.sol"; // Assurez-vous que le chemin d'importation est correct

contract AuctionContract {
    uint constant PERCENTAGE_SCALING_FACTOR = 10^18;
    uint public expectedValidatorReturn; // In ETH
    uint public maxDiscountRate; // The highest possible discount rate a node op can set (in %)
    uint public minDuration; // Minimum duration a node op has to bid for

    ByzantineFinance public owner;

    constructor() {
        owner = ByzantineFinance(msg.sender);
        expectedValidatorReturn = uint256(32 ether) * 37 / 1000 / 365;
        maxDiscountRate = 15 * PERCENTAGE_SCALING_FACTOR;
        minDuration = 30;
    }

    function updateMaxDiscount(uint8 newMaxDiscount) public {
        maxDiscountRate = newMaxDiscount * PERCENTAGE_SCALING_FACTOR;
    }

    function updateExpectedReturn(uint256 aprUpscaledPercentage) public {
        // APR % times 1000 - so 3.5% would be 3500
        require(aprUpscaledPercentage <= 100 * PERCENTAGE_SCALING_FACTOR);
        expectedValidatorReturn = uint256(32 ether) * aprUpscaledPercentage / (100 * PERCENTAGE_SCALING_FACTOR) / 365;
    }

    function updateMinDuration(uint8 newMinDuration) public {
        minDuration = newMinDuration;
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
        inProtocol, // Bond given, no bid set yet
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

    struct AuctionSetMember {
        address operator;
        uint auctionScore;
    }



/********************************************************************/
/********   ALL ABOUT THE AUCTION SET (JOIN, UPDATE, LEAVE  *********/
/********************************************************************/

    AuctionSetMember[] public auctionSet; // Bear in mind that this array maintains sorting throughout!

    function addToAuctionSet(address operator, uint auctionScore) internal {
        require(operatorDetails[msg.sender].opStat == OperatorStatus.inProtocol, "Can't do that right now.");

        uint targetPosition = 0;
        for(uint i = auctionSet.length - 1; i >= 0; i--) {
            if(auctionSet[i].auctionScore <= auctionScore) {
                targetPosition = i;
                auctionSet[i + 1] = auctionSet[i];
            } else {
                break;
            }
        }

        auctionSet[targetPosition] = AuctionSetMember(operator, auctionScore);

    }

    function updateAuctionSet(address operator, uint newAuctionScore) internal {
        require(operatorDetails[msg.sender].opStat == OperatorStatus.seekingWork, "Can't do that right now.");

        uint targetPosition = 0;
        uint currentPosition = 0;
        for(uint i = auctionSet.length - 1; i >= 0; i--) {
            if(auctionSet[i].auctionScore <= newAuctionScore) {
                targetPosition = i;
                auctionSet[i + 1] = auctionSet[i];
            }

            if(auctionSet[i].operator == operator) {
                currentPosition = i;
            }
        }

        if (targetPosition > currentPosition) {
            for(uint i = currentPosition + 1; i <= targetPosition; i++) {
                auctionSet[i - 1] = auctionSet[i];
            }
        } else if (targetPosition < currentPosition) {
            for(uint i = currentPosition - 1; i >= targetPosition; i--) {
                auctionSet[i + 1] = auctionSet[i];
            }
        }

        auctionSet[targetPosition] = AuctionSetMember(operator, newAuctionScore);

    }

    function removeBySwapping(uint[] storage array, uint index) internal {
        require(index < array.length, "Index out of bounds");
        array[index] = array[array.length - 1];
        array.pop(); // Remove the last element
    }

    function removeFromAuctionSet(address operator) internal {
        operatorDetails[operator].opStat = OperatorStatus.inProtocol;
        operatorDetails[operator].bid = Bid(0, 0, 0, 0);

        for(uint i = 0; i <= auctionSet.length; i++) {
            if(auctionSet[i].operator == operator) {
                auctionSet[i] = auctionSet[auctionSet.length - 1];
                auctionSet.pop();
                break;
            }
        }
    }



/********************************************************************/
/******************   JOIN AND EXIT PROTOCOL  ***********************/
/********************************************************************/

    function joinProtocol() payable external {
        require(msg.value == 1 ether, "Wrong bond value, must be 1ETH.");
        operatorDetails[msg.sender].opStat = OperatorStatus.inProtocol;
        emit OpJustJoined(msg.sender);
    }

    function leaveProtocol() external {
        require(operatorDetails[msg.sender].opStat == OperatorStatus.inProtocol || operatorDetails[msg.sender].opStat == OperatorStatus.seekingWork, "Can't perform this action with your current status");
        if(operatorDetails[msg.sender].opStat == OperatorStatus.seekingWork) {
            (bool success, ) = msg.sender.call{value: getOperatorEscrowBalance(msg.sender)}("");
            require(success);
            removeFromAuctionSet(msg.sender);
        }
        operatorDetails[msg.sender].opStat = OperatorStatus.untouched;
        emit OpJustLeft(msg.sender);
    }



/********************************************************************/
/********************   MAKING OR UPDATING A BID  *******************/
/********************************************************************/

    function setBid(uint128 duration, uint discountRate/*, uint8 clusterSize*/) payable external {

        // Make sure that the parameters are nice and good
        require(duration >= minDuration, "Duration too short");
        require(discountRate >= 0 && discountRate <= maxDiscountRate, "That's a weird discount rate.");

        // Put expected return into memory because we call it a few times
        uint256 expectedReturn = expectedValidatorReturn;

        // Calculate what the bid should be and then make sure that exactly this amount was received
        uint8 clusterSize = 1; // This one needs to be updated later
        uint256 dailyVcPrice = expectedReturn * (1 - discountRate / PERCENTAGE_SCALING_FACTOR);

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
            uint auctionScore = calculateAuctionScore(duration, dailyVcPrice, clusterSize);
            Bid memory myBid = Bid(duration, dailyVcPrice, clusterSize, auctionScore);
            operatorDetails[msg.sender].bid = myBid;
            updateAuctionSet(msg.sender, auctionScore);
            emit NewBid(msg.sender, myBid);

        } else if (operatorDetails[msg.sender].opStat == OperatorStatus.inProtocol) {

            // Do something for someone that has no bid yet.
            require(msg.value == calculateBidPrice(duration, dailyVcPrice, clusterSize), "That is not the right payment amount.");

            // If all goes well, then we note down the bid of the operators
            uint auctionScore = calculateAuctionScore(duration, dailyVcPrice, clusterSize);
            Bid memory myBid = Bid(duration, dailyVcPrice, clusterSize, auctionScore);
            operatorDetails[msg.sender].opStat = OperatorStatus.seekingWork;
            operatorDetails[msg.sender].bid = myBid;
            addToAuctionSet(msg.sender, auctionScore);
            emit NewBid(msg.sender, myBid);

        } else {
            revert();
        }
    }



/********************************************************************/
/**********   CUSTOM GETTER FUNCTIONS  ******************************/
/********************************************************************/

    function getOperatorDetails(address operator) public view returns(OperatorDetails memory) {
        return(operatorDetails[operator]);
    }

    function getStatus(address operator) public view returns(OperatorStatus) {
        return(operatorDetails[operator].opStat);
    }

    function getOperatorEscrowBalance(address operator) public view returns(uint) {
        Bid memory operatorBid = operatorDetails[operator].bid;
        return(calculateBidPrice(operatorBid.durationInDays, operatorBid.dailyVcPrice, operatorBid.clusterSize));
    }



/********************************************************************/
/**********   INTERNAL ADMIN FUNCTIONS (FOR CONSISTENCY)  ***********/
/********************************************************************/

    function calculateBidPrice(uint duration, uint dailyVcPrice, uint8 clusterSize) internal pure returns(uint) {
        return(duration * dailyVcPrice / clusterSize);
    }
    
    function calculateAuctionScore(uint duration, uint dailyVcPrice, uint8 clusterSize) internal pure returns(uint) {
        return(duration * dailyVcPrice / clusterSize * ((1001^duration) / (1000^duration)));
    }



/********************************************************************/
/******************   SERVICING OPERATOR REQUESTS  ******************/
/********************************************************************/

    function requestOperators(uint numberOfOps) public onlyStrategyModule() returns(address[] memory operators) {
        address[] memory operatorsToReturn;

        /*
        TO ADD:
        - Do NOT slot in ops marked as "recently inactive" (we have the "lastDvtKick" property for that
        */

        for(uint i = 0; i <= numberOfOps; i++) {
            address operator = auctionSet[i].operator;
            if(operatorsToReturn.length < numberOfOps) {
                if (operatorDetails[operator].opStat == OperatorStatus.seekingWork) {
                    operatorsToReturn[operatorsToReturn.length + 1] = operator;
                    operatorDetails[operator].assignedToStrategyModule = msg.sender;
                    operatorDetails[operator].opStat = OperatorStatus.pendingForDvt;
                }
            } else {
                break;
            }
        }

        if(operatorsToReturn.length < numberOfOps) {
            revert("Not enough operators in auction set!");
        } else {
            return(operatorsToReturn);
        }
    }

    function releaseOperators(address[] memory operators) public onlyStrategyModule() {
        for(uint i = 0; i <= operators.length; i++) {
            operatorDetails[operators[i]].assignedToStrategyModule = address(0);
            operatorDetails[operators[i]].opStat = OperatorStatus.inProtocol;
        }
    }

    function failedToSign(address offendingOperator) onlyStrategyModule() onlyParentStrategyModule(offendingOperator) public {
        // A function that gets called whenever some operator was selected for a DVT cluster but did not sign

        operatorDetails[offendingOperator].lastDvtKick = block.timestamp;
        (bool success, ) = offendingOperator.call{value: getOperatorEscrowBalance(offendingOperator)}("");
        require(success);
        removeFromAuctionSet(msg.sender);
    }



/********************************************************************/
/******************   DEALING WITH OPERATOR BIDS  *******************/
/********************************************************************/

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



/********************************************************************/
/***********************   MODIFIERS  *******************************/
/********************************************************************/

    modifier onlyStrategyModule() {
        require(owner.returnModuleStatus(msg.sender) != ByzantineFinance.stratModStatus.inactive);
        _;
    }

    modifier onlyOwner() {
        require(address(owner) == msg.sender);
        _;
    }

    modifier onlyParentStrategyModule(address operator) {
        require(operatorDetails[operator].assignedToStrategyModule == msg.sender, "You're not allowed to do that. Naughty naught.");
        _;
    }
}

/*

- Process node operator payment
    - Where does the money go?
- Handle payment regularisation
    - 
- Gas optimisation

*/