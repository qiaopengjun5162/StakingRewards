// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RNTToken} from "../src/RNTToken.sol";

contract RNTTokenTest is Test {
    RNTToken public rnt;
    address public owner = makeAddr("owner");
    address public bob = makeAddr("bob");

    function setUp() public {
        rnt = new RNTToken(owner);
    }
}
