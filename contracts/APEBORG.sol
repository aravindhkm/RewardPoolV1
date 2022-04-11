/** 

Telegram Portal: https://t.me/ShiborgInu
Website: https://shiborgtoken.com/ 
Twitter: https://twitter.com/ShiborgToken
Facebook: https://www.facebook.com/ShiborgToken
*/
// SPDX-License-Identifier: MIT
/// @custom:security-contact contact@shiborgtoken.com
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./TokenRecover.sol";

contract APEBORG is Context, IERC20, Ownable, TokenRecover {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;

    EnumerableSet.AddressSet private _isExcluded;
    
    mapping(address => bool) private _isBlackListedBot;

    mapping(address => bool) private _isExcludedFromLimit;
    address[] private _blackListedBots;

    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = 1000000000 * 10**6 * 10**9;    
    uint256 private _rTotal = (MAX -(MAX % _tTotal));
    uint256 private _tFeeTotal;

    address payable public _devwallet =
        payable(address(0x44d09f1495F4ab34F2C198cAb3FB63E9Fe9F82Dd));
    address private _donationAddress = 0x1AB28f05A083a8C9071700A8e66dA5CeEc588C4A;

    string private _name = "APEBORG";
    string private _symbol = "APEBORG";
    uint8 private _decimals = 9;

    struct FeeStore {
        uint8 feeForTaxLiquidity;
        uint8 feeForDonationMarketDev;
        uint8 devFeeForView;
    }

    struct tFeeStore {
        uint256 tAmount;
        uint256 tFee;
        uint256 tLiquidity;
        uint256 tWallet;
        uint256 tDonation;
        uint256 tTransferAmount;
    }

    struct rFeeStore {
        uint256 rAmount;
        uint256 rFee;
        uint256 rLiquidity;
        uint256 rWallet;
        uint256 rDonation;
        uint256 rTransferAmount;
    }

    FeeStore private buyFee;
    FeeStore private sellFee;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;

    uint256 public _maxTxAmount = 1000000000 * 10**6 * 10**9;
    uint256 private numTokensSellToAddToLiquidity = 500000 * 10**6 * 10**9;
    uint256 public _maxWalletSize = 1 * 10**13 * 10**9;

    event botAddedToBlacklist(address account);
    event botRemovedFromBlacklist(address account);
    
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(address _router) {
        _rOwned[_msgSender()] = _rTotal;

        buyFee.feeForTaxLiquidity = 2 + (8 << 4);
        buyFee.feeForDonationMarketDev = 0;
        buyFee.devFeeForView = 0;

        sellFee.feeForTaxLiquidity = 2 + (8 << 4);
        sellFee.feeForDonationMarketDev = 0;
        sellFee.devFeeForView = 0;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_router);
        // Create a uniswap pair for this new token        
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

        // exclude owner, dev wallet, and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_devwallet] = true;

        _isExcludedFromLimit[_devwallet] = true;             
        _isExcludedFromLimit[owner()] = true;
        _isExcludedFromLimit[address(this)] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function setRouterAddress(address payable newRouter) external onlyOwner {
        require(newRouter != address(uniswapV2Router), "The router already has that address");
            IUniswapV2Router02 _newUniswapRouter = IUniswapV2Router02(newRouter);
            uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), _newUniswapRouter.WETH());
            uniswapV2Router = _newUniswapRouter;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded.contains(account)) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] +  (addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded.contains(account);
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function donationAddress() public view returns (address) {
        return _donationAddress;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(
            !_isExcluded.contains(sender),
            "Excluded addresses cannot call this function"
        );

        uint256 currentRate = _getRate();
        tFeeStore memory tFees = calculateTFees(tAmount,0);        
        rFeeStore memory rFees = calculateRFees(tFees,currentRate);

        _rOwned[sender] = _rOwned[sender] - (rFees.rAmount);
        _rTotal = _rTotal - (rFees.rAmount);
        _tFeeTotal = _tFeeTotal +  (tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");

        uint256 currentRate = _getRate();
        tFeeStore memory tFees = calculateTFees(tAmount,0);        
        rFeeStore memory rFees = calculateRFees(tFees,currentRate);

        if (!deductTransferFee) {
            return rFees.rAmount;
        } else {
            return rFees.rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount /  (currentRate);
    }

    function updateDevWallet(address payable newAddress) external onlyOwner {
        _devwallet = newAddress;
    }

    function addBotToBlacklist(address account) external onlyOwner {
        require(
            account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
            "We cannot blacklist UniSwap router"
        );
        require(!_isBlackListedBot[account], "Account is already blacklisted");
        _isBlackListedBot[account] = true;
        _blackListedBots.push(account);

        emit botAddedToBlacklist(account);
    }

        function isBotBlacklisted(address account) public view returns(bool) {
            return _isBlackListedBot[account];
    }

    function removeBotFromBlacklist(address account) external onlyOwner {
        require(_isBlackListedBot[account], "Account is not blacklisted");
        for (uint256 i = 0; i < _blackListedBots.length; i++) {
            if (_blackListedBots[i] == account) {
                _blackListedBots[i] = _blackListedBots[
                    _blackListedBots.length -1
                ];
                _isBlackListedBot[account] = false;
                _blackListedBots.pop();
                break;
            }
        }
        emit botRemovedFromBlacklist(account);
    }

    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded.contains(account), "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded.add(account);
    }

    function includeInReward(address account) external onlyOwner {
        require(_isExcluded.contains(account), "Account is not excluded");
        _tOwned[account] = 0;
        _isExcluded.remove(account);
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function excludeFromLimit(address account) public onlyOwner {
        _isExcludedFromLimit[account] = true;
    }

    function includeInLimit(address account) public onlyOwner {
        _isExcludedFromLimit[account] = false;
    }

    function currentBuyFee() public view returns (
        uint8 tax,
        uint8 liquidity,
        uint8 marketing,
        uint8 dev,
        uint8 donation
    ) {
        tax = buyFee.feeForTaxLiquidity % 16;
        liquidity = buyFee.feeForTaxLiquidity >> 4;
        marketing = (buyFee.feeForDonationMarketDev >> 4) -buyFee.devFeeForView;
        dev = buyFee.devFeeForView;
        donation = buyFee.feeForDonationMarketDev % 16;
    }

    function currentSellFee() public view returns (
        uint8 tax,
        uint8 liquidity,
        uint8 marketing,
        uint8 dev,
        uint8 donation
    ) {
        tax = sellFee.feeForTaxLiquidity % 16;
        liquidity = sellFee.feeForTaxLiquidity >> 4;
        marketing = (sellFee.feeForDonationMarketDev >> 4) -sellFee.devFeeForView;
        dev = sellFee.devFeeForView;
        donation = sellFee.feeForDonationMarketDev % 16;
    }

    function setSellFee(
        uint8 tax,
        uint8 liquidity,
        uint8 marketing,
        uint8 dev,
        uint8 donation
    ) external onlyOwner {
        require (
            tax <= 15 &&
            liquidity <= 15 && 
            marketing + dev <= 15 &&
            donation <= 15, "Fee Can't be set more than 15%"
        );

        sellFee.feeForTaxLiquidity = tax + (liquidity << 4);
        sellFee.feeForDonationMarketDev = donation + ((marketing + dev) << 4);
        sellFee.devFeeForView = dev;
    }

    function setBuyFee(
        uint8 tax,
        uint8 liquidity,
        uint8 marketing,
        uint8 dev,
        uint8 donation
    ) external onlyOwner {
        require (
            tax <= 15 &&
            liquidity <= 15 && 
            marketing + dev <= 15 &&
            donation <= 15, "Fee Can't be set more than 15%"
        );

        buyFee.feeForTaxLiquidity = tax + (liquidity << 4);
        buyFee.feeForDonationMarketDev = donation + ((marketing + dev) << 4);
        buyFee.devFeeForView = dev;
    }

    function setBothFees(
        uint8 buy_tax,
        uint8 buy_liquidity,
        uint8 buy_marketing,
        uint8 buy_dev,
        uint8 buy_donation,
        uint8 sell_tax,
        uint8 sell_liquidity,
        uint8 sell_marketing,
        uint8 sell_dev,
        uint8 sell_donation

    ) external onlyOwner {
        require (
            buy_tax <= 15 &&
            buy_liquidity <= 15 && 
            buy_marketing + buy_dev <= 15 &&
            buy_donation <= 15, "BuyFee Can't be set more than 15%"
        );
        require (
            sell_tax <= 15 &&
            sell_liquidity <= 15 && 
            sell_marketing + sell_dev <= 15 &&
            sell_donation <= 15, "Sell Fee Can't be set more than 15%"
        );                
        buyFee.feeForTaxLiquidity = buy_tax + (buy_liquidity << 4);
        buyFee.feeForDonationMarketDev = buy_donation + ((buy_marketing + buy_dev) << 4);
        buyFee.devFeeForView = buy_dev;

        sellFee.feeForTaxLiquidity = sell_tax + (sell_liquidity << 4);
        sellFee.feeForDonationMarketDev = sell_donation + ((sell_marketing + sell_dev) << 4);
        sellFee.devFeeForView = sell_dev;
    }

    function setNumTokensSellToAddToLiquidity(uint256 numTokens) external onlyOwner {
        numTokensSellToAddToLiquidity = numTokens;
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
        _maxTxAmount = _tTotal *  (maxTxPercent) /  (10**2);
    }

    function _setMaxWalletSizePercent(uint256 maxWalletSize)
        external
        onlyOwner
    {
        _maxWalletSize = _tTotal *  (maxWalletSize) /  (10**2);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    //to receive ETH from uniswapV2Router when swapping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal - (rFee);
        _tFeeTotal = _tFeeTotal +  (tFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply /  (tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _isExcluded.length(); i++) {
            if (
                _rOwned[_isExcluded.at(i)] > rSupply ||
                _tOwned[_isExcluded.at(i)] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply - (_rOwned[_isExcluded.at(i)]);
            tSupply = tSupply - (_tOwned[_isExcluded.at(i)]);
        }
        if (rSupply < _rTotal /  (_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _takeFee(uint256 tFee,uint256 currentRate) private {
        uint256 rFee = tFee *  (currentRate);
        _rOwned[address(this)] = _rOwned[address(this)] +  (rFee);
        if (_isExcluded.contains(address(this)))
            _tOwned[address(this)] = _tOwned[address(this)] +  (tFee);       
    }

    function _takeDonationFee(uint256 tDonation) private {
        uint256 currentRate = _getRate();
        uint256 rDonation = tDonation *  (currentRate);
        _rOwned[_donationAddress] = _rOwned[_donationAddress] +  (rDonation);
        if (_isExcluded.contains(_donationAddress))
            _tOwned[_donationAddress] = _tOwned[_donationAddress] +  (
                tDonation
            );
    }

    function calculateTFees(uint256 amount,uint8 takeFee) internal view returns (tFeeStore memory tFee) {
        if(takeFee == 0 || takeFee == 1) {
            return (tFeeStore(amount,0,0,0,0,amount));
        }else if(takeFee == 2) {
            tFee.tAmount = amount;
            tFee.tFee = amount * (buyFee.feeForTaxLiquidity % 16) /  (10**2);
            tFee.tLiquidity = amount * (buyFee.feeForTaxLiquidity >> 4) /  (10**2);
            tFee.tWallet = amount * (buyFee.feeForDonationMarketDev >> 4) /  (10**2);
            tFee.tDonation = amount * (buyFee.feeForDonationMarketDev % 16) /  (10**2);
            tFee.tTransferAmount = amount - (tFee.tFee + (tFee.tLiquidity)+ (tFee.tWallet)+ (tFee.tDonation));
        }else {
            tFee.tAmount = amount;
            tFee.tFee = amount * (sellFee.feeForTaxLiquidity % 16) /  (10**2);
            tFee.tLiquidity = amount * (sellFee.feeForTaxLiquidity >> 4) /  (10**2);
            tFee.tWallet = amount * (sellFee.feeForDonationMarketDev >> 4) /  (10**2);
            tFee.tDonation = amount * (sellFee.feeForDonationMarketDev % 16) /  (10**2);
            tFee.tTransferAmount = amount - (tFee.tFee + (tFee.tLiquidity)+ (tFee.tWallet)+ (tFee.tDonation));
        }
    }

    function calculateRFees(tFeeStore memory tstore, uint256 currentRate) internal pure returns (rFeeStore memory rFees) {
        rFees.rAmount = tstore.tAmount *  (currentRate);
        rFees.rFee = tstore.tFee *  (currentRate);
        rFees.rLiquidity = tstore.tLiquidity *  (currentRate);
        rFees.rWallet = tstore.tWallet *  (currentRate);
        rFees.rDonation = tstore.tDonation *  (currentRate);
        rFees.rTransferAmount = rFees.rAmount - (rFees.rFee
             +  (rFees.rLiquidity)
             +  (rFees.rWallet)
             +  (rFees.rDonation));
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function isExcludedFromLimit(address account) public view returns (bool) {
        return _isExcludedFromLimit[account];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(!_isBlackListedBot[from], "from is blacklisted");
        require(!_isBlackListedBot[msg.sender], "you are blacklisted");
        require(!_isBlackListedBot[tx.origin], "blacklisted");

        if(to != uniswapV2Pair) { 
            require(balanceOf(to) + amount < _maxWalletSize, "TOKEN: Balance exceeds wallet size!");
        }
        
        if (!_isExcludedFromLimit[from] && !_isExcludedFromLimit[to]) { 
            require(amount <= _maxTxAmount,"Transfer amount exceeds the maxTxAmount.");
        }

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }

        bool overMinTokenBalance = contractTokenBalance >=
            numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != uniswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = numTokensSellToAddToLiquidity;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        uint8 takeFee_;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if ((_isExcludedFromFee[from] || _isExcludedFromFee[to]) || (from != uniswapV2Pair && to != uniswapV2Pair)) {
            takeFee_ = 1;
        } else {            
            //Set Fee for Buys
            if(from == uniswapV2Pair && to != address(uniswapV2Router)) {
                if(takeFee_ != 1) takeFee_ = 2;
            }
            //Set Fee for Sells
            if (to == uniswapV2Pair && from != address(uniswapV2Router)) {
                if(takeFee_ != 1) takeFee_ = 3;
            }
        }     
        
        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, takeFee_);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance /  (2);
        uint256 otherHalf = contractTokenBalance - (half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <-this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance - (initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        uint8 takeFee
    ) private { 
            
        if (_isExcluded.contains(sender) && !_isExcluded.contains(recipient)) {
            _transferFromExcluded(sender, recipient, amount,takeFee);
        } else if (!_isExcluded.contains(sender) && _isExcluded.contains(recipient)) {
            _transferToExcluded(sender, recipient, amount,takeFee);
        } else if (!_isExcluded.contains(sender) && !_isExcluded.contains(recipient)) {
            _transferStandard(sender, recipient, amount,takeFee);
        } else if (_isExcluded.contains(sender) && _isExcluded.contains(recipient)) {
            _transferBothExcluded(sender, recipient, amount,takeFee);
        } else {
            _transferStandard(sender, recipient, amount,takeFee);
        }
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount,
        uint8 takeFee
    ) private {

        uint256 currentRate = _getRate();
        tFeeStore memory tFees = calculateTFees(tAmount,takeFee);        
        rFeeStore memory rFees = calculateRFees(tFees,currentRate);

        _rOwned[sender] = _rOwned[sender] - (rFees.rAmount);
        _rOwned[recipient] = _rOwned[recipient] +  (rFees.rTransferAmount);
        _takeFee(tFees.tLiquidity +  (tFees.tWallet),currentRate);
        _takeDonationFee(tFees.tDonation);
        _reflectFee(rFees.rFee, tFees.tFee);
        emit Transfer(sender, recipient, tFees.tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint8 takeFee
    ) private {
        uint256 currentRate = _getRate();
        tFeeStore memory tFees = calculateTFees(tAmount,takeFee);        
        rFeeStore memory rFees = calculateRFees(tFees,currentRate);

        _rOwned[sender] = _rOwned[sender] - (rFees.rAmount);
        _tOwned[recipient] = _tOwned[recipient] +  (tFees.tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient] +  (rFees.rTransferAmount);
        _takeFee(tFees.tLiquidity +  (tFees.tWallet), currentRate);
        _takeDonationFee(tFees.tDonation);
        _reflectFee(rFees.rFee, tFees.tFee);
        emit Transfer(sender, recipient, tFees.tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint8 takeFee
    ) private {
        uint256 currentRate = _getRate();
        tFeeStore memory tFees = calculateTFees(tAmount,takeFee);        
        rFeeStore memory rFees = calculateRFees(tFees,currentRate);

        _tOwned[sender] = _tOwned[sender] - (tAmount);
        _rOwned[sender] = _rOwned[sender] - (rFees.rAmount);
        _rOwned[recipient] = _rOwned[recipient] +  (rFees.rTransferAmount);
        _takeFee(tFees.tLiquidity +  (tFees.tWallet), currentRate);
        _takeDonationFee(tFees.tDonation);
        _reflectFee(rFees.rFee, tFees.tFee);
        emit Transfer(sender, recipient, tFees.tTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount,
        uint8 takeFee
    ) private {
        uint256 currentRate = _getRate();
        tFeeStore memory tFees = calculateTFees(tAmount,takeFee);        
        rFeeStore memory rFees = calculateRFees(tFees,currentRate);

        _tOwned[sender] = _tOwned[sender] - (tAmount);
        _rOwned[sender] = _rOwned[sender] - (rFees.rAmount);
        _tOwned[recipient] = _tOwned[recipient] +  (tFees.tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient] +  (rFees.rTransferAmount);
        _takeFee(tFees.tLiquidity +  (tFees.tWallet), currentRate);
        _takeDonationFee(tFees.tDonation);
        _reflectFee(rFees.rFee, tFees.tFee);
        emit Transfer(sender, recipient, tFees.tTransferAmount);
    }
}