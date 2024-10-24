// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IReSwapPair {
  function MINIMUM_LIQUIDITY() external pure returns (uint);
  function factory() external view returns (address);
  function token0() external view returns (address);
  function token1() external view returns (address);
  function lastCumulativePrice0() external view returns (uint);
  function lastCumulativePrice1() external view returns (uint);
  function lastK() external view returns (uint);
  function mint(address to) external returns (uint liquidity);
  function burn(address to) external returns (uint amount0, uint amount1);
  function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
  function skim(address to) external;
  function sync() external;
  function initialize(address, address) external;
  // function update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) public;
}
