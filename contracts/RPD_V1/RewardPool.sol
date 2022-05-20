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
import "./library/SafeMathUint.sol";
import "./RewardDistributor.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract RewardPool is Initializable, ERC20Upgradeable, PausableUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;   
    using SafeMathInt for int256; 
    using SafeMathUint for uint256;
    using IterableMapping for IterableMapping.Map;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    
    address public nativeAsset;
    address public constant deadWallet = 0x000000000000000000000000000000000000dEaD; 
    uint256 internal constant magnitude = 2**128;
    uint256 private constant distributeSharePrecision = 100;
    uint256 public buyBackClaimWait;
    uint256 public lastBuyBackTimestamp;
    uint256 public defaultMinimumTokenBalanceForRewards;
    uint256 private minimumBnbBalanceForBuyback;
    uint256 private maximumBnbBalanceForBuyback;
    uint256 public gasForProcessing;
    uint8 public totalRewardDistributor;

    bool private swapping;

    struct rewardStore {
        address rewardDistributor;
        uint256 distributeShare;
        uint256 claimWait;
        uint256 lastProcessedIndex;
        uint256 minimumTokenBalanceForRewards;
        uint256 magnifiedRewardPerShare;
        uint256 totalRewardsDistributed;
        bool isActive;
    }

    struct distributeStore {
        uint256 lastClaimTimes;
        int256 magnifiedRewardCorrections;
        uint256 withdrawnRewards;
    }

    IterableMapping.Map private tokenHoldersMap;
    mapping (address => rewardStore) private _rewardInfo;
    mapping (uint8 => address) private _rewardAsset; 
    mapping (bytes32 => distributeStore) private _distributeInfo; 
    mapping (address => bool) private excludedFromRewards;

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);
    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);
    event SwapAndLiquify(uint256 tokensSwapped,uint256 ethReceived,uint256 tokensIntoLiqudity);
    event SendRewards(uint256 tokensSwapped,uint256 amount);
    event Claim(address indexed account, uint256 amount, bool indexed automatic); 
    event RewardsDistributed(address indexed from,uint256 weiAmount);
    event RewardWithdrawn(address indexed to,uint256 weiAmount,bool status);
    event ProcessedDistributorTracker(uint256 iterations,uint256 claims,uint256 lastProcessedIndex,bool indexed automatic,uint256 gas,address indexed processor);

    receive() external payable {}

    function initialize(address _nativeAsset) initializer public {
        __ERC20_init("Gold_Reward_Tracker", "GRT");
        __Pausable_init();
        __Ownable_init();

        nativeAsset = _nativeAsset;
        buyBackClaimWait = 86400;
        minimumBnbBalanceForBuyback = 10;
        maximumBnbBalanceForBuyback = 80;
        defaultMinimumTokenBalanceForRewards = 100 * (10 ** 18);
        gasForProcessing = 300000;

        // uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        // Testnet
        uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(uniswapV2Router.WETH(),_nativeAsset);

        excludedFromRewards[(address(this))] = true;
        excludedFromRewards[owner()] = true;
        excludedFromRewards[deadWallet] = true;
        excludedFromRewards[address(uniswapV2Router)] = true;
        excludedFromRewards[address(uniswapV2Pair)] = true;
    }

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

    function _transfer(address, address, uint256) internal override pure {
        require(false, "No transfers allowed");
    }

    function setDefaultMinimumTokenBalanceForRewards(uint256 newValue) external onlyOwner {
        defaultMinimumTokenBalanceForRewards = newValue;
    }

    function setMinimumTokenBalanceForRewards(address reward,uint256 newValue) external onlyOwner {
        _rewardInfo[reward].minimumTokenBalanceForRewards = newValue;
    }

    function setMultipleMinimumTokenBalanceForRewards(
        address[] memory rewards,uint256[] memory newValues
    ) external onlyOwner {
        require(rewards.length == newValues.length, "RewardPool: Invalid Param Passed");

        for(uint8 i;i<rewards.length; i++){
            _rewardInfo[rewards[i]].minimumTokenBalanceForRewards = newValues[i];
        }
    }

    function validateDistributeShare(uint256 newShare) public view returns (bool) {
        uint256 currenShares = newShare;
        for(uint8 i;i<totalRewardDistributor;i++) {
            currenShares = currenShares.add(_rewardInfo[_rewardAsset[i]].distributeShare);
        }
        return (currenShares <= distributeSharePrecision);
    }

    function setDistributeShare(address rewardToken,uint256 newShare) external onlyOwner {
        require(_rewardInfo[rewardToken].isActive, "RewardPool: Reward Token is invalid");
        _rewardInfo[rewardToken].distributeShare = newShare;
        require(validateDistributeShare(0), "RewardPool: DistributeShare is invalid");
    }

    function setBuyBackClaimWait(uint256 newClaimWait) external onlyOwner {
        buyBackClaimWait = newClaimWait;
    }

    function createRewardDistributor(
        address _rewardToken,
        uint256 _distributeShare,
        uint256 _claimWait,
        uint256 _minimumTokenBalanceForRewards
    ) external onlyOwner returns (address){
        require(validateDistributeShare(_distributeShare), "RewardPool: DistributeShare is invalid");
        require(_rewardInfo[_rewardToken].rewardDistributor == address(0), "RewardPool: RewardDistributor is already exist");
        require(totalRewardDistributor < 9, "RewardPool: Reward token limit exceed");

        RewardDistributor newRewardsDistributor = new RewardDistributor(_rewardToken);

        _rewardAsset[totalRewardDistributor] = _rewardToken;
        _rewardInfo[_rewardToken] = (
            rewardStore({
                rewardDistributor: address(newRewardsDistributor),
                distributeShare: _distributeShare,
                claimWait: _claimWait,
                lastProcessedIndex : 0,
                minimumTokenBalanceForRewards : _minimumTokenBalanceForRewards,
                magnifiedRewardPerShare : 0,
                totalRewardsDistributed : 0,
                isActive: true
            })
        ); 
        totalRewardDistributor++;

        // exclude from receiving rewards
        excludedFromRewards[(address(newRewardsDistributor))] = true;

        return address(newRewardsDistributor);
    }

    function updateRewardDistributor(address rewardToken,address newRewardsDistributor) external onlyOwner {
        require(_rewardInfo[rewardToken].rewardDistributor != address(0), "RewardPool: Reward is not exist");

        _rewardInfo[rewardToken].rewardDistributor = newRewardsDistributor;
        excludedFromRewards[(address(newRewardsDistributor))] = true;
    }

    function setRewardActiveStatus(address rewardAsset,bool status) external onlyOwner {
        _rewardInfo[rewardAsset].isActive = status;
    }

    function getBuyBackLimit(uint256 currentBalance) internal view returns (uint256,uint256) {
        return (currentBalance.mul(minimumBnbBalanceForBuyback).div(1e2),
                currentBalance.mul(maximumBnbBalanceForBuyback).div(1e2));
    }

    function generateBuyBackForOpen() external whenNotPaused {
        require(lastBuyBackTimestamp.add(buyBackClaimWait) < block.timestamp, "RewardPool: buybackclaim still not over");

        uint256 initialBalance = address(this).balance;

        (uint256 _minimumBnbBalanceForBuyback,) = getBuyBackLimit(initialBalance);

        require(initialBalance >= _minimumBnbBalanceForBuyback, "RewardPool: Required Minimum BuyBack Amount");
        lastBuyBackTimestamp = block.timestamp;

        for(uint8 i; i<totalRewardDistributor; i++) {
            address rewardToken = _rewardAsset[i];
            if(_rewardInfo[rewardToken].isActive) {                
                swapAndSendReward(
                    rewardToken,
                    _minimumBnbBalanceForBuyback.mul(_rewardInfo[rewardToken].distributeShare).div(1e2)
                );
            }
        }
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
        
        for(uint8 i; i<totalRewardDistributor; i++) {
            address rewardToken = _rewardAsset[i];
            if(_rewardInfo[rewardToken].isActive) {                
                swapAndSendReward(
                    rewardToken,
                    buyBackAmount.mul(_rewardInfo[rewardToken].distributeShare).div(1e2)
                );
            }
        }
    }

    function updateDexStore(address newRouter) public onlyOwner {
        emit UpdateUniswapV2Router(newRouter, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newRouter);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(uniswapV2Router.WETH(),nativeAsset);

        excludedFromRewards[address(uniswapV2Router)] = true;
        excludedFromRewards[address(uniswapV2Pair)] = true;
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue != gasForProcessing, "RewardPool: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(address rewardToken,uint256 claimWait) external onlyOwner {
        _rewardInfo[rewardToken].claimWait = claimWait;
    }

    function updateClaimWaitForAllDistributor(
        uint256 claimWait
    )  external onlyOwner {
        for(uint8 i; i<totalRewardDistributor; i++) {
            if(_rewardInfo[_rewardAsset[i]].isActive) {  
                _rewardInfo[_rewardAsset[i]].claimWait = claimWait;
            }
        }
    }

    function getClaimWait(address rewardToken) external view returns(uint256) {
        return _rewardInfo[rewardToken].claimWait;        
    }

    function getTotalRewardsDistribute(address reward) external view returns (uint256) {
        return IRewardDistributor(_rewardInfo[reward].rewardDistributor).totalRewardsDistributed();
    }

	function excludeFromRewards(address account) external onlyOwner{
        excludedFromRewards[account] = true;
	}

    function includeFromRewards(address account) external onlyOwner{
        excludedFromRewards[account] = false;
	}

    function multiExcludeFromRewards(address[] calldata accounts) external onlyOwner{
        for(uint8 i; i<accounts.length; i++) {   
             excludedFromRewards[accounts[i]] = true;       
        }
	}

    function multiIncludeFromRewards(address[] calldata accounts) external onlyOwner{
        for(uint8 i; i<accounts.length; i++) {                         
            excludedFromRewards[accounts[i]] = false;  
        }
	}
    	
    function getAccount(address reward,address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > _rewardInfo[reward].lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(_rewardInfo[reward].lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > _rewardInfo[reward].lastProcessedIndex ? 
                            tokenHoldersMap.keys.length.sub(_rewardInfo[reward].lastProcessedIndex) : 0;
                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }

        bytes32 slot = getDistributeSlot(reward,account);
        withdrawableDividends = withdrawableRewardOf(reward,account);
        totalDividends = accumulativeRewardOf(reward,account,_distributeInfo[slot].magnifiedRewardCorrections);

        lastClaimTime = _distributeInfo[slot].lastClaimTimes;

        nextClaimTime = lastClaimTime > 0 ? lastClaimTime.add(_rewardInfo[reward].claimWait) : 0;
        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ? nextClaimTime.sub(block.timestamp) : 0;
    }

    function accumulativeRewardOf(address reward,address user,int256 magnifiedRewardCorrections) internal view returns (uint256) {
        return (
        (_rewardInfo[reward].magnifiedRewardPerShare.mul(balanceOf(user)).toInt256Safe()
             .add(magnifiedRewardCorrections).toUint256Safe() / magnitude)
        );
    }

    function getAccountRewardsInfo(address reward,address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return getAccount(reward,account);
    }

	function getAccountRewardsInfoAtIndex(address reward,uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return getAccountAtIndex(reward,index);
    }

    function getAccountAtIndex(address reward,uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(reward,account);
    }


    function singleRewardClaimByUser(address rewardToken) external whenNotPaused{
        require(_rewardInfo[rewardToken].isActive, "RewardPool: Pool is not active");
        _withdrawRewardsOfUser(rewardToken,_msgSender(),false);
    }

    function multipleRewardClaimByUser() external whenNotPaused{
        address user = _msgSender();
        for(uint8 i;i<totalRewardDistributor;i++) {
            if(_rewardInfo[_rewardAsset[i]].isActive) { 
                _withdrawRewardsOfUser(_rewardAsset[i],user,false);
            }
        }  
    }

    function getLastProcessedIndex(address rewardToken) external view returns(uint256) {
    	return _rewardInfo[rewardToken].lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
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
    		tokenHoldersMap.set(account, newBalance);
            _setBalance(account, newBalance);
    	}
    	else {
    		tokenHoldersMap.remove(account);
            _setBalance(account, 0);
    	}
    }

    function autoDistribute(address rewardToken) external returns (uint256, uint256, uint256) {
        uint256 gas = gasForProcessing;
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, _rewardInfo[rewardToken].lastProcessedIndex);
    	}

    	uint256 _lastProcessedIndex = _rewardInfo[rewardToken].lastProcessedIndex;

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
    		
    		if(_withdrawRewardsOfUser(rewardToken,account, true)) {
    				claims++;
    		}
    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
    		}

    		gasLeft = newGasLeft;
    	}

    	_rewardInfo[rewardToken].lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, _rewardInfo[rewardToken].lastProcessedIndex);
    }

    function _setBalance(address account, uint256 newBalance) internal {
        uint256 currentBalance = balanceOf(account);

        if(newBalance > currentBalance) {
            uint256 mintAmount = newBalance.sub(currentBalance);
            _mint(account, mintAmount);
            _setMintBalance(account,mintAmount);
        } else if(newBalance < currentBalance) {
            uint256 burnAmount = currentBalance.sub(newBalance);
            _burn(account, burnAmount);
            _setBurnBalance(account,burnAmount);
        }
    }

    function _setMintBalance(address account,uint256 mintAmount) internal {
        for(uint8 i;i<totalRewardDistributor;i++) {
            bytes32 slot = getDistributeSlot(_rewardAsset[i],account);
            _distributeInfo[slot].magnifiedRewardCorrections = _distributeInfo[slot].magnifiedRewardCorrections.sub(
                (_rewardInfo[_rewardAsset[i]].magnifiedRewardPerShare.mul(mintAmount)).toInt256Safe()
            );
        }
    }

    function _setBurnBalance(address account,uint256 burnAmount) internal {
        for(uint8 i;i<totalRewardDistributor;i++) {
            bytes32 slot = getDistributeSlot(_rewardAsset[i],account);
            _distributeInfo[slot].magnifiedRewardCorrections = _distributeInfo[slot].magnifiedRewardCorrections.add(
                (_rewardInfo[_rewardAsset[i]].magnifiedRewardPerShare.mul(burnAmount)).toInt256Safe()
            );
        }
    }

    function _withdrawRewardsOfUser(address reward,address account,bool automatic) internal returns (bool) {
        bytes32 slot = getDistributeSlot(reward,account);
        if(!(canAutoClaim(_rewardInfo[reward].claimWait,_distributeInfo[slot].lastClaimTimes)) ||
            _rewardInfo[reward].minimumTokenBalanceForRewards > balanceOf(account)) {
            return false;
        }
        uint256 _withdrawableReward = _withdrawableRewardOf(
                                        _rewardInfo[reward].magnifiedRewardPerShare,
                                        slot,
                                        balanceOf(account)
                                        );
        if (_withdrawableReward > 0) {
            _distributeInfo[slot].withdrawnRewards = _distributeInfo[slot].withdrawnRewards.add(_withdrawableReward);

            bool success = IRewardDistributor(_rewardInfo[reward].rewardDistributor).distributeReward(account,_withdrawableReward);
            emit RewardWithdrawn(account, _withdrawableReward,success);

            if(!success) {
                _distributeInfo[slot].withdrawnRewards =  _distributeInfo[slot].withdrawnRewards.sub(_withdrawableReward);
                return false;
            }

            _distributeInfo[slot].lastClaimTimes = block.timestamp;
            emit Claim(account, _withdrawableReward, automatic);

            return true;
        }

        return false;
    }
    
    function withdrawableRewardOf(address reward,address account) public view returns(uint256) {
    	return _withdrawableRewardOf(
            _rewardInfo[reward].magnifiedRewardPerShare,
            getDistributeSlot(reward,account),
            balanceOf(account));
  	}

    function rewardOf(address reward,address account) external view returns(uint256) {
        return _withdrawableRewardOf(
            _rewardInfo[reward].magnifiedRewardPerShare,
            getDistributeSlot(reward,account),
            balanceOf(account));
    }

    function _withdrawableRewardOf(uint256 magnifiedRewardPerShare,bytes32 slot,uint256 balance) internal view returns(uint256) {
        return (magnifiedRewardPerShare.mul(balance).toInt256Safe()
        .add(_distributeInfo[slot].magnifiedRewardCorrections).toUint256Safe() / magnitude
        ).sub(_distributeInfo[slot].withdrawnRewards);
    }

    function withdrawnRewardOf(address reward,address user) external view returns(uint256) {
        return _distributeInfo[getDistributeSlot(reward,user)].withdrawnRewards;
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

    function swapAndSendReward(address rewardAsset,uint256 bnbAmount) private{
        swapBNBForReward(rewardAsset,bnbAmount);
        uint256 rewards = IERC20(rewardAsset).balanceOf(address(this));
        bool success = IERC20(rewardAsset).transfer(_rewardInfo[rewardAsset].rewardDistributor, rewards);
		
        if (success) {
            distributeRewards(rewardAsset,rewards);
            emit SendRewards(bnbAmount, rewards);
        }
    }

    function distributeRewards(address reward,uint256 amount) internal{
        require(totalSupply() > 0, "Rewards: Supply is Zero");

        if (amount > 0) {
        _rewardInfo[reward].magnifiedRewardPerShare = _rewardInfo[reward].magnifiedRewardPerShare.add(
            (amount).mul(magnitude) / totalSupply()
        );
        emit RewardsDistributed(msg.sender, amount);

        _rewardInfo[reward].totalRewardsDistributed = _rewardInfo[reward].totalRewardsDistributed.add(amount);      
        }
    }

    function getRewardsDistributor(address rewardAsset) external view returns (address) {
        return _rewardInfo[rewardAsset].rewardDistributor;     
    }

    function getRewardDistributorInfo(address rewardAsset) external view returns (
        address rewardDistributor,
        uint256 distributeShare,
        bool isActive
    ) {
        return (
            _rewardInfo[rewardAsset].rewardDistributor,
            _rewardInfo[rewardAsset].distributeShare,
            _rewardInfo[rewardAsset].isActive
        );
    }

    function getTotalNumberofRewardsDistributor() external view returns (uint256) {
        return totalRewardDistributor;
    }

    function getPoolStatus(address rewardAsset) external view returns (bool isActive) {
        return _rewardInfo[rewardAsset].isActive;
    }

    function rewardsDistributorAt(uint8 index) external view returns (address) {
        return  _rewardInfo[_rewardAsset[index]].rewardDistributor;
    }

    function getAllRewardsDistributor() external view returns (address[] memory rewardDistributors) {
        rewardDistributors = new address[](totalRewardDistributor);
        for(uint8 i; i<totalRewardDistributor; i++) {
            rewardDistributors[i] = _rewardInfo[_rewardAsset[i]].rewardDistributor;
        }
    }

    function getDistributeSlot(address rewardToken,address user) internal pure returns (bytes32) {
        return (
            keccak256(abi.encode(rewardToken,user))
        );
    }

    function getMinmumAndMaximumBuyback() external view returns (uint256 _minimumBnbBalanceForBuyback,uint256 _maximumBnbBalanceForBuyback) {
        return (getBuyBackLimit(address(this).balance));
    }

    function rewardInfo(address rewardToken) external view returns (
        address rewardDistributor,
        uint256 distributeShare,
        uint256 claimWait,
        uint256 lastProcessedIndex,
        uint256 minimumTokenBalanceForRewards,
        uint256 magnifiedRewardPerShare,
        uint256 totalRewardsDistributed,
        bool isActive
    ) {
        rewardStore memory store = _rewardInfo[rewardToken];
        return (
            store.rewardDistributor,
            store.distributeShare,
            store.claimWait,
            store.lastProcessedIndex,
            store.minimumTokenBalanceForRewards,
            store.magnifiedRewardPerShare,
            store.totalRewardsDistributed,
            store.isActive
        );
    }

    function distributeInfo(address reward,address user) external view returns (
        uint256 lastClaimTimes,
        int256 magnifiedRewardCorrections,
        uint256 withdrawnRewards
    ) {
        bytes32 slot = getDistributeSlot(reward,user);
        return (
            _distributeInfo[slot].lastClaimTimes,
            _distributeInfo[slot].magnifiedRewardCorrections,
            _distributeInfo[slot].withdrawnRewards
        );
    }

    function bnbBalance() external view returns (uint256) {
        return (address(this).balance);
    }
}