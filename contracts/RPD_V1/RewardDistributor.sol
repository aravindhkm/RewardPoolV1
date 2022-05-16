// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/RewardPayingTokenInterface.sol";
import "./interfaces/RewardPayingTokenOptionalInterface.sol";
import "./interfaces/IRewardPool.sol";
import "./library/SafeMathInt.sol";
import "./library/SafeMathUint.sol";

contract RewardDistributor is ERC20, Ownable, RewardPayingTokenInterface, RewardPayingTokenOptionalInterface  {
    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;

    address public rewardToken;
    uint256 constant internal magnitude = 2**128;

    uint256 internal magnifiedRewardPerShare;

    mapping(address => int256) internal magnifiedRewardCorrections;
    mapping(address => uint256) internal withdrawnRewards;

    uint256 public totalRewardsDistributed;

    constructor(address _rewardToken) ERC20("Gold_Reward_Tracker", "GRT") {
        _setRewardToken(_rewardToken);
    }

    function _setRewardToken(address newToken) internal {
        rewardToken = newToken;
    }

    function distributeRewardForTokenHolders(uint256 amount) external onlyOwner{
        require(totalSupply() > 0, "Rewards: Supply is Zero");

        if (amount > 0) {
        IERC20(rewardToken).transferFrom(_msgSender(),address(this),amount);
        magnifiedRewardPerShare = magnifiedRewardPerShare.add(
            (amount).mul(magnitude) / totalSupply()
        );
        emit RewardsDistributed(msg.sender, amount);

        totalRewardsDistributed = totalRewardsDistributed.add(amount);      
        }
    }

    function withdrawReward() external virtual override {
        _withdrawRewardsOfUser(msg.sender);
    }

    function _withdrawRewardsOfUser(address user) internal returns (uint256) {
        uint256 _withdrawableReward = withdrawableRewardOf(user);
        if (_withdrawableReward > 0) {
        withdrawnRewards[user] = withdrawnRewards[user].add(_withdrawableReward);
        emit RewardWithdrawn(user, _withdrawableReward);
        bool success = IERC20(rewardToken).transfer(user, _withdrawableReward);

        if(!success) {
            withdrawnRewards[user] = withdrawnRewards[user].sub(_withdrawableReward);
            return 0;
        }

        return _withdrawableReward;
        }

        return 0;
    }

    function rewardOf(address _owner) external view override returns(uint256) {
        return withdrawableRewardOf(_owner);
    }

    function withdrawableRewardOf(address _owner) public view override returns(uint256) {
        return accumulativeRewardOf(_owner).sub(withdrawnRewards[_owner]);
    }

    function withdrawnRewardOf(address _owner) external view override returns(uint256) {
        return withdrawnRewards[_owner];
    }

    function accumulativeRewardOf(address _owner) public view override returns(uint256) {
        return magnifiedRewardPerShare.mul(balanceOf(_owner)).toInt256Safe()
        .add(magnifiedRewardCorrections[_owner]).toUint256Safe() / magnitude;
    }

    function _mint(address account, uint256 value) internal override {

        magnifiedRewardCorrections[account] = magnifiedRewardCorrections[account]
        .sub( (magnifiedRewardPerShare.mul(value)).toInt256Safe() );
    }

    function _burn(address account, uint256 value) internal override {
        super._burn(account, value);

        magnifiedRewardCorrections[account] = magnifiedRewardCorrections[account]
        .add( (magnifiedRewardPerShare.mul(value)).toInt256Safe() );
    }

    
}