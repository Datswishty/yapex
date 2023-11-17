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
// - 4. Traders cannot utilize more than a configured percentage of the deposited liquidity [✅]
// - 5. Traders can increase the size of a perpetual position [✅]
// - 6. Traders can increase the collateral of a perpetual position [✅]
// - 7. Liquidity providers cannot withdraw liquidity that is reserved for positions [✅]

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
    AggregatorV3Interface internal BTCPriceFeed;
    Vault internal vault;
    IERC20 internal liquidityToken;
    uint internal constant maxLeverage = 20;
    uint internal constant maxReservPercentage = 10;
    uint internal constant maxReservUtilizationPercentage = 80;
    uint public openInterest;
    uint public openInterestBTC;

    // positions tracks all open positions
    mapping(bytes32 => Position) public positions;

    constructor(
        address _BTCPriceFeed,
        address _vaultTokenAddress,
        address _liquidityToken
    ) {
        BTCPriceFeed = AggregatorV3Interface(_BTCPriceFeed);
        vault = Vault(_vaultTokenAddress);
        liquidityToken = IERC20(_liquidityToken);
    }

    function depositLiquidity(uint amount) external {
        liquidityToken.safeTransferFrom(msg.sender, address(this), amount);
        vault.deposit(amount, msg.sender);
    }

    function withdrawLiquidity(uint amount) external {
        require(
            liquidityToken.balanceOf(address(vault)) - amount > openInterest,
            "Not enough liquidity"
        ); // TODO Do we need to check maxReservUtilizationPercentage too?
        vault.withdraw(amount, msg.sender, msg.sender);
    }

    function openPosition(uint collateral, uint size, bool isLong) external {
        require(
            collateral > 0 &&
                size > 0 &&
                collateral * maxLeverage >= size * getBTCPrice(),
            "Invalid inputs"
        ); // check that we are not exceding max leverage and values are not 0

        // this is ugly but I dunno how to make prettier do not prettify this line
        require(
            size * getBTCPrice() <=
                (liquidityToken.balanceOf(address(vault)) *
                    maxReservUtilizationPercentage) /
                    100
        ); // check do we have enought liquidity for position

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
        adjustOpenInterest(size);
    }

    function increaseCollateral(
        bytes32 positionKey,
        uint additionalCollateral
    ) external onlyPositionOwner(positionKey) onlyHealthyPosition(positionKey) {
        Position storage p = positions[positionKey];
        p.collateral += additionalCollateral;
    }

    function increasePositionSize(
        bytes32 positionKey,
        uint additionalSize
    ) external onlyPositionOwner(positionKey) onlyHealthyPosition(positionKey) {
        Position storage p = positions[positionKey];
        p.size += additionalSize;
        require(
            checkDoesNotExceedMaxLeverage(positionKey),
            "Wrong additional size"
        ); // TODO check does this work
    }

    // This one kinda "stollen" from gmx, but adjusted since we have only one index token
    // I think in v2 we would need to have more asses so function would be adjusted accordingly
    function getPositionKey(
        address _account,
        bool _isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _isLong));
    }

    function getBTCPrice() internal view returns (uint) {
        (, int BTCPrice, , , ) = BTCPriceFeed.latestRoundData(); // I tried to make this one liner but wasn't able to do so :(
        return uint(BTCPrice); // convert to uint cuz if BTC is less than 0 it's just sad
    }

    function adjustOpenInterest(uint size) internal {
        openInterest += size * getBTCPrice();
        openInterestBTC += size;
    }

    function checkDoesNotExceedMaxLeverage(
        bytes32 positionKey
    ) internal view returns (bool) {
        // TODO there is a warning above but I don't see why
        Position memory p = positions[positionKey];
        uint btcPrice = getBTCPrice();
        if (p.isLong) {
            return
                ((p.size * btcPrice) / p.collateral) > maxLeverage
                    ? false
                    : true;
        } else {
            ((p.size * btcPrice) / p.collateral) > maxLeverage ? true : false;
        }
    }

    modifier onlyPositionOwner(bytes32 positionKey) {
        require(positions[positionKey].owner == msg.sender, "Forbidden");
        _;
    }

    modifier onlyHealthyPosition(bytes32 positionKey) {
        require(
            checkDoesNotExceedMaxLeverage(positionKey),
            "Unhealthy position"
        );
        _;
    }
}
