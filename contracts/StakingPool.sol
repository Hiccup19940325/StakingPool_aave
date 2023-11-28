// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20} from "@aave/protocol-v2/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {WadRayMath} from "@aave/protocol-v2/contracts/protocol/libraries/math/WadRayMath.sol";
import {ILendingPool} from "@aave/protocol-v2/contracts/interfaces/ILendingPool.sol";
import {IAToken} from "@aave/protocol-v2/contracts/interfaces/IAToken.sol";
import {SafeERC20} from "@aave/protocol-v2/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {MockToken} from "./MockToken.sol";

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
    ILendingPool public aaveLendingPool;
    uint public rewardTokensPerBlock;
    uint public totalScaledAmount;
    uint public lastRewardedBlock;
    uint accumulatedRewardsPerShare;
    uint REWARDS_PRECISION = 1e12;
    address public test;

    MockToken public mockToken;

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
        address _aaveLendingPool,
        address _mockToken,
        uint rewardPerBlock
    ) public {
        usdcToken = IERC20(_usdcToken);
        aaveLendingPool = ILendingPool(_aaveLendingPool);
        ausdcToken = IAToken(_ausdcToken);
        rewardTokensPerBlock = rewardPerBlock;
        mockToken = MockToken(_mockToken);
        lastRewardedBlock = block.number;
    }

    /**
     * @dev Deposits an 'amount' of USDC into the stakingPool
     * @param amount the amount that staker staked into the stakingPool
     */
    function depositWithUSDC(uint amount) external {
        require(amount > 0, "amount should be more than 0");

        usdcToken.transferFrom(msg.sender, address(this), amount);
        usdcToken.approve(address(aaveLendingPool), amount);

        uint oldBalance = ausdcToken.scaledBalanceOf(address(this)); //balance before deposit
        aaveLendingPool.deposit(address(usdcToken), amount, address(this), 0);
        uint currentBalance = ausdcToken.scaledBalanceOf(address(this)); //balance after deposit

        //new minted balance
        uint _amount = currentBalance - oldBalance;

        stakerInfo storage staker = stakers[msg.sender];

        //update the states and get the pending rewards
        harvestRewards();

        //update the stakerInfo and totalScaledAmount
        staker.scaledAmount += _amount;
        staker.rewardsDebt =
            (staker.scaledAmount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        totalScaledAmount += _amount;

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
        ausdcToken.transferFrom(address(msg.sender), address(this), amount);
        uint currentBalance = ausdcToken.scaledBalanceOf(address(msg.sender)); //scaledBalance after deposit

        //new deposited amount
        uint _amount = oldBalance - currentBalance;

        //update the states and get the pending rewards
        harvestRewards();

        //update the stakerInfo and totalScaledAmount
        staker.scaledAmount += _amount;
        staker.rewardsDebt =
            (staker.scaledAmount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        totalScaledAmount += _amount;

        emit DepositWithAUSDC(msg.sender, amount);
    }

    /**
     * @dev Withdraw an 'amount' of USDC from stakingPool's aUSDC
     * @param amount the amount that staker withdraw from the stakingPool
     */
    function withdrawInUSDC(uint amount) external {
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

        //update the stakerInfo and totalScaledAmount
        staker.scaledAmount -= _amount;
        staker.rewardsDebt =
            (staker.scaledAmount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        totalScaledAmount -= _amount;

        aaveLendingPool.withdraw(address(usdcToken), amount, msg.sender);

        emit WithdrawInUSDC(msg.sender, amount);
    }

    /**
     * @dev Withdraw an 'amount' of aUSDC from stakingPool
     * @param amount the amount that staker withdraw from the stakingPool
     */
    function withdrawInAUSDC(uint amount) external {
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

        //update the stakerInfo and totalScaledAmount
        staker.scaledAmount -= _amount;
        staker.rewardsDebt =
            (staker.scaledAmount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION;
        totalScaledAmount -= _amount;

        ausdcToken.transfer(msg.sender, amount);

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

        uint rewards = (block.number - lastRewardedBlock) *
            rewardTokensPerBlock;

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
     * @return pendingReward the amount of the pendingRewards
     */
    function pendingRewards() public view returns (uint pendingReward) {
        stakerInfo storage staker = stakers[msg.sender];
        uint accRewardsPerShare = accumulatedRewardsPerShare;

        if (totalScaledAmount != 0 && lastRewardedBlock <= block.number) {
            uint rewards = (block.number - lastRewardedBlock) *
                rewardTokensPerBlock;

            //update the accumulatedRewardsPerShare
            accRewardsPerShare +=
                (rewards * REWARDS_PRECISION) /
                totalScaledAmount;
        }
        //calculate the pending rewards
        pendingReward =
            (staker.scaledAmount * accumulatedRewardsPerShare) /
            REWARDS_PRECISION -
            staker.rewardsDebt;
    }
}
