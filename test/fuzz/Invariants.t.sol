//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployMSC} from "../../script/DeployMSC.s.sol";
import {MSCEngine} from "../../src/MSCEngine.sol";
import {MarkStablecoin} from "../../src/MarkStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";
import {console} from "forge-std/console.sol";

// Have our invariants hold true for all test runs

contract Invariants is Test {
    DeployMSC deployMSC;
    MSCEngine mscEngine;
    MarkStablecoin msc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployMSC = new DeployMSC();
        (msc, mscEngine, config) = deployMSC.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(mscEngine));
        handler = new Handler(mscEngine, msc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = msc.totalSupply();
        uint256 totalWethValue = IERC20(weth).balanceOf(address(mscEngine));
        uint256 totalWbtcValue = IERC20(wbtc).balanceOf(address(mscEngine));

        uint256 wethValue = mscEngine.getUsdValue(weth, totalWethValue);
        uint256 wbtcValue = mscEngine.getUsdValue(wbtc, totalWbtcValue);
        console.log("wethValue", wethValue);
        console.log("wbtcValue", wbtcValue);
        console.log("totalSupply", totalSupply);
        console.log("Times mint called: ", handler.timeMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        mscEngine.getCollateralTokens();
        mscEngine.getCollateralTokenPriceFeed(weth);
        mscEngine.getMsc();
        mscEngine.getMinHealthFactor();
        mscEngine.getLiquidationThreshold();
        mscEngine.getPrecision();
        mscEngine.getLiquidationBonus();
        mscEngine.getAdditionalFeedPrecision();
    }
}
