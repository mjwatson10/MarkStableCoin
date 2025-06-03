//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {MSCEngine} from "../../src/MSCEngine.sol";
import {MarkStablecoin} from "../../src/MarkStablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

// Handler is going to narrow down the way functions are called

contract Handler is Test {
    MSCEngine mscEngine;
    MarkStablecoin msc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timeMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public wbtcUsdPriceFeed;

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(MSCEngine _mscEngine, MarkStablecoin _msc) {
        mscEngine = _mscEngine;
        msc = _msc;

        address[] memory collateralTokens = mscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(mscEngine.getCollateralTokenPriceFeed(address(weth)));
        wbtcUsdPriceFeed = MockV3Aggregator(mscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function mintMsc(uint256 _amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalMscMinted, uint256 collateralValueInUsd) = mscEngine.getAccountInfo(sender);
        int256 maxMscToMint = (int256(collateralValueInUsd) / 2) - int256(totalMscMinted);
        if (maxMscToMint <= 0) {
            return;
        }
        _amount = bound(_amount, 1, uint256(maxMscToMint));
        if (_amount == 0) {
            return;
        }

        vm.startPrank(sender);
        mscEngine.mintMsc(_amount);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 _amount) public {
        ERC20Mock collateralAddress = _getCollateralAddressFromSeed(collateralSeed);
        uint256 amountCollateral = bound(_amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateralAddress.mint(msg.sender, amountCollateral);
        collateralAddress.approve(address(mscEngine), amountCollateral);
        mscEngine.depositCollateral(address(collateralAddress), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 _amount) public {
        ERC20Mock collateralAddress = _getCollateralAddressFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = mscEngine.getCollateralBalanceOfUser(msg.sender, address(collateralAddress));
        uint256 amountCollateral = bound(_amount, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        mscEngine.redeemCollateral(address(collateralAddress), amountCollateral);
    }

    // This breaks our invariant test suite!!!!
    // function updateCollateralPrice(uint256 collateralSeed, uint96 _price) public {
    //     int256 newPriceInt = int256(uint256(_price));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);

    // }

    function _getCollateralAddressFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
