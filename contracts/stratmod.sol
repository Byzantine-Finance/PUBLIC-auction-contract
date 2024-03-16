// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./auction.sol";

contract StrategyModule {
    address payable owner;
    address byzHQ;
    AuctionContract public auctionContract;

    uint8 dvtClusterSize;

    address[] public operatorSet;

    constructor(uint8 _dvtClusterSize, address _stratModOwner, address _auctionContract) {
        owner = payable(_stratModOwner);
        byzHQ = msg.sender;
        auctionContract = AuctionContract(_auctionContract);

        dvtClusterSize = _dvtClusterSize;

        operatorSet = new address[](_dvtClusterSize);

        auctionContract.requestOperators(dvtClusterSize);

    }

    function releaseOperators() private {
        auctionContract.releaseOperators(operatorSet);
        for(uint i = 0; i <= 0; i++) {
            operatorSet[i] = address(0);
        }
    }

    function exitRequest() public onlyHQorOwner returns(bool success) {
        // Exit DVT, close down everything, etc.
        // Will get a lot more complicated as soon as things get spicy

        releaseOperators();
        (bool exitSuccess, ) = owner.call{ value: address(this).balance }("");

        return(exitSuccess);
    }

    modifier onlyHQorOwner() {
        require(msg.sender == owner || msg.sender == byzHQ);
        _;
    }
}