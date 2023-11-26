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
// - 8. Traders can decrease the size of their position and realize a proportional amount of their PnL [✅]
// - 9. Traders can decrease the collateral of their position [✅]
// - 10. Individual position’s can be liquidated with a liquidate function, any address may invoke the liquidate function [✅]
// - 11. A liquidatorFee is taken from the position’s remaining collateral upon liquidation with the liquidate function and given to the caller of the liquidate function [✅]
// - 12. Traders can never modify their position such that it would make the position liquidatable [✅]
// - 13. Traders are charged a borrowingFee which accrues as a function of their position size and the length of time the position is open []
// - 14. Traders are charged a positionFee from their collateral whenever they change the size of their position, the positionFee is a percentage of the position size delta (USD converted to collateral token). — Optional/Bonus []

struct Position {
    address owner;
    uint256 size;
    uint256 collateral;
    int256 realisedPnl; // if this value is not used then remove it
    bool isLong;
    uint256 averagePositionPrice;
    uint256 sizeInUsd;
    uint256 lastUpdateTime;
}

/// @title Yet Another Perpetual eXchange :)
/// @author https://github.com/Datswishty
/// @notice This is implementation of Mission 1 from https://guardianaudits.notion.site/Mission-1-Perpetuals-028ca44faa264d679d6789d5461cfb13

