// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console2 } from 'forge-std/Test.sol';
import { ERC20 } from 'solmate/tokens/ERC20.sol';
import { ReentrancyGuard } from 'solmate/utils/ReentrancyGuard.sol';
import { FixedPointMathLib } from 'solmate/utils/FixedPointMathLib.sol';

import { IERC20 } from '../interfaces/IERC20.sol';
import { IReSwapFactory } from '../interfaces/IReSwapFactory.sol';
import { IReSwapCallee } from '../interfaces/IReSwapCallee.sol';
import { IReSwapFlashLender } from '../interfaces/IReSwapFlashLender.sol';
import { IReSwapFlashBorrower } from '../interfaces/IReSwapFlashBorrower.sol';
import { UQ112x112 } from '../libraries/UQ112x112.sol';
//import { IReSwapPair } from '../interfaces/IReSwapPair.sol';
import { ReSwapCore } from './ReSwapCore.sol';
//import { IWETH } from '../interfaces/IWETH.sol';
import { YulEvent } from '../libraries/YulEvent.sol';
import { YulTransfer } from '../libraries/YulTransfer.sol';

contract ReSwapPair is ERC20, ReentrancyGuard, ReSwapCore, IReSwapFlashLender {
  using UQ112x112 for uint224;
  using YulEvent for *;
  using YulTransfer for *;

  uint256 public constant MINIMUM_LIQUIDITY = 1000;
  address public factory;
  uint256 public lastCumulativePrice0;
  uint256 public lastCumulativePrice1;
  uint256 public lastK;

  constructor() ERC20('LiquidityProvider', 'LP', 18) {
    factory = msg.sender;
  }

  function initialize(address _token0, address _token1) external {
    require(msg.sender == factory, 'SENDER_NOT_FACTORY');
    initializeTokens(_token0, _token1);
  }

  function computeLiquidity(
    address tokenA,
    uint256 desiredAmountA,
    uint256 desiredAmountB,
    uint256 minAmountA,
    uint256 minAmountB
  ) internal view returns (uint256 amountA, uint256 amountB) {
    (uint112 reserveA, uint112 reserveB) = getReserves(tokenA);

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

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 desiredAmountA,
    uint256 desiredAmountB,
    uint256 minAmountA,
    uint256 minAmountB,
    address to,
    uint256 deadline
  ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
    validateDeadline(deadline);
    (amountA, amountB) = computeLiquidity(tokenA, desiredAmountA, desiredAmountB, minAmountA, minAmountB);

    YulTransfer.safeTransferFrom(tokenA, msg.sender, address(this), amountA);
    YulTransfer.safeTransferFrom(tokenB, msg.sender, address(this), amountB);
    liquidity = mint(to, tokenA);
  }

  function removeLiquidity(
    address tokenA,
    uint256 liquidity,
    uint256 minAmountA,
    uint256 minAmountB,
    address to,
    uint256 deadline
  ) public returns (uint256 burnAmountA, uint256 burnAmountB) {
    validateDeadline(deadline);
    transferFrom(msg.sender, address(this), liquidity);
    (burnAmountA, burnAmountB) = burn(to, tokenA);
    require(burnAmountA >= minAmountA, 'INSUFFICIENT_A_AMOUNT');
    require(burnAmountB >= minAmountB, 'INSUFFICIENT_B_AMOUNT');
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
    (uint112 _swapReserveA, uint112 _swapReserveB) = getReserves(tokenA);

    swapAmountIn = amountIn;
    swapAmountOut = getAmountOut(amountIn, _swapReserveA, _swapReserveB);

    require(swapAmountOut >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
    YulTransfer.safeTransferFrom(tokenA, msg.sender, address(this), swapAmountIn);
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
    (uint112 _reserveA, uint112 _reserveB) = getReserves(tokenA);

    swapAmountIn = getAmountIn(amountOut, _reserveA, _reserveB);
    swapAmountOut = amountOut;

    require(swapAmountIn <= amountInMax, 'EXCESSIVE_INPUT_AMOUNT');
    YulTransfer.safeTransferFrom(tokenA, msg.sender, address(this), swapAmountIn);
    swap(tokenA, tokenB, _reserveA, _reserveB, 0, swapAmountOut, to);
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
    transferPair(tokenA, tokenB, amountOutA, amountOutB, to);

    (uint256 _balanceA, uint256 _balanceB) = getBalances(tokenA);

    uint256 amountInA = _balanceA > reserveA - amountOutA ? _balanceA - (reserveA - amountOutA) : 0;
    uint256 amountInB = _balanceB > reserveB - amountOutB ? _balanceB - (reserveB - amountOutB) : 0;

    require(amountInA <= reserveA / 100 && amountInB <= reserveB / 100, 'EXCEEDS_MAXIMUM_INPUT_FOR_SWAP');
    require(amountInA > 0 || amountInB > 0, 'INSUFFICIENT_INPUT_AMOUNT');

    unchecked {
      uint256 balanceAdjustedA = _balanceA * 1000 - amountInA * 3;
      uint256 balanceAdjustedB = _balanceB * 1000 - amountInB * 3;
      require(
        balanceAdjustedA * balanceAdjustedB >= uint256(reserveA) * uint256(reserveB) * (1000 ** 2),
        'K_INVARIANT_FAILED'
      );
    }

    update(_balanceA, _balanceB, reserveA, reserveB);
    YulEvent.emitSwap(to, amountInA, amountInB, amountOutA, amountOutB);
  }

  // function removeLiquidityWithPermit(
  //       address tokenA,
  //   uint256 liquidity,
  //   uint256 minAmount0,
  //   uint256 minAmount1,
  //   address to,
  //   uint256 deadline,
  //   bool approveMax,
  //   uint8 v,
  //   bytes32 r,
  //   bytes32 s
  // ) external returns (uint256 amount0, uint256 amount1) {
  //   uint256 value = approveMax ? type(uint256).max : liquidity;
  //   permit(msg.sender, address(this), value, deadline, v, r, s);
  //   (amount0, amount1) = removeLiquidity(liquidity, minAmount0, minAmount1, to, deadline);
  // }

  function maxFlashLoan(address tokenFL) external view returns (uint256 loan) {
    return getMaxFlashLoan(tokenFL);
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

    YulTransfer.safeTransfer(token, address(receiver), amount);
    IReSwapFlashBorrower(receiver).onFlashLoan(msg.sender, token, amount, fee, data);

    uint256 afterBalance = getBalanceByToken(token);

    require(afterBalance >= beforeBalance + fee, 'Insufficient repayment');

    return true;
  }

  function flashFee(address token, uint256 amount) external view returns (uint256) {
    return getFlashFee(token, amount);
  }

  function skim(address to) external nonReentrant {
    (uint112 _reserve0, uint112 _reserve1) = getReserves();
    transferPair(getBalance0() - _reserve0, getBalance1() - _reserve1, to);
  }

  function sync() external nonReentrant {
    (uint112 _reserve0, uint112 _reserve1) = getReserves();
    update(getBalance0(), getBalance1(), _reserve0, _reserve1);
  }

  function mint(address to, address tokenA) public nonReentrant returns (uint256 liquidity) {
    (uint112 _reserveA, uint112 _reserveB) = getReserves(tokenA);
    (uint256 _balanceA, uint256 _balanceB) = getBalances(tokenA);

    uint256 amountA = _balanceA - _reserveA;
    uint256 amountB = _balanceB - _reserveB;

    bool feeOn = mintFee(_reserveA, _reserveB);
    uint256 _totalSupply = totalSupply;
    if (_totalSupply == 0) {
      liquidity = FixedPointMathLib.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
      _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
    } else {
      unchecked {
        uint256 liquidityA = (amountA * _totalSupply) / _reserveA;
        uint256 liquidityB = (amountB * _totalSupply) / _reserveB;
        liquidity = liquidityA < liquidityB ? liquidityA : liquidityB;
      }
    }
    require(liquidity > 0, 'INSUFFICIENT_LIQUIDITY_MINTED');
    _mint(to, liquidity);

    update(_balanceA, _balanceB, _reserveA, _reserveB);
    if (feeOn) lastK = uint256(_reserveA) * _reserveB;
    YulEvent.emitMint(amountA, amountB);
  }

  function burn(address to, address tokenA) internal nonReentrant returns (uint256 amountA, uint256 amountB) {
    (uint112 _reserveA, uint112 _reserveB) = getReserves(tokenA);
    (uint256 _balanceA, uint256 _balanceB) = getBalances(tokenA);

    uint256 liquidity = balanceOf[address(this)];
    bool feeOn = mintFee(_reserveA, _reserveB);
    uint256 _totalSupply = totalSupply;

    amountA = (liquidity * _balanceA) / _totalSupply;
    amountB = (liquidity * _balanceB) / _totalSupply;
    require(amountA > 0 && amountB > 0, 'INSUFFICIENT_LIQUIDITY_BURNED');

    _burn(address(this), liquidity);
    transferPair(amountA, amountB, to);

    update(_balanceA, _balanceB, _reserveA, _reserveB);
    if (feeOn) lastK = uint256(_reserveA) * _reserveB;
    YulEvent.emitBurn(to, amountA, amountB);
  }

  function update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) public virtual {
    require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'BALANCE_OVERFLOW');
    uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
    uint32 timeElapsed = blockTimestamp - getLastTimestamp();

    if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
      unchecked {
        lastCumulativePrice0 += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
        lastCumulativePrice1 += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
      }
    }

    updateReserves(uint112(balance0), uint112(balance1), blockTimestamp);
    YulEvent.emitUpdate(_reserve0, _reserve1);
  }

  function mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
    address feeTo = IReSwapFactory(factory).feeTo();
    feeOn = feeTo != address(0);
    uint256 liquidity;
    uint256 _lastK = lastK;
    if (feeOn) {
      if (_lastK != 0) {
        uint256 rootK = FixedPointMathLib.sqrt(uint256(_reserve0) * uint256(_reserve1));
        uint256 lastRootK = FixedPointMathLib.sqrt(_lastK);
        if (rootK > lastRootK) {
          unchecked {
            uint256 numerator = totalSupply * (rootK - lastRootK);
            uint256 denominator = rootK * 5 + lastRootK;
            liquidity = numerator / denominator; // ???? can i use this here need to check!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
          }
          if (liquidity > 0) _mint(feeTo, liquidity);
        }
      }
    } else if (_lastK != 0) {
      lastK = 0;
    }
  }

  function transferPair(uint256 amountOut0, uint256 amountOut1, address to) private {
    (address _token0, address _token1) = getTokensAddress();

    require(to != _token0 && to != _token1, 'INVALID_TO_ADDRESS');
    if (amountOut0 > 0) YulTransfer.safeTransfer(_token0, to, amountOut0);
    if (amountOut1 > 0) YulTransfer.safeTransfer(_token1, to, amountOut1);
  }

  function transferPair(address tokenA, address tokenB, uint256 amountOutA, uint256 amountOutB, address to) private {
    require(to != tokenA && to != tokenB, 'INVALID_TO_ADDRESS');

    if (amountOutA > 0) YulTransfer.safeTransfer(tokenA, to, amountOutA);
    if (amountOutB > 0) YulTransfer.safeTransfer(tokenB, to, amountOutB);
  }
}
