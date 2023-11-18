// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract USDCToken is ERC20, Ownable {
    constructor() ERC20("Fake USD Coin", "USDC") Ownable(msg.sender) {
        _mint(msg.sender, 1000000e6);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6; // Like in real USDC coin
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
