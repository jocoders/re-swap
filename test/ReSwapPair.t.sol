// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ReSwapPair} from "../src/ReSwapPair.sol";
import {MockERC20} from "./MockERC20.t.sol";
import {ReSwapPairTestHelper} from "./ReSwapPairTestHelper.t.sol";
import {ReSwapFactoryTestHelper} from "./ReSwapFactoryTestHelper.t.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";
import {IReSwapFlashBorrower} from "../interfaces/IReSwapFlashBorrower.sol";

contract MockFlashBorrower is IReSwapFlashBorrower {
    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        uint256 balance = MockERC20(token).balanceOf(address(this));
        MockERC20(token).transfer(sender, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

contract ReSwapPairTest is Test {
    ReSwapFactoryTestHelper private reSwapFactory;
    MockERC20 private _token0;
    MockERC20 private _token1;
    MockFlashBorrower private borrower;
    address private pair;

    address private Alice = address(0x1);
    uint256 bobPrivateKey = 0x12344545664;

    // Получаем адрес из приватного ключа
    address Bob = vm.addr(bobPrivateKey);
    //address private Bob = address(0x2);
    uint256 privateKey = 0x123;
    address private traider1 = address(0x3);
    address private traider2 = address(0x4);

    uint256 private INIT_SUPPLY_0 = 1e18 / 5;
    uint256 private INIT_SUPPLY_1 = 1e18 / 2;

    uint112 private RESERVE_0 = 1e18 / 5;
    uint112 private RESERVE_1 = 1e18 / 2;
    uint256 private USER_INIT_BALANCE = 10_000_000;

    function setUp() public {
        _token0 = new MockERC20("Token0", "TK0", 18);
        _token1 = new MockERC20("Token1", "TK1", 18);

        reSwapFactory = new ReSwapFactoryTestHelper();
        pair = reSwapFactory.testCreatePair(address(_token0), address(_token1));

        // Минтим токены для использования в тестах
        _token0.mint(address(this), INIT_SUPPLY_0);
        _token1.mint(address(this), INIT_SUPPLY_1);
        borrower = new MockFlashBorrower();

        MockERC20(_token0).transfer(address(Alice), USER_INIT_BALANCE);
        MockERC20(_token1).transfer(address(Alice), USER_INIT_BALANCE);

        MockERC20(_token0).transfer(address(Bob), USER_INIT_BALANCE);
        MockERC20(_token1).transfer(address(Bob), USER_INIT_BALANCE);

        MockERC20(_token0).transfer(address(traider1), USER_INIT_BALANCE);
        MockERC20(_token1).transfer(address(traider1), USER_INIT_BALANCE);

        MockERC20(_token0).transfer(address(traider2), USER_INIT_BALANCE);
        MockERC20(_token1).transfer(address(traider2), USER_INIT_BALANCE);

        MockERC20(_token0).transfer(address(borrower), USER_INIT_BALANCE);
        MockERC20(_token1).transfer(address(borrower), USER_INIT_BALANCE);
    }

    function reSwapPair() private view returns (ReSwapPairTestHelper) {
        return ReSwapPairTestHelper(pair);
    }

    function getTokens() private view returns (address, address) {
        return _token0 < _token1 ? (address(_token0), address(_token1)) : (address(_token1), address(_token0));
    }

    function testSuccessInitialize() public view {
        (address _t0, address _t1) = getTokens();
        assertEq(reSwapPair().token0(), _t0, "token0 have to be address(token0)");
        assertEq(reSwapPair().token1(), _t1, "token1 have to be address(token1)");
    }

    function testFailedInitialize() public {
        vm.expectRevert("ALREADY_INITIALIZED");
        reSwapPair().initialize(address(_token0), address(_token1));
    }

    function testGetBalances() public {
        (uint256 beforeBalance0, uint256 beforeBalance1) = reSwapPair().getBalances();

        assertEq(beforeBalance0, 0, "Init balance0 have to be 0");
        assertEq(beforeBalance1, 0, "Init balance1 have to be 0");

        uint256 AMOUNT_0 = 1_999_999;
        uint256 AMOUNT_1 = 599_456;

        (address _t0, address _t1) = getTokens();
        MockERC20(_t0).transfer(pair, AMOUNT_0);
        MockERC20(_t1).transfer(pair, AMOUNT_1);

        (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();
        assertEq(afterBalance0, AMOUNT_0, "balance0 have to be 1_999_999");
        assertEq(afterBalance1, AMOUNT_1, "balance1 have to be 599_456");
    }

    function testGetReserves() public {
        (uint112 beforeReserve0, uint112 beforeReserve1) = reSwapPair().getReserves();
        assertEq(beforeReserve0, 0, "reserve0 have to be 0");
        assertEq(beforeReserve1, 0, "reserve1 have to be 0");

        uint32 beforeLastTimestamp = reSwapPair().getLastTimestamp();
        assertEq(beforeLastTimestamp, 0, "lastTimestamp have to be 0");

        uint256 AMOUNT_0 = 433_009;
        uint256 AMOUNT_1 = 2_456_890;
        reSwapPair().testUpdate(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

        (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
        assertEq(afterReserve0, AMOUNT_0, "reserve0 have to be 433_009");
        assertEq(afterReserve1, AMOUNT_1, "reserve1 have to be 2_456_890");

        uint32 afterLastTimestamp = reSwapPair().getLastTimestamp();
        assertNotEq(afterLastTimestamp, 0, "lastTimestamp have to be block.timestamp");
    }

    function testXFailedUpdate() public {
        vm.expectRevert();
        reSwapPair().testUpdate(type(uint256).max + 1, type(uint256).max + 1, 0, 0);
    }

    function testSuccessUpdate() public {
        prepareTransfer();

        uint256 AMOUNT_0 = 100_500;
        uint256 AMOUNT_1 = 45_987;

        reSwapPair().testUpdate(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

        uint32 afterLastTimestamp = reSwapPair().getLastTimestamp();
        assertNotEq(afterLastTimestamp, 0, "lastTimestamp have to be block.timestamp");

        (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
        assertEq(afterReserve0, AMOUNT_0, "reserve0 have to be 1_999_999 + 100_500");
        assertEq(afterReserve1, AMOUNT_1, "reserve1 have to be 599_456 + 45_987");
    }

    function testGetLastTimestamp() public {
        uint32 beforeLastTimestamp = reSwapPair().getLastTimestamp();
        assertEq(beforeLastTimestamp, 0, "lastTimestamp have to be 0");

        uint256 AMOUNT_0 = 433_009;
        uint256 AMOUNT_1 = 2_456_890;

        reSwapPair().testUpdate(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

        uint32 afterLastTimestamp = reSwapPair().getLastTimestamp();
        assertNotEq(afterLastTimestamp, 0, "lastTimestamp have to be block.timestamp");
    }

    function testValidateSwap() public {
        uint256 AMOUNT_0 = 433_009;
        uint256 AMOUNT_1 = 2_456_890;

        reSwapPair().testUpdate(AMOUNT_0, AMOUNT_1, uint112(AMOUNT_0), uint112(AMOUNT_1));

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

        assertEq(aliceBalance1, 500_000 + USER_INIT_BALANCE, "Alice balance should increase by 500_000");
        assertEq(bobBalance1, 100_500 + USER_INIT_BALANCE, "Bob balance should increase by 100_500");
    }

    function testFTransferPair() public {
        prepareTransfer();

        vm.expectRevert("INVALID_TO_ADDRESS");
        reSwapPair().testTransferPair(1_999_999, 599_456, address(_token0));

        vm.expectRevert("INVALID_TO_ADDRESS");
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

        assertEq(aliceBalance0, AMOUNT_0 + USER_INIT_BALANCE, "Alice balance0 have to be 87_999");
        assertEq(bobBalance0, AMOUNT_1 + USER_INIT_BALANCE, "Bob balance0 have to be 255_457");

        assertEq(aliceBalance1, AMOUNT_1 + USER_INIT_BALANCE, "Alice balance1 have to be 255_457");
        assertEq(bobBalance1, AMOUNT_0 + USER_INIT_BALANCE, "Bob balance1 have to be 87_999");
    }

    function testSkim() public {
        uint256 AMOUNT_0 = 1_999_999;
        uint256 AMOUNT_1 = 599_456;
        uint256 AMOUNT_0_SKIM = 100_000;
        uint256 AMOUNT_1_SKIM = 50_000;

        (address _t0, address _t1) = getTokens();
        MockERC20(_t0).transfer(address(pair), AMOUNT_0);
        MockERC20(_t1).transfer(address(pair), AMOUNT_1);

        reSwapPair().testUpdate(
            AMOUNT_0 - AMOUNT_0_SKIM,
            AMOUNT_1 - AMOUNT_1_SKIM,
            uint112(AMOUNT_0 - AMOUNT_0_SKIM),
            uint112(AMOUNT_1 - AMOUNT_1_SKIM)
        );
        vm.prank(address(reSwapFactory));
        reSwapPair().skim(Alice);
        uint256 aliceBalance0 = MockERC20(_t0).balanceOf(Alice);
        uint256 aliceBalance1 = MockERC20(_t1).balanceOf(Alice);
        assertEq(aliceBalance0, AMOUNT_0_SKIM + USER_INIT_BALANCE, "Alice balance0 have to be 100_000");
        assertEq(aliceBalance1, AMOUNT_1_SKIM + USER_INIT_BALANCE, "Alice balance1 have to be 50_000");
        uint256 contractBalance0 = MockERC20(_t0).balanceOf(address(pair));
        uint256 contractBalance1 = MockERC20(_t1).balanceOf(address(pair));
        assertEq(contractBalance0, AMOUNT_0 - AMOUNT_0_SKIM, "Contract balance0 have to be 100_000");
        assertEq(contractBalance1, AMOUNT_1 - AMOUNT_1_SKIM, "Contract balance1 have to be 50_000");
    }

    function testSwapTokensForExactTokens() public {
        testAddLiquidity();
        (uint112 beforeReserve0, uint112 beforeReserve1) = reSwapPair().getReserves();
        (uint256 beforeBalance0, uint256 beforeBalance1) = reSwapPair().getBalances();
        (address _t0, address _t1) = getTokens();

        vm.startPrank(traider1);
        MockERC20(_t0).approve(address(reSwapPair()), 3000);
        reSwapPair().swapTokensForExactTokens(address(_t0), address(_t1), 300, 3000, traider1, 5);
        vm.stopPrank();

        (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
        (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();

        assertGt(afterReserve0, beforeReserve0, "afterReserve0 have to be greater than beforeReserve0");
        assertEq(afterReserve1, beforeReserve1 - 300, "afterReserve1 have to lesser than beforeReserve1 - 300");
        assertGt(afterBalance0, beforeBalance0, "afterBalance0 have to be greater than beforeBalance0");
        assertEq(afterBalance1, beforeBalance1 - 300, "afterBalance1 have to be lesser than beforeBalance1 - 300");
    }

    function testFailedSwapExactTokensForTokens() public {
        (address _t0, address _t1) = getTokens();
        testAddLiquidity();
        vm.startPrank(traider1);
        MockERC20(_t0).approve(address(reSwapPair()), USER_INIT_BALANCE);
        vm.expectRevert();
        reSwapPair().swapExactTokensForTokens(address(_t0), address(_t1), 100, 0, traider1, block.timestamp);

        vm.expectRevert();
        reSwapPair().swapTokensForExactTokens(
            address(_t0), address(_t1), 100, USER_INIT_BALANCE, traider1, block.timestamp
        );
        vm.stopPrank();
    }

    function testSwapExactTokensForTokens() public {
        testAddLiquidity();
        (uint112 beforeReserve0, uint112 beforeReserve1) = reSwapPair().getReserves();
        (uint256 beforeBalance0, uint256 beforeBalance1) = reSwapPair().getBalances();

        (address _t0, address _t1) = getTokens();

        vm.startPrank(traider1);
        MockERC20(_t0).approve(address(reSwapPair()), 100);
        reSwapPair().swapExactTokensForTokens(address(_t0), address(_t1), 100, 0, traider1, 5);
        vm.stopPrank();

        (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
        (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();
        uint256 traiderBalance0 = MockERC20(_t0).balanceOf(traider1);
        uint256 traiderBalance1 = MockERC20(_t1).balanceOf(traider1);

        assertEq(traiderBalance0, USER_INIT_BALANCE - 100, "traiderBalance0 have to be 100 more");
        assertGt(traiderBalance1, USER_INIT_BALANCE, "traiderBalance1 have to be greater then USER_INIT_BALANCE");
        assertEq(afterReserve0, beforeReserve0 + 100, "afterReserve0 have to be 100 more");
        assertLt(afterReserve1, beforeReserve1, "afterReserve1 have to be lesseer than beforeReserve1");
        assertEq(afterBalance0, beforeBalance0 + 100, "afterBalance0 have to be 100 more");
        assertLt(afterBalance1, beforeBalance1, "afterBalance0 have to be lesseer than beforeBalance0");
    }

    function testFailedAddLiquidity() public {
        vm.expectRevert();
        prepareAddLiquidity(Bob, 1500, 2500, block.timestamp);

        vm.expectRevert();
        prepareAddLiquidity(Bob, 1500, 10_500, 4);

        vm.expectRevert();
        prepareAddLiquidity(Bob, 1_500_000, 2500, 4);
    }

    function testAddLiquidity() public {
        (uint112 reserve0, uint112 reserve1) = reSwapPair().getReserves();
        (uint256 balance0, uint256 balance1) = reSwapPair().getBalances();
        assertEq(reserve0, 0, "reserve0 have to be 0");
        assertEq(reserve1, 0, "reserve1 have to be 0");
        assertEq(balance0, 0, "balance0 have to be 0");
        assertEq(balance1, 0, "balance1 have to be 0");

        (address _t0, address _t1) = getTokens();
        uint256 ALICE_AMOUNT_0 = 1500;
        uint256 ALICE_AMOUNT_1 = 2500;
        {
            prepareAddLiquidity(Alice, ALICE_AMOUNT_0, ALICE_AMOUNT_1, 4);
            (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();
            assertEq(afterBalance0, ALICE_AMOUNT_0, "balance0 have to be 1500");
            assertEq(afterBalance1, ALICE_AMOUNT_1, "balance1 have to be 2500");

            (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
            assertEq(afterReserve0, ALICE_AMOUNT_0, "reserve0 have to be 1500");
            assertEq(afterReserve1, ALICE_AMOUNT_1, "reserve1 have to be 2500");

            uint256 aliceLiquidity = reSwapPair().balanceOf(Alice);
            assertGt(aliceLiquidity, 0, "Alice liquidity have to be more than 0");

            uint256 totalLiquidity = reSwapPair().totalSupply();
            assertEq(
                totalLiquidity,
                aliceLiquidity + reSwapPair().MINIMUM_LIQUIDITY(),
                "Total liquidity have to be equal to Alice liquidity"
            );
        }

        {
            uint256 BOB_AMOUNT_0 = ALICE_AMOUNT_0 * 3;
            uint256 BOB_AMOUNT_1 = ALICE_AMOUNT_1 * 3;
            prepareAddLiquidity(Bob, BOB_AMOUNT_0, BOB_AMOUNT_1, 8);

            (uint256 afterBalance0, uint256 afterBalance1) = reSwapPair().getBalances();
            assertEq(afterBalance0, ALICE_AMOUNT_0 + BOB_AMOUNT_0, "balance0 have to be 1500");
            assertEq(afterBalance1, ALICE_AMOUNT_1 + BOB_AMOUNT_1, "balance1 have to be 2500");

            (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
            assertEq(afterReserve0, ALICE_AMOUNT_0 + BOB_AMOUNT_0, "reserve0 have to be 1500");
            assertEq(afterReserve1, ALICE_AMOUNT_1 + BOB_AMOUNT_1, "reserve1 have to be 2500");

            uint256 bobLiquidity = reSwapPair().balanceOf(Bob);
            uint256 totalLiquidity2 = reSwapPair().totalSupply();
            assertGt(bobLiquidity, 0, "Bob liquidity have to be more than 0");

            uint256 lastCumulativePrice0 = reSwapPair().lastCumulativePrice0();
            uint256 lastCumulativePrice1 = reSwapPair().lastCumulativePrice1();
            uint256 lastConstant = reSwapPair().lastConstant();
        }
    }

    function prepareAddLiquidity(address user, uint256 amount0, uint256 amount1, uint256 deadline) private {
        (address _t0, address _t1) = getTokens();
        uint256 userBalance0 = MockERC20(_t0).balanceOf(user);
        uint256 userBalance1 = MockERC20(_t1).balanceOf(user);
        assertEq(userBalance0, USER_INIT_BALANCE, "User balance0 have to be not USER_INIT_BALANCE");
        assertEq(userBalance1, USER_INIT_BALANCE, "User balance1 have to be not USER_INIT_BALANCE");

        vm.startPrank(user);
        MockERC20(_t0).approve(pair, amount0);
        MockERC20(_t1).approve(pair, amount1);
        reSwapPair().addLiquidity(amount0, amount1, amount0 - 10, amount1 - 10, user, deadline);
        vm.stopPrank();
    }

    function testSuccessfulFlashLoan() public {
        uint256 AMOUNT_0 = 1500;
        uint256 AMOUNT_1 = 4000;
        prepareAddLiquidity(Alice, AMOUNT_0, AMOUNT_1, 4);
        prepareAddLiquidity(Bob, AMOUNT_0 * 3, AMOUNT_1 * 3, 4);

        (address _t0, address _t1) = getTokens();
        uint256 amount = 100;
        uint256 fee = reSwapPair().flashFee(address(_t0), amount);
        uint256 totalRepayment = amount + fee;

        uint256 initBal = MockERC20(_t0).balanceOf(pair);

        vm.prank(address(this));
        bool success = reSwapPair().flashLoan(borrower, address(_t0), amount, "0x");

        assertTrue(success, "Flash loan should succeed");

        uint256 finalBal = MockERC20(_t0).balanceOf(pair);
        assertEq(finalBal, initBal + fee, "Pool balance should be restored after repayment");
    }

    function testRemoveLiquidity() public {
        (address _t0, address _t1) = getTokens();
        uint256 ALICE_AMOUNT_0 = 1500;
        uint256 ALICE_AMOUNT_1 = 2500;
        prepareAddLiquidity(Alice, ALICE_AMOUNT_0, ALICE_AMOUNT_1, 8);

        uint256 BOB_AMOUNT_0 = ALICE_AMOUNT_0; // 4500
        uint256 BOB_AMOUNT_1 = ALICE_AMOUNT_1; // 7500
        prepareAddLiquidity(Bob, BOB_AMOUNT_0, BOB_AMOUNT_1, 8);

        uint256 JO_AMOUNT_0 = ALICE_AMOUNT_0; // 4500
        uint256 JO_AMOUNT_1 = ALICE_AMOUNT_1; // 7500
        prepareAddLiquidity(traider1, JO_AMOUNT_0, JO_AMOUNT_1, 8);

        uint256 liquidity = reSwapPair().totalSupply();
        uint256 aliceLiquidity = reSwapPair().balanceOf(Alice);
        uint256 bobLiquidity = reSwapPair().balanceOf(Bob);
        uint256 joLiquidity = reSwapPair().balanceOf(traider1);

        (uint112 reserve0, uint112 reserve1) = reSwapPair().getReserves();

        assertEq(
            liquidity,
            aliceLiquidity + bobLiquidity + joLiquidity + reSwapPair().MINIMUM_LIQUIDITY(),
            "liquidity have to be equal to aliceLiquidity + bobLiquidity + MINIMUM_LIQUIDITY"
        );
        assertEq(
            reserve0,
            ALICE_AMOUNT_0 + BOB_AMOUNT_0 + JO_AMOUNT_0,
            "reserve0 have to be equal to ALICE_AMOUNT_0 + BOB_AMOUNT_0 + JO_AMOUNT_0"
        );
        assertEq(
            reserve1,
            ALICE_AMOUNT_1 + BOB_AMOUNT_1 + JO_AMOUNT_1,
            "reserve1 have to be equal to ALICE_AMOUNT_1 + BOB_AMOUNT_1 + JO_AMOUNT_1"
        );

        vm.startPrank(Bob);
        reSwapPair().approve(pair, bobLiquidity);
        reSwapPair().removeLiquidity(bobLiquidity, 100, 100, Bob, 4);
        vm.stopPrank();

        (uint112 afterReserve0, uint112 afterReserve1) = reSwapPair().getReserves();
        uint256 afterBobLiquidity = reSwapPair().balanceOf(Bob);
        uint256 afterLiquidity = reSwapPair().totalSupply();

        assertEq(
            afterLiquidity, liquidity - bobLiquidity, "afterLiquidity have to be less than liquidity - bobLiquidity"
        );
        assertEq(afterBobLiquidity, 0, "afterBobLiquidity have to be 0");
        assertEq(afterReserve0, reserve0 - BOB_AMOUNT_0, "afterReserve0 have to be reserve0 - BOB_AMOUNT_0");
        assertEq(afterReserve1, reserve1 - BOB_AMOUNT_1, "afterReserve1 have to be reserve1 - BOB_AMOUNT_1");
    }

    function testMaxFlashLoan() public {
        uint256 AMOUNT_0 = 1_999_999;
        uint256 AMOUNT_1 = 599_456;
        prepareAddLiquidity(Alice, AMOUNT_0, AMOUNT_1, 4);

        (uint112 reserve0, uint112 reserve1) = reSwapPair().getReserves();
        (address _t0, address _t1) = getTokens();
        uint256 maxFlashLoan0 = reSwapPair().maxFlashLoan(address(_t0));
        uint256 maxFlashLoan1 = reSwapPair().maxFlashLoan(address(_t1));

        assertEq(maxFlashLoan0, (reserve0 * 10) / 100, "maxFlashLoan0 have to be reserve0");
        assertEq(maxFlashLoan1, (reserve1 * 5) / 100, "maxFlashLoan1 have to be reserve1");
    }

    function prepareTransfer() private {
        uint256 aliceBalance0 = _token0.balanceOf(Alice);
        uint256 bobBalance0 = _token0.balanceOf(Bob);
        assertEq(aliceBalance0, USER_INIT_BALANCE, "Alice balance0 have to be 0");
        assertEq(bobBalance0, USER_INIT_BALANCE, "Bob balance0 have to be 0");

        uint256 AMOUNT_0 = 1_999_999;
        uint256 AMOUNT_1 = 599_456;

        (address _t0, address _t1) = getTokens();
        MockERC20(_t0).transfer(address(reSwapPair()), AMOUNT_0);
        MockERC20(_t1).transfer(address(reSwapPair()), AMOUNT_1);

        uint256 contractBalance0 = MockERC20(_t0).balanceOf(address(reSwapPair()));
        uint256 contractBalance1 = MockERC20(_t1).balanceOf(address(reSwapPair()));

        assertEq(contractBalance0, AMOUNT_0, "Contract balance0 have to be 1_999_999");
        assertEq(contractBalance1, AMOUNT_1, "Contract balance1 have to be 599_456");
    }

    // function testRemoveLiquidityWithPermit() public {
    //   (address _t0, address _t1) = getTokens();
    //   uint256 INIT_AMOUNT_0 = 1500;
    //   uint256 INIT_AMOUNT_1 = 2500;
    //   prepareAddLiquidity(Alice, INIT_AMOUNT_0, INIT_AMOUNT_1, 8);
    //   prepareAddLiquidity(Bob, INIT_AMOUNT_0 * 3, INIT_AMOUNT_1 * 3, 8);
    //   // prepareAddLiquidity(Jo, INIT_AMOUNT_0 * 9, INIT_AMOUNT_1 * 9, 8);

    //   uint256 liquidity = reSwapPair().totalSupply();
    //   uint256 aliceLiquidity = reSwapPair().balanceOf(Alice);
    //   uint256 bobLiquidity = reSwapPair().balanceOf(Bob);
    //   // uint256 joLiquidity = reSwapPair().balanceOf(Jo);

    //   bool approveMax = false;

    //   uint256 nonce = reSwapPair().nonces(Bob); // Получаем актуальный nonce для Bob
    //   uint256 deadline = block.timestamp + 3600; // Устанавливаем deadline на 1 час вперед

    //   bytes32 digest = keccak256(
    //     abi.encodePacked(
    //       '\x19\x01',
    //       reSwapPair().DOMAIN_SEPARATOR(),
    //       keccak256(
    //         abi.encode(
    //           keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'),
    //           Bob,
    //           address(pair),
    //           bobLiquidity,
    //           nonce, // nonce (предполагается, что это первая транзакция)
    //           deadline
    //         )
    //       )
    //     )
    //   );

    //   (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);

    //   vm.startPrank(Bob);
    //   reSwapPair().removeLiquidityWithPermit(bobLiquidity, 100, 100, Bob, 4, false, v, r, s);
    //   vm.stopPrank();

    //   (uint112 reserve0, uint112 reserve1) = reSwapPair().getReserves();
    // }
}
