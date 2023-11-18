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
    uint constant DEPOSIT_AMT = 1000000e6; // 1M USDC
    uint constant COLLATERAL_AMT = 1000e6; // 1000

    Pool pool;
    USDCToken usdc;
    WBTCToken wbtc;
    Perp perp;
    MockV3Aggregator oracle;

    function setUp() public {
        usdc = new USDCToken();
        wbtc = new WBTCToken();
        pool = new Pool(address(usdc));
        oracle = new MockV3Aggregator(8, 20000e8);
        perp = new Perp(address(oracle), address(pool), address(usdc));
        pool.setPerpAddress(address(perp));

        usdc.mint(lp, DEPOSIT_AMT);
        usdc.mint(trader, 100000e6);
    }

    function depositToPool() public {
        usdc.approve(address(pool), DEPOSIT_AMT);
        pool.deposit(DEPOSIT_AMT, lp);
    }

    /* ------------------------------- CONSTRUCTOR ------------------------------ */

    function test_constructor() public {
        assertEq(perp.pool(), address(pool));
        assertEq(perp.liquidityToken(), address(usdc));
        assertEq(perp.openInterestLongBtc(), 0);
        assertEq(perp.openInterestShortBtc(), 0);
        assertEq(perp.totalCollateral(), 0);
        assertEq(perp.getCurrentTotalPnl(), 0);
        assertEq(perp.getPoolUsableBalance(), 0);
    }

    /* ------------------------------- POOL TESTS ------------------------------- */
    function test_depositInPool() public {
        vm.startPrank(lp);
        depositToPool();
        assertEq(usdc.balanceOf(address(pool)), DEPOSIT_AMT);
        assertEq(usdc.balanceOf(address(perp)), 0);
        assertEq(pool.balanceOf(lp), DEPOSIT_AMT);
        vm.stopPrank();
    }

    function test_withdrawFromPoolFailWhenWithdrawMoreThan80Percent() public {
        vm.startPrank(lp);
        depositToPool();
        vm.stopPrank();

        vm.startPrank(lp);
        vm.expectRevert(Pool.NotEnoughLiqudityInPool.selector);
        pool.withdraw(DEPOSIT_AMT, lp, lp);

        vm.stopPrank();
    }

    function test_withdrawFromPool() public {
        vm.startPrank(lp);
        depositToPool();
        vm.stopPrank();

        vm.startPrank(lp);
        pool.withdraw(800000e6, lp, lp); // 80% of 1M
        assertEq(usdc.balanceOf(address(pool)), 200000e6); // 20% of 1M
        assertEq(usdc.balanceOf(address(lp)), 800000e6); // 80% of 1M
        assertEq(usdc.balanceOf(address(perp)), 0);
        assertEq(pool.balanceOf(lp), 200000e6); // 20% of 1M
        vm.stopPrank();
    }

    function test_totalAssetWhenPnlIsZero() public {
        vm.startPrank(lp);
        depositToPool();
        vm.stopPrank();

        vm.startPrank(lp);
        assertEq(pool.totalAssets(), DEPOSIT_AMT);
        vm.stopPrank();
    }

    /* ------------------------------- PERP TESTS ------------------------------- */
    function test_openPositionFailWhenCollateralIsZero() public {
        vm.startPrank(lp);
        depositToPool();
        vm.stopPrank();

        vm.startPrank(trader);
        usdc.approve(address(perp), COLLATERAL_AMT);
        vm.expectRevert(Perp.InvalidPosition.selector);
        perp.openPosition(0, 1e8, true);
        vm.stopPrank();
    }

    function test_openPosition() public {
        vm.startPrank(lp);
        depositToPool();
        vm.stopPrank();

        vm.startPrank(trader);
        usdc.approve(address(perp), COLLATERAL_AMT);
        bytes32 key = perp.openPosition(COLLATERAL_AMT, 1e8, true); // 1 btc = $ 20000 so leverage will be = 20000/1000 = 20(max)
        assertEq(usdc.balanceOf(address(perp)), COLLATERAL_AMT);
        assertEq(perp.openInterestLongBtc(), 1e8);
        assertEq(perp.openInterestLongUsd(), 20000e6);
        assertEq(perp.openInterestShortBtc(), 0);
        assertEq(perp.totalCollateral(), COLLATERAL_AMT);
        assertEq(perp.getCurrentTotalPnl(), 0);

        (
            address owner,
            uint256 size,
            uint256 collateral,
            int256 pnl,
            bool isLong,
            uint256 lastIncreasedTime
        ) = perp.positions(key);

        assertEq(owner, trader);
        assertEq(size, 1e8);
        assertEq(collateral, COLLATERAL_AMT);
        assertEq(pnl, 0);
        assertEq(isLong, true);
        assertEq(lastIncreasedTime, block.timestamp);
        vm.stopPrank();
    }

    function test_openPositionFailIfLeverageIsMoreThan20() public {
        vm.startPrank(lp);
        depositToPool();
        vm.stopPrank();

        vm.startPrank(trader);
        usdc.approve(address(perp), COLLATERAL_AMT);
        vm.expectRevert(Perp.InvalidPosition.selector);
        perp.openPosition(COLLATERAL_AMT, 2e8, true); // 1 btc = $ 20000 so leverage will be = 20000/1000 = 20(max)
        vm.stopPrank();
    }

    function test_openPositioFailWhenPoolDoesNotHaveEnoughLiquidity() public {
        vm.startPrank(lp);
        depositToPool();
        vm.stopPrank();

        vm.startPrank(trader);
        usdc.approve(address(perp), 100000e6);
        vm.expectRevert(Perp.NotEnoughLiqudityInPool.selector);
        perp.openPosition(100000e6, 41e8, true); // 100k usdc collateral and 41 btc($820k) size, 1m in pool
        vm.stopPrank();
    }
}
