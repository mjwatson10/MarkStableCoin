# MarkStablecoin (MSC)

MarkStablecoin (MSC) is a decentralized stablecoin designed to maintain a peg to $1.00 USD. It is over-collateralized using exogenous crypto assets like Wrapped Ether (wETH) and Wrapped Bitcoin (wBTC).

## Core Principles

1.  **Relative Stability**: Anchored or Pegged to $1.00 USD.
    *   Utilizes Chainlink Price Feeds for reliable asset pricing.
    *   Allows exchange of collateral (e.g., ETH, BTC) for MSC based on their USD value.
2.  **Stability Mechanism (Algorithmic & Decentralized Minting)**:
    *   Users can only mint MSC if they provide sufficient collateral.
3.  **Collateral (Exogenous Crypto)**:
    *   Currently supports wETH and wBTC.

## Features

*   **Deposit Collateral**: Users can deposit supported collateral (wETH, wBTC) into the system.
*   **Mint MSC**: After depositing collateral, users can mint MSC tokens. The system requires users to maintain a health factor above a minimum threshold, ensuring over-collateralization (initially set at 200%).
*   **Redeem Collateral**: Users can burn their MSC to redeem their deposited collateral, provided their health factor remains above the minimum threshold after redemption.
*   **Burn MSC**: Users can burn MSC to reduce their debt and improve their health factor.
*   **Combined Operations**:
    *   `depositCollateralAndMintMsc`: Allows users to deposit collateral and mint MSC in a single transaction.
    *   `redeemCollateralForMsc`: Allows users to burn MSC and redeem collateral in a single transaction.

## Liquidation

Liquidation is a critical mechanism to ensure the solvency of the MarkStablecoin system.

*   **How it Works**:
    *   Each user position (collateral deposited vs. MSC minted) has a "health factor". This factor represents the safety of their loan.
    *   If a user's health factor falls below a predefined minimum threshold (e.g., if the value of their collateral drops significantly or they mint too much MSC relative to their collateral), their position becomes eligible for liquidation.
    *   Other users (liquidators) can then repay a portion of the undercollateralized user's MSC debt.
    *   In return, liquidators receive a portion of the user's collateral at a discount (a "liquidation bonus," currently set at 10%). This incentivizes liquidators to participate and helps bring the user's health factor back above the minimum.
    *   The `liquidate` function in `MSCEngine.sol` handles this process. It ensures that the liquidation improves the user's health factor.

*   **How to Prevent Liquidation**:
    *   **Maintain a Healthy Collateralization Ratio**: Do not mint MSC close to the maximum allowed for your collateral. Keep your health factor significantly above the `MIN_HEALTH_FACTOR`.
    *   **Monitor Collateral Value**: Crypto asset prices can be volatile. If the value of your deposited collateral drops, your health factor will decrease.
    *   **Add More Collateral**: If your health factor is approaching the liquidation threshold, deposit more collateral.
    *   **Repay/Burn MSC**: Reduce your outstanding MSC debt by burning some of your MSC tokens.

## Chainlink Oracle Integration

Reliable price data is crucial for a stablecoin system. MarkStablecoin utilizes Chainlink Price Feeds to obtain the current market prices of collateral assets.

*   **Price Feeds**: The `MSCEngine.sol` contract is configured with addresses for Chainlink Price Feeds corresponding to each whitelisted collateral token (e.g., ETH/USD, BTC/USD).
*   **Stale Price Check**: The `OracleLib.sol` library is used to ensure the freshness of price data.
    *   It includes a `staleCheckLatestRoundData` function that verifies if the latest price update from the oracle is within an acceptable timeframe (currently set to 3 hours).
    *   If the price data is found to be stale (older than the defined timeout), the function will revert. This is a safety mechanism designed to "freeze" the MSCEngine's core operations (like minting, redeeming, liquidating) if reliable, up-to-date price information is unavailable, preventing actions based on outdated prices.
