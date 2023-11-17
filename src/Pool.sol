// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IPerp {
    function checkLiquidity() external view returns (uint256);
}

error NotSupported();
error NotEnoughLiqudityInPool();

contract Pool is ERC4626, Ownable {
    address perp;

    constructor(address usdc)
        ERC4626(IERC20(usdc))
        ERC20("Yet Another Perp eXchange Liquidity Provider Token", "YALP")
        Ownable(msg.sender)
    {}

    /**
     * @dev LPs cannot withdraw liquidity if it is being used in a position
     */
    function withdraw(uint256 assets, address receiver, address owner) public override(ERC4626) returns (uint256) {
        uint256 idleLiquidity = IPerp(perp).checkLiquidity();

        if (idleLiquidity < assets) {
            revert NotEnoughLiqudityInPool();
        }
        uint256 shares = super.withdraw(assets, receiver, owner);
        return shares;
    }

    function redeem(uint256, address, address) public pure override(ERC4626) returns (uint256) {
        revert NotSupported();
    }

    function setPerpAddress(address _perp) public onlyOwner {
        perp = _perp;
    }
}
