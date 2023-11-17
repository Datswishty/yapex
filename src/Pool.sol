// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract Pool is ERC4626 {
    constructor(address usdc)
        ERC4626(IERC20(usdc))
        ERC20("Yet Another Perp eXchange Liquidity Provider Token", "YALP")
    {}
}
