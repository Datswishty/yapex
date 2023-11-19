## YAPEX

Yet Another Perpetual eXchange

This is an implementation of [mission #1](https://guardianaudits.notion.site/Mission-1-Perpetuals-028ca44faa264d679d6789d5461cfb13)
from [Gateway](https://twitter.com/intogateway) (Advanced open course for auditors)

# How does the system work?
Our perpetual contract allows traders to open long or short positions on BTC with a given size and collateral, while also enabling liquidity providers to deposit and withdraw liquidity. The contract uses Chainlink's AggregatorV3Interface to fetch real-time BTC/USD price feed, ensuring accurate and reliable pricing data for the trading operations.

# How to run
1.  **Install Foundry**

First run the command below to get foundryup, the Foundry toolchain installer:

``` bash
curl -L https://foundry.paradigm.xyz | bash
```

Then, in a new terminal session or after reloading your PATH, run it to get the latest forge and cast binaries:

``` console
foundryup
```

2. **Clone This Repo and install dependencies**
``` 
git clone https://github.com/Datswishty/yapex
cd yapex
forge install
forge test
```
