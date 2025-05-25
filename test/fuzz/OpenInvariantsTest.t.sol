// //SPDX-License-Identifier: MIT
// pragma solidity ^0.8.18;

// import {Test} from "forge-std/Test.sol";
// import {DeployMSC} from "../../script/DeployMSC.s.sol";
// import {MSCEngine} from "../../src/MSCEngine.sol";
// import {MarkStablecoin} from "../../src/MarkStablecoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// // Have our invariants hold true for all test runs

// contract OpenInvariantsTest is Test {
//     DeployMSC deployMSC;
//     MSCEngine mscEngine;
//     MarkStablecoin msc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployMSC = new DeployMSC();
//         (msc, mscEngine, config) = deployMSC.run();
//         (,, weth, wbtc,) = config.activeNetworkConfig();
//         targetContract(address(mscEngine));
//     }

//     function invariant_protocolMustHaveValueThanTotalSupply() public view {
//         uint256 totalSupply = msc.totalSupply();
//         uint256 totalWethValue = IERC20(weth).balanceOf(address(mscEngine));
//         uint256 totalWbtcValue = IERC20(wbtc).balanceOf(address(mscEngine));

//         uint256 wethValue = mscEngine.getUsdValue(weth, totalWethValue);
//         uint256 wbtcValue = mscEngine.getUsdValue(wbtc, totalWbtcValue);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
