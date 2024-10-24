// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReSwapPair} from "../src/ReSwapPair.sol";
import {Test, console2} from "forge-std/Test.sol";

contract ReSwapPairTestHelper is ReSwapPair {
    function testValidateSwap(uint256 _amountOut0, uint256 _amountOut1, uint112 reserveA, uint112 reserveB)
        public
        pure
    {
        super.validateSwap(_amountOut0, _amountOut1, reserveA, reserveB);
    }

    function testUpdate(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) public {
        super.update(balance0, balance1, _reserve0, _reserve1);
    }

    function testGetReserves() public view returns (uint112, uint112) {
        return super.getReserves();
    }

    function testTransferPair(uint256 amountOut0, uint256 amountOut1, address to) public {
        super.transferPair(amountOut0, amountOut1, to);
    }
}
