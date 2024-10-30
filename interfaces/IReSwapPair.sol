// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Interface for ReSwap Pair
/// @notice This interface handles the pair functionalities in the ReSwap decentralized exchange.
interface IReSwapPair {
  /// @notice Returns the minimum liquidity enforced by the protocol
  /// @return The minimum liquidity threshold
  function MINIMUM_LIQUIDITY() external pure returns (uint);

  /// @notice Returns the factory address that created the pair
  /// @return The factory address
  function factory() external view returns (address);

  /// @notice Returns the address of the first token in the pair
  /// @return The address of token0
  function token0() external view returns (address);

  /// @notice Returns the address of the second token in the pair
  /// @return The address of token1
  function token1() external view returns (address);

  /// @notice Returns the last stored cumulative price of token0
  /// @return The last cumulative price of token0
  function lastCumulativePrice0() external view returns (uint);

  /// @notice Returns the last stored cumulative price of token1
  /// @return The last cumulative price of token1
  function lastCumulativePrice1() external view returns (uint);

  /// @notice Returns the last recorded value of the constant product (k) of the reserves
  /// @return The last recorded constant product k
  function lastK() external view returns (uint);

  /// @notice Adds liquidity to the pool and mints new LP tokens to the provided address
  /// @param to The address to which the minted liquidity tokens will be sent
  /// @return liquidity The amount of liquidity tokens minted
  function mint(address to) external returns (uint liquidity);

  /// @notice Removes liquidity from the pool and returns the underlying tokens to the provided address
  /// @param to The address to which the underlying tokens will be sent
  /// @return amount0 The amount of token0 returned
  /// @return amount1 The amount of token1 returned
  function burn(address to) external returns (uint amount0, uint amount1);

  /// @notice Executes a swap of tokens within the pair
  /// @param amount0Out The amount of token0 to send to the `to` address
  /// @param amount1Out The amount of token1 to send to the `to` address
  /// @param to The recipient of the tokens
  /// @param data Additional data passed to the callback function, if any
  function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

  /// @notice Skims excess tokens from the contract to the provided address
  /// @param to The address to which the skimmed tokens will be sent
  function skim(address to) external;

  /// @notice Synchronizes the reserves of token0 and token1 with the actual balances
  function sync() external;

  /// @notice Initializes the pair with the given token addresses
  /// @param tokenA The address of the first token
  /// @param tokenB The address of the second token
  function initialize(address tokenA, address tokenB) external;
}
