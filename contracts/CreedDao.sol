// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract CreedDao is ERC20, Ownable {
    using SafeMath for uint256;

    address public uniswapV2Router;
    address public uniswapV2Factory;
    address public uniswapV2Pair;
    address public weth;
    address public marketingWalletAddress;
    address public treasuryWalletAddress;

    uint256 public buyFee = 5;
    uint256 public sellFee = 5;
    uint256 public liquidityFee = 1;
    uint256 public stakingFee = 1;
    uint256 public treasuryFee = 2;
    uint256 public marketingFee = 2;
    uint256 public taxFees = liquidityFee.add(stakingFee).add(treasuryFee).add(marketingFee);
    uint256 public swapTokensAtAmount = 200000 * (1e18);

    bool private swapping;

    mapping (address => bool) private _isExcludedFromFees;
    mapping(address => bool) public isBlacklisted;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event ExcludeFromFees(
        address indexed account, 
        bool isExcluded
    );

    constructor(address _marketingWalletAddress,address _treasuryWalletAddress) ERC20("CreedDao", "Creed") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());

        marketingWalletAddress = _marketingWalletAddress;
        treasuryWalletAddress = _treasuryWalletAddress;

        // mainnet
        // uniswapV2Factory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
        // weth = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

        // testnet
        uniswapV2Factory = 0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc;
        weth = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;

        uniswapV2Pair = IUniswapV2Factory(uniswapV2Factory).createPair(address(this),weth);

        _mint(msg.sender, 100000000 * (10**18));

        // feeExemption
        _isExcludedFromFees[0x000000000000000000000000000000000000dEaD] = true;
        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[marketingWalletAddress] = true;
        _isExcludedFromFees[treasuryWalletAddress] = true;
        _isExcludedFromFees[address(this)] = true;
    }

    receive() external payable {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function setMarketFee(uint256 newFee) public onlyOwner {
        marketingFee = newFee;
        taxFees = liquidityFee.add(stakingFee).add(treasuryFee).add(marketingFee);
        require(taxFees.add(buyFee).add(sellFee) <= 25, "CreedDao: Total fee is over 15%");
    }

    function setTreasuryFee(uint256 newFee) public onlyOwner {
        treasuryFee = newFee;
        taxFees = liquidityFee.add(stakingFee).add(treasuryFee).add(marketingFee);
        require(taxFees.add(buyFee).add(sellFee) <= 25, "CreedDao: Total fee is over 15%");
    }
    
    function setStakingFee(uint256 newFee) public onlyOwner {
        stakingFee = newFee;
        taxFees = liquidityFee.add(stakingFee).add(treasuryFee).add(marketingFee);
        require(taxFees.add(buyFee).add(sellFee) <= 25, "CreedDao: Total fee is over 15%");
    }

    function setLiquidityFee(uint256 newFee) public onlyOwner {
        liquidityFee = newFee;
        taxFees = liquidityFee.add(stakingFee).add(treasuryFee).add(marketingFee);
        require(taxFees.add(buyFee).add(sellFee) <= 25, "CreedDao: Total fee is over 15%");
    }

    function setBuySellFee(uint256 newBuyFee,uint256 newSellFee) public onlyOwner {
        buyFee = newBuyFee;
        sellFee = newSellFee;
        require(taxFees.add(buyFee).add(sellFee) <= 25, "CreedDao: Total fee is over 15%");
    }

    function setBlacklistAddress(address _address, bool _blacklisted) external onlyOwner {
        isBlacklisted[_address] = _blacklisted;
    }

    function setMarketingWallet(address wallet) external onlyOwner{
        require(wallet != address(0), "CreedDao: newAddress is a zero address");
        marketingWalletAddress = wallet;
    }

    function setTreasuryWallet(address wallet) external onlyOwner{
        require(wallet != address(0), "CreedDao: newAddress is a zero address");
        treasuryWalletAddress = wallet;
    }

    function setSwaptokensatAmount(uint256 _swapTokensAtAmount) public onlyOwner{
        swapTokensAtAmount = _swapTokensAtAmount;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20) {
        require(!isBlacklisted[from], "CreedDao: The from address is Blacklisted.");
        require(!isBlacklisted[to], "CreedDao: The to address is Blacklisted.");

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if( canSwap &&
            !swapping &&
            from != owner() &&
            to != owner()
        ) {
            swapping = true;

            uint256 marketingTokens = contractTokenBalance.mul(marketingFee).div(1e2);
            swapTokensForBNB(marketingTokens, marketingWalletAddress);

            uint256 tresuryTokens = contractTokenBalance.mul(treasuryFee).div(1e2);
            swapTokensForBNB(tresuryTokens, treasuryWalletAddress);

            uint256 swapTokens = contractTokenBalance.sub(marketingTokens).sub(tresuryTokens);
            swapAndLiquify(swapTokens);

            swapping = false;
        }

        bool takeFee = !swapping;
        uint256 totalFees = taxFees.add(getBuySellFee(from,to));

        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if(takeFee) {
        	uint256 fees = amount.mul(totalFees).div(100);
        	amount = amount.sub(fees);
            super._transfer(from, address(this), fees);
        }

        return super._transfer(from,to, amount);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "CreedDao: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function swapTokensForBNB(uint256 tokenAmount,address to) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = weth;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        IUniswapV2Router02(uniswapV2Router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            to,
            block.timestamp
        );
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        uint256 initialBalance = address(this).balance;
		
        swapTokensForBNB(half,address(this));
		
        uint256 newBalance = address(this).balance - initialBalance;
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        IUniswapV2Router02(uniswapV2Router).addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, 
            0, 
            owner(),
            block.timestamp
        );
    }

    function getBuySellFee(address sender,address receiver) internal view returns (uint256) {
        if(sender == uniswapV2Pair){
            return buyFee;
        }else if(receiver == uniswapV2Pair){
            return sellFee;
        }else {        
            return 0;
        }
    }

    function isExcludedFromFees(address account) external view returns(bool) {
        return _isExcludedFromFees[account];
    }

}