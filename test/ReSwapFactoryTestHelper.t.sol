// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReSwapFactory} from "../src/ReSwapFactory.sol";
import {ReSwapPairTestHelper} from "./ReSwapPairTestHelper.t.sol";

contract ReSwapFactoryTestHelper is ReSwapFactory {
    constructor() ReSwapFactory(msg.sender) {}

    function testCreatePair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "TOKEN_A_EQUALS_TOKEN_B");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS"); // single check is sufficient
        bytes memory bytecode = type(ReSwapPairTestHelper).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ReSwapPairTestHelper(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
