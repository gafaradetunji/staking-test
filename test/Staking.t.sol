// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {StakingRewards, IERC20} from "src/Staking.sol";
import {MockERC20} from "test/MockErc20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(address(staking.stakingToken()), address(stakingToken), "Wrong staking token address");
        assertEq(address(staking.rewardsToken()), address(rewardToken), "Wrong reward token address");

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(staking.totalSupply(), _totalSupplyBeforeStaking + 5e18, "totalsupply didnt update correctly");
    }

    function test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), userStakebefore - 2e18, "Balance didnt update correctly");
        assertLt(staking.totalSupply(), totalSupplyBefore, "total supply didnt update correctly");
    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward
        vm.warp(block.timestamp + 200);
        // notify rewards
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);

        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether) / uint256(1 weeks));
        assertEq(staking.finishAt(), uint256(block.timestamp) + uint256(1 weeks));
        assertEq(staking.updatedAt(), block.timestamp);

        // Calculate expected remaining rewards
        uint256 remainingRewards = (staking.finishAt() - block.timestamp) * staking.rewardRate();

        uint256 expectedRewardRate = (100 ether + remainingRewards) / uint256(1 weeks);

        console.log("Expected reward", expectedRewardRate);

        // vm.warp(block.timestamp - 1);
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        staking.notifyRewardAmount(100 ether);

        // assertEq(
        //     staking.rewardRate(),
        //     expectedRewardRate,
        //     "Reward rate mismatch"
        // );
        assertEq(staking.finishAt(), block.timestamp + 1 weeks, "FinishAt should be extended by duration");
        assertEq(staking.updatedAt(), block.timestamp, "UpdatedAt should equal current block.timestamp");

        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
    }

    function test_get_rewards() public {
        vm.prank(owner);
        staking.setRewardsDuration(1000);
        deal(address(rewardToken), owner, 200 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 200 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        deal(address(stakingToken), bob, 2 ether);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(2 ether);

        vm.warp(block.timestamp + 500);

        uint256 beforeBal = rewardToken.balanceOf(bob);
        staking.getReward();
        uint256 afterBal = rewardToken.balanceOf(bob);
        assertGt(afterBal, beforeBal, "bob's new balance should be more");
        vm.stopPrank();
    }

    function test_lastTimeRewardApplicable() public {
        vm.prank(owner);
        staking.setRewardsDuration(1000);
        deal(address(rewardToken), owner, 2 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 2 ether);
        staking.notifyRewardAmount(2 ether);

        uint256 finishAt = staking.finishAt();
        vm.warp(finishAt + 1);
        assertEq(staking.lastTimeRewardApplicable(), finishAt, "Should return the time if it is passed");
    }

    function test_rewardPerToken_noSupply() public {
        uint256 rpt = staking.rewardPerToken();
        assertEq(rpt, 0, "With no staking supply, should return stored rewardPerToken");
    }

    function test_earned_function() public {
        vm.prank(owner);
        staking.setRewardsDuration(1000);
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        deal(address(stakingToken), bob, 2 ether);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(2 ether);

        vm.warp(block.timestamp + 200);
        uint256 reward = staking.earned(bob);
        assertGt(reward, 0, "reward should be greater than zero after time elapses");
        vm.stopPrank();
    }
}
