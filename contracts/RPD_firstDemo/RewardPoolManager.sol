// SPDX-License-Identifier: MIT


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IRewardPool.sol";
import "./RewardPool.sol";

pragma solidity 0.8.13;

contract RewardPoolManager is Ownable, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address payable;

    uint256 public maximumDividendContracts = 10;
    uint256 public createPoolFee = 0.1e18;    
    uint256 private minimumBnbBalanceForBuyback = 0.1e18;
    uint256 private maximumBnbBalanceForBuyback = 10e18;

    address payable public tresuryAddress;
    address private implementation;

    mapping (address => address) public rewardPoolInfo;

    constructor (address _implementation) {
        tresuryAddress = payable(_msgSender());
        implementation = _implementation;
    }

    receive() external payable{}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function recoverLeftOverBNB(uint256 amount) external onlyOwner {
        payable(owner()).sendValue(amount);
    }

    function recoverLeftOverToken(address token,uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(),amount);
    }

    function setMaximumDividendContracts(uint256 _maximumDividendContracts) external onlyOwner {
        require(_maximumDividendContracts != 0, "RewardPoolManager: Can't be Zero");
        maximumDividendContracts = _maximumDividendContracts;
    }

    function setCreatePoolFee(uint256 newFee) external onlyOwner {
        createPoolFee = newFee;
    }

    function setImplementation(address newImplementation) external onlyOwner {
        require(newImplementation != address(0), "RewardPoolManager: Can't be Zero");
        implementation = newImplementation;
    }

    function setTresuryAddress(address payable _tresuryAddress) external onlyOwner {
        require(_tresuryAddress != address(0), "RewardPoolManager: Can't be zero address");

        tresuryAddress = _tresuryAddress;
    }

    function createRewardPool(
        address nativeAsset,
        address rewardAsset,
        address projectAdmin,
        uint256 rewardDistributeShare,
        uint256 minimumTokenBalanceForDividends,
        bool createDistribute
    ) external payable whenNotPaused{
        require(nativeAsset != rewardAsset, "RewardPoolManager: Can't be same");
        require(rewardPoolInfo[nativeAsset] == address(0), "RewardPoolManager: RewardPool Already Created");
        require(createPoolFee <= msg.value, "RewardPoolManager: Fee is required");
        require(minimumTokenBalanceForDividends != 0, "RewardPoolManager: Invalid minimumTokenBalanceForDividends");

        if(createPoolFee != 0) tresuryAddress.sendValue(msg.value); 
               
        RewardPool newRewardPool = new RewardPool(
            nativeAsset,
            projectAdmin
        );

        if(createDistribute) {
            newRewardPool.createRewardDistributor(
                implementation,
                nativeAsset,
                rewardAsset,
                rewardDistributeShare,
                minimumTokenBalanceForDividends
            );
        }
        rewardPoolInfo[nativeAsset] = address(newRewardPool);
    }

    function createRewardDistributor(
        address nativeAsset,
        address rewardAsset,
        uint256 rewardDistributeShare,
        uint256 minimumTokenBalanceForDividends
    ) external payable whenNotPaused {
        require(nativeAsset != rewardAsset, "RewardPoolManager: Can't be same");
        require(rewardPoolInfo[nativeAsset] != address(0), "RewardPoolManager: RewardPool Still Not Created");

        IRewardPool rewardPool = IRewardPool(rewardPoolInfo[nativeAsset]);
        require(rewardPool.getTotalNumberofRewardsDistributor() <= maximumDividendContracts, "RewardPoolManager: Dividends Limit Exceed");
        require(!rewardPool.rewardsDistributorContains(rewardAsset), "RewardPoolManager: Dividends Already Created");
        require(createPoolFee <= msg.value, "RewardPoolManager: Fee is required");
        require(minimumTokenBalanceForDividends != 0, "RewardPoolManager: Invalid minimumTokenBalanceForDividends");
        require(rewardPool.getRewardsDistributor(rewardAsset) == address(0xdEaD), "RewardPoolManager: RewardDistributor is not created");

        if(createPoolFee != 0) tresuryAddress.sendValue(msg.value);

        rewardPool.createRewardDistributor(
            implementation,
            nativeAsset,
            rewardAsset,
            rewardDistributeShare,
            minimumTokenBalanceForDividends
        );
    }

    function multicall(
        address _implementation,
        bytes calldata _data
    ) external onlyOwner {
        Address.functionCall(_implementation, _data);
    }

    function  setMinMaxBnbBalanceForBuyback(uint256 newMinValue,uint256 newMaxValue) external onlyOwner {
        require(newMinValue != 0 && newMaxValue != 0, "RewardDistributor: Can't be zero");
        require(newMinValue < newMaxValue, "RewardDistributor: Invalid Amount");

        minimumBnbBalanceForBuyback = newMinValue;
        maximumBnbBalanceForBuyback = newMaxValue;
    }

    function buyBackRidge() external view returns (uint256 _minimumBnbBalanceForBuyback,uint256 _maximumBnbBalanceForBuyback) {
        return (
            minimumBnbBalanceForBuyback,
            maximumBnbBalanceForBuyback
        );
    }
}