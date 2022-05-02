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
    uint256 public totalDividendsDistributed;

    IERC20 public nativeAsset;
    IERC20 public rewardAsset; 

    mapping (address => bool) public excludedFromDividends;
    mapping(address => uint256) internal withdrawnDividends;
    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);
    event Claim(address indexed account, uint256 amount, bool indexed automatic);  
    event DividendsDistributed(
        address indexed from,
        uint256 weiAmount
    );
    event DividendWithdrawn(
        address indexed to,
        uint256 weiAmount
    );

    function initialize(
        address _nativeAsset,
        address _rewardAsset,
        uint256 _minimumTokenBalanceForDividends
    ) initializer public {
        __Ownable_init();  

        nativeAsset = IERC20(_nativeAsset);
        rewardAsset = IERC20(_rewardAsset); 

        claimWait = 3600;
        minimumTokenBalanceForDividends = _minimumTokenBalanceForDividends;
    } 

    receive() external payable {}

    function excludeFromDividends(address account) external onlyOwner {
    	require(!excludedFromDividends[account], "RewardDistributor: Already excluded");
    	excludedFromDividends[account] = true;

    	tokenHoldersMap.remove(account);

    	emit ExcludeFromDividends(account);
    }
      
    function distributeRewards(uint256 amount) public onlyOwner{
        if (amount > 0) {
        emit DividendsDistributed(msg.sender, amount);
        totalDividendsDistributed = totalDividendsDistributed.add(amount);
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
            uint256 withdrawableDividends,
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

        withdrawableDividends = withdrawableDividendOf(account);
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
    	if(excludedFromDividends[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForDividends) {
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
    		tokenHoldersMap.remove(account);
    	}
    }

    function processAccountInternal(address account, uint256 newBalance,bool automatic) internal returns(bool){

        if(excludedFromDividends[account] && !canAutoClaim(lastClaimTimes[account])) {
    		return false;
    	}
    
    	(newBalance >= minimumTokenBalanceForDividends) ? tokenHoldersMap.set(account, newBalance) : tokenHoldersMap.remove(account);
    	
        uint256 amount = _withdrawDividendOfUser(account);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }

    function withdrawDividend() public {
        _withdrawDividendOfUser(msg.sender);
    }

    function _withdrawDividendOfUser(address user) internal returns (uint256) {
        uint256 _withdrawableDividend = withdrawableDividendOf(user);
        if(_withdrawableDividend > 0) {
        withdrawnDividends[user] = withdrawnDividends[user].add(_withdrawableDividend);
        emit DividendWithdrawn(user, _withdrawableDividend);
        bool success = rewardAsset.transfer(user, _withdrawableDividend);

        if(!success) {
            withdrawnDividends[user] = withdrawnDividends[user].sub(_withdrawableDividend);
            return 0;
        }
        return _withdrawableDividend;
        }
        return 0;
    }

    function dividendOf(address _owner) public view returns(uint256) {
        return withdrawableDividendOf(_owner);
    }

    function withdrawableDividendOf(address _owner) public view returns(uint256) {
        return nativeAsset.balanceOf(_owner).mul(rewardAsset.balanceOf(address(this))).div(nativeAsset.totalSupply());
    }

    function withdrawnDividendOf(address _owner) public view returns(uint256) {
        return withdrawnDividends[_owner];
    }
}
