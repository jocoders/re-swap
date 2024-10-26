// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console2 } from 'forge-std/Test.sol';
import { ReSwapPair } from '../src/ReSwapPair.sol';
import { MockERC20 } from './MockERC20.t.sol';
import { ReSwapPairTestHelper } from './ReSwapPairTestHelper.t.sol';
import { ReSwapFactoryTestHelper } from './ReSwapFactoryTestHelper.t.sol';
import { TransferHelper } from '../libraries/TransferHelper.sol';

contract ReSwapPairTest is Test {
  ReSwapFactoryTestHelper private reSwapFactory;
  MockERC20 private _token0;
  MockERC20 private _token1;
  address private pair;

  address private Alice = address(0x1);
  address private Bob = address(0x2);

  uint256 private INIT_SUPPLY_0 = 1e18 / 5;
  uint256 private INIT_SUPPLY_1 = 1e18 / 2;

  uint112 private RESERVE_0 = 1e18 / 5;
  uint112 private RESERVE_1 = 1e18 / 2;
  uint256 private USER_INIT_BALANCE = 10_000_000;

  function setUp() public {
    _token0 = new MockERC20('Token0', 'TK0', 18);
    _token1 = new MockERC20('Token1', 'TK1', 18);

    reSwapFactory = new ReSwapFactoryTestHelper();
    pair = reSwapFactory.testCreatePair(address(_token0), address(_token1));

    // Минтим токены для использования в тестах
    _token0.mint(address(this), INIT_SUPPLY_0);
    _token1.mint(address(this), INIT_SUPPLY_1);

    MockERC20(_token0).transfer(address(Alice), USER_INIT_BALANCE);
    MockERC20(_token1).transfer(address(Alice), USER_INIT_BALANCE);

    MockERC20(_token0).transfer(address(Bob), USER_INIT_BALANCE);
    MockERC20(_token1).transfer(address(Bob), USER_INIT_BALANCE);
  }

  function reSwapPair() private view returns (ReSwapPairTestHelper) {
    return ReSwapPairTestHelper(pair);
  }

  function getTokens() private view returns (address, address) {
    return _token0 < _token1 ? (address(_token0), address(_token1)) : (address(_token1), address(_token0));
  }

  function testSuccessInitialize() public view {
    (address _t0, address _t1) = getTokens();
    assertEq(reSwapPair().token0(), _t0, 'token0 have to be address(token0)');
    assertEq(reSwapPair().token1(), _t1, 'token1 have to be address(token1)');
  }

  function testFailedInitialize() public {
    vm.expectRevert('ALREADY_INITIALIZED');
    reSwapPair().initialize(address(_token0), address(_token1));
  }

  function testGetBalances() public {
    (uint256 beforeBalance0, uint256 beforeBalance1) = reSwapPair().getBalances();

    assertEq(beforeBalance0, 0, 'Init balance0 have to be 0');
    assertEq(beforeBalance1, 0, 'Init balance1 have to be 0');

    uint256 AMOUNT_0 = 1_999_999;
    uint256 AMOUNT_1 = 599_456;

    (address _t0, address _t1) = getTokens();
    MockERC20(_t0).transfer(pair, AMOUNT_0);
    MockERC20(_t1).transfer(pair, AMOUNT_1);

    (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();
    assertEq(afterBalance0, AMOUNT_0, 'balance0 have to be 1_999_999');
    assertEq(afterBalance1, AMOUNT_1, 'balance1 have to be 599_456');
  }

  function testGetReserves() public {
    (uint112 beforeReserve0, uint112 beforeReserve1) = reSwapPair().getReserves();
    assertEq(beforeReserve0, 0, 'reserve0 have to be 0');
    assertEq(beforeReserve1, 0, 'reserve1 have to be 0');

    uint32 beforeLastTimestamp = reSwapPair().getLastTimestamp();
    assertEq(beforeLastTimestamp, 0, 'lastTimestamp have to be 0');

    uint256 AMOUNT_0 = 433_009;
    uint256 AMOUNT_1 = 2_456_890;
    reSwapPair().update(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

    (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
    assertEq(afterReserve0, AMOUNT_0, 'reserve0 have to be 433_009');
    assertEq(afterReserve1, AMOUNT_1, 'reserve1 have to be 2_456_890');

    uint32 afterLastTimestamp = reSwapPair().getLastTimestamp();
    console2.log('afterLastTimestamp', afterLastTimestamp);
    assertNotEq(afterLastTimestamp, 0, 'lastTimestamp have to be block.timestamp');
  }

  function testXFailedUpdate() public {
    vm.expectRevert();
    reSwapPair().update(type(uint256).max + 1, type(uint256).max + 1, 0, 0);
  }

  function testSuccessUpdate() public {
    prepareTransfer();

    uint256 AMOUNT_0 = 100_500;
    uint256 AMOUNT_1 = 45_987;

    reSwapPair().update(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

    uint32 afterLastTimestamp = reSwapPair().getLastTimestamp();
    assertNotEq(afterLastTimestamp, 0, 'lastTimestamp have to be block.timestamp');

    (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
    assertEq(afterReserve0, AMOUNT_0, 'reserve0 have to be 1_999_999 + 100_500');
    assertEq(afterReserve1, AMOUNT_1, 'reserve1 have to be 599_456 + 45_987');
  }

  function testGetLastTimestamp() public {
    uint32 beforeLastTimestamp = reSwapPair().getLastTimestamp();
    assertEq(beforeLastTimestamp, 0, 'lastTimestamp have to be 0');

    uint256 AMOUNT_0 = 433_009;
    uint256 AMOUNT_1 = 2_456_890;

    reSwapPair().update(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

    uint32 afterLastTimestamp = reSwapPair().getLastTimestamp();
    assertNotEq(afterLastTimestamp, 0, 'lastTimestamp have to be block.timestamp');
  }

  function testValidateSwap() public {
    uint256 AMOUNT_0 = 433_009;
    uint256 AMOUNT_1 = 2_456_890;

    reSwapPair().update(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

    (uint112 reserve0, uint112 reserve1) = reSwapPair().getReserves();

    vm.expectRevert();
    reSwapPair().testValidateSwap(0, 0, reserve0, reserve1);

    vm.expectRevert();
    reSwapPair().testValidateSwap(AMOUNT_0 + 1, 0, reserve0, reserve1);

    vm.expectRevert();
    reSwapPair().testValidateSwap(0, AMOUNT_1 + 1, reserve0, reserve1);
  }

  function testSuccessTransfer() public {
    prepareTransfer();

    vm.prank(address(pair));
    TransferHelper.safeTransfer(address(_token0), Alice, 500_000);
    TransferHelper.safeTransfer(address(_token0), Bob, 100_500);

    uint256 aliceBalance1 = _token0.balanceOf(Alice);
    uint256 bobBalance1 = _token0.balanceOf(Bob);

    assertEq(aliceBalance1, 500_000 + USER_INIT_BALANCE, 'Alice balance should increase by 500_000');
    assertEq(bobBalance1, 100_500 + USER_INIT_BALANCE, 'Bob balance should increase by 100_500');
  }

  function testFTransferPair() public {
    prepareTransfer();

    vm.expectRevert('INVALID_TO_ADDRESS');
    reSwapPair().testTransferPair(1_999_999, 599_456, address(_token0));

    vm.expectRevert('INVALID_TO_ADDRESS');
    reSwapPair().testTransferPair(1_999_999, 599_456, address(_token1));
  }

  function testSuccessTransferPair() public {
    prepareTransfer();

    uint256 AMOUNT_0 = 87_999;
    uint256 AMOUNT_1 = 255_457;

    reSwapPair().testTransferPair(AMOUNT_0, AMOUNT_1, Alice);
    reSwapPair().testTransferPair(AMOUNT_1, AMOUNT_0, Bob);

    (address _t0, address _t1) = getTokens();
    uint256 aliceBalance0 = MockERC20(_t0).balanceOf(Alice);
    uint256 bobBalance0 = MockERC20(_t0).balanceOf(Bob);

    uint256 aliceBalance1 = MockERC20(_t1).balanceOf(Alice);
    uint256 bobBalance1 = MockERC20(_t1).balanceOf(Bob);

    assertEq(aliceBalance0, AMOUNT_0 + USER_INIT_BALANCE, 'Alice balance0 have to be 87_999');
    assertEq(bobBalance0, AMOUNT_1 + USER_INIT_BALANCE, 'Bob balance0 have to be 255_457');

    assertEq(aliceBalance1, AMOUNT_1 + USER_INIT_BALANCE, 'Alice balance1 have to be 255_457');
    assertEq(bobBalance1, AMOUNT_0 + USER_INIT_BALANCE, 'Bob balance1 have to be 87_999');
  }

  function testSkim() public {
    uint256 AMOUNT_0 = 1_999_999;
    uint256 AMOUNT_1 = 599_456;
    uint256 AMOUNT_0_SKIM = 100_000;
    uint256 AMOUNT_1_SKIM = 50_000;

    (address _t0, address _t1) = getTokens();
    MockERC20(_t0).transfer(address(pair), AMOUNT_0);
    MockERC20(_t1).transfer(address(pair), AMOUNT_1);
    reSwapPair().update(
      AMOUNT_0 - AMOUNT_0_SKIM,
      AMOUNT_1 - AMOUNT_1_SKIM,
      uint112(AMOUNT_0 - AMOUNT_0_SKIM),
      uint112(AMOUNT_1 - AMOUNT_1_SKIM)
    );
    reSwapPair().skim(Alice);
    uint256 aliceBalance0 = MockERC20(_t0).balanceOf(Alice);
    uint256 aliceBalance1 = MockERC20(_t1).balanceOf(Alice);
    assertEq(aliceBalance0, AMOUNT_0_SKIM + USER_INIT_BALANCE, 'Alice balance0 have to be 100_000');
    assertEq(aliceBalance1, AMOUNT_1_SKIM + USER_INIT_BALANCE, 'Alice balance1 have to be 50_000');
    uint256 contractBalance0 = MockERC20(_t0).balanceOf(address(pair));
    uint256 contractBalance1 = MockERC20(_t1).balanceOf(address(pair));
    assertEq(contractBalance0, AMOUNT_0 - AMOUNT_0_SKIM, 'Contract balance0 have to be 100_000');
    assertEq(contractBalance1, AMOUNT_1 - AMOUNT_1_SKIM, 'Contract balance1 have to be 50_000');
  }

  function testAliceAddLiquidity() public {
    (uint112 reserve0, uint112 reserve1) = reSwapPair().getReserves();
    (uint256 balance0, uint256 balance1) = reSwapPair().getBalances();
    assertEq(reserve0, 0, 'reserve0 have to be 0');
    assertEq(reserve1, 0, 'reserve1 have to be 0');
    assertEq(balance0, 0, 'balance0 have to be 0');
    assertEq(balance1, 0, 'balance1 have to be 0');

    (address _t0, address _t1) = getTokens();
    uint256 ALICE_AMOUNT_0 = 1500;
    uint256 ALICE_AMOUNT_1 = 2500;

    uint256 aliceBalance0 = MockERC20(_t0).balanceOf(Alice);
    uint256 aliceBalance1 = MockERC20(_t1).balanceOf(Alice);
    assertEq(aliceBalance0, USER_INIT_BALANCE, 'Alice balance0 have to be 0');
    assertEq(aliceBalance1, USER_INIT_BALANCE, 'Alice balance1 have to be 0');

    {
      vm.startPrank(Alice);
      MockERC20(_t0).approve(pair, ALICE_AMOUNT_0);
      MockERC20(_t1).approve(pair, ALICE_AMOUNT_1);
      reSwapPair().addLiquidity(ALICE_AMOUNT_0, ALICE_AMOUNT_1, ALICE_AMOUNT_0 - 10, ALICE_AMOUNT_1 - 10, Alice, 4);
      vm.stopPrank();

      (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();
      assertEq(afterBalance0, ALICE_AMOUNT_0, 'balance0 have to be 1500');
      assertEq(afterBalance1, ALICE_AMOUNT_1, 'balance1 have to be 2500');

      (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
      assertEq(afterReserve0, ALICE_AMOUNT_0, 'reserve0 have to be 1500');
      assertEq(afterReserve1, ALICE_AMOUNT_1, 'reserve1 have to be 2500');

      uint256 aliceLiquidity = reSwapPair().balanceOf(Alice);
      console2.log('aliceLiquidity', aliceLiquidity);
      assertGt(aliceLiquidity, 0, 'Alice liquidity have to be more than 0');

      uint256 totalLiquidity = reSwapPair().totalSupply();
      assertEq(
        totalLiquidity,
        aliceLiquidity + reSwapPair().MINIMUM_LIQUIDITY(),
        'Total liquidity have to be equal to Alice liquidity'
      );
    }

    {
      uint256 BOB_AMOUNT_0 = ALICE_AMOUNT_0 * 3;
      uint256 BOB_AMOUNT_1 = ALICE_AMOUNT_1 * 3;
      vm.startPrank(Bob);
      MockERC20(_t0).approve(pair, BOB_AMOUNT_0);
      MockERC20(_t1).approve(pair, BOB_AMOUNT_1);
      reSwapPair().addLiquidity(BOB_AMOUNT_0, BOB_AMOUNT_1, BOB_AMOUNT_0 - 10, BOB_AMOUNT_1 - 10, Bob, 4);
      vm.stopPrank();
      (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();
      assertEq(afterBalance0, ALICE_AMOUNT_0 + BOB_AMOUNT_0, 'balance0 have to be 1500');
      assertEq(afterBalance1, ALICE_AMOUNT_1 + BOB_AMOUNT_1, 'balance1 have to be 2500');

      console2.log('afterBalance0', afterBalance0);
      console2.log('afterBalance1', afterBalance1);
      (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
      assertEq(afterReserve0, ALICE_AMOUNT_0 + BOB_AMOUNT_0, 'reserve0 have to be 1500');
      assertEq(afterReserve1, ALICE_AMOUNT_1 + BOB_AMOUNT_1, 'reserve1 have to be 2500');

      console2.log('afterReserve0', afterReserve0);
      console2.log('afterReserve1', afterReserve1);

      uint256 bobLiquidity = reSwapPair().balanceOf(Bob);

      uint256 totalLiquidity2 = reSwapPair().totalSupply();
      assertGt(bobLiquidity, 0, 'Bob liquidity have to be more than 0');
    }
  }

  function addUserLiquidity(address sender, uint256 amount0, uint256 amount1, uint256 deadline) public {
    (address _t0, address _t1) = getTokens();
    MockERC20(_t0).transfer(address(sender), amount0);
    MockERC20(_t1).transfer(address(sender), amount0);

    vm.startPrank(sender);
    MockERC20(_t0).approve(pair, amount0);
    MockERC20(_t1).approve(pair, amount1);
    reSwapPair().addLiquidity(amount0, amount1, amount0 - 10, amount1 - 10, sender, deadline);
    vm.stopPrank();
  }

  function prepareTransfer() private {
    uint256 aliceBalance0 = _token0.balanceOf(Alice);
    uint256 bobBalance0 = _token0.balanceOf(Bob);
    assertEq(aliceBalance0, USER_INIT_BALANCE, 'Alice balance0 have to be 0');
    assertEq(bobBalance0, USER_INIT_BALANCE, 'Bob balance0 have to be 0');

    uint256 AMOUNT_0 = 1_999_999;
    uint256 AMOUNT_1 = 599_456;

    (address _t0, address _t1) = getTokens();
    MockERC20(_t0).transfer(address(reSwapPair()), AMOUNT_0);
    MockERC20(_t1).transfer(address(reSwapPair()), AMOUNT_1);

    uint256 contractBalance0 = MockERC20(_t0).balanceOf(address(reSwapPair()));
    uint256 contractBalance1 = MockERC20(_t1).balanceOf(address(reSwapPair()));

    assertEq(contractBalance0, AMOUNT_0, 'Contract balance0 have to be 1_999_999');
    assertEq(contractBalance1, AMOUNT_1, 'Contract balance1 have to be 599_456');
  }

  function init() private {
    vm.prank(address(reSwapFactory));
    reSwapPair().initialize(address(_token0), address(_token1));
  }
}
