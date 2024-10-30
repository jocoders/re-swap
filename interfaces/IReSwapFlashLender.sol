// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IReSwapFlashBorrower } from './IReSwapFlashBorrower.sol';

/// @title Interface for the ReSwap Flash Lending functionality
interface IReSwapFlashLender {
  /// @notice Calculates the maximum loan amount available for a specific token
  /// @param token The address of the token for which the max loan amount is queried
  /// @return The maximum amount of the token that can be loaned
  function maxFlashLoan(address token) external view returns (uint256);

  /// @notice Calculates the fee for a flash loan of a specific amount of a given token
  /// @param token The token for which the flash loan is requested
  /// @param amount The amount of the token for which the fee is calculated
  /// @return The fee amount for the flash loan
  function flashFee(address token, uint256 amount) external view returns (uint256);

  /// @notice Executes a flash loan transaction
  /// @dev This function allows users to borrow and return a loan within one transaction
  /// @param receiver The contract that receives and is responsible for returning the flash loan
  /// @param token The address of the token to be borrowed
  /// @param amount The amount of the token to be borrowed
  /// @param data Arbitrary data passed to the receiver's `executeOperation` function
  /// @return True if the loan was successful, otherwise reverts
  function flashLoan(
    IReSwapFlashBorrower receiver,
    address token,
    uint256 amount,
    bytes calldata data
  ) external returns (bool);
}
