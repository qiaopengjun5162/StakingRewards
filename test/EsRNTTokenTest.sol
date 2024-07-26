// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {EsRNTToken} from "../src/EsRNTToken.sol";
import {RNTToken} from "../src/RNTToken.sol";

contract EsRNTTokenTest is Test {
    RNTToken public rnt;
    EsRNTToken public esrnt;

    address internal owner = makeAddr("owner");

    function setUp() public {
        rnt = new RNTToken(owner);
        esrnt = new EsRNTToken(address(esrnt));
    }
}
