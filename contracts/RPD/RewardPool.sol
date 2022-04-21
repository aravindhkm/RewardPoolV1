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
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract RewardPool is OwnableUpgradeable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    IUniswapV2Router02 public uniswapV2Router;
    IRewardPoolManager public rewardPoolManager;

    address public uniswapV2Pair;
    address public nativeAsset;
    address public constant deadWallet = 0x000000000000000000000000000000000000dEaD;

    uint256 public gasForProcessing;
    uint256 public rewardShareAmount;

    bool private swapping;

    EnumerableSet.AddressSet private _rewardAssets;
    mapping (address => address) private _dividendTrackerInfo;

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

        rewardShareAmount = 10000 * (10 ** IERC20Metadata(_nativeAsset).decimals());

        // Mainnet
        // uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        // Testnet
        uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).getPair(uniswapV2Router.WETH(),_nativeAsset);
    }

    receive() external payable {}

    function createRewardDistributor(
        address _implementation,
        address _nativeAsset,
        address _rewardAsset,
        uint256 _minimumTokenBalanceForDividends
    ) external returns (address){
        require(_msgSender() == address(rewardPoolManager), "RewardPool: Only manager can accessible");

        RewardDistributor newDividend = RewardDistributor(payable(Clones.clone(_implementation)));
        newDividend.initialize(
            _nativeAsset,
            _rewardAsset,
            _minimumTokenBalanceForDividends
        ); 

        _rewardAssets.add(_rewardAsset);
        _dividendTrackerInfo[_rewardAsset] = address(newDividend);

        // exclude from receiving dividends
        newDividend.excludeFromDividends(address(newDividend));
        newDividend.excludeFromDividends(address(this));
        newDividend.excludeFromDividends(owner());
        newDividend.excludeFromDividends(deadWallet);
        newDividend.excludeFromDividends(address(uniswapV2Router));
        newDividend.excludeFromDividends(address(uniswapV2Pair));

        return address(newDividend);
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

    function updateClaimWait(IRewardDistributor dividendTracker,uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait(IRewardDistributor dividendTracker) external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed(IRewardDistributor dividendTracker) external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function withdrawableDividendOf(IRewardDistributor dividendTracker,address account) public view returns(uint256) {
    	return dividendTracker.withdrawableDividendOf(account);
  	}

	function dividendTokenBalanceOf(IRewardDistributor dividendTracker,address account) public view returns (uint256) {
		return dividendTracker.balanceOf(account);
	}

	function excludeFromDividends(IRewardDistributor dividendTracker,address account) external onlyOwner{
	    dividendTracker.excludeFromDividends(account);
	}

    function getAccountDividendsInfo(IRewardDistributor dividendTracker,address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

	function getAccountDividendsInfoAtIndex(IRewardDistributor dividendTracker,int256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return dividendTracker.getAccountAtIndex(index);
    }

	function processDividendTracker(IRewardDistributor dividendTracker,uint256 gas) external {
		(uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim(IRewardDistributor dividendTracker) external {
		dividendTracker.processAccount(msg.sender, false);
    }

    function getLastProcessedIndex(IRewardDistributor dividendTracker) external view returns(uint256) {
    	return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders(IRewardDistributor dividendTracker) external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function _distribute(
        IRewardDistributor dividendTracker,
        address account
    ) internal  {
        require(account != address(0), "ERC20: transfer from the zero address");

		uint256 contractTokenBalance = IERC20(nativeAsset).balanceOf(address(this));

        bool canSwap = contractTokenBalance >= rewardShareAmount;

        if( canSwap &&
            !swapping &&
            account != owner() 
        ) {
            swapping = true;

            address rewardAsset;
            swapAndSendDividends(dividendTracker,rewardAsset,rewardShareAmount);

            swapping = false;
        }

        try dividendTracker.setBalance(account, IERC20(nativeAsset).balanceOf(account)) {} catch {}

        if(!swapping) {
	    	uint256 gas = gasForProcessing;

	    	try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	}
	    	catch {}
        }
    }

    function setBalance(
        IRewardDistributor dividendTracker,
        address account
    ) external returns (bool){
        dividendTracker.setBalance(account, IERC20(nativeAsset).balanceOf(account));
        return true;
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        uint256 initialBalance = address(this).balance;
		
        swapTokensForEth(half);
		
        uint256 newBalance = address(this).balance.sub(initialBalance);
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }


    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        IERC20(nativeAsset).approve(address(uniswapV2Router), tokenAmount);
		
        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

    }

    function swapTokensForReward(address rewardAsset,uint256 tokenAmount) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = rewardAsset;

        IERC20(nativeAsset).approve(address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
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

    function swapAndSendDividends(IRewardDistributor dividendTracker,address rewardAsset,uint256 tokens) private{
        swapTokensForReward(rewardAsset,tokens);
        uint256 dividends = IERC20(rewardAsset).balanceOf(address(this));
        bool success = IERC20(rewardAsset).transfer(address(this), dividends);
		
        if (success) {
            dividendTracker.distributeDividends(dividends);
            emit SendDividends(tokens, dividends);
        }
    }

    function dividendTrackerInfo(address rewardAsset) external view returns (address) {
        return _dividendTrackerInfo[rewardAsset];
    }

    function rewardContains(address rewardAsset) external view returns (bool) {
        return _rewardAssets.contains(rewardAsset);
    }

    function rewardLength() external view returns (uint256) {
        return  _rewardAssets.length();
    }

    function rewardAt(uint256 index) external view returns (address) {
        return  _rewardAssets.at(index);
    }

    function rewardValues() external view returns (address[] memory) {
        return  _rewardAssets.values();
    }
}