//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployMSC} from "../../script/DeployMSC.s.sol";
import {MarkStablecoin} from "../../src/MarkStablecoin.sol";
import {
    MSCEngine,
    MSCEngine__MustBeGreaterThanZero,
    MSCEngine__TokenAddressesLengthNotEqualToPriceFeedAddressesLength,
    MSCEngine__TokenNotWhitelisted,
    MSCEngine__FailedToTransfer,
    MSCEngine__BreaksHealthFactor
} from "../../src/MSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {console} from "forge-std/console.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract MscEngineTest is Test {
    DeployMSC deployMSC;
    MarkStablecoin msc;
    MSCEngine mscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address wbtcUsdPriceFeed;
    address wbtc;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public {
        deployMSC = new DeployMSC();
        (msc, mscEngine, config) = deployMSC.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    ///Constructor Tests///
    //////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthNotEqualToPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(MSCEngine__TokenAddressesLengthNotEqualToPriceFeedAddressesLength.selector);
        new MSCEngine(tokenAddresses, priceFeedAddresses, address(msc));
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

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = mscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    //////////////////////////////
    ///Deposit Collateral Tests///
    //////////////////////////////

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockCollateralToken = new MockFailedTransferFrom();
        tokenAddresses = [address(mockCollateralToken)];
        priceFeedAddresses = [ethUsdPriceFeed];
        // MSCEngine receives the third parameter as mscAddress, not the tokenAddress used as collateral.
        vm.prank(owner);
        MSCEngine mockDsce = new MSCEngine(tokenAddresses, priceFeedAddresses, address(msc));
        mockCollateralToken.mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(address(mockCollateralToken)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(MSCEngine__FailedToTransfer.selector);
        mockDsce.depositCollateral(address(mockCollateralToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTokenNotWhitelisted() public {
        ERC20Mock whateverToken = new ERC20Mock();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(MSCEngine__TokenNotWhitelisted.selector);
        mscEngine.depositCollateral(address(whateverToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfCollateralAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(MSCEngine__MustBeGreaterThanZero.selector);
        mscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock whateverToken = new ERC20Mock();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(MSCEngine__TokenNotWhitelisted.selector);
        mscEngine.depositCollateral(address(whateverToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mscEngine), AMOUNT_COLLATERAL);
        mscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalMscMinted, uint256 collateralValueInUsd) = mscEngine.getAccountInfo(USER);
        uint256 expectedTotalMscMinted = 0;
        uint256 expectedDepositAmount = mscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalMscMinted, expectedTotalMscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testRevertIfApproveAmountIsLessThanDepositAmount() public depositedCollateral {
        uint256 amountToApprove = 5 ether;
        ERC20Mock(weth).approve(address(mscEngine), amountToApprove);

        vm.startPrank(USER);
        vm.expectRevert(); // ERC20InsufficientAllowance found in draft-IERC6093.sol interface IERC20Errors
        mscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfMintedMscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (amountCollateral * (uint256(price) * mscEngine.getAdditionalFeedPrecision())) / mscEngine.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mscEngine), amountCollateral);

        uint256 expectedHealthFactor =
            mscEngine.calculateHealthFactor(amountToMint, mscEngine.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(MSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        mscEngine.depositCollateralAndMintMsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    /////////////////////////////
    ///Redeem Collateral Tests///
    /////////////////////////////

    function testRevertIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(MSCEngine__MustBeGreaterThanZero.selector);
        mscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertIfRedeemAmountIsGreaterThanDepositAmount() public depositedCollateral {
        uint256 redeemAmount = 11 ether;
        vm.startPrank(USER);
        vm.expectRevert();
        mscEngine.redeemCollateral(weth, redeemAmount);
        vm.stopPrank();
    }

    function testRedeemCollateral() public depositedCollateral {
        uint256 redeemAmount = 10 ether;
        vm.startPrank(USER);
        mscEngine.redeemCollateral(weth, redeemAmount);
        vm.stopPrank();
    }

    function testRedeemCollateralForMsc() public {
        uint256 redeemAmount = 10 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mscEngine), AMOUNT_COLLATERAL);
        mscEngine.depositCollateralAndMintMsc(weth, AMOUNT_COLLATERAL, redeemAmount);
        ERC20Mock(address(msc)).approve(address(mscEngine), redeemAmount);
        mscEngine.redeemCollateralForMsc(weth, redeemAmount, redeemAmount);
        vm.stopPrank();
    }

    /////////////////////////////
    //////View & Pure Tests//////
    /////////////////////////////
    function testGetMsc() public view {
        address mscAddress = mscEngine.getMsc();
        assertEq(mscAddress, address(msc));
    }

    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = mscEngine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = mscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = mscEngine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = mscEngine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = mscEngine.getAccountInfo(USER);
        uint256 expectedCollateralValue = mscEngine.getUsdValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 collateralBalance = mscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, amountCollateral);
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collateralValue = mscEngine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = mscEngine.getUsdValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = mscEngine.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
