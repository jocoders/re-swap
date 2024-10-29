// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library UQ112x112 {
  uint224 private constant Q112 = 2 ** 112;
  uint112 constant MAX_UINT112 = type(uint112).max;

  function encode(uint112 x) internal pure returns (uint224 z) {
    assembly {
      z := shl(112, x)
    }
  }

  function decode(uint224 x) internal pure returns (uint256 z) {
    assembly {
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
}
