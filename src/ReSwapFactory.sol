// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReSwapPair} from "./ReSwapPair.sol";

/// @title A factory for creating new ReSwap pairs
/// @notice This contract allows users to create new liquidity pairs and manage fees
/// @dev This contract uses create2 for deterministic address generation
contract ReSwapFactory {
    /// @notice Address where fees are sent
    address public feeTo;
    /// @notice Address allowed to set the feeTo address
    address public feeToSetter;

    /// @notice Array of all pairs created
    address[] public allPairs;
    /// @notice Mapping of token addresses to pairs
    mapping(address => mapping(address => address)) public getPair;

    /// @notice An event emitted when a pair is created
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    /// @notice Creates a factory managed by `_feeToSetter`
    /// @param _feeToSetter The address that will be allowed to set feeTo
    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    /// @notice Creates a new pair for two tokens
    /// @dev Throws if the pair already exists or if token addresses are invalid
    /// @param tokenA The first token of the pair
    /// @param tokenB The second token of the pair
    /// @return pair The address of the newly created pair
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "TOKEN_A_EQUALS_TOKEN_B");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "PAIR_EXISTS");
        bytes memory bytecode = type(ReSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ReSwapPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /// @notice Returns the number of all pairs created
    /// @return The number of all pairs
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Sets the address to which fees are sent
    /// @dev Only callable by the current feeToSetter
    /// @param _feeTo The address that will receive the fees
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "SENDER_NOT_FEE_TO_SETTER");
        feeTo = _feeTo;
    }

    /// @notice Sets the address allowed to set the feeTo address
    /// @dev Only callable by the current feeToSetter
    /// @param _feeToSetter The new address that will be allowed to set feeTo
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "SENDER_NOT_FEE_TO_SETTER");
        feeToSetter = _feeToSetter;
    }
}
