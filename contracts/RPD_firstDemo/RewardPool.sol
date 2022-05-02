// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./RewardDistributor.sol";
import "./interfaces/IRewardPool.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IRewardPoolManager.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardPool is Ownable, Pausable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    IUniswapV2Router02 public uniswapV2Router;
    IRewardPoolManager public rewardPoolManager;

    address public uniswapV2Pair;
    address public nativeAsset;
    address public constant deadWallet = 0x000000000000000000000000000000000000dEaD; 

    uint256 private constant distributeSharePrecision = 100;
    uint256 public gasForProcessing;

    bool private swapping;

    struct rewardStore {
        address rewardAsset;
        address rewardDistributor;
        uint256 distributeShare;
    }
    rewardStore[] private _rewardInfo;
    mapping (address => uint8) private _rewardStoreId;

    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);
    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);
    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);
    event SwapAndLiquify(uint256 tokensSwapped,uint256 ethReceived,uint256 tokensIntoLiqudity);
    event SendDividends(uint256 tokensSwapped,uint256 amount);
    event ProcessedDividendTracker(uint256 iterations,uint256 claims,uint256 lastProcessedIndex,bool indexed automatic,uint256 gas,address indexed processor);

    constructor(
        address _nativeAsset,
        address _projectAdmin
    ) {
        require(_projectAdmin != address(0), "RewardDistributor: projectAdmin can't be zero");
        _transferOwnership(_projectAdmin);  

        rewardPoolManager = IRewardPoolManager(_msgSender());                 
        nativeAsset = _nativeAsset;

        // Mainnet
        // uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        // Testnet
        uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(uniswapV2Router.WETH(),_nativeAsset);

        _rewardStoreId[deadWallet] = uint8(_rewardInfo.length);
        _rewardInfo.push(
            rewardStore({
                rewardAsset: deadWallet,
                rewardDistributor: deadWallet,
                distributeShare: 0
            })
        ); 
    }

    receive() external payable {}

    modifier onlyOperator(address account) {
        require(
            account == owner() ||
            account == address(rewardPoolManager) ||
            account == rewardPoolManager.owner(), "Not a Operator Person"
        );
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
        for(uint8 i=1;i<_rewardInfo.length;i++) {
            currenShares = currenShares.add(_rewardInfo[i].distributeShare);
        }
        return (currenShares <= distributeSharePrecision);
    }

    function createRewardDistributor(
        address _implementation,
        address _nativeAsset,
        address _rewardAsset,
        uint256 _distributeShare,
        uint256 _minimumTokenBalanceForDividends
    ) external returns (address){
        require(_msgSender() == address(rewardPoolManager), "RewardPool: Only manager can accessible");
        require(validateDistributeShare(_distributeShare), "RewardPool: DistributeShare is invalid");


        RewardDistributor newRewardsDistributor = RewardDistributor(payable(Clones.clone(_implementation)));
        newRewardsDistributor.initialize(
            _nativeAsset,
            _rewardAsset,
            _minimumTokenBalanceForDividends
        );

        _rewardStoreId[_rewardAsset] = uint8(_rewardInfo.length);
        _rewardInfo.push(
            rewardStore({
                rewardAsset: _rewardAsset,
                rewardDistributor: address(newRewardsDistributor),
                distributeShare: _distributeShare
            })
        ); 

        // exclude from receiving rewards
        newRewardsDistributor.excludeFromDividends(address(newRewardsDistributor));
        newRewardsDistributor.excludeFromDividends(address(this));
        newRewardsDistributor.excludeFromDividends(owner());
        newRewardsDistributor.excludeFromDividends(deadWallet);
        newRewardsDistributor.excludeFromDividends(address(uniswapV2Router));
        newRewardsDistributor.excludeFromDividends(address(uniswapV2Pair));

        return address(newRewardsDistributor);
    }

    function generateBuyBack(uint256 buyBackAmount) external whenNotPaused onlyOperator(_msgSender()) {
        uint256 initialBalance = address(this).balance;

        (uint256 minimumBnbBalanceForBuyback,uint256 maximumBnbBalanceForBuyback) = rewardPoolManager.buyBackRidge();

        require(initialBalance > minimumBnbBalanceForBuyback, "RewardDistributor: Required Minimum BuyBack Amount");

        buyBackAmount = buyBackAmount > maximumBnbBalanceForBuyback ? 
                            maximumBnbBalanceForBuyback : 
                            buyBackAmount > minimumBnbBalanceForBuyback ? buyBackAmount : minimumBnbBalanceForBuyback;
        
        for(uint8 i=1; i<_rewardInfo.length; i++) {
            swapAndSendReward(
                IRewardDistributor(_rewardInfo[i].rewardDistributor),
                _rewardInfo[i].rewardAsset,
                buyBackAmount.mul(_rewardInfo[i].distributeShare).div(1e2));
        }
    }

    function updateDexStore(address newRouter) public onlyOwner {
        require(newRouter != address(uniswapV2Router), "HAM: The router already has that address");
        emit UpdateUniswapV2Router(newRouter, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newRouter);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(uniswapV2Router.WETH(),nativeAsset);
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "HAM: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "HAM: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(IRewardDistributor rewardsDistributor,uint256 claimWait) external onlyOwner {
        require(claimWait >= 3600 && claimWait <= 86400, "RewardDistributor: claimWait must be updated to between 1 and 24 hours");
        rewardsDistributor.updateClaimWait(claimWait);
    }

    function getClaimWait(IRewardDistributor rewardsDistributor) external view returns(uint256) {
        return rewardsDistributor.claimWait();
    }

    function getTotalDividendsDistributed(IRewardDistributor rewardsDistributor) external view returns (uint256) {
        return rewardsDistributor.totalDividendsDistributed();
    }

    function withdrawableDividendOf(IRewardDistributor rewardsDistributor,address account) public view returns(uint256) {
    	return rewardsDistributor.withdrawableDividendOf(account);
  	}

	function excludeFromDividends(IRewardDistributor rewardsDistributor,address account) external onlyOwner{
	    rewardsDistributor.excludeFromDividends(account);
	}

    function getAccountDividendsInfo(IRewardDistributor rewardsDistributor,address account)
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

	function getAccountDividendsInfoAtIndex(IRewardDistributor rewardsDistributor,int256 index)
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

    function enrollForSingleReward(
        address rewardAsset,
        address account
    ) external whenNotPaused {
        IRewardDistributor(_rewardInfo[_rewardStoreId[rewardAsset]].rewardDistributor).setBalance(
            account, 
            IERC20(nativeAsset).balanceOf(account)
        );
    }

    function multipleAccountEnRollForSingleReward(
        address rewardAsset,
        address[] calldata accounts
    ) external whenNotPaused {     
        address dividend = _rewardInfo[_rewardStoreId[rewardAsset]].rewardDistributor;
        for(uint256 i=1; i<accounts.length; i++) {
            IRewardDistributor(dividend).setBalance(
                accounts[i],
                IERC20(nativeAsset).balanceOf(accounts[i])
            );
        }
    }

    function enrollForAllReward(
        address account
    ) external whenNotPaused {
        uint256 balance = IERC20(nativeAsset).balanceOf(account);
        for(uint8 i=1; i<_rewardInfo.length; i++) {
            IRewardDistributor(_rewardInfo[i].rewardDistributor).setBalance(account,balance);
        }        
    }

    function multipleAccountEnRollForAllReward(
        address[] calldata accounts
    ) external whenNotPaused { 
        for(uint8 i=1; i<_rewardInfo.length; i++) {
            address dividend = _rewardInfo[i].rewardDistributor;
            uint256 balance = IERC20(nativeAsset).balanceOf(accounts[i]);

            for(uint8 k; k<accounts.length; k++) {
            IRewardDistributor(dividend).setBalance(
                accounts[k],
                balance
            );
            }
        }
    }

	function processDividendTracker(IRewardDistributor rewardsDistributor,uint256 gas) external {
		(uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = rewardsDistributor.process(gas);
		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function singleRewardClaim(address rewardToken) external whenNotPaused{
        address rewardDistributor = _rewardInfo[_rewardStoreId[rewardToken]].rewardDistributor;
        require(rewardDistributor != address(0), "RewardPool: Invalid Reward Asset");
		IRewardDistributor(rewardDistributor).processAccount(_msgSender(), false);
    }

    function multipleRewardClaim() external whenNotPaused{
        address user = _msgSender();
        for(uint8 i=1; i<_rewardInfo.length; i++) {
		    IRewardDistributor(_rewardInfo[i].rewardDistributor).processAccount(user, false);
        }
    }

    function getLastProcessedIndex(IRewardDistributor rewardsDistributor) external view returns(uint256) {
    	return rewardsDistributor.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders(IRewardDistributor rewardsDistributor) external view returns(uint256) {
        return rewardsDistributor.getNumberOfTokenHolders();
    }

    function singleRewardDistribute(address rewardToken) external whenNotPaused {
        uint256 gas = gasForProcessing;
	    address rewardDistributor = _rewardInfo[_rewardStoreId[rewardToken]].rewardDistributor;
        try IRewardDistributor(rewardDistributor).process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
        }
	    catch {}
    }

    function multiDistribute() external whenNotPaused {        
	    uint256 gas = gasForProcessing;
        for(uint8 index=1;index<_rewardInfo.length;index++) {
	    	try IRewardDistributor(_rewardInfo[index].rewardDistributor).process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	}
	    	catch {}
        }
    }

    function setBalance(
        IRewardDistributor rewardsDistributor,
        address account
    ) external returns (bool){
        rewardsDistributor.setBalance(account, IERC20(nativeAsset).balanceOf(account));
        return true;
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

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        IERC20(nativeAsset).approve(address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );

    }

    function swapAndSendReward(IRewardDistributor rewardsDistributor,address rewardAsset,uint256 bnbAmount) private{
        swapBNBForReward(rewardAsset,bnbAmount);
        uint256 rewards = IERC20(rewardAsset).balanceOf(address(this));
        bool success = IERC20(rewardAsset).transfer(address(rewardsDistributor), rewards);
		
        if (success) {
            rewardsDistributor.distributeRewards(rewards);
            emit SendDividends(bnbAmount, rewards);
        }
    }

    function getRewardsDistributor(address rewardAsset) external view returns (address) {
        return _rewardInfo[_rewardStoreId[rewardAsset]].rewardDistributor;
    }

    function rewardsDistributorContains(address rewardAsset) external view returns (bool) {
        return (_rewardStoreId[rewardAsset] != 0);
    }

    function getTotalNumberofRewardsDistributor() external view returns (uint256) {
        return   _rewardInfo.length - 1;
    }

    function rewardsDistributorAt(uint256 index) external view returns (address) {
        return  _rewardInfo[index].rewardDistributor;
    }

    function getAllRewardsDistributor() external view returns (address[] memory rewardDistributors) {
        rewardDistributors = new address[](_rewardInfo.length);
        for(uint8 i=1; i<_rewardInfo.length; i++) {
            rewardDistributors[i] = _rewardInfo[i].rewardDistributor;
        }
    }
}