// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./interfaces/AggregatorV3Interface.sol";
import "./Pool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console2} from "forge-std/Test.sol";

//                             ,-.
//        ___,---.__          /'|`\          __,---,___
//     ,-'    \`    `-.____,-'  |  `-.____,-'    //    `-.
//   ,'        |           ~'\     /`~           |        `.
//  /      ___//              `. ,'          ,  , \___      \
// |    ,-'   `-.__   _         |        ,    __,-'   `-.    |
// |   /          /\_  `   .    |    ,      _/\          \   |
// \  |           \ \`-.___ \   |   / ___,-'/ /           |  /
//  \  \           | `._   `\\  |  //'   _,' |           /  /
//   `-.\         /'  _ `---'' , . ``---' _  `\         /,-'
//      ``       /     \    ,='/ \`=.    /     \       ''
//              |__   /|\_,--.,-.--,--._/|\   __|
//              /  `./  \\`\ |  |  | /,//' \,'  \
//             /   /     ||--+--|--+-/-|     \   \
//            |   |     /'\_\_\ | /_/_/`\     |   |
//             \   \__, \_     `~'     _/ .__/   /
//              `-._,-'   `-._______,-'   `-._,-'
// GOALS
// - 1. Liquidity Providers can deposit and withdraw liquidity [✅]
// - 2. Traders can open a perpetual position for BTC, with a given size and collateral [✅]
// - 3. A way to get the realtime price of the asset being traded [✅]
// - 4. Traders cannot utilize more than a configured percentage of the deposited liquidity [✅]
// - 5. Traders can increase the size of a perpetual position [✅]
// - 6. Traders can increase the collateral of a perpetual position [✅]
// - 7. Liquidity providers cannot withdraw liquidity that is reserved for positions [✅]
// - BONUS 8. Create and emit events [ ]
struct Position {
    address owner;
    uint256 size;
    uint256 collateral;
    int256 realisedPnl; // if this value is not used then remove it
    bool isLong;
    uint256 lastIncreasedTime; // if this value is not used then remove it
}

/// @title Yet Another Perpetual eXchange :)
/// @author https://github.com/Datswishty
/// @notice This is implementation of Mission 1 from https://guardianaudits.notion.site/Mission-1-Perpetuals-028ca44faa264d679d6789d5461cfb13

