// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ByzETH is ERC20, ReentrancyGuard, Ownable {
    constructor() ERC20("Byzantine ETH", "byzETH") Ownable(msg.sender) {
        transferOwnership(_msgSender());
    }

    function depositETH() external payable nonReentrant onlyOwner {
        require(msg.value > 0, "You need to send some ether");
        _mint(msg.sender, msg.value); // 1 ETH = 1 byzETH
    }

    function withdrawETH(uint256 byzETHAmount) external nonReentrant {
        require(balanceOf(msg.sender) >= byzETHAmount, "Insufficient byzETH balance");
        uint256 ethAmount = byzETHAmount; // 1:1 Exchange
        require(address(this).balance >= ethAmount, "Insufficient ETH in contract");
        
        _burn(msg.sender, byzETHAmount);
        payable(msg.sender).transfer(ethAmount);
    }

    function withdrawContractETH(address to, uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(to).transfer(amount);
    }

    function getContractETHBalance() external view returns(uint256) {
        return address(this).balance;
    }
}