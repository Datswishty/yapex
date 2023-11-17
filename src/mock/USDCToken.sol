// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YALP is ERC20 {
    constructor() ERC20("Fake USD Coin", "USDC") {}

    function decimals() public view virtual override returns (uint8) {
        return 6; // Like in real USDC coin
    }
}