contract Perp {
    using SafeERC20 for IERC20;

    AggregatorV3Interface internal btcPriceFeed;
    uint256 constant MAX_LEVERAGE = 20;
    uint256 constant MAX_RESERVE_PERCENT_BPS = 1_000;
    uint256 constant PRECISION_WBTC_USD = 1e10;
    uint256 constant PRECISION_WBTC = 1e8;
    uint256 constant PRECISION_USDC = 1e6;
    uint256 constant MAX_RESERVE_UTILIZATION_PERCENT_BPS = 8_000;
    uint256 constant PERCENTAGE_BPS = 10_000;
    uint256 constant PERCENTAGE_LIQUIDATION_FEE = 5;
    uint256 constant PERCENTAGE_BORROW_FEE = 1;
    uint256 constant borrowingPerSecond = 315_360_000;
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
    error NotPositionOwner(address);
    error ZeroAmount();
    error CollateralDecreaseExceedsPositionCollateral();

    modifier onlyPositionOwner(bytes32 positionKey) {
        if (msg.sender != positions[positionKey].owner)
            revert NotPositionOwner(msg.sender);
        _;
    }

    modifier onlyHealthyPosition(bytes32 positionKey) {
        if (checkExceedMaxLeverage(positionKey)) {
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
        // 20000e6 / 1000e6 = 20
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
            price,
            sizeInUsd,
            block.timestamp
        );
        adjustOpenInterest(size, isLong, sizeInUsd);
        return positionKey; // @audit do we really need this? Yes there is no other way to get user position key
    }

    function increaseCollateral(
        bytes32 positionKey,
        uint256 additionalCollateral
    ) external onlyPositionOwner(positionKey) onlyHealthyPosition(positionKey) {
        if (additionalCollateral == 0) revert ZeroAmount();
        Position storage p = positions[positionKey];
        p.collateral += additionalCollateral;
    }

    function increasePositionSize(
        bytes32 positionKey,
        uint256 additionalSize
    ) external onlyPositionOwner(positionKey) onlyHealthyPosition(positionKey) {
        if (additionalSize == 0) revert ZeroAmount();
        uint256 sizeInUsd = (getBTCPrice() * additionalSize) /
            PRECISION_WBTC_USD;
        Position storage p = positions[positionKey];
        p.sizeInUsd += sizeInUsd;
        p.size += additionalSize;
        if (checkExceedMaxLeverage(positionKey)) {
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

    function decreasePositionCollateral(
        bytes32 positionKey,
        uint256 collateralDecrease
    ) external onlyPositionOwner(positionKey) onlyHealthyPosition(positionKey) {
        if (collateralDecrease == 0) revert ZeroAmount();
        if (collateralDecrease >= positions[positionKey].collateral)
            revert CollateralDecreaseExceedsPositionCollateral();
        Position storage p = positions[positionKey];
        p.collateral -= collateralDecrease; // @audit underflow can happen if collateralDecrease > p.collateral
        if (checkExceedMaxLeverage(positionKey)) {
            revert MaxLeverageExceeded();
        }

        liquidityToken.safeTransfer(msg.sender, collateralDecrease);
    }

    function decreasePositionSize(
        bytes32 positionKey,
        uint256 sizeDecrease
    ) external onlyPositionOwner(positionKey) {
        if (sizeDecrease == 0) revert InvalidPosition();
        //@audit sizeDelta should be calulated on positionOpen price or current price?
        uint256 sizeDeltaInUsd = (getBTCPrice() * sizeDecrease) /
            PRECISION_WBTC_USD;
        Position storage p = positions[positionKey];
        uint256 currentTotalSizeInUsd = (getBTCPrice() * p.size) /
            PRECISION_WBTC_USD;
        int totalPositionPNL = getPositionPNL(positionKey);
        p.size -= sizeDecrease; // @audit underflow can happen if sizeDecrese > p.size
        p.sizeInUsd = (getBTCPrice() * p.size) / PRECISION_WBTC_USD; //@audit not sure of this,there can be some issue.
        int realisedPNL = (totalPositionPNL * int(sizeDeltaInUsd)) /
            int(currentTotalSizeInUsd);
        if (realisedPNL > 0) {
            liquidityToken.safeTransfer(msg.sender, abs(realisedPNL));
        } else {
            p.collateral -= abs(realisedPNL);
            liquidityToken.safeTransfer(address(pool), abs(realisedPNL));
        }
    }

    function liquidatePosition(bytes32 positionKey) external {
        if (checkExceedMaxLeverage(positionKey)) {
            revert("Position is healthy");
        }
        Position storage p = positions[positionKey];
        int realisedPNL = getPositionPNL(positionKey);
        if (realisedPNL < 0 && abs(realisedPNL) > p.collateral) {
            revert("IDK what to do in that case");
        }
        uint positionBorrowFees = getPositionBorrowFees(positionKey);
        delete positions[positionKey];

        if (realisedPNL > 0) {
            uint liquidationFee = positionBorrowFees +
                (abs(realisedPNL) * PERCENTAGE_LIQUIDATION_FEE) /
                100;
            uint remainingPNL = abs(realisedPNL) - liquidationFee;
            liquidityToken.safeTransfer(msg.sender, liquidationFee);
            liquidityToken.safeTransfer(p.owner, remainingPNL);
        } else {
            uint remainingAmount = p.collateral - abs(realisedPNL);
            uint liquidationFee = positionBorrowFees +
                (remainingAmount * PERCENTAGE_LIQUIDATION_FEE) /
                100;
            uint remainingPNL = remainingAmount - liquidationFee;
            liquidityToken.safeTransfer(msg.sender, liquidationFee);
            liquidityToken.safeTransfer(p.owner, remainingPNL);
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

    function checkExceedMaxLeverage(
        bytes32 positionKey
    ) internal view returns (bool) {
        uint256 leverage = getPositionLeverage(positionKey);
        return leverage > MAX_LEVERAGE;
    }

    /* --------------------------------- GETTERS -------------------------------- */

    function getPositionBorrowFees(
        bytes32 positionKey
    ) internal view returns (uint) {
        Position memory p = positions[positionKey];
        return
            p.size *
            (block.timestamp - p.lastUpdateTime) *
            (1 / borrowingPerSecond);
    } // I dunno why we check only lastUpdateTime

    function getPositionKey(
        address _account,
        bool _isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _isLong));
    }

    function getPositionLeverage(
        bytes32 positionKey
    ) public view returns (uint256) {
        Position memory p = positions[positionKey];
        // uint price = getBTCPrice();
        // uint borrowingFees = p.size *
        //     (block.timestamp - p.lastUpdateTime) *
        //     (1 / borrowingPerSecond);

        // position leverage = debt/collateral
        int256 positionPnL = getPositionPNL(positionKey);
        uint256 leverage;
        if (positionPnL > 0) {
            leverage = p.sizeInUsd / (p.collateral + abs(positionPnL));
        } else {
            leverage = (p.sizeInUsd + abs(positionPnL)) / (p.collateral);
        }
        return leverage;
    }

    function getBTCPrice() internal view returns (uint256) {
        (, int256 answer, uint256 timestamp, , ) = btcPriceFeed
            .latestRoundData();
        // require(updatedAt >= roundID, "Stale price"); this one should be in production but tests will fail with it
        // @audit make this more robust
        require(timestamp != 0, "Round not complete");
        require(answer > 0, "Chainlink answer reporting 0");
        return uint256(answer);
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
        uint256 currentLongOpenInterestValue = (openInterestLongBtc *
            getBTCPrice()) / PRECISION_WBTC_USD;
        return int256(currentLongOpenInterestValue - openInterestLongUsd);
    }

    function getCurrentPnlShorts() public view returns (int256) {
        uint256 currentShortOpenInterestValue = (openInterestShortBtc *
            getBTCPrice()) / PRECISION_WBTC_USD;
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

    function getPositionPNL(bytes32 positionKey) public view returns (int) {
        Position storage p = positions[positionKey];
        uint256 price = getBTCPrice();
        uint256 currentPositionUsdValue = (p.size * price) / PRECISION_WBTC_USD;
        uint256 positionUsdValue = p.sizeInUsd;

        if (p.isLong) {
            int256 pnl = int256(currentPositionUsdValue) -
                int256(positionUsdValue);
            return pnl;
            // return int(price - p.averagePositionPrice) * int(p.size);
        } else {
            int256 pnl = int256(positionUsdValue) -
                int256(currentPositionUsdValue);
            return pnl;
            // return int(p.averagePositionPrice - price) * int(p.size);
        }
    }

    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }
}
