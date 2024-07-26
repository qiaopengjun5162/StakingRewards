// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {EsRNTToken} from "../src/EsRNTToken.sol";
import {RNTToken} from "../src/RNTToken.sol";

contract StakingRewardsScript is Script {
    StakingRewards public staking_rewards;
    RNTToken public rnt;
    EsRNTToken public esrnt;

    Account owner = makeAccount("owner");

    function setUp() public {
        rnt = new RNTToken(owner.addr);

        esrnt = new EsRNTToken(address(rnt));
    }

    function run() public {
        vm.startBroadcast();

        staking_rewards = new StakingRewards(address(rnt), address(esrnt));

        vm.stopBroadcast();
    }
}
