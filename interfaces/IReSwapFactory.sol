// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Interface for the ReSwap Factory
/// @notice This interface manages the creation and tracking of token pairs for the ReSwap decentralized exchange.
interface IReSwapFactory {
  /// @notice Emitted when a new pair is created
  /// @param token0 The address of the first token in the pair
  /// @param token1 The address of the second token in the pair
  /// @param pair The address of the newly created token pair
  /// @param index The index of this pair in the list of all pairs
  event PairCreated(address indexed token0, address indexed token1, address pair, uint index);

  /// @notice Returns the address to which trading fees are sent
  /// @return The address of the fee recipient
  function feeTo() external view returns (address);

  /// @notice Returns the address allowed to set the fee recipient
  /// @return The address of the fee setter
  function feeToSetter() external view returns (address);

  /// @notice Returns the address of the pair for given tokens
  /// @param tokenA The address of the first token
  /// @param tokenB The address of the second token
  /// @return pair The address of the pair
  function getPair(address tokenA, address tokenB) external view returns (address pair);

  /// @notice Returns the address of the pair at a given index
  /// @param index The index of the pair in the list
  /// @return pair The address of the pair
  function allPairs(uint index) external view returns (address pair);

  /// @notice Returns the total number of pairs created
  /// @return The total number of pairs
  function allPairsLength() external view returns (uint);

  /// @notice Creates a pair for two tokens and returns the address of the pair
  /// @param tokenA The address of the first token
  /// @param tokenB The address of the second token
  /// @return pair The address of the newly created token pair
  function createPair(address tokenA, address tokenB) external returns (address pair);

  /// @notice Sets the address to which trading fees are sent
  /// @param _feeTo The address of the fee recipient
  function setFeeTo(address _feeTo) external;

  /// @notice Sets the address allowed to set the fee recipient
  /// @param _feeToSetter The address of the fee setter
  function setFeeToSetter(address _feeToSetter) external;
}
