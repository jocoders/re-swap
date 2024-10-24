// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library TransferHelper {
  function safeTransferFrom(address token, address from, address to, uint256 value) public {
    assembly {
      let callData := mload(0x40)

      mstore(callData, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
      mstore(add(callData, 0x04), from)
      mstore(add(callData, 0x24), to)
      mstore(add(callData, 0x44), value)

      let success := call(
        gas(), // Передаем доступный газ
        token, // Адрес токена
        0, // Нет передачи ETH
        callData, // Указатель на calldata
        0x64, // Длина calldata (4 байта селектор + 32 байта from + 32 байта to + 32 байта value)
        0, // Место для ответа (не сохраняем ответ)
        0 // Длина ответа
      )

      let dataSize := returndatasize()
      returndatacopy(callData, 0, dataSize)

      // Check for boolean success
      if or(iszero(success), or(iszero(eq(dataSize, 0x20)), iszero(mload(callData)))) {
        // Set custom error selector with two parameters
        let selector := 0xf4059071 // SafeTransferFromFailed()
        mstore(0x00, selector)
        mstore(0x04, token)
        mstore(0x24, value)
        revert(0x00, 0x44) // Revert with selector and arguments (4 + 32 + 32 bytes)
      }
    }
  }

  function safeTransferETH(address to, uint256 value) internal {
    assembly {
      // Попытка отправить ETH с использованием call
      let success := call(gas(), to, value, 0, 0, 0, 0)

      // Проверка на успех
      if iszero(success) {
        let selector := 0xb12d13eb //  ETHTransferFailed()
        mstore(0x00, 0xb12d13eb)
        revert(0x00, 0x04)
      }
    }
  }

  function safeTransfer(address token, address to, uint256 value) public {
    assembly {
      // Allocate memory for the call data: selector + address (20 bytes) + uint256 (32 bytes)
      let callData := mload(0x40) // Load the free memory pointer
      mstore(callData, 0xa9059cbb00000000000000000000000000000000000000000000000000000000) // Store the selector at the start of the call data
      mstore(add(callData, 0x04), to) // Store the 'to' address after the selector
      mstore(add(callData, 0x24), value) // Store the 'value' after the address

      // Perform the call
      let success := call(
        gas(), // forward all gas
        token, // address of the token contract
        0, // no ether to be sent
        callData, // pointer to start of input
        0x44, // length of input (selector + address + uint256)
        0, // output will be at position 0
        0 // output is zero bytes
      )

      let dataSize := returndatasize()
      returndatacopy(callData, 0, dataSize) // Copy return data to callData position for easier access

      // Log to see output details
      mstore(0x00, success)
      log1(0x00, 0x20, 0x123456789) // Logging success

      // Check for boolean success
      if or(iszero(success), or(iszero(eq(dataSize, 0x20)), iszero(mload(callData)))) {
        // Set custom error selector with two parameters
        let selector := 0xfb7f5079 // SafeTransferFailed()
        mstore(0x00, selector)
        mstore(0x04, token)
        mstore(0x24, value)
        revert(0x00, 0x44) // Revert with selector and arguments (4 + 32 + 32 bytes)
      }
    }
  }
}