contract Perp {
    using SafeERC20 for IERC20;

    AggregatorV3Interface internal btcPriceFeed;
    uint256 constant MAX_LEVERAGE = 20;
    uint256 constant MAX_RESERVE_PERCENT_BPS = 1_000;
    uint256 constant PRECISION_WBTC_USD = 1e8;
    uint256 constant PRECISION_USDC = 1e6;
    uint256 constant MAX_RESERVE_UTILIZATION_PERCENT_BPS = 8_000;
    uint256 constant PERCENTAGE_BPS = 10_000;
    IERC20 public liquidityToken; //usdc
    uint256 public openInterestLongBtc;
    uint256 public openInterestShortBtc;
    uint256 public openInterestLongUsd;
    uint256 public openInterestShortUsd;
    address public pool;

    // positions tracks all open positions
    mapping(bytes32 => Position) public positions;

    error NotEnoughLiqudityInPool();
    error InvalidPosition();
    error MaxLeverageExceeded();

    modifier onlyPositionOwner(bytes32 positionKey) {
        require(positions[positionKey].owner == msg.sender, "Forbidden");
        _;
    }

    modifier onlyHealthyPosition(bytes32 positionKey) {
        if (checkDoesNotExceedMaxLeverage(positionKey)) {
            revert MaxLeverageExceeded();
        }
        _;
    }

    /**
     * @dev constructor
     * @param _btcPriceFeed btc/usd price feed adress
     * @param _pool usdc liquidity pool address
     * @param _liquidityToken usdc address
     */
    constructor(address _btcPriceFeed, address _pool, address _liquidityToken) {
        btcPriceFeed = AggregatorV3Interface(_btcPriceFeed);
        pool = _pool;
        liquidityToken = IERC20(_liquidityToken);
    }

    /* -------------------------------- EXTERNAL -------------------------------- */
    function openPosition(
        uint256 collateral,
        uint256 size,
        bool isLong
    ) external returns (bytes32) {
        if (collateral == 0 || size == 0) revert InvalidPosition();
        // collateral will be in 6 decimal and size will be in 8 so handling maths accordingly
        uint256 price = getBTCPrice();
        //@dev if sizeInUsd < collateral. this will underflow and revert, this is intended behaviour as we don't want to allow size < collateral
        uint256 sizeInUsd = (price * size) / PRECISION_WBTC_USD;
        uint256 leverage = sizeInUsd / collateral;

        if (leverage > MAX_LEVERAGE) revert InvalidPosition();

        if (sizeInUsd > getPoolUsableBalance()) {
            revert NotEnoughLiqudityInPool();
        }

        liquidityToken.safeTransferFrom(msg.sender, address(this), collateral);
        bytes32 positionKey = getPositionKey(msg.sender, isLong);

        positions[positionKey] = Position(
            msg.sender,
            size,
            collateral,
            0,
            isLong,
            block.timestamp
        );
        adjustOpenInterest(size, isLong, sizeInUsd);
        return positionKey; // @audit do we really need this?
    }

    function increaseCollateral(
        bytes32 positionKey,
        uint256 additionalCollateral
    ) external onlyPositionOwner(positionKey) onlyHealthyPosition(positionKey) {
        Position storage p = positions[positionKey];
        p.collateral += additionalCollateral;
    }

    function increasePositionSize(
        bytes32 positionKey,
        uint256 additionalSize
    ) external onlyPositionOwner(positionKey) onlyHealthyPosition(positionKey) {
        Position storage p = positions[positionKey];
        p.size += additionalSize;

        uint256 sizeInUsd = getBTCPrice() * additionalSize;
        if (!checkDoesNotExceedMaxLeverage(positionKey)) {
            revert MaxLeverageExceeded();
        }
        if (p.isLong) {
            openInterestLongBtc += additionalSize;
            openInterestLongUsd += sizeInUsd;
        } else {
            openInterestShortBtc += additionalSize;
            openInterestShortUsd += sizeInUsd;
        }
    }

    /* -------------------------------- INTERNAL -------------------------------- */

    function adjustOpenInterest(
        uint256 size,
        bool isLong,
        uint256 sizeUsd
    ) internal {
        if (isLong) {
            openInterestLongBtc += size;
            openInterestLongUsd += sizeUsd;
        } else {
            openInterestShortBtc += size;
            openInterestShortUsd += sizeUsd;
        }
    }

    function checkDoesNotExceedMaxLeverage(
        bytes32 positionKey
    ) internal view returns (bool) {
        Position memory p = positions[positionKey];
        uint256 btcPrice = getBTCPrice();
        uint256 sizeInUsd = btcPrice * p.size;
        uint256 leverage = sizeInUsd / p.collateral;
        return leverage <= MAX_LEVERAGE;
    }

    /* --------------------------------- GETTERS -------------------------------- */

    // This one kinda "stollen" from gmx, but adjusted since we have only one index token
    // I think in v2 we would need to have more asses so function would be adjusted accordingly
    function getPositionKey(
        address _account,
        bool _isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _isLong));
    }

    function getBTCPrice() internal view returns (uint256) {
        (, int256 BTCPrice, , , ) = btcPriceFeed.latestRoundData();
        return uint256(BTCPrice);
    }

    function getPoolUsableBalance() public view returns (uint256) {
        uint256 poolBalance = liquidityToken.balanceOf(pool);
        uint256 totalOpenInterestUsd = openInterestShortUsd +
            openInterestLongBtc *
            getBTCPrice();
        uint256 maxUsableBalance = (poolBalance *
            MAX_RESERVE_UTILIZATION_PERCENT_BPS) / PERCENTAGE_BPS; // 80% of pool balance

        if (totalOpenInterestUsd < maxUsableBalance) {
            return maxUsableBalance - totalOpenInterestUsd;
        } else {
            return 0;
        }
    }

    function getCurrentTotalPnl() public view returns (int256) {
        return getCurrentPnlLongs() + getCurrentPnlShorts();
    }

    function getCurrentPnlLongs() public view returns (int256) {
        uint256 currentLongOpenInterestValue = (openInterestLongBtc /
            PRECISION_WBTC_USD) * getBTCPrice();
        return int256(currentLongOpenInterestValue - openInterestLongUsd);
    }

    function getCurrentPnlShorts() public view returns (int256) {
        uint256 currentShortOpenInterestValue = openInterestShortBtc *
            getBTCPrice();
        return int256(openInterestShortUsd - currentShortOpenInterestValue);
    }

    function getLongOpenInterestUsd() public view returns (uint256) {
        return openInterestLongBtc * getBTCPrice();
    }

    function getShortOpenInterestUsd() public view returns (uint256) {
        return openInterestShortBtc * getBTCPrice();
    }

    function getTotalOpenInterestUsd() public view returns (uint256) {
        return getLongOpenInterestUsd() + getShortOpenInterestUsd();
    }
}
