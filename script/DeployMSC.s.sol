//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MarkStablecoin} from "../src/MarkStablecoin.sol";
import {MSCEngine} from "../src/MSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (MarkStablecoin, MSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        MarkStablecoin msc = new MarkStablecoin();
        MSCEngine mscEngine = new MSCEngine(tokenAddresses, priceFeedAddresses, address(msc));

        msc.transferOwnership(address(mscEngine));
        vm.stopBroadcast();
        return (msc, mscEngine, config);
    }
}
