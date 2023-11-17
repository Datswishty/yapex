// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WBTCToken is ERC20 {
    constructor() ERC20("Fake WBTC Coin", "WBTC") {
        _mint(msg.sender, 1000000e8);
    }

    function decimals() public pure override returns (uint8) {
        return 8; // Like in real BTC coin
    }
}
