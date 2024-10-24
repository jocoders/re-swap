// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UQ112x112 {
  uint224 private constant Q112 = 2 ** 112;
  uint112 constant MAX_UINT112 = type(uint112).max;

  error OverflowError();
  error DivisionByZeroError();

  function encode(uint112 x) internal pure returns (uint224 z) {
    assembly {
      if gt(x, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
        let OverflowErrorSelector := 0x3050f6b6
        mstore(0x00, OverflowErrorSelector)
        revert(0x00, 0x04)
      }

      z := shl(112, x)
    }
  }

  function decode(uint224 x) internal pure returns (uint256 z) {
    assembly {
      if gt(x, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
        let OverflowErrorSelector := 0x3050f6b6
        mstore(0x00, OverflowErrorSelector)
        revert(0x00, 0x04)
      }

      let q112 := 0x10000000000000000000000000000
      z := div(x, q112)
    }
  }

  function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
    assembly {
      if iszero(y) {
        let DivisionByZeroErrorSelector := 0xa791837c
        mstore(0x00, DivisionByZeroErrorSelector)
        revert(0x00, 0x04)
      }

      z := div(x, y)
    }
  }

  // function uqdivX(uint224 x, uint112 y) internal pure returns (uint224 z) {
  //   require(y > 0, 'Division by zero');
  //   z = x / uint224(y);
  // }

  // function uqmul(uint224 x, uint224 y) internal pure returns (uint224 z) {
  //   z = (x * y) >> 112;
  // }

  // function toUint256(uint224 x) internal pure returns (uint256 z) {
  //   z = uint256(x) / Q112; // Converts back to a standard integer format
  // }

  // function encodeX(uint112 y) internal pure returns (uint224 z) {
  //   if (y > MAX_UINT112) {
  //     revert OverflowError();
  //   }
  //   z = uint224(y) << 112; // equivalent to y * 2^112
  // }

  // function decodeX(uint224 x) internal pure returns (uint112 y) {
  //   if (x > type(uint224).max) {
  //     revert OverflowError();
  //   }
  //   y = uint112(x >> 112); // equivalent to x / 2^112
  // }
}
