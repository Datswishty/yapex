// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "./interfaces/AggregatorV3Interface.sol";

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
//             /   /     ||--+--|--+-/-|     \   \     DATSW
//            |   |     /'\_\_\ | /_/_/`\     |   |
//             \   \__, \_     `~'     _/ .__/   /
//              `-._,-'   `-._______,-'   `-._,-'
// GOALS
// - Liquidity Providers can deposit and withdraw liquidity [ ]
// - A way to get the realtime price of the asset being traded [ ]
// - Traders can open a perpetual position for BTC, with a given size and collateral [ ]
// - Traders can increase the size of a perpetual position [ ]
// - Traders can increase the collateral of a perpetual position [ ]
// - Traders cannot utilize more than a configured percentage of the deposited liquidity [ ]
// - Liquidity providers cannot withdraw liquidity that is reserved for positions [ ]

contract YAPEX {
    AggregatorV3Interface internal ETHpriceFeed;

    constructor() {
        ETHpriceFeed = AggregatorV3Interface(
            0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
        );
    }

    function depositLiquidity() external {}

    function withdrawLiquidity() external {}

    function openPosition() external {}

    function increaseCollateral(uint positionId) external {} // add modifier onlyPositionOwner

    function increasePositionSize(uint positionId) external {} // add modifier onlyPositionOwner

    function forseLiquidatePosition(uint positionId) external {}
}
