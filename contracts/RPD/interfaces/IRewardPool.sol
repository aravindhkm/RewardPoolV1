// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IRewardDistributor.sol";

interface IRewardPool {
    function owner() external view returns (address);
    function createRewardDistributor(
        address _implementation,
        address _nativeAsset,
        address _rewardAsset,
        uint256 _minimumTokenBalanceForDividends
    ) external returns (address);
    function setBalance(
        IRewardDistributor dividendTracker,
        address account
    ) external returns (bool);
    function dividendTrackerInfo(address rewardAsset) external view returns (address);
    function rewardContains(address rewardAsset) external view returns (bool);
    function rewardLength() external view returns (uint256);
    function rewardAt(uint256 index) external view returns (address);
    function rewardValues() external view returns (address[] memory);
}