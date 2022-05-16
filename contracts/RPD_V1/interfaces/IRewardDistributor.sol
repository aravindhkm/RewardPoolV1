// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IRewardDistributor {
    function updateClaimWait(uint256 newClaimWait) external;
    function claimWait() external view returns (uint256);
    function totalRewardsDistributed() external view returns (uint256);
    function withdrawableRewardOf(address _owner) external view returns (uint256);
    function excludeFromRewards(address account,bool status) external;
    function process(uint256 gas) external returns (uint256, uint256, uint256);
    function processAccount(address account, bool automatic) external returns (bool);
    function getLastProcessedIndex() external view returns(uint256);
    function getNumberOfTokenHolders() external view returns(uint256);
    function distributeRewards(uint256 amount) external;
    function setBalance(address account, uint256 newBalance) external;
    function getAccount(address _account) external view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableRewards,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable);
    function getAccountAtIndex(int256 index) external view returns(
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256);

}