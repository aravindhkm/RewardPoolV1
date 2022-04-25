// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IRewardPoolManager {
    function owner() external view returns (address);
    function buyBackRidge() external view returns (uint256 _minimumBnbBalanceForBuyback,uint256 _maximumBnbBalanceForBuyback);
    function getMaximumBuybackRewardShare() external view returns(uint8);
    function router() external view returns (address);
}