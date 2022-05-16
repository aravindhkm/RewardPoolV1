// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IRewardDistributor.sol";

interface IRewardPool {
    function owner() external view returns (address);
    function createRewardDistributor(
        address _implementation,
        address _nativeAsset,
        address _rewardAsset,
        uint256 _distributeShare,
        uint256 _minimumTokenBalanceForRewards
    ) external returns (address);
    function setBalance(
        IRewardDistributor rewardDistributor,
        address account
    ) external returns (bool);
    function getRewardsDistributor(address rewardAsset) external view returns (address);
    function rewardsDistributorContains(address rewardAsset) external view returns (bool);
    function getTotalNumberofRewardsDistributor() external view returns (uint256);
    function rewardsDistributorAt(uint256 index) external view returns (address);
    function getAllRewardsDistributor() external view returns (address[] memory);
    function getPoolStatus(address rewardAsset) external view returns (bool isActive);
}