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

        // (address owner, uint256 ownerPrivateKey) = makeAddrAndKey("owner");

        rnt = new RNTToken(owner.addr);
        sigUtils = new SigUtils(rnt.DOMAIN_SEPARATOR());
        esrnt = new EsRNTToken(owner.addr);

        sr = new StakingRewards(address(rnt), address(esrnt));
        vm.startPrank(owner.addr);
        rnt.mint(owner.addr, 1_000_000e18);
        esrnt.mint(owner.addr, 1_000_000e18);
        esrnt.mint(address(sr), 1_500_000_000e18);

        vm.stopPrank();
    }

    function testBalance() public view {
        assertEq(rnt.balanceOf(address(sr)), 0);
        assertEq(esrnt.balanceOf(address(sr)), 1_500_000_000e18);
        assertEq(rnt.balanceOf(owner.addr), 1_000_000e18);

        assertEq(esrnt.balanceOf(owner.addr), 1_000_000e18);
    }

    function testStake() public {
        vm.prank(owner.addr);
        rnt.transfer(alice, 1000e18);
        assertEq(rnt.balanceOf(alice), 1000e18);
        assertEq(rnt.balanceOf(owner.addr), 999000e18);

        vm.startPrank(alice);
        rnt.approve(address(sr), 1000e18);
        assertEq(rnt.allowance(alice, address(sr)), 1000e18);

        sr.stake(100e18);
        assertEq(rnt.balanceOf(alice), 900e18);
        assertEq(rnt.balanceOf(address(sr)), 100e18);

        assertEq(sr.staked(alice), 100e18);
        assertEq(sr.claimed(alice), 0e18);

        vm.stopPrank();
    }

    function testPermitStakeSuccess() public {
        vm.prank(owner.addr);
        rnt.transfer(alice, 1e18);
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
        assertEq(rnt.balanceOf(address(sr)), 1e18);

        assertEq(sr.staked(alice), 1e18);
        assertEq(sr.claimed(alice), 0e18);

        vm.stopPrank();
    }

    function testUnstake() public {
        vm.prank(owner.addr);
        rnt.transfer(alice, 1000);
        vm.startPrank(alice);
        rnt.approve(address(sr), 1000);
        sr.stake(1000);
        assertEq(rnt.balanceOf(address(sr)), 1000);
        sr.unstake(1000);
        assertEq(rnt.balanceOf(address(sr)), 0);
        assertEq(sr.staked(alice), 0);
        vm.stopPrank();
    }

    function testClaim() public {
        vm.prank(owner.addr);
        rnt.transfer(alice, 10e18);
        vm.startPrank(alice);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(sr),
            value: 1e18,
            nonce: 0,
            deadline: 1 days
        });
        bytes memory signature = _getPermitsignature(permit);
        sr.permitStake(1e18, 1 days, signature);

        assertEq(rnt.balanceOf(alice), 9e18);
        assertEq(rnt.balanceOf(address(sr)), 1e18);
        vm.warp(block.timestamp + 20 days);
        sr.claim();
        assertEq(rnt.balanceOf(address(sr)), 1e18);
        assertEq(sr.staked(alice), 1e18);
        assertEq(sr.claimed(alice), 20e18);
        assertEq(esrnt.balanceOf(alice), 20e18);

        vm.stopPrank();
    }

    function testRedeemSuccess() public {
        vm.prank(owner.addr);
        rnt.transfer(alice, 10e18);
        vm.prank(owner.addr);
        rnt.transfer(address(sr), 30e18);
        vm.startPrank(alice);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(sr),
            value: 1e18,
            nonce: 0,
            deadline: 1 days
        });
        bytes memory signature = _getPermitsignature(permit);
        sr.permitStake(1e18, 1 days, signature);

        assertEq(rnt.balanceOf(alice), 9e18);
        assertEq(rnt.balanceOf(address(sr)), 31e18);
        vm.warp(block.timestamp + 30 days);
        sr.claim();
        assertEq(rnt.balanceOf(address(sr)), 31e18);
        assertEq(esrnt.balanceOf(alice), 30e18);
        esrnt.approve(address(sr), 20e18);
        sr.redeem(20e18);
        assertEq(esrnt.balanceOf(alice), 10e18);
        assertEq(rnt.balanceOf(alice), 29e18);
        vm.stopPrank();
    }

    function testRedeemFailed() public {
        vm.prank(owner.addr);
        rnt.transfer(alice, 10e18);
        vm.prank(owner.addr);
        rnt.transfer(address(sr), 30e18);
        vm.startPrank(alice);
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: alice,
            spender: address(sr),
            value: 1e18,
            nonce: 0,
            deadline: 1 days
        });
        bytes memory signature = _getPermitsignature(permit);
        sr.permitStake(1e18, 1 days, signature);

        assertEq(rnt.balanceOf(alice), 9e18);
        assertEq(rnt.balanceOf(address(sr)), 31e18);
        vm.warp(block.timestamp + 29 days);
        sr.claim();
        assertEq(rnt.balanceOf(address(sr)), 31e18);
        assertEq(esrnt.balanceOf(alice), 29e18);
        esrnt.approve(address(sr), 20e18);
        vm.expectRevert("Staking period not ended");
        sr.redeem(20e18);
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
