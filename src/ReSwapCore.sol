// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/Test.sol";

contract ReSwapCore {
    // Slot 0 - do not change order of variables!!!
    address public token0;

    // Slot 1 - do not change order of variables
    address public token1;

    // Slot 2 - do not change order of variables
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private lastTimestamp;

    uint256 constant SLOT_TOKEN_0 = 0;
    uint256 constant SLOT_TOKEN_1 = 1;
    uint256 constant SLOT_RESERVES = 2;

    function getBalances() public view returns (uint256 _balance0, uint256 _balance1) {
        _balance0 = getBalance0();
        _balance1 = getBalance1();
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1) {
        assembly {
            let data := sload(SLOT_RESERVES) // Загрузка данных из слота 6
            _reserve0 := and(data, 0xfffffffffffffffffffffffffff) // Маска для первых 112 бит
            _reserve1 := and(shr(112, data), 0xfffffffffffffffffffffffffff) // Сдвиг на 112 бит вправо и маска
        }
    }

    function getLastTimestamp() public view returns (uint32 _lastTimestamp) {
        assembly {
            let data := sload(SLOT_RESERVES) // Загрузка данных из слота 6
            _lastTimestamp := and(shr(224, data), 0xffffffff) // Сдвиг на 224 бита вправо и маска для последних 32 бит
        }
    }

    function initializeTokens(address _token0, address _token1) internal {
        (address _t0, address _t1) = getSortPair(_token0, _token1);
        token0 = _t0;
        token1 = _t1;
    }

    function updateReserves(uint112 _reserve0, uint112 _reserve1, uint32 _lastTimestamp) internal {
        assembly {
            // Упаковываем _reserve0, _reserve1 и _lastTimestamp в один слот
            let combined := or(or(shl(144, _reserve0), shl(32, _reserve1)), _lastTimestamp)
            sstore(SLOT_RESERVES, combined)
        }
    }

    function getSortedBalances(address tokenA) internal view returns (uint256 _balance0, uint256 _balance1) {
        if (isToken0(tokenA)) {
            _balance0 = getBalance0();
            _balance1 = getBalance1();
        } else {
            _balance0 = getBalance1();
            _balance1 = getBalance0();
        }
    }

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

    function getTokensAddress() internal view returns (address _token0, address _token1) {
        assembly {
            _token0 := sload(SLOT_TOKEN_0)
            _token1 := sload(SLOT_TOKEN_1)
        }
    }

    function getBalanceByToken(address token) internal view returns (uint256 _balance) {
        if (isToken0(token)) {
            _balance = getBalance0();
        } else {
            _balance = getBalance1();
        }
    }

    function validateDeadline(uint256 deadline) internal view {
        assembly {
            if lt(deadline, timestamp()) {
                let selector := 0xf87d9271 // ExpiredDeadline()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }
        }
    }

    function getMaxFlashLoan(address tokenFL) internal view returns (uint256 loan) {
        validateToken(tokenFL);
        uint256 percent = getPercentFL(tokenFL);
        address _token0;
        assembly {
            _token0 := sload(SLOT_TOKEN_0)
        }

        if (tokenFL == token0) {
            // Если токеном для flash loan является token0
            loan = (reserve0 * percent) / 1000; // Делим на 1000, так как процент в тысячных долях
        } else {
            // Если токеном для flash loan является token1
            loan = (reserve1 * percent) / 1000; // Делим на 1000 для корректного расчета
        }
    }

    function getBalance0() internal view returns (uint256 _balance0) {
        _balance0 = getTokenBalance(SLOT_TOKEN_0);
    }

    function getBalance1() internal view returns (uint256 _balance0) {
        _balance0 = getTokenBalance(SLOT_TOKEN_1);
    }

    function getFlashFee(address token, uint256 amount) internal view returns (uint256 fee) {
        validateToken(token);
        fee = (amount * 1003) / 1000;
    }

    function getAmountOut(uint256 amountIn, uint112 reserveIn, uint112 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        checkReserves(amountIn, reserveIn, reserveOut);

        assembly {
            // Calculate amountInWithFee = amountIn * 997
            let amountInWithFee := mul(amountIn, 997)

            // Calculate numerator = amountInWithFee * reserveOut
            let numerator := mul(amountInWithFee, reserveOut)

            // Calculate denominator = reserveIn * 1000 + amountInWithFee
            let denominator := add(mul(reserveIn, 1000), amountInWithFee)

            if iszero(denominator) {
                let selector := 0x23d359a3 // DivisionByZero()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }

            // Calculate amountOut = numerator / denominator
            amountOut := div(numerator, denominator)
        }
    }

    function getAmountIn(uint256 amountOut, uint112 reserveIn, uint112 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        checkReserves(amountOut, reserveIn, reserveOut);

        assembly {
            // reserveIn * amountOut * 1000
            let numerator := mul(mul(reserveIn, amountOut), 1000)

            // reserveOut - amountOut
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

    function quote(uint256 amount0, uint256 r0, uint256 r1) internal pure returns (uint256 amount1) {
        checkReserves(amount0, r0, r1);
        assembly {
            amount1 := div(mul(amount0, r1), r0)
        }
    }

    function getSortPair(address _t0, address _t1) internal pure returns (address t0, address t1) {
        assembly {
            if iszero(_t0) {
                let selector := 0xd92e233d // ZeroAddress()
                mstore(0x00, selector)
                revert(0x00, 0x04)
            }

            switch lt(_t0, _t1)
            case 1 {
                t0 := _t0
                t1 := _t1
            }
            default {
                t0 := _t1
                t1 := _t0
            }
        }
    }

    function isToken0(address token) private view returns (bool) {
        address _token0;
        assembly {
            _token0 := sload(SLOT_TOKEN_0)
        }
        return token == _token0;
    }

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

    function getPercentFL(address tokenFL) private view returns (uint256 percent) {
        (uint112 r0, uint112 r1) = getReserves();

        assembly {
            let _token0 := sload(SLOT_TOKEN_0)

            // Максимальный процент - 15% (в долях от 1000, то есть 150 = 15%)
            let maxPercent := 150
            let minPercent := 50

            // Рассчитываем соотношение резервов
            let ratio
            if eq(tokenFL, _token0) {
                // Соотношение token1 к token0
                ratio := div(mul(r1, 1000), r0)
            }
            if iszero(eq(tokenFL, _token0)) {
                // Соотношение token0 к token1
                ratio := div(mul(r0, 1000), r1)
            }

            // Умная корреляция процента на основе соотношения резервов
            if gt(ratio, 1000) {
                // Если актив перекуплен (соотношение больше 1000), уменьшаем процент
                percent := sub(maxPercent, div(sub(ratio, 1000), 10))

                // Убедимся, что процент не опускается ниже минимального значения
                if lt(percent, minPercent) { percent := minPercent }
            }
            if iszero(gt(ratio, 1000)) {
                // Если актив менее ликвиден (соотношение меньше 1000), увеличиваем процент
                percent := add(maxPercent, div(sub(1000, ratio), 10))

                // Убедимся, что процент не превышает максимального значения
                if gt(percent, maxPercent) { percent := maxPercent }
            }
        }
    }

    function getTokenBalance(uint256 slot) private view returns (uint256 bal) {
        assembly {
            let token := sload(slot)
            let ptr := mload(0x40) // Получаем указатель на свободную память
            mstore(ptr, 0x70a0823100000000000000000000000000000000000000000000000000000000) // Код функции balanceOf
            mstore(add(ptr, 0x04), address()) // Передаем адрес контракта как аргумент balanceOf

            let success :=
                staticcall(
                    gas(), // передаем все доступное количество газа
                    token, // адрес токена
                    ptr, // передаем данные (вычисленный вызов balanceOf)
                    0x24, // длина данных (4 байта селектор + 32 байта адрес)
                    ptr, // место для ответа
                    0x20 // ожидаем 32 байта в ответе
                )

            if iszero(success) { revert(0, 0) } // Если вызов неуспешен, делаем реверт

            bal := mload(ptr) // Загружаем баланс из памяти
        }
    }
}
