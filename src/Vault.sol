// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract Vault is ERC4626 {
    constructor(
        address _mainLpTokenAddress
    )
        ERC4626(IERC20(_mainLpTokenAddress))
        ERC20("Yet Another Perp eXchange Liquidity Provider Token", "YALP")
    {}
}
