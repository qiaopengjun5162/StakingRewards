// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {RNTToken} from "../src/RNTToken.sol";
import {EsRNTToken} from "../src/EsRNTToken.sol";

contract EsRNTTokenScript is Script {
    EsRNTToken public es;
    RNTToken public rnt;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with the account:", deployerAddress);
        vm.startBroadcast(deployerPrivateKey);
        rnt = new RNTToken(deployerAddress);
        es = new EsRNTToken(address(rnt));

        vm.stopBroadcast();
    }
}
