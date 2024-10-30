// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title A library for event handling in Solidity smart contracts
/// @notice This library provides utility functions to work with events more efficiently
/// @dev This library can be used with any contract that emits events
library EventHelper {
  /// @notice Logs a mint event with specified amounts
  /// @dev This function logs events directly to the Ethereum Virtual Machine log
  /// @param amount0 The first amount to log
  /// @param amount1 The second amount to log
  function emitMint(uint256 amount0, uint256 amount1) internal {
    assembly {
      let eventMintHash := 0x4c209b5fc8ad50758f13e2e1088ba56a560dff690a1c6fef26394f4c03821c4f
      let sender := caller()

      mstore(0x20, amount0)
      mstore(0x40, amount1)
      log2(0x20, 0x40, eventMintHash, sender)
    }
  }

  /// @notice Logs a burn event with specified amounts to a specific address
  /// @dev Logs are emitted using low-level assembly for efficiency
  /// @param to The address where tokens are burned
  /// @param amount0 The first amount of tokens burned
  /// @param amount1 The second amount of tokens burned
  function emitBurn(address to, uint256 amount0, uint256 amount1) internal {
    assembly {
      let eventBurnHash := 0x5d624aa9c148153ab3446c1b154f660ee7701e549fe9b62dab7171b1c80e6fa2
      let sender := caller()

      mstore(0x20, amount0)
      mstore(0x40, amount1)
      log3(0x00, 0x40, eventBurnHash, sender, to)
    }
  }

  /// @notice Logs a swap event detailing amounts in and out for a swap operation
  /// @dev Utilizes inline assembly for optimized event logging
  /// @param to The recipient of the swap output
  /// @param amountIn0 Input amount of the first token
  /// @param amountIn1 Input amount of the second token
  /// @param amountOut0 Output amount of the first token
  /// @param amountOut1 Output amount of the second token
  function emitSwap(address to, uint256 amountIn0, uint256 amountIn1, uint256 amountOut0, uint256 amountOut1) internal {
    assembly {
      let eventSwapHash := 0x4937157c05c26764385efdf746290ea19ec0a9d658c87cbb3f09b1164f45dced
      let sender := caller()

      mstore(0x00, amountIn0)
      mstore(0x20, amountIn1)
      mstore(0x40, amountOut0)
      mstore(0x60, amountOut1)
      log3(0x00, 0x80, eventSwapHash, sender, to)
    }
  }

  /// @notice Logs an update event for reserve changes
  /// @dev Efficiently logs reserve updates using assembly
  /// @param _reserve0 New reserve amount for the first token
  /// @param _reserve1 New reserve amount for the second token
  function emitUpdate(uint112 _reserve0, uint112 _reserve1) internal {
    assembly {
      let eventUpdateHash := 0x8ecf343d22d1934aea3fb34b7332371552b19286c5bc696adae16c7690a90d54

      mstore(0x00, _reserve0)
      mstore(0x20, _reserve1)
      log1(0x00, 0x40, eventUpdateHash)
    }
  }
}
