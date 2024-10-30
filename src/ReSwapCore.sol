// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title ReSwapCore Contract
/// @notice Manages core functionalities for ReSwap, including token reserves and balances
/// @dev This contract handles low-level operations using assembly for optimal gas usage
contract ReSwapCore {
    // SLOT_TOKEN_0
    address public token0;

    // SLOT_TOKEN_1
    address public token1;

    // SLOT_RESERVES
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private lastTimestamp;

    /// @dev Constants for storage slots to ensure correct storage layout
    uint256 constant SLOT_TOKEN_0 = 0;
    uint256 constant SLOT_TOKEN_1 = 1;
    uint256 constant SLOT_RESERVES = 2;

    /// @dev Error for incorrect inheritance order in derived contracts
    error FirstInInheritance(uint256 slotToken0, uint256 slotToken1);

    /// @notice Initializes the contract ensuring correct slot positions for token addresses
    constructor() {
        assembly {
            let slotToken0 := token0.slot
            let slotToken1 := token1.slot

            if and(iszero(eq(slotToken0, SLOT_TOKEN_0)), iszero(eq(slotToken1, SLOT_TOKEN_1))) {
                let selector := 0xd1a150a1 // FirstInInheritance(uint256,uint256)
                let ptr := mload(0x40)

                mstore(ptr, selector)
                mstore(add(ptr, 0x04), slotToken0)
                mstore(add(ptr, 0x24), slotToken1)

                revert(ptr, 0x44)
            }
        }
    }

    /// @notice Initializes token addresses
    /// @param _token0 Address of the first token
    /// @param _token1 Address of the second token
    function initialize(address _token0, address _token1) public virtual {
        token0 = _token0;
        token1 = _token1;
    }

    /// @notice Retrieves the balances of both tokens
    /// @return _balance0 Balance of token0
    /// @return _balance1 Balance of token1
    function getBalances() public view returns (uint256 _balance0, uint256 _balance1) {
        _balance0 = getBalance0();
        _balance1 = getBalance1();
    }

    /// @notice Retrieves the reserves for both tokens
    /// @return _reserve0 Reserve of token0
    /// @return _reserve1 Reserve of token1
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1) {
        assembly {
            let data := sload(SLOT_RESERVES)
            _reserve0 := and(data, 0xfffffffffffffffffffff)
            _reserve1 := and(shr(112, data), 0xfffffffffffffffffffff)
        }
    }

    /// @notice Retrieves the last timestamp when reserves were updated
    /// @return _lastTimestamp The last update timestamp
    function getLastTimestamp() public view returns (uint32 _lastTimestamp) {
        assembly {
            let data := sload(SLOT_RESERVES)
            _lastTimestamp := and(shr(224, data), 0xffffffff)
        }
    }

    /// @dev Updates the reserves and timestamp in a single storage slot
    /// @param _reserve0 New reserve for token0
    /// @param _reserve1 New reserve for token1
    /// @param _lastTimestamp New timestamp
    function updateReserves(uint112 _reserve0, uint112 _reserve1, uint32 _lastTimestamp) internal {
        assembly {
            let combined := or(or(_reserve0, shl(112, _reserve1)), shl(224, _lastTimestamp))
            sstore(SLOT_RESERVES, combined)
        }
    }

    /// @dev Retrieves balances in a sorted order based on the token address
    /// @param tokenA Address of the token to compare
    /// @return _balance0 Balance of the first token
    /// @return _balance1 Balance of the second token
    function getSortedBalances(address tokenA) internal view returns (uint256 _balance0, uint256 _balance1) {
        if (isToken0(tokenA)) {
            _balance0 = getBalance0();
            _balance1 = getBalance1();
        } else {
            _balance0 = getBalance1();
            _balance1 = getBalance0();
        }
    }

    /// @dev Retrieves reserves in a sorted order based on the token address
    /// @param tokenA Address of the token to compare
    /// @return reserveA Reserve of the first token
    /// @return reserveB Reserve of the second token
    function getSortedReserves(address tokenA) internal view returns (uint112 reserveA, uint112 reserveB) {
        (uint112 r0, uint112 r1) = getReserves();

        if (isToken0(tokenA)) {
            reserveA = r0;
            reserveB = r1;
        } else {
            reserveA = r1;
            reserveB = r0;
        }
    }

    /// @dev Retrieves the addresses of token0 and token1 from storage
    /// @return _token0 Address of the first token
    /// @return _token1 Address of the second token
    function getTokensAddress() internal view returns (address _token0, address _token1) {
        assembly {
            _token0 := sload(SLOT_TOKEN_0)
            _token1 := sload(SLOT_TOKEN_1)
        }
    }

    /// @dev Returns the balance of a specified token
    /// @param token The address of the token to query
    /// @return _balance The balance of the specified token
    function getBalanceByToken(address token) internal view returns (uint256 _balance) {
        if (isToken0(token)) {
            _balance = getBalance0();
        } else {
            _balance = getBalance1();
        }
    }

    /// @dev Validates that a given deadline has not passed
    /// @param deadline The deadline timestamp to validate against the current block timestamp
    function validateDeadline(uint256 deadline) internal view {
        assembly {
            if lt(deadline, timestamp()) {
                let selector := 0xf87d9271 // ExpiredDeadline()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }
        }
    }

    /// @dev Calculates the maximum flash loan amount available for a given token
    /// @param tokenFL The address of the token for which the flash loan is requested
    /// @return loan The maximum amount that can be loaned
    function getMaxFlashLoan(address tokenFL) internal view returns (uint256 loan) {
        validateToken(tokenFL);
        uint256 percent = getPercentFL(tokenFL);
        address _token0;
        assembly {
            _token0 := sload(SLOT_TOKEN_0)
        }

        if (tokenFL == token0) {
            loan = (reserve0 * percent) / 1000;
        } else {
            loan = (reserve1 * percent) / 1000;
        }
    }

    /// @dev Retrieves the balance of token0
    /// @return _balance0 The balance of token0
    function getBalance0() internal view returns (uint256 _balance0) {
        _balance0 = getTokenBalance(SLOT_TOKEN_0);
    }

    /// @dev Retrieves the balance of token1
    /// @return _balance1 The balance of token1
    function getBalance1() internal view returns (uint256 _balance1) {
        _balance1 = getTokenBalance(SLOT_TOKEN_1);
    }

    /// @dev Calculates the flash fee for a given amount of a specified token
    /// @param token The token for which the flash fee is calculated
    /// @param amount The amount of the token to calculate the fee on
    /// @return fee The calculated flash fee
    function getFlashFee(address token, uint256 amount) internal view returns (uint256 fee) {
        validateToken(token);
        assembly {
            fee := div(mul(amount, 3), 100)
        }
    }

    /// @dev Calculates the output amount for a given input amount and reserves
    /// @param amountIn The input amount
    /// @param reserveIn The reserve of the input token
    /// @param reserveOut The reserve of the output token
    /// @return amountOut The calculated output amount
    function getAmountOut(uint256 amountIn, uint112 reserveIn, uint112 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        checkReserves(amountIn, reserveIn, reserveOut);

        assembly {
            let amountInWithFee := mul(amountIn, 997)
            let numerator := mul(amountInWithFee, reserveOut)
            let denominator := add(mul(reserveIn, 1000), amountInWithFee)

            if iszero(denominator) {
                let selector := 0x23d359a3 // DivisionByZero()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }
            amountOut := div(numerator, denominator)
        }
    }

    /// @dev Calculates the input amount required to achieve a specific output amount given reserves
    /// @param amountOut The desired output amount
    /// @param reserveIn The reserve of the input token
    /// @param reserveOut The reserve of the output token
    /// @return amountIn The calculated input amount needed
    function getAmountIn(uint256 amountOut, uint112 reserveIn, uint112 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        checkReserves(amountOut, reserveIn, reserveOut);

        assembly {
            let numerator := mul(mul(reserveIn, amountOut), 1000)
            let temp := sub(reserveOut, amountOut)

            if iszero(gt(temp, 0)) {
                let selector := 0x47e42f56 // ReserveOutGTAmountOut()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }

            let denominator := mul(temp, 997)
            if iszero(denominator) {
                let selector := 0x23d359a3 // DivisionByZero()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }
            amountIn := add(div(numerator, denominator), 1)
        }
    }

    /// @dev Validates the swap amounts against the reserves
    /// @param amountOut0 The output amount of token0
    /// @param amountOut1 The output amount of token1
    /// @param reserveA The reserve of tokenA
    /// @param reserveB The reserve of tokenB
    function validateSwap(uint256 amountOut0, uint256 amountOut1, uint112 reserveA, uint112 reserveB) internal pure {
        assembly {
            if iszero(or(gt(amountOut0, 0), gt(amountOut1, 0))) {
                let selector := 0x42301c23 // InsufficientOutputAmount()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }
            if or(iszero(lt(amountOut0, reserveA)), iszero(lt(amountOut1, reserveB))) {
                let selector := 0xbb55fd27 // InsufficientLiquidity()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }
        }
    }

    /// @dev Checks if the given amount and reserves are sufficient
    /// @param amount0 The amount of token0
    /// @param _reserve0 The reserve of token0
    /// @param _reserve1 The reserve of token1
    function checkReserves(uint256 amount0, uint256 _reserve0, uint256 _reserve1) internal pure {
        assembly {
            if iszero(gt(amount0, 0)) {
                let selector := 0x5945ea56 // InsufficientAmount()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }

            if iszero(and(gt(_reserve0, 0), gt(_reserve1, 0))) {
                let selector := 0xbb55fd27 // InsufficientLiquidity()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }
        }
    }

    /// @dev Calculates the output amount for a given input amount and reserves
    /// @param amount0 The input amount
    /// @param r0 The reserve of the input token
    /// @param r1 The reserve of the output token
    /// @return amount1 The calculated output amount
    function quote(uint256 amount0, uint256 r0, uint256 r1) internal pure returns (uint256 amount1) {
        checkReserves(amount0, r0, r1);
        assembly {
            amount1 := div(mul(amount0, r1), r0)
        }
    }

    /// @dev Checks if the given address is the address of token0
    /// @param token The address to check against token0
    /// @return True if the given address is token0, false otherwise
    function isToken0(address token) private view returns (bool) {
        address _token0;
        assembly {
            _token0 := sload(SLOT_TOKEN_0)
        }
        return token == _token0;
    }

    /// @dev Validates that the given token address is either token0 or token1
    /// @param token The token address to validate
    /// @notice This function will revert the transaction if the token is neither token0 nor token1
    function validateToken(address token) private view {
        assembly {
            let _token0 := sload(SLOT_TOKEN_0)
            let _token1 := sload(SLOT_TOKEN_1)

            if iszero(or(eq(token, _token0), eq(token, _token1))) {
                let selector := 0xc1ab6dc1 // InvalidToken()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }
        }
    }

    /// @dev Calculates the percentage for flash loans based on token reserves
    /// @param tokenFL The address of the token for which the flash loan percentage is calculated
    /// @return percent The calculated percentage for flash loans
    function getPercentFL(address tokenFL) private view returns (uint256 percent) {
        (uint112 r0, uint112 r1) = getReserves();
        assembly {
            let _token0 := sload(SLOT_TOKEN_0)

            let maxPercent := 100
            let minPercent := 50

            let isTokenFL0 := eq(tokenFL, _token0)
            let ratio

            switch isTokenFL0
            case 0 { ratio := div(mul(r1, 1000), r0) }
            default { ratio := div(mul(r0, 1000), r1) }

            let basePercent := 100
            let isTokenOverSold := iszero(gt(ratio, 1000))

            switch isTokenOverSold
            case 0 { percent := maxPercent }
            default { percent := minPercent }
        }
    }

    /// @dev Retrieves the balance of a token stored at a specific slot
    /// @param slot The storage slot of the token
    /// @return bal The balance of the token
    function getTokenBalance(uint256 slot) private view returns (uint256 bal) {
        assembly {
            let token := sload(slot)
            let ptr := mload(0x40)
            mstore(ptr, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x04), address())
            let success := staticcall(gas(), token, ptr, 0x24, ptr, 0x20)
            if iszero(success) { revert(0, 0) }
            bal := mload(ptr)
        }
    }
}
