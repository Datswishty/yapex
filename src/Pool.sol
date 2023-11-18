// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Perp} from "./Perp.sol";
import {console2} from "forge-std/Test.sol";

contract Pool is ERC4626, Ownable {
    error NotEnoughLiqudityInPool();
    error NotSupported();

    address perp;

    constructor(
        address usdc
    )
        ERC4626(IERC20(usdc))
        ERC20("Yet Another Perp eXchange Liquidity Provider Token", "YALP")
        Ownable(msg.sender)
    {}

    /**
     * @dev LPs cannot withdraw liquidity if it is being used in a position
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override(ERC4626) returns (uint256) {
        uint256 idleLiquidity = Perp(perp).getPoolUsableBalance();
        if (idleLiquidity < assets) {
            revert NotEnoughLiqudityInPool();
        }
        uint256 shares = super.withdraw(assets, receiver, owner);
        return shares;
    }

    function setPerpAddress(address _perp) public onlyOwner {
        perp = _perp;
    }

    function totalAssets() public view override(ERC4626) returns (uint256) {
        int256 pnl = Perp(perp).getCurrentTotalPnl();
        if (pnl <= 0) {
            return super.totalAssets();
        }
        return super.totalAssets() - uint256(pnl);
    }

    function redeem(
        uint256,
        address,
        address
    ) public pure override(ERC4626) returns (uint256) {
        revert NotSupported();
    }
}
