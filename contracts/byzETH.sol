// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ByzETH is ERC20, ReentrancyGuard, Ownable {
    constructor() ERC20("Byzantine ETH", "byzETH") Ownable(msg.sender) {
        transferOwnership(_msgSender());
    }

    function mintByzEth(uint amount, address _to) external nonReentrant onlyOwner {

        // Gets called when a liquid staker sent money to the vault

        require(amount > 0, "You need to send some ether");
        _mint(_to, amount); // 1 ETH = 1 byzETH
    }

    function burnByzEth(uint amount, address _to) external nonReentrant onlyOwner returns(bool) {

        // Gets called after someone withdrew ETH from the vault
        _burn(_to, amount);
        return(true);
    }

    function withdrawContractETH(address to, uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(to).transfer(amount);
    }
}