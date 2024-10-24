// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IReSwapFlashBorrower } from './IReSwapFlashBorrower.sol';

interface IReSwapFlashLender {
  function maxFlashLoan(address token) external view returns (uint256);

  function flashFee(address token, uint256 amount) external view returns (uint256);

  function flashLoan(
    IReSwapFlashBorrower receiver,
    address token,
    uint256 amount,
    bytes calldata data
  ) external returns (bool);
}
