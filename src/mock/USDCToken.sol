// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDCToken is ERC20 {
    constructor() ERC20("Fake USD Coin", "USDC") {
        _mint(msg.sender, 1000000e6);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6; // Like in real USDC coin
    }
}
