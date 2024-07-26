// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {EsRNTToken} from "../src/EsRNTToken.sol";
import {RNTToken} from "../src/RNTToken.sol";
import {SigUtils} from "../src/SigUtils.sol";

contract StakingRewardsTest is Test {
    StakingRewards public sr;
    RNTToken public rnt;
    EsRNTToken public esrnt;
    SigUtils internal sigUtils;

    address public bob = makeAddr("bob");
    Account owner = makeAccount("owner");
    address public alice;
    uint256 public aliceKey;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        vm.startPrank(owner.addr);
        rnt = new RNTToken(owner.addr);
        sigUtils = new SigUtils(rnt.DOMAIN_SEPARATOR());
        esrnt = new EsRNTToken(address(rnt));

        sr = new StakingRewards(address(rnt), address(esrnt));

        rnt.mint(owner.addr, 100 * 10 ** 9 * 1 ether);
        rnt.transfer(address(sr), 15 * 10 ** 9 * 1 ether);

        vm.stopPrank();
    }

    function testBalance() public view {
        assertEq(rnt.balanceOf(address(sr)), 15 * 10 ** 9 * 1 ether);
        assertEq(rnt.balanceOf(owner.addr), 85 * 10 ** 9 * 1 ether);
    }

    function testStakeSuccessful() public {
        vm.prank(owner.addr);
        rnt.transfer(alice, 1_000e18);
        assertEq(rnt.balanceOf(alice), 1_000e18);
        assertEq(rnt.balanceOf(owner.addr), 84999999000 * 1 ether);
        vm.startPrank(alice);
        rnt.approve(address(sr), 1000e18);
        assertEq(rnt.allowance(alice, address(sr)), 1000e18);
        sr.stake(100e18);
        assertEq(rnt.balanceOf(alice), 900e18);
        assertEq(rnt.balanceOf(address(sr)), 15000000100e18);
        (uint256 stakedAmount, uint256 lastUpdateTime, ) = sr.staked(alice);
        assertEq(lastUpdateTime, block.timestamp);
        assertEq(stakedAmount, 100e18);
        vm.stopPrank();
    }

    function testPermitStakeSuccess() public {
        vm.prank(owner.addr);
        rnt.transfer(alice, 1e18);
        assertEq(rnt.balanceOf(alice), 1e18);

        vm.startPrank(alice);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(sr),
            value: 1e18,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        sr.permitStake(1e18, 1 days, signature);
        assertEq(rnt.allowance(alice, address(sr)), 0);
        assertEq(rnt.balanceOf(alice), 0);
        assertEq(rnt.balanceOf(address(sr)), 15000000001 * 1 ether);

        (uint256 stakedAmount, uint256 lastUpdateTime, ) = sr.staked(alice);
        assertEq(stakedAmount, 1e18);
        assertEq(lastUpdateTime, block.timestamp);

        vm.stopPrank();
    }

    function testUnstakeSuccess() public {
        vm.prank(owner.addr);
        rnt.transfer(alice, 1_000e18);
        vm.startPrank(alice);
        rnt.approve(address(sr), 1_000e18);
        sr.stake(1_000e18);
        assertEq(rnt.balanceOf(address(sr)), 15000001000e18);
        (uint256 stakedAmount, uint256 lastUpdateTime, ) = sr.staked(alice);
        assertEq(stakedAmount, 1_000e18);
        assertEq(lastUpdateTime, block.timestamp);
        sr.unstake(100e18);
        assertEq(rnt.balanceOf(address(sr)), 15000000900e18);
        (uint256 unstakedAmount, uint256 unlastUpdateTime, ) = sr.staked(alice);
        assertEq(unstakedAmount, 900e18);
        assertEq(unlastUpdateTime, block.timestamp);
        vm.stopPrank();
    }

    function testClaimSuccess() public {
        vm.startPrank(owner.addr);
        rnt.transfer(alice, 1_000e18);
        esrnt.setOnlyOwner(address(sr));
        assertEq(esrnt.stakePoolAddress(), address(sr));

        vm.stopPrank();
        vm.startPrank(alice);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(sr),
            value: 100e18,
            nonce: 0,
            deadline: 1 days
        });
        bytes memory signature = _getPermitsignature(permit);
        sr.permitStake(100e18, 1 days, signature);
        assertEq(rnt.balanceOf(alice), 900e18);
        assertEq(rnt.balanceOf(address(sr)), 15000000100e18);
        (uint256 stakedAmount, uint256 lastUpdateTime, ) = sr.staked(alice);
        assertEq(stakedAmount, 100e18);
        assertEq(lastUpdateTime, block.timestamp);
        vm.warp(block.timestamp + 20 days);

        assertEq(rnt.balanceOf(address(sr)), 15_000_000_100e18);

        sr.claim();
        assertEq(rnt.balanceOf(address(sr)), 14_999_998_100e18);
        (
            uint256 claimStakedAmount,
            uint256 claimLastUpdateTime,
            uint256 unClaimed
        ) = sr.staked(alice);
        assertEq(claimStakedAmount, 100e18);
        assertEq(unClaimed, 0);
        assertEq(claimLastUpdateTime, block.timestamp);
        assertEq(rnt.balanceOf(alice), 900e18);

        assertEq(esrnt.balanceOf(alice), 2000e18);
        (address user, uint256 lockamount, uint256 lockTime) = esrnt.lockInfos(
            0
        );
        assertEq(user, alice);
        assertEq(lockamount, 2000e18);
        assertEq(lockTime, block.timestamp);
        assertEq(rnt.balanceOf(address(esrnt)), 2000e18);
        vm.stopPrank();
    }

    function testBurnSuccess() public {
        vm.startPrank(owner.addr);
        rnt.transfer(alice, 1_000e18);
        esrnt.setOnlyOwner(address(sr));
        assertEq(esrnt.stakePoolAddress(), address(sr));

        vm.stopPrank();
        vm.startPrank(alice);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(sr),
            value: 100e18,
            nonce: 0,
            deadline: 1 days
        });
        bytes memory signature = _getPermitsignature(permit);
        sr.permitStake(100e18, 1 days, signature);
        assertEq(rnt.balanceOf(alice), 900e18);
        assertEq(rnt.balanceOf(address(sr)), 15000000100e18);
        (uint256 stakedAmount, uint256 lastUpdateTime, ) = sr.staked(alice);
        assertEq(stakedAmount, 100e18);
        assertEq(lastUpdateTime, block.timestamp);
        vm.warp(block.timestamp + 20 days);

        assertEq(rnt.balanceOf(address(sr)), 15_000_000_100e18);
        assertEq(sr.getUnclaimedRewards(address(alice)), 2_000e18);

        sr.claim();
        assertEq(rnt.balanceOf(address(sr)), 14_999_998_100e18);
        (
            uint256 claimStakedAmount,
            uint256 claimLastUpdateTime,
            uint256 unClaimed
        ) = sr.staked(alice);
        assertEq(claimStakedAmount, 100e18);
        assertEq(unClaimed, 0);
        assertEq(claimLastUpdateTime, block.timestamp);

        (address user, uint256 lockamount, uint256 lockTime) = esrnt.lockInfos(
            0
        );
        assertEq(user, alice);
        assertEq(lockTime, block.timestamp);
        assertEq(esrnt.totalSupply(), 2000e18);
        assertEq(rnt.balanceOf(address(sr)), 14_999_998_100e18);
        assertEq(esrnt.balanceOf(address(sr)), 0);
        assertEq(esrnt.size(), 1);
        assertEq(rnt.balanceOf(alice), 900e18);
        assertEq(esrnt.balanceOf(alice), 2000e18);
        assertEq(lockamount, 2000e18);
        assertEq(rnt.balanceOf(address(esrnt)), 2000e18);

        rnt.approve(address(esrnt), 2000 ether);
        vm.warp(block.timestamp + 20 days);

        esrnt.burn(0);
        assertEq(rnt.balanceOf(alice), 2233_333333333333333333);
        assertEq(esrnt.balanceOf(alice), 0);
        assertEq(rnt.balanceOf(address(esrnt)), 0);
        assertEq(esrnt.totalSupply(), 0);
        assertEq(rnt.balanceOf(address(sr)), 14_999_998_100e18);
        assertEq(esrnt.balanceOf(address(esrnt)), 0);
        assertEq(esrnt.size(), 0);

        vm.stopPrank();
    }

    function test_Permit() public {
        console.log("owner address: ", owner.addr);
        console.log("alice address: ", alice);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner.addr,
            spender: address(sr),
            value: 1e18,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner.key, digest);

        rnt.permit(
            permit.owner,
            permit.spender,
            permit.value,
            permit.deadline,
            v,
            r,
            s
        );

        assertEq(rnt.allowance(owner.addr, address(sr)), 1e18);
        assertEq(rnt.nonces(owner.addr), 1);
    }

    function _getPermitsignature(
        SigUtils.Permit memory permit
    ) internal view returns (bytes memory) {
        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }
}
