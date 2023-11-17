// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "./interfaces/AggregatorV3Interface.sol";
import "./Vault.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
// - 4. Traders cannot utilize more than a configured percentage of the deposited liquidity [ ]
// - 5. Traders can increase the size of a perpetual position [ ]
// - 6. Traders can increase the collateral of a perpetual position [ ]
// - 7. Liquidity providers cannot withdraw liquidity that is reserved for positions [ ]

struct Position {
    address owner;
    uint256 size;
    uint256 collateral;
    int256 realisedPnl;
    bool isLong;
    uint256 lastIncreasedTime;
}

/// @title Yet Another Perpetual eXchange :)
/// @author https://github.com/Datswishty
/// @notice This is implementation of Mission 1 from https://guardianaudits.notion.site/Mission-1-Perpetuals-028ca44faa264d679d6789d5461cfb13
contract Perp {
    using SafeERC20 for IERC20;
    AggregatorV3Interface internal BTCPriceFeed;
    Vault internal vault;
    IERC20 internal mainLiquidityToken;
    uint internal constant maxLeverage = 20;
    uint internal constant maxReservPercentage = 10;
    uint internal constant maxReservUtilizationPercentage = 80;
    int public openInterest;
    uint public openInterestBTC;

    // positions tracks all open positions
    mapping(bytes32 => Position) public positions;

    constructor(
        address _BTCPriceFeed,
        address _yalpTokenAddress,
        address _mainLiquidityToken
    ) {
        BTCPriceFeed = AggregatorV3Interface(_BTCPriceFeed);
        vault = Vault(_yalpTokenAddress);
        mainLiquidityToken = IERC20(_mainLiquidityToken);
    }

    function depositLiquidity(uint amount) external {
        mainLiquidityToken.safeTransferFrom(msg.sender, address(this), amount);
        vault.deposit(amount, msg.sender);
    }

    function withdrawLiquidity(uint amount) external {
        // add check if liquidity is used in open position -> can't withdraw
        vault.withdraw(amount, msg.sender, msg.sender);
    }

    function openPosition(uint collateral, uint size, bool isLong) external {
        require(collateral > 0 && size > 0, "Invalid inputs");
        // check that we are not exceding max leverage
        // check do we have enought liquidity for position

        //vault.deposit();
        bytes32 positionKey = getPositionKey(msg.sender, isLong);

        positions[positionKey] = Position(
            msg.sender,
            size,
            collateral,
            0,
            isLong,
            block.timestamp
        );
        adjustOpenInterest(size);
    }

    function increaseCollateral(
        bytes32 positionId
    ) external onlyPositionOwner(positionId) {} // add modifier onlyPositionOwner

    function increasePositionSize(
        bytes32 positionId
    ) external onlyPositionOwner(positionId) {} // add modifier onlyPositionOwner

    // This one kinda "stollen" from gmx, but adjusted since we have only one index token
    // I think in v2 we would need to have more asses so function would be adjusted accordingly
    function getPositionKey(
        address _account,
        bool _isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _isLong));
    }

    function getBTCPrice() internal view returns (int) {
        (, int BTCPrice, , , ) = BTCPriceFeed.latestRoundData(); // I tried to make this one liner but wasn't able to do so :(
        return BTCPrice;
    }

    function adjustOpenInterest(uint size) internal {
        openInterest += int(size) * getBTCPrice();
        openInterestBTC += size;
    }

    function isPositionHealthy(bytes32 positionKey) internal {}

    modifier onlyPositionOwner(bytes32 positionKey) {
        require(positions[positionKey].owner == msg.sender, "Forbidden");
        _;
    }
}
