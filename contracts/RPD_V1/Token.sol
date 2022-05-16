// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IRewardPool.sol";

contract MyToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {

    bool public isRewardEnable;
    IRewardPool public rewardPool;

    function initialize(address _rewardPool) initializer public {
        __ERC20_init("MyToken", "MTK");
        __Ownable_init();

        _mint(msg.sender, 100000000 * 10 ** decimals());
        rewardPool = IRewardPool(_rewardPool);
        isRewardEnable = true;
    }

    receive() external payable {}

    function updateRewardPool(address newRewardPool) public onlyOwner {
        rewardPool = IRewardPool(newRewardPool);
    }

    function setRewardEnable(bool status) external onlyOwner {
        isRewardEnable = status;
    }

    function _afterTokenTransfer(address from, address to, uint256) internal override{
        if(isRewardEnable) {
            rewardPool.setBalance(from, balanceOf(from));
            rewardPool.setBalance(to, balanceOf(to));  
        }  
    }

    function recoverLeftOverBNB(uint256 amount) external onlyOwner {
        payable(owner()).transfer(amount);
    }

    function recoverLeftOverToken(address token,uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(),amount);
    }
}
