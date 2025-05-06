//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployMSC} from "../../script/DeployMSC.s.sol";
import {MarkStablecoin} from "../../src/MarkStablecoin.sol";
import {MSCEngine, MSCEngine__MustBeGreaterThanZero} from "../../src/MSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

contract MscEngineTest is Test {
    DeployMSC deployMSC;
    MarkStablecoin msc;
    MSCEngine mscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address wbtcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployMSC = new DeployMSC();
        (msc, mscEngine, config) = deployMSC.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    ///Price Feed Tests///
    //////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = mscEngine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    //////////////////////////////
    ///Deposit Collateral Tests///
    //////////////////////////////

    function testRevertsIfCollateralAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(MSCEngine__MustBeGreaterThanZero.selector);
        mscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
