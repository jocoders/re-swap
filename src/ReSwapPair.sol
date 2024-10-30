// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IReSwapFactory} from "../interfaces/IReSwapFactory.sol";
import {IReSwapFlashLender} from "../interfaces/IReSwapFlashLender.sol";
import {IReSwapFlashBorrower} from "../interfaces/IReSwapFlashBorrower.sol";
import {ReSwapCore} from "./ReSwapCore.sol";
import {UQ112x112} from "../libraries/UQ112x112.sol";
import {EventHelper} from "../helpers/EventHelper.sol";
import {TransferHelper} from "../helpers/TransferHelper.sol";

/// @title ReSwap Pair Contract
/// @notice Handles liquidity operations and token swaps for the ReSwap decentralized exchange
/// @dev Extends ReSwapCore for core functionalities, uses ERC20 for liquidity token standards, and includes reentrancy protection
contract ReSwapPair is ReSwapCore, ERC20, ReentrancyGuard, IReSwapFlashLender {
    using UQ112x112 for uint224;
    using EventHelper for *;
    using TransferHelper for *;

    /// @notice Minimum liquidity enforced to prevent extreme price manipulation
    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    /// @notice Address of the factory contract that creates pairs
    address public factory;
    /// @notice Last recorded cumulative price for token0
    uint256 public lastCumulativePrice0;
    /// @notice Last recorded cumulative price for token1
    uint256 public lastCumulativePrice1;
    /// @notice Last recorded constant product of reserves for price calculation
    uint256 public lastConstant;
    /// @notice Indicates if the pair has been initialized with token addresses
    bool private initialized = false;

    /// @notice Creates a liquidity token representing a position in the liquidity pool
    constructor() ERC20("LiquidityProvider", "LP", 18) {
        factory = msg.sender;
    }

    /// @notice Initializes the pair with token addresses, can only be called by the factory
    /// @param _token0 Address of the first token
    /// @param _token1 Address of the second token
    function initialize(address _token0, address _token1) public override {
        require(msg.sender == factory, "SENDER_NOT_FACTORY");
        require(!initialized, "ALREADY_INITIALIZED");
        super.initialize(_token0, _token1);
        initialized = true;
    }

    /// @notice Adds liquidity to the pool
    /// @param desiredAmount0 Desired amount of token0
    /// @param desiredAmount1 Desired amount of token1
    /// @param minAmount0 Minimum amount of token0 to add, prevents slippage
    /// @param minAmount1 Minimum amount of token1 to add, prevents slippage
    /// @param to Address to receive the liquidity tokens
    /// @param deadline Time by which the transaction must be included to succeed
    /// @return amount0 Actual amount of token0 added to the pool
    /// @return amount1 Actual amount of token1 added to the pool
    /// @return liquidity Amount of liquidity tokens minted to the provider
    function addLiquidity(
        uint256 desiredAmount0,
        uint256 desiredAmount1,
        uint256 minAmount0,
        uint256 minAmount1,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        validateDeadline(deadline);
        (amount0, amount1) = computeLiquidity(desiredAmount0, desiredAmount1, minAmount0, minAmount1);
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amount0);
        TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amount1);
        liquidity = mint(to);
    }

    /// @notice Removes liquidity from the pool and returns underlying tokens to the remover
    /// @param liquidity Amount of liquidity tokens to burn
    /// @param minAmount0 Minimum amount of token0 to receive, prevents slippage
    /// @param minAmount1 Minimum amount of token1 to receive, prevents slippage
    /// @param to Address to receive the underlying tokens
    /// @param deadline Time by which the transaction must be included to succeed
    /// @return burnAmount0 Actual amount of token0 returned to the user
    /// @return burnAmount1 Actual amount of token1 returned to the user
    function removeLiquidity(uint256 liquidity, uint256 minAmount0, uint256 minAmount1, address to, uint256 deadline)
        public
        nonReentrant
        returns (uint256 burnAmount0, uint256 burnAmount1)
    {
        (burnAmount0, burnAmount1) = _removeLiquidity(liquidity, minAmount0, minAmount1, to, deadline);
    }

    /// @notice Allows liquidity removal with a permit, avoiding separate approval transaction
    /// @param liquidity Amount of liquidity tokens to burn
    /// @param minAmount0 Minimum amount of token0 to receive
    /// @param minAmount1 Minimum amount of token1 to receive
    /// @param to Address to receive the underlying tokens
    /// @param deadline Time by which the transaction must be included to succeed
    /// @param approveMax Whether to approve maximum uint256 value
    /// @param v Part of the signature
    /// @param r Part of the signature
    /// @param s Part of the signature
    /// @return amount0 Actual amount of token0 returned to the user
    /// @return amount1 Actual amount of token1 returned to the user
    function removeLiquidityWithPermit(
        uint256 liquidity,
        uint256 minAmount0,
        uint256 minAmount1,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        uint256 value = approveMax ? type(uint256).max : liquidity;
        permit(msg.sender, address(this), value, deadline, v, r, s);
        (amount0, amount1) = _removeLiquidity(liquidity, minAmount0, minAmount1, to, deadline);
    }

    /// @notice Executes a token swap with exact input for tokens
    /// @param tokenA Address of the input token
    /// @param tokenB Address of the output token
    /// @param amountIn Amount of input tokens to swap
    /// @param amountOutMin Minimum amount of output tokens to receive, prevents slippage
    /// @param to Address to receive output tokens
    /// @param deadline Time by which the transaction must be included to succeed
    /// @return swapAmountIn Amount of tokens taken from the sender
    /// @return swapAmountOut Amount of tokens sent to the receiver
    function swapExactTokensForTokens(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 swapAmountIn, uint256 swapAmountOut) {
        validateDeadline(deadline);
        (uint112 _swapReserveA, uint112 _swapReserveB) = getSortedReserves(tokenA);

        swapAmountIn = amountIn;
        swapAmountOut = getAmountOut(amountIn, _swapReserveA, _swapReserveB);
        require(swapAmountOut >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");

        TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), swapAmountIn);
        swap(tokenA, tokenB, _swapReserveA, _swapReserveB, 0, swapAmountOut, to);
    }

    /// @notice Executes a token swap with exact output for tokens
    /// @param tokenA Address of the input token
    /// @param tokenB Address of the output token
    /// @param amountOut Amount of output tokens to receive
    /// @param amountInMax Maximum amount of input tokens that can be taken, prevents slippage
    /// @param to Address to receive output tokens
    /// @param deadline Time by which the transaction must be included to succeed
    /// @return swapAmountIn Amount of tokens taken from the sender
    /// @return swapAmountOut Amount of tokens sent to the receiver
    function swapTokensForExactTokens(
        address tokenA,
        address tokenB,
        uint256 amountOut,
        uint256 amountInMax,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 swapAmountIn, uint256 swapAmountOut) {
        validateDeadline(deadline);
        (uint112 _reserveA, uint112 _reserveB) = getSortedReserves(tokenA);

        swapAmountIn = getAmountIn(amountOut, _reserveA, _reserveB);
        swapAmountOut = amountOut;
        require(swapAmountIn <= amountInMax, "EXCESSIVE_INPUT_AMOUNT");

        TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), swapAmountIn);
        swap(tokenA, tokenB, _reserveA, _reserveB, 0, swapAmountOut, to);
    }

    /// @notice Provides a flash loan
    /// @param receiver Address of the flash loan receiver contract
    /// @param token Address of the token to be loaned
    /// @param amount Amount of tokens to loan
    /// @param data Arbitrary data passed to the receiver
    /// @return True if the flash loan was successful
    function flashLoan(IReSwapFlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        nonReentrant
        returns (bool)
    {
        (address _token0, address _token1) = getTokensAddress();
        require(token == _token0 || token == _token1, "INVALID_TOKEN");
        require(amount <= getMaxFlashLoan(token), "EXCEEDS_MAX_FLASH_LOAN_AMOUNT");

        uint256 fee = getFlashFee(token, amount);
        uint256 beforeBalance = getBalanceByToken(token);

        TransferHelper.safeTransfer(token, address(receiver), amount);
        IReSwapFlashBorrower(receiver).onFlashLoan(address(this), token, amount, fee, data);

        uint256 afterBalance = getBalanceByToken(token);
        require(afterBalance >= beforeBalance + fee, "Insufficient repayment");
        return true;
    }

    /// @notice Allows the factory to skim tokens sent to this contract by mistake
    /// @param to Address to receive the skimmed tokens
    function skim(address to) external nonReentrant {
        require(msg.sender == factory, "SENDER_NOT_FACTORY");
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        transferPair(getBalance0() - _reserve0, getBalance1() - _reserve1, to);
    }

    /// @notice Synchronizes the reserves with the actual balances
    function sync() external nonReentrant {
        require(msg.sender == factory, "SENDER_NOT_FACTORY");
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        update(getBalance0(), getBalance1(), _reserve0, _reserve1);
    }

    /// @notice Returns the maximum amount that can be loaned for a given token
    /// @param token Address of the token
    /// @return loan Maximum loanable amount
    function maxFlashLoan(address token) external view returns (uint256 loan) {
        loan = getMaxFlashLoan(token);
    }

    /// @notice Returns the fee for a given flash loan amount and token
    /// @param token Address of the token
    /// @param amount Amount of the flash loan
    /// @return fee Calculated fee for the flash loan
    function flashFee(address token, uint256 amount) external view returns (uint256 fee) {
        fee = getFlashFee(token, amount);
    }

    /// @notice Updates the reserves and emits an update event
    /// @param balance0 New balance of token0
    /// @param balance1 New balance of token1
    /// @param _reserve0 Old reserve of token0
    /// @param _reserve1 Old reserve of token1
    function update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "BALANCE_OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed;

        unchecked {
            timeElapsed = blockTimestamp - getLastTimestamp();
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                lastCumulativePrice0 += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                lastCumulativePrice1 += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
        }

        updateReserves(uint112(balance0), uint112(balance1), blockTimestamp);
        EventHelper.emitUpdate(_reserve0, _reserve1);
    }

    /// @notice Internal function to execute token swaps
    /// @param tokenA Address of the input token
    /// @param tokenB Address of the output token
    /// @param reserveA Reserve of the input token
    /// @param reserveB Reserve of the output token
    /// @param amountOutA Amount of tokenA to output
    /// @param amountOutB Amount of tokenB to output
    /// @param to Address to receive the swapped tokens
    function swap(
        address tokenA,
        address tokenB,
        uint112 reserveA,
        uint112 reserveB,
        uint256 amountOutA,
        uint256 amountOutB,
        address to
    ) internal {
        validateSwap(amountOutA, amountOutB, reserveA, reserveB);
        _transferPair(tokenA, tokenB, amountOutA, amountOutB, to);

        (uint256 _balanceA, uint256 _balanceB) = getSortedBalances(tokenA);
        uint256 amountInA = _balanceA > reserveA - amountOutA ? _balanceA - (reserveA - amountOutA) : 0;
        uint256 amountInB = _balanceB > reserveB - amountOutB ? _balanceB - (reserveB - amountOutB) : 0;
        require(amountInA > 0 || amountInB > 0, "INSUFFICIENT_INPUT_AMOUNT");

        unchecked {
            uint256 balanceAdjustedA = _balanceA * 1000 - amountInA * 3;
            uint256 balanceAdjustedB = _balanceB * 1000 - amountInB * 3;
            require(
                balanceAdjustedA * balanceAdjustedB >= uint256(reserveA) * uint256(reserveB) * (1000 ** 2),
                "CONSTANT_INVARIANT_FAILED"
            );
        }

        update(_balanceA, _balanceB, reserveA, reserveB);
        EventHelper.emitSwap(to, amountInA, amountInB, amountOutA, amountOutB);
    }

    /// @notice Burns liquidity tokens to remove liquidity from the pool
    /// @param to Address to receive the underlying tokens
    /// @return amount0 Amount of token0 returned to the user
    /// @return amount1 Amount of token1 returned to the user
    function burn(address to) internal returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        (uint256 _balance0, uint256 _balance1) = getBalances();

        uint256 liquidity = balanceOf[address(this)];
        bool feeOn = mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;

        amount0 = (liquidity * _balance0) / _totalSupply;
        amount1 = (liquidity * _balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "INSUFFICIENT_LIQUIDITY_BURNED");

        _burn(address(this), liquidity);
        transferPair(amount0, amount1, to);

        (uint256 _afterBalance0, uint256 _afterBalance1) = getBalances();
        update(_afterBalance0, _afterBalance1, _reserve0, _reserve1);

        if (feeOn) lastConstant = uint256(_reserve0) * _reserve1;
        EventHelper.emitBurn(to, amount0, amount1);
    }

    /// @notice Transfers tokens to a specified address
    /// @param amountOut0 Amount of token0 to transfer
    /// @param amountOut1 Amount of token1 to transfer
    /// @param to Address to receive the tokens
    function transferPair(uint256 amountOut0, uint256 amountOut1, address to) internal {
        (address _token0, address _token1) = getTokensAddress();
        _transferPair(_token0, _token1, amountOut0, amountOut1, to);
    }

    /// @notice Computes the optimal amounts of tokens to add to the liquidity pool
    /// @param desiredAmountA Desired amount of tokenA
    /// @param desiredAmountB Desired amount of tokenB
    /// @param minAmountA Minimum amount of tokenA to add, prevents slippage
    /// @param minAmountB Minimum amount of tokenB to add, prevents slippage
    /// @return amountA Actual amount of tokenA added to the pool
    /// @return amountB Actual amount of tokenB added to the pool
    function computeLiquidity(uint256 desiredAmountA, uint256 desiredAmountB, uint256 minAmountA, uint256 minAmountB)
        internal
        view
        returns (uint256 amountA, uint256 amountB)
    {
        (uint112 reserveA, uint112 reserveB) = getReserves();

        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (desiredAmountA, desiredAmountB);
        } else {
            uint256 optimalAmountB = quote(desiredAmountA, reserveA, reserveB);
            if (optimalAmountB <= desiredAmountB) {
                require(optimalAmountB >= minAmountB, "INSUFFICIENT_1_AMOUNT");
                (amountA, amountB) = (desiredAmountA, optimalAmountB);
            } else {
                uint256 optimalAmountA = quote(desiredAmountB, reserveB, reserveA);
                assert(optimalAmountA <= desiredAmountA);
                require(optimalAmountA >= minAmountA, "INSUFFICIENT_0_AMOUNT");
                (amountA, amountB) = (optimalAmountA, desiredAmountB);
            }
        }
    }

    /// @notice Mints liquidity tokens and sends them to the specified address
    /// @dev Calculates liquidity based on the current reserves and the amounts provided
    /// @param to The address to which the liquidity tokens will be sent
    /// @return liquidity The amount of liquidity minted
    function mint(address to) private returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        (uint256 _balance0, uint256 _balance1) = getBalances();

        uint256 amount0 = _balance0 - _reserve0;
        uint256 amount1 = _balance1 - _reserve1;
        bool feeOn = mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply;

        if (_totalSupply == 0) {
            liquidity = FixedPointMathLib.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            unchecked {
                uint256 liquidity0 = (amount0 * _totalSupply) / _reserve0;
                uint256 liquidity1 = (amount1 * _totalSupply) / _reserve1;
                liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
            }
        }

        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        update(_balance0, _balance1, _reserve0, _reserve1);

        if (feeOn) lastConstant = uint256(_reserve0) * _reserve1;
        EventHelper.emitMint(amount0, amount1);
    }

    /// @notice Calculates and mints the fee to the feeTo address if applicable
    /// @dev This function is called within the mint function to handle fee distribution
    /// @param _reserve0 The reserve of token0
    /// @param _reserve1 The reserve of token1
    /// @return feeOn Boolean indicating if the fee was applied
    function mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IReSwapFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 liquidity;
        uint256 _lastConstant = lastConstant;

        if (feeOn) {
            if (_lastConstant != 0) {
                uint256 rootConstant = FixedPointMathLib.sqrt(uint256(_reserve0) * uint256(_reserve1));
                uint256 lastRootConstant = FixedPointMathLib.sqrt(_lastConstant);
                if (rootConstant > lastRootConstant) {
                    unchecked {
                        uint256 numerator = totalSupply * (rootConstant - lastRootConstant);
                        uint256 denominator = rootConstant * 5 + lastRootConstant;
                        liquidity = numerator / denominator;
                    }
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_lastConstant != 0) {
            lastConstant = 0;
        }
    }

    /// @notice Internal function to transfer tokens to a specified address
    /// @dev Used by various liquidity and swap functions to handle token transfers
    /// @param tokenA The address of token A
    /// @param tokenB The address of token B
    /// @param amountOutA The amount of token A to transfer
    /// @param amountOutB The amount of token B to transfer
    /// @param to The recipient address
    function _transferPair(address tokenA, address tokenB, uint256 amountOutA, uint256 amountOutB, address to)
        private
    {
        require(to != tokenA && to != tokenB, "INVALID_TO_ADDRESS");
        if (amountOutA > 0) TransferHelper.safeTransfer(tokenA, to, amountOutA);
        if (amountOutB > 0) TransferHelper.safeTransfer(tokenB, to, amountOutB);
    }

    /// @notice Removes liquidity and returns the underlying tokens to the specified address
    /// @dev Handles the removal of liquidity by burning the liquidity tokens and transferring the underlying tokens
    /// @param liquidity The amount of liquidity to remove
    /// @param minAmount0 The minimum amount of token0 that must be returned
    /// @param minAmount1 The minimum amount of token1 that must be returned
    /// @param to The address to receive the underlying tokens
    /// @param deadline The deadline by which the transaction must be completed
    /// @return burnAmount0 The amount of token0 returned
    /// @return burnAmount1 The amount of token1 returned
    function _removeLiquidity(uint256 liquidity, uint256 minAmount0, uint256 minAmount1, address to, uint256 deadline)
        private
        returns (uint256 burnAmount0, uint256 burnAmount1)
    {
        validateDeadline(deadline);
        TransferHelper.safeTransferFrom(address(this), msg.sender, address(this), liquidity);
        (burnAmount0, burnAmount1) = burn(to);
        require(burnAmount0 >= minAmount0, "INSUFFICIENT_0_AMOUNT");
        require(burnAmount1 >= minAmount1, "INSUFFICIENT_1_AMOUNT");
    }
}
