// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title A library for handling 112x112 fixed point numbers
/// @notice Provides functions for encoding, decoding, and dividing uint112 values using a fixed point format
/// @dev This library uses a fixed point format with 112 fractional bits
library UQ112x112 {
  uint224 private constant Q112 = 2 ** 112;
  uint112 constant MAX_UINT112 = type(uint112).max;

  /// @notice Encodes a uint112 as a UQ112x112
  /// @dev Encodes by shifting the uint112 value left by 112 bits
  /// @param x The uint112 value to encode
  /// @return z The encoded UQ112x112 value
  function encode(uint112 x) internal pure returns (uint224 z) {
    assembly {
      z := shl(112, x)
    }
  }

  /// @notice Decodes a UQ112x112 to a uint256
  /// @dev Decodes by dividing the UQ112x112 value by Q112
  /// @param x The UQ112x112 value to decode
  /// @return z The decoded uint256 value
  function decode(uint224 x) internal pure returns (uint256 z) {
    assembly {
      let q112 := 0x10000000000000000000000000000
      z := div(x, q112)
    }
  }

  /// @notice Divides one UQ112x112 by a uint112, returning a UQ112x112
  /// @dev Performs division after checking for division by zero
  /// @param x The UQ112x112 numerator
  /// @param y The uint112 denominator
  /// @return z The result of the division as a UQ112x112
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
