// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;


/// @title Reward-Paying Token Interface
/// @author Roger Wu (https://github.com/roger-wu)
/// @dev An interface for a reward-paying token contract.
interface RewardPayingTokenInterface {
  /// @notice View the amount of reward in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of reward in wei that `_owner` can withdraw.
  function rewardOf(address _owner) external view returns(uint256);


  /// @notice Withdraws the ether distributed to the sender.
  /// @dev SHOULD transfer `rewardOf(msg.sender)` wei to `msg.sender`, and `rewardOf(msg.sender)` SHOULD be 0 after the transfer.
  ///  MUST emit a `RewardWithdrawn` event if the amount of ether transferred is greater than 0.
  function withdrawReward() external;

  /// @dev This event MUST emit when ether is distributed to token holders.
  /// @param from The address which sends ether to this contract.
  /// @param weiAmount The amount of distributed ether in wei.
  event RewardsDistributed(
    address indexed from,
    uint256 weiAmount
  );

  /// @dev This event MUST emit when an address withdraws their reward.
  /// @param to The address which withdraws ether from this contract.
  /// @param weiAmount The amount of withdrawn ether in wei.
  event RewardWithdrawn(
    address indexed to,
    uint256 weiAmount
  );
}
