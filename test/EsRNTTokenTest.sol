// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {EsRNTToken} from "../src/EsRNTToken.sol";

contract EsRNTTokenTest is Test {
    EsRNTToken public esrnt;

    address internal owner = makeAddr("owner");

    function setUp() public {
        esrnt = new EsRNTToken(owner);
    }
}
