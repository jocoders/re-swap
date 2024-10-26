// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from 'solmate/tokens/ERC20.sol';
import { ReentrancyGuard } from 'solmate/utils/ReentrancyGuard.sol';
import { FixedPointMathLib } from 'solmate/utils/FixedPointMathLib.sol';
import { IReSwapFactory } from '../interfaces/IReSwapFactory.sol';
import { IReSwapFlashLender } from '../interfaces/IReSwapFlashLender.sol';
import { IReSwapFlashBorrower } from '../interfaces/IReSwapFlashBorrower.sol';
import { ReSwapCore } from './ReSwapCore.sol';
import { UQ112x112 } from '../libraries/UQ112x112.sol';
import { EventHelper } from 'libraries/EventHelper.sol';
import { TransferHelper } from '../libraries/TransferHelper.sol';

import { console2 } from 'forge-std/Test.sol';

contract ReSwapPair is ReSwapCore, ERC20, ReentrancyGuard, IReSwapFlashLender {
  using UQ112x112 for uint224;
  using EventHelper for *;
  using TransferHelper for *;

  uint256 public constant MINIMUM_LIQUIDITY = 1000;
  address public factory;
  uint256 public lastCumulativePrice0;
  uint256 public lastCumulativePrice1;
  uint256 public lastConstant;
  bool public initialized = false;

  constructor() ERC20('LiquidityProvider', 'LP', 18) {
    factory = msg.sender;
  }

  function initialize(address _token0, address _token1) public override {
    require(msg.sender == factory, 'SENDER_NOT_FACTORY');
    require(!initialized, 'ALREADY_INITIALIZED');
    super.initialize(_token0, _token1);
    initialized = true;
  }

  function addLiquidity(
    uint256 desiredAmount0,
    uint256 desiredAmount1,
    uint256 minAmount0,
    uint256 minAmount1,
    address to,
    uint256 deadline
  ) external returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
    validateDeadline(deadline);
    (amount0, amount1) = computeLiquidity(desiredAmount0, desiredAmount1, minAmount0, minAmount1);

    TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amount0);
    TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amount1);
    liquidity = mint(to);
  }

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
  ) external returns (uint256 amount0, uint256 amount1) {
    uint256 value = approveMax ? type(uint256).max : liquidity;
    permit(msg.sender, address(this), value, deadline, v, r, s);
    (amount0, amount1) = removeLiquidity(liquidity, minAmount0, minAmount1, to, deadline);
  }

  function swapExactTokensForTokens(
    address tokenA,
    address tokenB,
    uint256 amountIn,
    uint256 amountOutMin,
    address to,
    uint256 deadline
  ) external returns (uint256 swapAmountIn, uint256 swapAmountOut) {
    validateDeadline(deadline);
    (uint112 _swapReserveA, uint112 _swapReserveB) = getSortedReserves(tokenA);

    swapAmountIn = amountIn;
    swapAmountOut = getAmountOut(amountIn, _swapReserveA, _swapReserveB);

    require(swapAmountOut >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
    TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), swapAmountIn);
    swap(tokenA, tokenB, _swapReserveA, _swapReserveB, 0, swapAmountOut, to);
  }

  function swapTokensForExactTokens(
    address tokenA,
    address tokenB,
    uint256 amountOut,
    uint256 amountInMax,
    address to,
    uint256 deadline
  ) external returns (uint256 swapAmountIn, uint256 swapAmountOut) {
    validateDeadline(deadline);
    (uint112 _reserveA, uint112 _reserveB) = getSortedReserves(tokenA);

    swapAmountIn = getAmountIn(amountOut, _reserveA, _reserveB);
    swapAmountOut = amountOut;

    require(swapAmountIn <= amountInMax, 'EXCESSIVE_INPUT_AMOUNT');
    TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), swapAmountIn);
    swap(tokenA, tokenB, _reserveA, _reserveB, 0, swapAmountOut, to);
  }

  function flashLoan(
    IReSwapFlashBorrower receiver,
    address token,
    uint256 amount,
    bytes calldata data
  ) external nonReentrant returns (bool) {
    require(token == token0 || token == token1, 'INVALID_TOKEN');
    require(amount <= getMaxFlashLoan(token), 'EXCEEDS_MAX_FLASH_LOAN_AMOUNT');

    uint256 fee = getFlashFee(token, amount);
    uint256 beforeBalance = getBalanceByToken(token);

    TransferHelper.safeTransfer(token, address(receiver), amount);
    IReSwapFlashBorrower(receiver).onFlashLoan(msg.sender, token, amount, fee, data);

    uint256 afterBalance = getBalanceByToken(token);

    require(afterBalance >= beforeBalance + fee, 'Insufficient repayment');

    return true;
  }

  function skim(address to) external nonReentrant {
    (uint112 _reserve0, uint112 _reserve1) = getReserves();
    transferPair(getBalance0() - _reserve0, getBalance1() - _reserve1, to);
  }

  function sync() external nonReentrant {
    (uint112 _reserve0, uint112 _reserve1) = getReserves();
    update(getBalance0(), getBalance1(), _reserve0, _reserve1);
  }

  function maxFlashLoan(address token) external view returns (uint256 loan) {
    loan = getMaxFlashLoan(token);
  }

  function flashFee(address token, uint256 amount) external view returns (uint256 fee) {
    fee = getFlashFee(token, amount);
  }

  function removeLiquidity(
    uint256 liquidity,
    uint256 minAmount0,
    uint256 minAmount1,
    address to,
    uint256 deadline
  ) public returns (uint256 burnAmount0, uint256 burnAmount1) {
    validateDeadline(deadline);
    transferFrom(msg.sender, address(this), liquidity);
    (burnAmount0, burnAmount1) = burn(to);
    require(burnAmount0 >= minAmount0, 'INSUFFICIENT_0_AMOUNT');
    require(burnAmount1 >= minAmount1, 'INSUFFICIENT_1_AMOUNT');
  }

  function update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) public {
    require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'BALANCE_OVERFLOW');

    uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
    uint32 timeElapsed = blockTimestamp - getLastTimestamp();

    // console2.log('timeElapsed', timeElapsed);
    // console2.log('_reserve0', _reserve0);
    // console2.log('_reserve1', _reserve1);

    if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
      unchecked {
        lastCumulativePrice0 += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
        lastCumulativePrice1 += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
      }
    }

    // console2.log('XXX_lastCumulativePrice0', lastCumulativePrice0);
    // console2.log('XXX_lastCumulativePrice1', lastCumulativePrice1);

    updateReserves(uint112(balance0), uint112(balance1), blockTimestamp);
    EventHelper.emitUpdate(_reserve0, _reserve1);
  }

  function swap(
    address tokenA,
    address tokenB,
    uint112 reserveA,
    uint112 reserveB,
    uint256 amountOutA,
    uint256 amountOutB,
    address to
  ) internal nonReentrant {
    validateSwap(amountOutA, amountOutB, reserveA, reserveB);
    finalizeTransferPair(tokenA, tokenB, amountOutA, amountOutB, to);

    (uint256 _balanceA, uint256 _balanceB) = getSortedBalances(tokenA);

    uint256 amountInA = _balanceA > reserveA - amountOutA ? _balanceA - (reserveA - amountOutA) : 0;
    uint256 amountInB = _balanceB > reserveB - amountOutB ? _balanceB - (reserveB - amountOutB) : 0;

    require(amountInA > 0 || amountInB > 0, 'INSUFFICIENT_INPUT_AMOUNT');

    unchecked {
      uint256 balanceAdjustedA = _balanceA * 1000 - amountInA * 3;
      uint256 balanceAdjustedB = _balanceB * 1000 - amountInB * 3;
      require(
        balanceAdjustedA * balanceAdjustedB >= uint256(reserveA) * uint256(reserveB) * (1000 ** 2),
        'CONSTANT_INVARIANT_FAILED'
      );
    }

    update(_balanceA, _balanceB, reserveA, reserveB);
    EventHelper.emitSwap(to, amountInA, amountInB, amountOutA, amountOutB);
  }

  function burn(address to) internal nonReentrant returns (uint256 amount0, uint256 amount1) {
    (uint112 _reserve0, uint112 _reserve1) = getReserves();
    (uint256 _balance0, uint256 _balance1) = getBalances();

    uint256 liquidity = balanceOf[address(this)];
    bool feeOn = mintFee(_reserve0, _reserve1);
    uint256 _totalSupply = totalSupply;

    amount0 = (liquidity * _balance0) / _totalSupply;
    amount1 = (liquidity * _balance1) / _totalSupply;
    require(amount0 > 0 && amount1 > 0, 'INSUFFICIENT_LIQUIDITY_BURNED');

    _burn(address(this), liquidity);
    transferPair(amount0, amount1, to);

    update(_balance0, _balance1, _reserve0, _reserve1);
    if (feeOn) lastConstant = uint256(_reserve0) * _reserve1;
    EventHelper.emitBurn(to, amount0, amount1);
  }

  function transferPair(uint256 amountOut0, uint256 amountOut1, address to) internal {
    (address _token0, address _token1) = getTokensAddress();
    finalizeTransferPair(_token0, _token1, amountOut0, amountOut1, to);
  }

  function finalizeTransferPair(
    address tokenA,
    address tokenB,
    uint256 amountOutA,
    uint256 amountOutB,
    address to
  ) internal {
    require(to != tokenA && to != tokenB, 'INVALID_TO_ADDRESS');

    if (amountOutA > 0) TransferHelper.safeTransfer(tokenA, to, amountOutA);
    if (amountOutB > 0) TransferHelper.safeTransfer(tokenB, to, amountOutB);
  }

  function computeLiquidity(
    uint256 desiredAmountA,
    uint256 desiredAmountB,
    uint256 minAmountA,
    uint256 minAmountB
  ) internal view returns (uint256 amountA, uint256 amountB) {
    (uint112 reserveA, uint112 reserveB) = getReserves();

    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (desiredAmountA, desiredAmountB);
    } else {
      uint256 optimalAmountB = quote(desiredAmountA, reserveA, reserveB);
      if (optimalAmountB <= desiredAmountB) {
        require(optimalAmountB >= minAmountB, 'INSUFFICIENT_1_AMOUNT');
        (amountA, amountB) = (desiredAmountA, optimalAmountB);
      } else {
        uint256 optimalAmountA = quote(desiredAmountB, reserveB, reserveA);
        assert(optimalAmountA <= desiredAmountA);
        require(optimalAmountA >= minAmountA, 'INSUFFICIENT_0_AMOUNT');
        (amountA, amountB) = (optimalAmountA, desiredAmountB);
      }
    }
  }

  function mint(address to) private nonReentrant returns (uint256 liquidity) {
    (uint112 _reserve0, uint112 _reserve1) = getReserves();
    (uint256 _balance0, uint256 _balance1) = getBalances();

    uint256 amount0 = _balance0 - _reserve0;
    uint256 amount1 = _balance1 - _reserve1;

    bool feeOn = mintFee(_reserve0, _reserve1);

    // console2.log('amount0', amount0);
    // console2.log('amount1', amount1);
    // console2.log('_reserve0', _reserve0);
    // console2.log('_reserve1', _reserve1);
    // console2.log('feeOn', feeOn);

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
    require(liquidity > 0, 'INSUFFICIENT_LIQUIDITY_MINTED');

    //console2.log('liquidity', liquidity);
    _mint(to, liquidity);

    update(_balance0, _balance1, _reserve0, _reserve1);
    if (feeOn) lastConstant = uint256(_reserve0) * _reserve1;
    EventHelper.emitMint(amount0, amount1);
  }

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
}
