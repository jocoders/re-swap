// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ReSwapPair} from "../src/ReSwapPair.sol";
import {MockERC20} from "./MockERC20.t.sol";
import {ReSwapPairTestHelper} from "./ReSwapPairTestHelper.t.sol";
import {ReSwapFactoryTestHelper} from "./ReSwapFactoryTestHelper.t.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";

contract ReSwapPairTest is Test {
    ReSwapFactoryTestHelper private reSwapFactory;
    MockERC20 private token0;
    MockERC20 private token1;
    address private pair;

    address private Alice = address(0x1);
    address private Bob = address(0x2);

    uint256 private INIT_SUPPLY_0 = 1e18 / 5;
    uint256 private INIT_SUPPLY_1 = 1e18 / 2;

    uint112 private RESERVE_0 = 1e18 / 5;
    uint112 private RESERVE_1 = 1e18 / 2;

    function setUp() public {
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);

        reSwapFactory = new ReSwapFactoryTestHelper();
        pair = reSwapFactory.testCreatePair(address(token0), address(token1));

        // Минтим токены для использования в тестах
        token0.mint(address(this), INIT_SUPPLY_0);
        token1.mint(address(this), INIT_SUPPLY_1);
    }

    function reSwapPair() private view returns (ReSwapPairTestHelper) {
        return ReSwapPairTestHelper(pair);
    }

    function testSuccessInitialize() public {
        init();
        assertEq(reSwapPair().token0(), address(token0), "token0 have to be address(token0)");
        assertEq(reSwapPair().token1(), address(token1), "token1 have to be address(token1)");
    }

    function testFailedInitialize() public {
        vm.prank(address(0x1));
        reSwapPair().initialize(address(token0), address(token1));

        assertEq(reSwapPair().token0(), address(0), "token0 have to be 0");
        assertEq(reSwapPair().token1(), address(0), "token1 have to be 0");
    }

    function testGetBalances() public {
        init();
        (uint256 beforeBalance0, uint256 beforeBalance1) = reSwapPair().getBalances();
        assertEq(beforeBalance0, 0, "Init balance0 have to be 0");
        assertEq(beforeBalance1, 0, "Init balance1 have to be 0");

        uint256 AMOUNT_0 = 1_999_999;
        uint256 AMOUNT_1 = 599_456;

        token0.transfer(pair, AMOUNT_0);
        token1.transfer(pair, AMOUNT_1);

        (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();
        assertEq(afterBalance0, AMOUNT_0, "balance0 have to be 1_999_999");
        assertEq(afterBalance1, AMOUNT_1, "balance1 have to be 599_456");
    }

    function testGetReserves() public {
        init();
        (uint112 beforeReserve0, uint112 beforeReserve1) = reSwapPair().getReserves();
        assertEq(beforeReserve0, 0, "reserve0 have to be 0");
        assertEq(beforeReserve1, 0, "reserve1 have to be 0");

        uint256 AMOUNT_0 = 433_009;
        uint256 AMOUNT_1 = 2_456_890;

        reSwapPair().update(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

        (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
        assertEq(afterReserve0, AMOUNT_0, "reserve0 have to be 433_009");
        assertEq(afterReserve1, AMOUNT_1, "reserve1 have to be 2_456_890");
    }

    function testXFailedUpdate() public {
        vm.expectRevert();
        reSwapPair().update(type(uint256).max + 1, type(uint256).max + 1, 0, 0);
    }

    function testSuccessUpdate() public {
        prepareTransfer();

        uint256 AMOUNT_0 = 1_999_999 + 100_500;
        uint256 AMOUNT_1 = 599_456 + 45_987;

        reSwapPair().update(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

        uint32 afterLastTimestamp = reSwapPair().getLastTimestamp();
        assertNotEq(afterLastTimestamp, 0, "lastTimestamp have to be block.timestamp");

        (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
        assertEq(afterReserve0, AMOUNT_0, "reserve0 have to be 1_999_999 + 100_500");
        assertEq(afterReserve1, AMOUNT_1, "reserve1 have to be 599_456 + 45_987");
    }

    function testGetLastTimestamp() public {
        init();
        uint32 beforeLastTimestamp = reSwapPair().getLastTimestamp();
        assertEq(beforeLastTimestamp, 0, "lastTimestamp have to be 0");

        uint256 AMOUNT_0 = 433_009;
        uint256 AMOUNT_1 = 2_456_890;

        reSwapPair().update(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

        uint32 afterLastTimestamp = reSwapPair().getLastTimestamp();
        assertNotEq(afterLastTimestamp, 0, "lastTimestamp have to be block.timestamp");
    }

    function testValidateSwap() public {
        init();
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
        TransferHelper.safeTransfer(address(token0), Alice, 500_000);
        TransferHelper.safeTransfer(address(token0), Bob, 100_500);

        uint256 aliceBalance1 = token0.balanceOf(Alice);
        uint256 bobBalance1 = token0.balanceOf(Bob);

        assertEq(aliceBalance1, 500_000, "Alice balance should increase by 500_000");
        assertEq(bobBalance1, 100_500, "Bob balance should increase by 100_500");
    }

    function testFTransferPair() public {
        prepareTransfer();

        vm.expectRevert();
        reSwapPair().testTransferPair(1_999_999, 599_456, address(token0));

        vm.expectRevert();
        reSwapPair().testTransferPair(1_999_999, 599_456, address(token1));
    }

    function testSuccessTransferPair() public {
        prepareTransfer();

        uint256 AMOUNT_0 = 87_999;
        uint256 AMOUNT_1 = 255_457;

        reSwapPair().testTransferPair(AMOUNT_0, AMOUNT_1, Alice);

        reSwapPair().testTransferPair(AMOUNT_1, AMOUNT_0, Bob);

        uint256 aliceBalance0 = token0.balanceOf(Alice);
        uint256 bobBalance0 = token0.balanceOf(Bob);

        uint256 aliceBalance1 = token1.balanceOf(Alice);
        uint256 bobBalance1 = token1.balanceOf(Bob);

        assertEq(aliceBalance0, AMOUNT_0, "Alice balance0 have to be 87_999");
        assertEq(bobBalance0, AMOUNT_1, "Bob balance0 have to be 255_457");

        assertEq(aliceBalance1, AMOUNT_1, "Alice balance1 have to be 255_457");
        assertEq(bobBalance1, AMOUNT_0, "Bob balance1 have to be 87_999");
    }

    function testSkim() public {
        init();

        uint256 AMOUNT_0 = 1_999_999;
        uint256 AMOUNT_1 = 599_456;
        uint256 AMOUNT_0_SKIM = 100_000;
        uint256 AMOUNT_1_SKIM = 50_000;

        token0.transfer(address(pair), AMOUNT_0);
        token1.transfer(address(pair), AMOUNT_1);

        reSwapPair().update(
            AMOUNT_0 - AMOUNT_0_SKIM,
            AMOUNT_1 - AMOUNT_1_SKIM,
            uint112(AMOUNT_0 - AMOUNT_0_SKIM),
            uint112(AMOUNT_1 - AMOUNT_1_SKIM)
        );

        reSwapPair().skim(Alice);

        uint256 aliceBalance0 = token0.balanceOf(Alice);
        uint256 aliceBalance1 = token1.balanceOf(Alice);

        assertEq(aliceBalance0, AMOUNT_0_SKIM, "Alice balance0 have to be 100_000");
        assertEq(aliceBalance1, AMOUNT_1_SKIM, "Alice balance1 have to be 50_000");

        uint256 contractBalance0 = token0.balanceOf(address(pair));
        uint256 contractBalance1 = token1.balanceOf(address(pair));

        assertEq(contractBalance0, AMOUNT_0 - AMOUNT_0_SKIM, "Contract balance0 have to be 100_000");
        assertEq(contractBalance1, AMOUNT_1 - AMOUNT_1_SKIM, "Contract balance1 have to be 50_000");
    }

    function testMint() public {
        init();
        (uint112 reserve0, uint112 reserve1) = reSwapPair().getReserves();
        (uint256 balance0, uint256 balance1) = reSwapPair().getBalances();
        assertEq(reserve0, 0, "reserve0 have to be 0");
        assertEq(reserve1, 0, "reserve1 have to be 0");
        assertEq(balance0, 0, "balance0 have to be 0");
        assertEq(balance1, 0, "balance1 have to be 0");

        token0.approve(address(reSwapPair()), 1500);
        token1.approve(address(reSwapPair()), 2500);
        token0.transfer(pair, 1500);
        token1.transfer(pair, 2500);

        (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();
        assertEq(afterBalance0, 1500, "balance0 have to be 1500");
        assertEq(afterBalance1, 2500, "balance1 have to be 2500");

        reSwapPair().update(1000, 2000, uint112(1000), uint112(2000));
        (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();

        assertEq(afterReserve0, 1000, "reserve0 have to be 1000");
        assertEq(afterReserve1, 2000, "reserve1 have to be 2000");

        reSwapPair().mint(Alice);
        uint256 aliceLiquidity = reSwapPair().balanceOf(Alice);
        console2.log(aliceLiquidity);
        //assertGt(aliceLiquidity, 0, 'Alice liquidity have to be more than 0');

        // console2.log(reserve0);
        // console2.log(reserve1);
        // console2.log(balance0);
        // console2.log(balance1);
    }

    function prepareTransfer() private {
        init();

        uint256 aliceBalance0 = token0.balanceOf(Alice);
        uint256 bobBalance0 = token0.balanceOf(Bob);
        assertEq(aliceBalance0, 0, "Alice balance0 have to be 0");
        assertEq(bobBalance0, 0, "Bob balance0 have to be 0");

        uint256 AMOUNT_0 = 1_999_999;
        uint256 AMOUNT_1 = 599_456;

        token0.transfer(address(reSwapPair()), AMOUNT_0);
        token1.transfer(address(reSwapPair()), AMOUNT_1);

        uint256 contractBalance0 = token0.balanceOf(address(reSwapPair()));
        uint256 contractBalance1 = token1.balanceOf(address(reSwapPair()));

        assertEq(contractBalance0, AMOUNT_0, "Contract balance0 have to be 1_999_999");
        assertEq(contractBalance1, AMOUNT_1, "Contract balance1 have to be 599_456");
    }

    function init() private {
        vm.prank(address(reSwapFactory));
        reSwapPair().initialize(address(token0), address(token1));
    }
}
