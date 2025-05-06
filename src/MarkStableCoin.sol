//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error MarkStablecoin__BurnAmountExceedsBalance();
error MarkStablecoin__MustBeGreaterThanZero();
error MarkStablecoin__NoZeroAddress();

/*
 *@title MarkStablecoin
 *@author Mark Watson
 * Collateral: Exogenous (wETH & wBTC)
 * Minting: Algorithmic (Decentralized)
 *Relative Stability: Anchored (Pegged to USD)
 *
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system.
 */
contract MarkStablecoin is ERC20Burnable, Ownable {
    constructor() ERC20("Mark Stablecoin", "mUSDC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert MarkStablecoin__MustBeGreaterThanZero();
        }
        if (_amount > balance) {
            revert MarkStablecoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert MarkStablecoin__NoZeroAddress();
        }
        if (_amount <= 0) {
            revert MarkStablecoin__MustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
