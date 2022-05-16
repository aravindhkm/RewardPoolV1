// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IRewardPoolManager {
    function owner() external view returns (address);
    function buyBackRidge() external view returns (uint256 _minimumBnbBalanceForBuyback,uint256 _maximumBnbBalanceForBuyback);
}