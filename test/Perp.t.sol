// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {USDCToken} from "../src/mock/USDCToken.sol";
import {WBTCToken} from "../src/mock/WBTCToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Perp} from "../src/Perp.sol";
import {MockV3Aggregator} from "../src/mock/MockV3Aggregator.sol";

contract PerpTest is Test {
    address lp = makeAddr("lp");
    address trader = makeAddr("trader");

    Pool pool;
    USDCToken usdc;
    WBTCToken wbtc;
    Perp perp;
    MockV3Aggregator oracle;

    function setUp() public {
        usdc = new USDCToken();
        wbtc = new WBTCToken();
        pool = new Pool(address(usdc));
        oracle = new MockV3Aggregator(8, 3000e8);
        perp = new Perp(address(oracle), address(pool), address(usdc));
        pool.setPerpAddress(address(perp));

        usdc.mint(lp, 10000e6);
        usdc.mint(trader, 1000e6);
    }

    function depositToPool() public {
        vm.startPrank(lp);
        usdc.approve(address(pool), 10000e6);
        pool.deposit(10000e6, lp);
        vm.stopPrank();
    }

    // function
}
