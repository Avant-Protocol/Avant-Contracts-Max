// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddressesWhitelist} from "../src/AddressesWhitelist.sol";
import {IAddressesWhitelist} from "../src/interfaces/IAddressesWhitelist.sol";

contract AddressesWhitelistTest is Test {
    AddressesWhitelist public whitelist;
    
    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    
    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        
        vm.prank(owner);
        whitelist = new AddressesWhitelist();
    }
    
    // Constructor Tests
    function test_Constructor() public {
        vm.prank(alice);
        AddressesWhitelist newWhitelist = new AddressesWhitelist();
        vm.snapshotGasLastCall("AddressesWhitelist_constructor");
        
        assertEq(newWhitelist.owner(), alice);
        assertEq(newWhitelist.pendingOwner(), address(0));
    }
    
    // addAccount Tests
    function test_AddAccount_Success() public {
        vm.prank(owner);
        vm.expectEmit(address(whitelist));
        emit IAddressesWhitelist.AccountAdded(alice);
        whitelist.addAccount(alice);
        vm.snapshotGasLastCall("AddressesWhitelist_addAccount_firstTime");
        
        assertTrue(whitelist.isAllowedAccount(alice));
    }
    
    function test_AddAccount_MultipleAccounts() public {
        vm.startPrank(owner);
        whitelist.addAccount(alice);
        vm.snapshotGasLastCall("AddressesWhitelist_addAccount_cold");
        
        whitelist.addAccount(bob);
        vm.snapshotGasLastCall("AddressesWhitelist_addAccount_warm");
        
        whitelist.addAccount(charlie);
        vm.snapshotGasLastCall("AddressesWhitelist_addAccount_third");
        vm.stopPrank();
        
        assertTrue(whitelist.isAllowedAccount(alice));
        assertTrue(whitelist.isAllowedAccount(bob));
        assertTrue(whitelist.isAllowedAccount(charlie));
    }
    
    function test_AddAccount_AlreadyWhitelisted() public {
        vm.startPrank(owner);
        whitelist.addAccount(alice);
        
        // Adding again should still work (idempotent)
        whitelist.addAccount(alice);
        vm.snapshotGasLastCall("AddressesWhitelist_addAccount_alreadyWhitelisted");
        vm.stopPrank();
        
        assertTrue(whitelist.isAllowedAccount(alice));
    }
    
    function test_AddAccount_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IAddressesWhitelist.ZeroAddress.selector);
        whitelist.addAccount(address(0));
    }
    
    function test_AddAccount_RevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        whitelist.addAccount(bob);
    }
    
    // removeAccount Tests
    function test_RemoveAccount_Success() public {
        vm.startPrank(owner);
        whitelist.addAccount(alice);
        assertTrue(whitelist.isAllowedAccount(alice));
        
        vm.expectEmit(address(whitelist));
        emit IAddressesWhitelist.AccountRemoved(alice);
        whitelist.removeAccount(alice);
        vm.snapshotGasLastCall("AddressesWhitelist_removeAccount_existing");
        vm.stopPrank();
        
        assertFalse(whitelist.isAllowedAccount(alice));
    }
    
    function test_RemoveAccount_NotWhitelisted() public {
        vm.prank(owner);
        // Should not revert even if account wasn't whitelisted
        whitelist.removeAccount(alice);
        vm.snapshotGasLastCall("AddressesWhitelist_removeAccount_nonExisting");
        
        assertFalse(whitelist.isAllowedAccount(alice));
    }
    
    function test_RemoveAccount_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IAddressesWhitelist.ZeroAddress.selector);
        whitelist.removeAccount(address(0));
    }
    
    function test_RemoveAccount_RevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        whitelist.removeAccount(bob);
    }
    
    // isAllowedAccount Tests
    function test_IsAllowedAccount_DefaultFalse() public {
        assertFalse(whitelist.isAllowedAccount(alice));
        vm.snapshotGasLastCall("AddressesWhitelist_isAllowedAccount_false");
        
        assertFalse(whitelist.isAllowedAccount(bob));
        assertFalse(whitelist.isAllowedAccount(address(0)));
    }
    
    function test_IsAllowedAccount_AfterAddRemove() public {
        vm.startPrank(owner);
        
        assertFalse(whitelist.isAllowedAccount(alice));
        
        whitelist.addAccount(alice);
        assertTrue(whitelist.isAllowedAccount(alice));
        vm.snapshotGasLastCall("AddressesWhitelist_isAllowedAccount_true");
        
        whitelist.removeAccount(alice);
        assertFalse(whitelist.isAllowedAccount(alice));
        vm.snapshotGasLastCall("AddressesWhitelist_isAllowedAccount_afterRemove");
        
        vm.stopPrank();
    }
    
    // Ownership Transfer Tests (Ownable2Step)
    function test_TransferOwnership_TwoStep() public {
        vm.prank(owner);
        whitelist.transferOwnership(alice);
        vm.snapshotGasLastCall("AddressesWhitelist_transferOwnership");
        
        // Owner should still be the original owner
        assertEq(whitelist.owner(), owner);
        assertEq(whitelist.pendingOwner(), alice);
        
        // Alice accepts ownership
        vm.prank(alice);
        whitelist.acceptOwnership();
        vm.snapshotGasLastCall("AddressesWhitelist_acceptOwnership");
        
        assertEq(whitelist.owner(), alice);
        assertEq(whitelist.pendingOwner(), address(0));
    }
    
    function test_TransferOwnership_OnlyOwnerCanInitiate() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        whitelist.transferOwnership(bob);
    }
    
    function test_TransferOwnership_OnlyPendingOwnerCanAccept() public {
        vm.prank(owner);
        whitelist.transferOwnership(alice);
        
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", bob));
        whitelist.acceptOwnership();
    }
    
    function test_TransferOwnership_CannotAcceptIfNoPending() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        whitelist.acceptOwnership();
    }
    
    function test_TransferOwnership_CanRenounce() public {
        vm.prank(owner);
        whitelist.renounceOwnership();
        vm.snapshotGasLastCall("AddressesWhitelist_renounceOwnership");
        
        assertEq(whitelist.owner(), address(0));
    }
    
    function test_TransferOwnership_ZeroAddressCannotAccept() public {
        vm.prank(owner);
        whitelist.transferOwnership(address(0));
        
        // This would be impossible since we can't prank as address(0)
        // The ownership transfer is effectively blocked
        assertEq(whitelist.owner(), owner);
        assertEq(whitelist.pendingOwner(), address(0));
    }
    
    // Integration Tests
    function test_FullLifecycle() public {
        // Add multiple accounts
        vm.startPrank(owner);
        whitelist.addAccount(alice);
        whitelist.addAccount(bob);
        vm.stopPrank();
        
        assertTrue(whitelist.isAllowedAccount(alice));
        assertTrue(whitelist.isAllowedAccount(bob));
        assertFalse(whitelist.isAllowedAccount(charlie));
        
        // Transfer ownership
        vm.prank(owner);
        whitelist.transferOwnership(alice);
        
        // Original owner can still manage while transfer pending
        vm.prank(owner);
        whitelist.addAccount(charlie);
        assertTrue(whitelist.isAllowedAccount(charlie));
        
        // Accept ownership
        vm.prank(alice);
        whitelist.acceptOwnership();
        
        // New owner manages whitelist
        vm.startPrank(alice);
        whitelist.removeAccount(bob);
        assertFalse(whitelist.isAllowedAccount(bob));
        
        // Old owner cannot manage
        vm.stopPrank();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        whitelist.addAccount(bob);
    }
    
    // Fuzz Tests
    function testFuzz_AddAccount(address account) public {
        vm.assume(account != address(0));
        
        vm.prank(owner);
        whitelist.addAccount(account);
        vm.snapshotGasLastCall("AddressesWhitelist_addAccount_fuzz");
        
        assertTrue(whitelist.isAllowedAccount(account));
    }
    
    function testFuzz_RemoveAccount(address account) public {
        vm.assume(account != address(0));
        
        vm.startPrank(owner);
        whitelist.addAccount(account);
        assertTrue(whitelist.isAllowedAccount(account));
        
        whitelist.removeAccount(account);
        vm.snapshotGasLastCall("AddressesWhitelist_removeAccount_fuzz");
        
        assertFalse(whitelist.isAllowedAccount(account));
        vm.stopPrank();
    }
    
    function testFuzz_IsAllowedAccount(address account) public {
        // All accounts should be false by default
        assertFalse(whitelist.isAllowedAccount(account));
        vm.snapshotGasLastCall("AddressesWhitelist_isAllowedAccount_fuzz");
    }
    
    // Gas Benchmark Tests
    function test_GasBenchmark_AddRemoveSequence() public {
        vm.startPrank(owner);
        
        // Benchmark adding accounts to different storage slots
        for (uint i = 0; i < 5; i++) {
            address account = address(uint160(i + 1));
            whitelist.addAccount(account);
            if (i == 0) vm.snapshotGasLastCall("AddressesWhitelist_addAccount_firstSlot");
            if (i == 4) vm.snapshotGasLastCall("AddressesWhitelist_addAccount_fifthSlot");
        }
        
        // Benchmark removing from different positions
        whitelist.removeAccount(address(1));
        vm.snapshotGasLastCall("AddressesWhitelist_removeAccount_firstSlot");
        
        whitelist.removeAccount(address(5));
        vm.snapshotGasLastCall("AddressesWhitelist_removeAccount_fifthSlot");
        
        vm.stopPrank();
    }
}