// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UQ112x112} from "../libraries/UQ112x112.sol";

contract UQ112x112Test is Test {
    uint112 constant UINT_112_MAX = type(uint112).max;
    uint224 constant UINT_224_MAX = type(uint224).max;

    error OverflowError();
    error DivisionByZeroError();

    function testEncodeDecode() public pure {
        uint112 input = 123456789;

        uint224 encoded = UQ112x112.encode(input);
        uint256 decoded = UQ112x112.decode(encoded);

        assertEq(decoded, input, "Encode followed by decode should return the original value");
    }

    function testDecodeOverflow() public {
        vm.expectRevert();
        UQ112x112.encode(UINT_112_MAX + 1);

        uint224 encodedZero = UQ112x112.encode(0);
        uint256 decodedZero = UQ112x112.decode(encodedZero);
        assertEq(decodedZero, 0, "Decoding zero should return zero");
    }

    function testDivision() public pure {
        uint224 x = UQ112x112.encode(890350);
        uint112 y = 25;

        uint224 result = UQ112x112.uqdiv(x, y);
        uint256 decodedResult = UQ112x112.decode(result);

        assertEq(decodedResult, 35614, "890350 divided by 25 should be 35614");
    }

    function testDivisionByZero() public {
        uint224 x = UQ112x112.encode(890350);

        vm.expectRevert();
        UQ112x112.uqdiv(x, 0);
    }

    function testEncodeMaxInput() public pure {
        uint224 encoded = UQ112x112.encode(UINT_112_MAX);
        uint256 decoded = UQ112x112.decode(encoded);
        assertEq(decoded, UINT_112_MAX, "Encoding and decoding max input should return the original value");
    }
}
