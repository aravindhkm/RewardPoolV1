// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;


/// @title reward-Paying Token Optional Interface
/// @author Roger Wu (https://github.com/roger-wu)
/// @dev OPTIONAL functions for a reward-paying token contract.
interface RewardPayingTokenOptionalInterface {
  /// @notice View the amount of reward in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of reward in wei that `_owner` can withdraw.
  function withdrawableRewardOf(address _owner) external view returns(uint256);

  /// @notice View the amount of reward in wei that an address has withdrawn.
  /// @param _owner The address of a token holder.
  /// @return The amount of reward in wei that `_owner` has withdrawn.
  function withdrawnRewardOf(address _owner) external view returns(uint256);

  /// @notice View the amount of reward in wei that an address has earned in total.
  /// @dev accumulativeRewardOf(_owner) = withdrawablerewardOf(_owner) + withdrawnRewardOf(_owner)
  /// @param _owner The address of a token holder.
  /// @return The amount of reward in wei that `_owner` has earned in total.
  function accumulativeRewardOf(address _owner) external view returns(uint256);
}
