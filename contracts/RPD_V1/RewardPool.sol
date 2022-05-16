// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./RewardDistributor.sol";
import "./interfaces/IRewardPool.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IRewardDistributor.sol";
import "./library/IterableMapping.sol";
import "./library/SafeMathInt.sol";
import "./RewardDistributor.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardPool is ERC20, Ownable, Pausable {
    using SafeMathInt for int256;
    using SafeMath for uint256;
    using IterableMapping for IterableMapping.Map;

    IUniswapV2Router02 public uniswapV2Router;

    address public uniswapV2Pair;
    address public nativeAsset;
    address public constant deadWallet = 0x000000000000000000000000000000000000dEaD; 
    uint256 public buyBackClaimWait = 86400;
    uint256 public lastBuyBackTimestamp;
    uint256 public defaultMinimumTokenBalanceForRewards = 1000 * (10 ** 18);
    uint256 private minimumBnbBalanceForBuyback = 10;
    uint256 private maximumBnbBalanceForBuyback = 80;

    uint256 private constant distributeSharePrecision = 100;
    uint256 public gasForProcessing;

    bool private swapping;

    struct rewardStore {
        address rewardAsset;
        address rewardDistributor;
        uint256 distributeShare;
        uint256 claimWait;
        uint256 lastProcessedIndex;
        uint256 minimumTokenBalanceForRewards;
        bool isActive;
    }

    IterableMapping.Map private tokenHoldersMap;
    rewardStore[] private _rewardInfo;
    mapping (address => uint8) private _rewardStoreId;    
    mapping (address => mapping(address => bool)) public excludedFromRewards;
    mapping (address => mapping(address => uint256)) public lastClaimTimes;

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);
    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);
    event SwapAndLiquify(uint256 tokensSwapped,uint256 ethReceived,uint256 tokensIntoLiqudity);
    event SendRewards(uint256 tokensSwapped,uint256 amount);
    event ProcessedDistributorTracker(uint256 iterations,uint256 claims,uint256 lastProcessedIndex,bool indexed automatic,uint256 gas,address indexed processor);

    constructor(
        address _nativeAsset,
        address _projectAdmin
    ) {
        require(_projectAdmin != address(0), "RewardDistributor: projectAdmin can't be zero");
        _transferOwnership(_projectAdmin);  

        nativeAsset = _nativeAsset;

        // Mainnet
        // uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        // Testnet
        uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(uniswapV2Router.WETH(),_nativeAsset);
    }

    receive() external payable {}

    modifier onlyOperator() {
        require((msg.sender == owner()) || 
                (msg.sender == nativeAsset), "unable to access");
        _;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function validateDistributeShare(uint256 newShare) public view returns (bool) {
        uint256 currenShares = newShare;
        for(uint8 i;i<_rewardInfo.length;i++) {
            currenShares = currenShares.add(_rewardInfo[i].distributeShare);
        }
        return (currenShares <= distributeSharePrecision);
    }

    function setDistributeShare(address rewardToken,uint256 newShare) external onlyOwner {
        require(_rewardStoreId[rewardToken] != 0 , "RewardPool: Reward Token is invalid");
        _rewardInfo[_rewardStoreId[rewardToken]].distributeShare = newShare;
        require(validateDistributeShare(0), "RewardPool: DistributeShare is invalid");
    }

    function setBuyBackClaimWait(uint256 newClaimWait) external onlyOwner {
        buyBackClaimWait = newClaimWait;
    }

    function createRewardDistributor(
        address _rewardAsset,
        uint256 _distributeShare,
        uint256 _claimWait,
        uint256 _lastProcessedIndex,
        uint256 _minimumTokenBalanceForRewards
    ) external onlyOwner returns (address){
        require(validateDistributeShare(_distributeShare), "RewardPool: DistributeShare is invalid");

        RewardDistributor newRewardsDistributor = new RewardDistributor(_rewardAsset);

        _rewardStoreId[_rewardAsset] = uint8(_rewardInfo.length);
        _rewardInfo.push(
            rewardStore({
                rewardAsset: _rewardAsset,
                rewardDistributor: address(newRewardsDistributor),
                distributeShare: _distributeShare,
                claimWait: _claimWait,
                lastProcessedIndex : _lastProcessedIndex,
                minimumTokenBalanceForRewards : _minimumTokenBalanceForRewards,
                isActive: true
            })
        ); 

        // exclude from receiving rewards
        excludedFromRewards[_rewardAsset][(address(newRewardsDistributor))] = false;
        excludedFromRewards[_rewardAsset][(address(this))] = false;
        excludedFromRewards[_rewardAsset][owner()] = false;
        excludedFromRewards[_rewardAsset][deadWallet] = false;
        excludedFromRewards[_rewardAsset][address(uniswapV2Router)] = false;
        excludedFromRewards[_rewardAsset][address(uniswapV2Pair)] = false;

        return address(newRewardsDistributor);
    }

    function setRewardActiveStatus(address rewardAsset,bool status) external onlyOwner {
        _rewardInfo[_rewardStoreId[rewardAsset]].isActive = status;
    }

    function getBuyBackLimit(uint256 currentBalance) internal view returns (uint256,uint256) {
        return (currentBalance.mul(minimumBnbBalanceForBuyback).div(1e2),
                currentBalance.mul(maximumBnbBalanceForBuyback).div(1e2));
    }

    function generateBuyBack(uint256 buyBackAmount) external whenNotPaused onlyOwner {
        require(lastBuyBackTimestamp.add(buyBackClaimWait) < block.timestamp, "RewardPool: buybackclaim still not over");

        uint256 initialBalance = address(this).balance;

        (uint256 _minimumBnbBalanceForBuyback,uint256 _maximumBnbBalanceForBuyback) = getBuyBackLimit(initialBalance);

        require(initialBalance > _minimumBnbBalanceForBuyback, "RewardPool: Required Minimum BuyBack Amount");

        lastBuyBackTimestamp = block.timestamp;
        buyBackAmount = buyBackAmount > _maximumBnbBalanceForBuyback ? 
                            _maximumBnbBalanceForBuyback : 
                            buyBackAmount > _minimumBnbBalanceForBuyback ? buyBackAmount : _minimumBnbBalanceForBuyback;
        
        for(uint8 i; i<_rewardInfo.length; i++) {
            if(_rewardInfo[i].isActive) {                
                swapAndSendReward(
                    IRewardDistributor(_rewardInfo[i].rewardDistributor),
                    _rewardInfo[i].rewardAsset,
                    buyBackAmount.mul(_rewardInfo[i].distributeShare).div(1e2));
            }
        }
    }

    function updateDexStore(address newRouter) public onlyOwner {
        require(newRouter != address(uniswapV2Router), "RewardPool: The router already has that address");
        emit UpdateUniswapV2Router(newRouter, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newRouter);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(uniswapV2Router.WETH(),nativeAsset);
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue != gasForProcessing, "RewardPool: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(address rewardToken,uint256 claimWait) external onlyOwner {
        require(_rewardInfo[_rewardStoreId[rewardToken]].rewardAsset == rewardToken, "RewardPool: Reward is not active");

        _rewardInfo[_rewardStoreId[rewardToken]].claimWait = claimWait;
    }

    function updateClaimWaitForAllDistributore(
        uint256 claimWait
    )  external onlyOwner {
        for(uint8 i; i<_rewardInfo.length; i++) {
            if(_rewardInfo[i].isActive) {  
                _rewardInfo[i].claimWait = claimWait;
            }
        }
    }

    function getClaimWait(address rewardToken) external view returns(uint256) {
        if(_rewardInfo[_rewardStoreId[rewardToken]].rewardAsset == rewardToken) {
            return _rewardInfo[_rewardStoreId[rewardToken]].claimWait;
        }else {
            return 0;
        }
        
    }

    function getTotalRewardsDistribute(IRewardDistributor rewardsDistributor) external view returns (uint256) {
        return rewardsDistributor.totalRewardsDistributed();
    }

    function withdrawableRewardOf(IRewardDistributor rewardsDistributor,address account) public view returns(uint256) {
    	return rewardsDistributor.withdrawableRewardOf(account);
  	}

	function excludeFromRewards(address rewardToken,address account) external onlyOwner{
	    excludedFromRewards[rewardToken][account] = true;
	}

    function includeFromRewards(address rewardToken,address account) external onlyOwner{
	    excludedFromRewards[rewardToken][account] = false;
	}

    function multiExcludeFromRewards(address[] calldata accounts) external onlyOwner{
        for(uint8 k; k<_rewardInfo.length; k++) {
            if(!_rewardInfo[k].isActive) {
                continue;
            }
            address rewardToken = _rewardInfo[k].rewardAsset;
            for(uint8 i; i<accounts.length; i++) {   
                excludedFromRewards[rewardToken][accounts[i]] = true;          
            }
        }
	}

    function multiIncludeFromRewards(address[] calldata accounts) external onlyOwner{
        for(uint8 k; k<_rewardInfo.length; k++) {
            if(!_rewardInfo[k].isActive) {
                continue;
            }
            address rewardToken = _rewardInfo[k].rewardAsset;
            for(uint8 i; i<accounts.length; i++) {   
                excludedFromRewards[rewardToken][accounts[i]] = false;          
            }
        }
	}

    function getAccountRewardsInfo(IRewardDistributor rewardsDistributor,address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return rewardsDistributor.getAccount(account);
    }

	function getAccountRewardsInfoAtIndex(IRewardDistributor rewardsDistributor,int256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return rewardsDistributor.getAccountAtIndex(index);
    }

    function singleRewardClaimByUser(address rewardToken) external whenNotPaused{
        address rewardDistributor = _rewardInfo[_rewardStoreId[rewardToken]].rewardDistributor;
        require(rewardDistributor != address(0), "RewardPool: Invalid Reward Asset");
        require(_rewardInfo[_rewardStoreId[rewardToken]].isActive, "RewardPool: Pool is not active");
		IRewardDistributor(rewardDistributor).processAccount(_msgSender(), false);
    }

    function multipleRewardClaimByUser() external whenNotPaused{
        address user = _msgSender();
        for(uint8 i; i<_rewardInfo.length; i++) {
            if(_rewardInfo[i].isActive) {               
		        IRewardDistributor(_rewardInfo[i].rewardDistributor).processAccount(user, false);
            }
        }
    }

    function getLastProcessedIndex(IRewardDistributor rewardsDistributor) external view returns(uint256) {
    	return rewardsDistributor.getLastProcessedIndex();
    }

    function getNumberOfRewardTokenHolders(IRewardDistributor rewardsDistributor) external view returns(uint256) {
        return rewardsDistributor.getNumberOfTokenHolders();
    }

    function singleRewardDistributeOnlyEnrolled(address rewardToken) external whenNotPaused {
        uint256 gas = gasForProcessing;
	    address rewardDistributor = _rewardInfo[_rewardStoreId[rewardToken]].rewardDistributor;
        require(_rewardInfo[_rewardStoreId[rewardToken]].isActive, "RewardPool: Pool is not active");
        try IRewardDistributor(rewardDistributor).process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	        emit ProcessedDistributorTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
        }
	    catch {}
    }

    function multiRewardDistributeOnlyEnrolled() external whenNotPaused {        
	    uint256 gas = gasForProcessing;
        for(uint8 i;i<_rewardInfo.length;i++) {
            if(_rewardInfo[i].isActive) {
                try IRewardDistributor(_rewardInfo[i].rewardDistributor).process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
                    emit ProcessedDistributorTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
                }
                catch {}
            }

        }
    }

     function claim() external {
		_processAccount(msg.sender, false);
    }

    function canAutoClaim(uint256 claimWait,uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address account, uint256 newBalance) external onlyOperator {
    	if(excludedFromRewards[account]) {
    		return;
    	}

    	if(newBalance >= defaultMinimumTokenBalanceForRewards) {
            _setBalance(account, newBalance);
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}

    	_processAccount(account, true);
    }

    function autoDistribute() external returns (uint256, uint256, uint256) {
        uint256 gas = gasForProcessing;
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
    			if(_processAccount(account, true)) {
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

    function _processAccount(address account, bool automatic) internal returns (bool) {
        uint256 amount = _withdrawRewardsOfUser(account);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }

    function _setBalance(address account, uint256 newBalance) internal {
        uint256 currentBalance = balanceOf(account);

        if(newBalance > currentBalance) {
        uint256 mintAmount = newBalance.sub(currentBalance);
        _mint(account, mintAmount);
        } else if(newBalance < currentBalance) {
        uint256 burnAmount = currentBalance.sub(newBalance);
        _burn(account, burnAmount);
        }
    }

    function swapBNBForReward(address rewardAsset,uint256 bnbAmount) private {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = rewardAsset;

        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: bnbAmount}(
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapAndSendReward(IRewardDistributor rewardsDistributor,address rewardAsset,uint256 bnbAmount) private{
        swapBNBForReward(rewardAsset,bnbAmount);
        uint256 rewards = IERC20(rewardAsset).balanceOf(address(this));
        bool success = IERC20(rewardAsset).transfer(address(rewardsDistributor), rewards);
		
        if (success) {
            rewardsDistributor.distributeRewards(rewards);
            emit SendRewards(bnbAmount, rewards);
        }
    }

    function getRewardsDistributor(address rewardAsset) external view returns (address) {
        uint8 slot = _rewardStoreId[rewardAsset];

        if(_rewardInfo[slot].rewardAsset == rewardAsset) {
            return _rewardInfo[slot].rewardDistributor;
        } else {
            return address(0);
        }        
    }

    function getRewardDistributorInfo(address rewardAsset) external view returns (
        address rewardDistributor,
        uint256 distributeShare,
        bool isActive
    ) {
        return (
            _rewardInfo[_rewardStoreId[rewardAsset]].rewardDistributor,
            _rewardInfo[_rewardStoreId[rewardAsset]].distributeShare,
            _rewardInfo[_rewardStoreId[rewardAsset]].isActive
        );
    }

    function rewardsDistributorContains(address rewardAsset) external view returns (bool) {
        return (_rewardStoreId[rewardAsset] != 0);
    }

    function getTotalNumberofRewardsDistributor() external view returns (uint256) {
        return _rewardInfo.length - 1;
    }

    function getPoolStatus(address rewardAsset) external view returns (bool isActive) {
        return _rewardInfo[_rewardStoreId[rewardAsset]].isActive;
    }

    function rewardsDistributorAt(uint256 index) external view returns (address) {
        return  _rewardInfo[index].rewardDistributor;
    }

    function getAllRewardsDistributor() external view returns (address[] memory rewardDistributors) {
        rewardDistributors = new address[](_rewardInfo.length);
        for(uint8 i; i<_rewardInfo.length; i++) {
            rewardDistributors[i] = _rewardInfo[i].rewardDistributor;
        }
    }
}