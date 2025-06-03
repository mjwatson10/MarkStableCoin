//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MarkStablecoin} from "./MarkStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

//// Errors ////
error MSCEngine__MustBeGreaterThanZero();
error MSCEngine__TokenAddressesLengthNotEqualToPriceFeedAddressesLength();
error MSCEngine__TokenNotWhitelisted();
error MSCEngine__FailedToTransfer();
error MSCEngine__BreaksHealthFactor(uint256 healthFactor);
error MSCEngine__FailedToMint();
error MSCEngine__TransferFailed();
error MSCEngine__HealthFactorIsOk();
error MSCEngine__HealthFactorNotImproved();

/*
 *@title MSCEngine
 *@author Mark Watson
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 *
 * This stablecoin has the properties
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH & wBTC
 *
 * Our MSC system should always be "over-collateralized". At no point should the value of all collateral be less than the total supply of MSC
 *
 * @notice This contract is the core of the MSC system, it handles all the logic for minting and redeeming MSC, as well as depositing and withdrawing collateral
 * @notice this contract is very loosely based on the MakerDAO DSS (DAI) system
 */
contract MSCEngine is ReentrancyGuard {
    /// Types ///
    using OracleLib for AggregatorV3Interface;

    //// State Variables ////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% over-collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100; // 10% liquidation discount
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% liquidation bonus

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMscMinted) private s_mscMinted;
    address[] private s_collateralTokens;

    MarkStablecoin private immutable i_msc;

    //// Events ////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemerFrom, address indexed redeemerTo, address indexed token, uint256 amount
    );

    //// Modifiers ////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert MSCEngine__MustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert MSCEngine__TokenNotWhitelisted();
        }
        _;
    }

    //// Functions ////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address mscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert MSCEngine__TokenAddressesLengthNotEqualToPriceFeedAddressesLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_msc = MarkStablecoin(mscAddress);
    }

    //// External Functions ////
    /**
     * @notice follows CEI (Checks, Effects, Interactions)
     * @notice Deposits collateral into the system and mints MSC in one transaction
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountMscToMint The amount of MSC to mint
     */
    function depositCollateralAndMintMsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountMscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintMsc(amountMscToMint);
    }

    /**
     * @notice follows CEI (Checks, Effects, Interactions)
     * @notice Deposits collateral into the system and mints MSC in return
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert MSCEngine__FailedToTransfer();
        }
    }

    /**
     * @notice follows CEI (Checks, Effects, Interactions)
     * @notice Burns MSC and redeems collateral in return
     * @param tokenCollateralAddress The address of the token to redeem as collateral
     * @param amountCollateral The amount of collateral to redeem
     */
    function redeemCollateralForMsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountMscToBurn)
        external
    {
        burnMsc(amountMscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks for health factor
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    /**
     * @notice follows CEI (Checks, Effects, Interactions)
     * @notice Must have more collateral value than the minimum threshold
     * @param amountMscToMint The amount of MSC to mint
     */
    function mintMsc(uint256 amountMscToMint) public moreThanZero(amountMscToMint) {
        s_mscMinted[msg.sender] += amountMscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_msc.mint(msg.sender, amountMscToMint);
        if (!minted) {
            revert MSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnMsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        _revertIfHealthFactorIsBroken(msg.sender);
        _burnMsc(amount, msg.sender, msg.sender);
    }

    /**
     * @notice follows CEI (Checks, Effects, Interactions)
     * @notice you can partially liquidate a user
     * @notice you will get a liquidation bonus taking users funds
     * @notice this function working assumes the protocol will be roughly 200% over-collateralized in order for this to work
     * @param collateral The address of the ERC20 token to be liquidated from the user
     * @param user The address that has broken the health factor
     * @param debtToCover The amount of MSC to burn in order to improve the user's health factor
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        //check health factor of user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert MSCEngine__HealthFactorIsOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

        _burnMsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert MSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view returns (uint256) {}

    //// Private & Internal View Functions ////

    /**
     * @dev low level internal function, do not call unless the function calling it is checking health factors being broken
     */
    function _burnMsc(uint256 amount, address onBehalfOf, address mscFrom) private {
        s_mscMinted[onBehalfOf] -= amount;
        bool success = i_msc.transferFrom(mscFrom, address(this), amount);
        if (!success) {
            revert MSCEngine__TransferFailed();
        }
        i_msc.burn(amount);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert MSCEngine__FailedToTransfer();
        }
    }

    function _getAccountInfor(address user)
        private
        view
        returns (uint256 totalMscMinted, uint256 collateralValueInUsd)
    {
        totalMscMinted = s_mscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Returns the health factor of a user
     * @param user The address of the user
     * @return How close a user is to liquidation
     * if a user goes below 1, they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalMscMinted, uint256 collateralValueInUsd) = _getAccountInfor(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalMscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert MSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalMscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalMscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalMscMinted;
    }

    //// Public & External View Functions ////

    function calculateHealthFactor(uint256 totalMscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalMscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 1 eth = 1000000000000000000 wei
        // the returned value from Chainlink will be 1000 * 1e8 (ETH/USD has 8 decimals)
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountInfo(address user)
        external
        view
        returns (uint256 totalMscMinted, uint256 collateralValueInUsd)
    {
        (totalMscMinted, collateralValueInUsd) = _getAccountInfor(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getMsc() external view returns (address) {
        return address(i_msc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
