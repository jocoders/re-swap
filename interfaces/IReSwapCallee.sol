// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Interface for the ReSwap Callback Functionality
/// @notice This interface is used for the ReSwap callback mechanism, allowing users to implement custom logic to be executed during swaps.
interface IReSwapCallee {
  /**
   * @notice Handles custom logic that executes as part of a swap operation in ReSwap
   * @dev This function is called by the ReSwap contract during a swap operation. Implementers can include any logic that needs to execute atomically with the swap.
   * @param sender The address of the caller that initiated the swap operation
   * @param amount0 The amount of token0 being swapped
   * @param amount1 The amount of token1 being swapped
   * @param data Arbitrary data passed from the caller, can be used to encode additional information needed by the callee
   */
  function reSwapCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
