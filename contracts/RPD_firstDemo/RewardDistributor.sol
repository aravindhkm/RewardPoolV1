// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./library/IterableMapping.sol";
import "./interfaces/IRewardPool.sol";
import "./library/SafeMathInt.sol";

contract RewardDistributor is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;
    uint256 public totalRewardsDistributed;

    IERC20 public nativeAsset;
    IERC20 public rewardAsset; 
    IRewardPool public rewardPool;

    mapping (address => bool) public excludedFromRewards;
    mapping(address => uint256) internal withdrawnRewards;
    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public minimumTokenBalanceForRewards;

    event ExcludeFromRewards(address indexed account,bool status);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);
    event Claim(address indexed account, uint256 amount, bool indexed automatic);  
    event RewardsDistributed(
        address indexed from,
        uint256 weiAmount
    );
    event RewardWithdrawn(
        address indexed to,
        uint256 weiAmount
    );

    function initialize(
        address _nativeAsset,
        address _rewardAsset,
        uint256 _minimumTokenBalanceForRewards
    ) initializer public {
        __Ownable_init();  

        nativeAsset = IERC20(_nativeAsset);
        rewardAsset = IERC20(_rewardAsset); 
        rewardPool = IRewardPool(_msgSender());

        claimWait = 3600;
        minimumTokenBalanceForRewards = _minimumTokenBalanceForRewards;
    } 

    receive() external payable {}

    function excludeFromRewards(address account,bool status) external onlyOwner {
    	excludedFromRewards[account] = status;

        if(status) {
            uint256 newBalance = nativeAsset.balanceOf(account);

    		if(newBalance >= minimumTokenBalanceForRewards) tokenHoldersMap.set(account, newBalance);
    	}else {
    	    tokenHoldersMap.remove(account);
        }
    	emit ExcludeFromRewards(account,status);
    }
      
    function distributeRewards(uint256 amount) public onlyOwner{
        if (amount > 0) {
        emit RewardsDistributed(msg.sender, amount);
        totalRewardsDistributed = totalRewardsDistributed.add(amount);
        }
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }
	
    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableRewards,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ? tokenHoldersMap.keys.length.sub(lastProcessedIndex) : 0;
                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }

        withdrawableRewards = withdrawableRewardOf(account);
        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ? lastClaimTime.add(claimWait) : 0;
        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ? nextClaimTime.sub(block.timestamp) : 0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function process(uint256 gas) external returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, lastProcessedIndex);
    	}

    	uint256 _lastProcessedIndex = lastProcessedIndex;

    	uint256 gasUsed = 0;

    	uint256 gasLeft = gasleft();

    	uint256 iterations = 0;
    	uint256 claims = 0;

    	while(gasUsed < gas && iterations < numberOfTokenHolders) {
    		_lastProcessedIndex++;

    		if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
    			_lastProcessedIndex = 0;
    		}

    		address account = tokenHoldersMap.keys[_lastProcessedIndex];
    		if(canAutoClaim(lastClaimTimes[account])) {
    			if(processAccountInternal(account,nativeAsset.balanceOf(account),true)) {
    				claims++;
    			}
    		}

    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
    		}

    		gasLeft = newGasLeft;
    	}

    	lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address account,bool automatic) public onlyOwner returns (bool) {
       return processAccountInternal(account,nativeAsset.balanceOf(account),automatic);
    }
    
    function setBalance(address account, uint256 newBalance) external onlyOwner {
    	if(excludedFromRewards[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForRewards) {
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
    		tokenHoldersMap.remove(account);
    	}
    }

    function processAccountInternal(address account, uint256 newBalance,bool automatic) internal returns(bool){

        if(excludedFromRewards[account] && !canAutoClaim(lastClaimTimes[account])) {
    		return false;
    	}
    
    	(newBalance >= minimumTokenBalanceForRewards) ? tokenHoldersMap.set(account, newBalance) : tokenHoldersMap.remove(account);
    	
        uint256 amount = _withdrawRewardOfUser(account);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }

    function _withdrawRewardOfUser(address user) internal returns (uint256) {
        uint256 _withdrawableReward = withdrawableRewardOf(user);
        if(_withdrawableReward > 0) {
        withdrawnRewards[user] = withdrawnRewards[user].add(_withdrawableReward);
        emit RewardWithdrawn(user, _withdrawableReward);
        bool success = rewardAsset.transfer(user, _withdrawableReward);

        if(!success) {
            withdrawnRewards[user] = withdrawnRewards[user].sub(_withdrawableReward);
            return 0;
        }
        return _withdrawableReward;
        }
        return 0;
    }

    function rewardOf(address _owner) public view returns(uint256) {
        return withdrawableRewardOf(_owner);
    }

    function checkThresHold(uint256 balance) internal view returns (uint256) {
        uint256 maxBalanceThreshold = nativeAsset.totalSupply().mul(1).div(100);

        if(maxBalanceThreshold <= balance) {
            return maxBalanceThreshold;
        }else {
            return balance;
        }
    }

    function withdrawableRewardOf(address _owner) public view returns(uint256) {
        return checkThresHold(nativeAsset.balanceOf(_owner)).mul(rewardAsset.balanceOf(address(this))).div(nativeAsset.totalSupply());
    }

    function withdrawnRewardOf(address _owner) public view returns(uint256) {
        return withdrawnRewards[_owner];
    }
}
