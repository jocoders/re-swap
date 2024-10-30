// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title A library for safe token transfers
/// @notice This library provides functions to safely transfer tokens and ETH
/// @dev This library uses low-level call and assembly to perform transfers
library TransferHelper {
  /// @notice Transfers tokens from one address to another
  /// @dev This function uses a low-level call to transfer tokens and reverts on failure
  /// @param token The address of the ERC-20 token
  /// @param from The address to transfer tokens from
  /// @param to The address to transfer tokens to
  /// @param value The amount of tokens to transfer
  function safeTransferFrom(address token, address from, address to, uint256 value) public {
    assembly {
      let callData := mload(0x40)

      mstore(callData, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
      mstore(add(callData, 0x04), from)
      mstore(add(callData, 0x24), to)
      mstore(add(callData, 0x44), value)

      let success := call(gas(), token, 0, callData, 0x64, 0, 0)

      let dataSize := returndatasize()
      returndatacopy(callData, 0, dataSize)

      if or(iszero(success), or(iszero(eq(dataSize, 0x20)), iszero(mload(callData)))) {
        let selector := 0xf4059071 // SafeTransferFromFailed()
        mstore(0x00, selector)
        mstore(0x04, token)
        mstore(0x24, value)
        revert(0x00, 0x44)
      }
    }
  }

  /// @notice Transfers ETH to an address
  /// @dev This function uses a low-level call to transfer ETH and reverts on failure
  /// @param to The address to transfer ETH to
  /// @param value The amount of ETH to transfer
  function safeTransferETH(address to, uint256 value) internal {
    assembly {
      let success := call(gas(), to, value, 0, 0, 0, 0)

      if iszero(success) {
        let selector := 0xb12d13eb //  ETHTransferFailed()
        mstore(0x00, 0xb12d13eb)
        revert(0x00, 0x04)
      }
    }
  }

  /// @notice Transfers tokens to an address
  /// @dev This function uses a low-level call to transfer tokens and reverts on failure
  /// @param token The address of the ERC-20 token
  /// @param to The address to transfer tokens to
  /// @param value The amount of tokens to transfer
  function safeTransfer(address token, address to, uint256 value) public {
    assembly {
      let callData := mload(0x40)
      mstore(callData, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
      mstore(add(callData, 0x04), to)
      mstore(add(callData, 0x24), value)

      let success := call(gas(), token, 0, callData, 0x44, 0, 0)

      let dataSize := returndatasize()
      returndatacopy(callData, 0, dataSize)

      mstore(0x00, success)
      log1(0x00, 0x20, 0x123456789)

      if or(iszero(success), or(iszero(eq(dataSize, 0x20)), iszero(mload(callData)))) {
        let selector := 0xfb7f5079 // SafeTransferFailed()
        mstore(0x00, selector)
        mstore(0x04, token)
        mstore(0x24, value)
        revert(0x00, 0x44)
      }
    }
  }
}
