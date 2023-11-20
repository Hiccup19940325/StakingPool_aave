// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IERC20} from "@aave/protocol-v2/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {WadRayMath} from "@aave/protocol-v2/contracts/libraries/math/WadRayMath.sol";
import {ILendingPool} from "@aave/protocol-v2/contracts/interfaces/ILendingPool.sol";
import {IAToken} from "@aave/protocol-v2/contracts/interfaces/IAToken.sol";
import {SafeERC20} from "@aave/protocol-v2/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";

/**
 * @title StakingPool contract
 * @dev Main point of staking USDC/aUSDC with an Aave protocol
 * - Users can:
 *   # depositWithUSDC
 *   # depositWithAUSDC
 *   # withdrawInUSDC
 *   # withdrawInAUSDC
 *   # harvestReward
 * @author John
 */
contract StakingPool {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public usdcToken;
    IAToken public ausdcToken;
    IERC20 public mockToken;
    ILendingPool public aaveLendingPool;
    uint rewardTokensPerBlock;
    uint totalScaledAmount;
    uint lastRewardedBlock;
    uint accumulatedRewardsPerShare;
    uint REWARDS_PRECISION = 12;

    struct stakerInfo {
        uint scaledAmount;
        uint rewardsDebt;
    }

    mapping(address => stakerInfo) public stakers;

    event DepositWithAUSDC(address provider, uint amount);
    event DepositWithUSDC(address provider, uint amount);
    event WithdrawInUSDC(address receiver, uint amount);
    event WithdrawInAUSDC(address receiver, uint amount);

    constructor(
        address _usdcToken,
        address _ausdcToken,
        address _mockToken,
        address _aaveLendingPool,
        uint rewardPerBlock
    ) {
        usdcToken = _usdcToken;
        ausdcToken = _ausdcToken;
        mockToken = _mockToken;
        aaveLendingPool = _aaveLendingPool;
        rewardTokensPerBlock = rewardPerBlock;
    }

    /**
     * @dev Deposits an 'amount' of USDC into the stakingPool
     * @param amount the amount that staker staked into the stakingPool
     */
    function depositWithUSDC(uint amount) external {
        require(amount > 0, "amount should be more than 0");

        usdcToken.safeTransferFrom(msg.sender, address(this), amount);
        usdcToken.approve(address(aaveLendingPool), amount);

        uint oldBalance = ausdcToken.scaledBalanceOf(address(this)); //balance before deposit
        aaveLendingPool.deposit(address(usdcToken), amount, address(this), 0);
        uint currentBalance = ausdcToken.scaledBalanceOf(address(this)); //balance after deposit

        //new minted balance
        uint _amount = currentBalance - oldBalance;

        stakerInfo storage staker = stakers[msg.sender];

        //update the states and get the pending rewards
        harvestRewards();

        //update the stakerInfo and totalAmount
        staker.scaledAmount += _amount;
        staker.rewardsDebt =
            (staker.scaledAmount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        totalamount += _amount;

        emit DepositWithUSDC(msg.sender, amount);
    }

    /**
     * @dev Deposits an 'amount' of aUSDC into the stakingPool
     * @param amount the amount that staker staked into the stakingPool
     */
    function depositWithAUSDC(uint amount) external {
        require(amount > 0, "amount should be more than 0");
        stakerInfo storage staker = stakers[msg.sender];

        uint oldBalance = ausdcToken.scaledBalanceOf(address(msg.sender)); //scaledBalance before deposit
        ausdcToken.safeTransferFrom(address(msg.sender), address(this), amount);
        uint currentBalance = ausdcToken.scaledBalanceOf(address(msg.sender)); //scaledBalance after deposit

        //new deposited amount
        uint _amount = oldBalance - currentBalance;

        //update the states and get the pending rewards
        harvestRewards();

        //update the stakerInfo and totalAmount
        staker.scaledAmount += _amount;
        staker.rewardsDebt =
            (staker.scaledAmount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        totalAmount += _amount;

        emit DepositWithAUSDC(msg.sender, amount);
    }

    /**
     * @dev Withdraw an 'amount' of USDC from stakingPool's aUSDC
     * @param amount the amount that staker withdraw from the stakingPool
     */
    function depositInUSDC(uint amount) external {
        require(amount > 0, "amount should be more than 0");

        //convert amount to scaledAmount
        uint _amount = amount.rayDiv(
            aaveLendingPool.getReserveData(address(usdcToken)).liquidityIndex
        );
        stakerInfo storage staker = stakers[msg.sender];

        require(
            _amount <= staker.scaledAmount,
            "amount should be less than staker's staked amount"
        );

        //update the states and get the pending rewards
        harvestRewards();

        //update the stakerInfo and totalAmount
        staker.scaledAmount -= _amount;
        staker.rewardsDebt =
            (staker.amount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        totalAmount -= _amount;

        aaveLendingPool.withdraw(address(usdcToken), amount, msg.sender);

        emit WithdrawInUSDC(msg.sender, amount);
    }

    /**
     * @dev Withdraw an 'amount' of aUSDC from stakingPool
     * @param amount the amount that staker withdraw from the stakingPool
     */
    function depositInAUSDC(uint amount) external {
        require(amount > 0, "amount should be more than 0");

        //convert amount to scaledAmount
        uint _amount = amount.rayDiv(
            aaveLendingPool.getReserveData(address(usdcToken)).liquidityIndex
        );
        stakerInfo storage staker = stakers[msg.sender];

        require(
            _amount <= staker.scaledAmount,
            "amount should be less than staker's staked amount"
        );

        //update the states and get the pending rewards
        harvestRewards();

        //update the stakerInfo and totalAmount
        staker.scaledAmount -= _amount;
        staker.rewardsDebt =
            (staker.amount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        totalAmount -= _amount;

        ausdcToken.safeTransfer(msg.sender, amount);

        emit WithdrawInAUSDC(msg.sender, amount);
    }

    /**
     * @dev Update the accumulatedRewardsPerShare, staker's rewardsDebt and mint the pending reward mocktoken to staker
     */
    function harvestRewards() public {
        if (totalScaledAmount == 0) {
            lastRewardedBlock = block.number;
            return;
        }

        stakerInfo storage staker = stakers[msg.sender];

        uint rewards = (block.number - lastRewardedBlock) * rewardPerBlock;

        //update the accumulatedRewardsPerShare
        accumulatedRewardsPerShare +=
            (rewards * REWARDS_PRECISION) /
            totalScaledAmount;
        lastRewardedBlock = block.number;

        //calculate the pending rewards
        uint rewardsToHarvest = (staker.scaledAmount *
            accumulatedRewardsPerShare) /
            REWARDS_PRECISION -
            staker.rewardsDebt;

        if (rewardsToHarvest == 0) {
            staker.rewardsDebt =
                (staker.scaledAmount * accumulatedRewardsPerShare) /
                REWARDS_PRECISION;
            return;
        }

        //update the rewardsDebt
        staker.rewardsDebt =
            (staker.scaledAmount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION;

        mockToken.mint(msg.sender, rewardsToHarvest);
    }

    /**
     * @dev Get the pending Rewards
     * @return pendingRewards the amount of the pendingRewards
     */
    function pendingRewards() public view returns (uint pendingRewards) {
        stakerInfo storage staker = stakers[msg.sender];

        //calculate the pending rewards
        pendingRewards =
            (staker.scaledAmount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION -
            staker.rewardsDebt;
    }
}
