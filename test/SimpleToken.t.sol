// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SimpleToken} from "../src/SimpleToken.sol";
import {ISimpleToken} from "../src/interfaces/ISimpleToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SimpleTokenTest is Test {
    SimpleToken public token;
    SimpleToken public implementation;
    
    address public admin;
    address public service;
    address public alice;
    address public bob;
    
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    
    function setUp() public {
        admin = makeAddr("admin");
        service = makeAddr("service");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        
        vm.startPrank(admin);
        
        // Deploy implementation
        implementation = new SimpleToken();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            SimpleToken.initialize.selector,
            "Test Token",
            "TEST"
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = SimpleToken(address(proxy));
        
        // Grant service role
        token.grantRole(SERVICE_ROLE, service);
        
        vm.stopPrank();
    }
    
    // Initialization Tests
    function test_Initialize() public {
        SimpleToken newImplementation = new SimpleToken();
        
        bytes memory initData = abi.encodeWithSelector(
            SimpleToken.initialize.selector,
            "Another Token",
            "ANOTHER"
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(newImplementation), initData);
        SimpleToken newToken = SimpleToken(address(proxy));
        vm.snapshotGasLastCall("SimpleToken_initialize");
        
        assertEq(newToken.name(), "Another Token");
        assertEq(newToken.symbol(), "ANOTHER");
        assertTrue(newToken.hasRole(newToken.DEFAULT_ADMIN_ROLE(), address(this)));
    }
    
    function test_Initialize_RevertAlreadyInitialized() public {
        vm.expectRevert();
        token.initialize("New Name", "NEW");
    }
    
    // Constructor Test
    function test_Constructor_DisablesInitializers() public {
        SimpleToken newImpl = new SimpleToken();
        vm.expectRevert();
        newImpl.initialize("Test", "TST");
    }
    
    // Non-idempotent mint Tests
    function test_Mint_NonIdempotent_Success() public {
        vm.prank(service);
        token.mint(alice, 1000e18);
        vm.snapshotGasLastCall("SimpleToken_mint_nonIdempotent");
        
        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }
    
    function test_Mint_NonIdempotent_Multiple() public {
        vm.startPrank(service);
        token.mint(alice, 1000e18);
        token.mint(alice, 500e18);
        token.mint(bob, 2000e18);
        vm.stopPrank();
        
        assertEq(token.balanceOf(alice), 1500e18);
        assertEq(token.balanceOf(bob), 2000e18);
        assertEq(token.totalSupply(), 3500e18);
    }
    
    function test_Mint_NonIdempotent_RevertNotServiceRole() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1000e18);
    }
    
    // Idempotent mint Tests
    function test_Mint_Idempotent_Success() public {
        bytes32 key = keccak256("MINT_001");
        
        vm.prank(service);
        token.mint(key, alice, 1000e18);
        vm.snapshotGasLastCall("SimpleToken_mint_idempotent_first");
        
        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }
    
    function test_Mint_Idempotent_RevertDuplicateKey() public {
        bytes32 key = keccak256("MINT_002");
        
        vm.startPrank(service);
        token.mint(key, alice, 1000e18);
        
        vm.expectRevert(abi.encodeWithSelector(
            ISimpleToken.IdempotencyKeyAlreadyExist.selector,
            key
        ));
        token.mint(key, bob, 500e18);
        vm.stopPrank();
    }
    
    function test_Mint_Idempotent_DifferentKeys() public {
        vm.startPrank(service);
        token.mint(keccak256("KEY1"), alice, 1000e18);
        token.mint(keccak256("KEY2"), alice, 500e18);
        token.mint(keccak256("KEY3"), bob, 2000e18);
        vm.snapshotGasLastCall("SimpleToken_mint_idempotent_third");
        vm.stopPrank();
        
        assertEq(token.balanceOf(alice), 1500e18);
        assertEq(token.balanceOf(bob), 2000e18);
    }
    
    function test_Mint_Idempotent_RevertNotServiceRole() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(keccak256("KEY"), alice, 1000e18);
    }
    
    // Non-idempotent burn Tests
    function test_Burn_NonIdempotent_Success() public {
        // First mint some tokens
        vm.prank(service);
        token.mint(alice, 1000e18);
        
        // Then burn
        vm.prank(service);
        token.burn(alice, 400e18);
        vm.snapshotGasLastCall("SimpleToken_burn_nonIdempotent");
        
        assertEq(token.balanceOf(alice), 600e18);
        assertEq(token.totalSupply(), 600e18);
    }
    
    function test_Burn_NonIdempotent_Multiple() public {
        vm.startPrank(service);
        token.mint(alice, 1000e18);
        token.mint(bob, 1000e18);
        
        token.burn(alice, 200e18);
        token.burn(alice, 300e18);
        token.burn(bob, 1000e18);
        vm.stopPrank();
        
        assertEq(token.balanceOf(alice), 500e18);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), 500e18);
    }
    
    function test_Burn_NonIdempotent_RevertInsufficientBalance() public {
        vm.prank(service);
        token.mint(alice, 100e18);
        
        vm.prank(service);
        vm.expectRevert();
        token.burn(alice, 101e18);
    }
    
    function test_Burn_NonIdempotent_RevertNotServiceRole() public {
        vm.prank(alice);
        vm.expectRevert();
        token.burn(alice, 100e18);
    }
    
    // Idempotent burn Tests
    function test_Burn_Idempotent_Success() public {
        // Setup: mint tokens first
        vm.prank(service);
        token.mint(alice, 1000e18);
        
        bytes32 key = keccak256("BURN_001");
        
        vm.prank(service);
        token.burn(key, alice, 400e18);
        vm.snapshotGasLastCall("SimpleToken_burn_idempotent_first");
        
        assertEq(token.balanceOf(alice), 600e18);
        assertEq(token.totalSupply(), 600e18);
    }
    
    function test_Burn_Idempotent_RevertDuplicateKey() public {
        vm.startPrank(service);
        token.mint(alice, 1000e18);
        
        bytes32 key = keccak256("BURN_002");
        token.burn(key, alice, 400e18);
        
        vm.expectRevert(abi.encodeWithSelector(
            ISimpleToken.IdempotencyKeyAlreadyExist.selector,
            key
        ));
        token.burn(key, alice, 100e18);
        vm.stopPrank();
    }
    
    function test_Burn_Idempotent_DifferentKeys() public {
        vm.startPrank(service);
        token.mint(alice, 1000e18);
        token.mint(bob, 1000e18);
        
        token.burn(keccak256("BURN1"), alice, 200e18);
        token.burn(keccak256("BURN2"), alice, 300e18);
        token.burn(keccak256("BURN3"), bob, 500e18);
        vm.snapshotGasLastCall("SimpleToken_burn_idempotent_third");
        vm.stopPrank();
        
        assertEq(token.balanceOf(alice), 500e18);
        assertEq(token.balanceOf(bob), 500e18);
        assertEq(token.totalSupply(), 1000e18);
    }
    
    function test_Burn_Idempotent_RevertNotServiceRole() public {
        vm.prank(alice);
        vm.expectRevert();
        token.burn(keccak256("KEY"), alice, 100e18);
    }
    
    // ERC20 Permit Tests
    function test_Permit_Functionality() public {
        uint256 alicePrivateKey = 0x1234;
        address aliceSigner = vm.addr(alicePrivateKey);
        
        // Mint tokens to signer
        vm.prank(service);
        token.mint(aliceSigner, 1000e18);
        
        // Create permit
        uint256 nonce = token.nonces(aliceSigner);
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                aliceSigner,
                bob,
                500e18,
                nonce,
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, hash);
        
        // Execute permit
        token.permit(aliceSigner, bob, 500e18, deadline, v, r, s);
        vm.snapshotGasLastCall("SimpleToken_permit");
        
        assertEq(token.allowance(aliceSigner, bob), 500e18);
    }
    
    // Integration Tests
    function test_MintBurnCycle() public {
        vm.startPrank(service);
        
        // Mint with idempotent
        token.mint(keccak256("MINT1"), alice, 1000e18);
        
        // Mint without idempotent
        token.mint(bob, 500e18);
        
        // Burn with idempotent
        token.burn(keccak256("BURN1"), alice, 300e18);
        
        // Burn without idempotent
        token.burn(bob, 100e18);
        
        vm.stopPrank();
        
        assertEq(token.balanceOf(alice), 700e18);
        assertEq(token.balanceOf(bob), 400e18);
        assertEq(token.totalSupply(), 1100e18);
    }
    
    // Fuzz Tests
    function testFuzz_Mint_NonIdempotent(address account, uint256 amount) public {
        vm.assume(account != address(0));
        amount = bound(amount, 0, type(uint128).max);
        
        vm.prank(service);
        token.mint(account, amount);
        vm.snapshotGasLastCall("SimpleToken_mint_nonIdempotent_fuzz");
        
        assertEq(token.balanceOf(account), amount);
    }
    
    function testFuzz_Mint_Idempotent(bytes32 key, address account, uint256 amount) public {
        vm.assume(account != address(0));
        amount = bound(amount, 0, type(uint128).max);
        
        vm.prank(service);
        token.mint(key, account, amount);
        vm.snapshotGasLastCall("SimpleToken_mint_idempotent_fuzz");
        
        assertEq(token.balanceOf(account), amount);
    }
    
    function testFuzz_Burn(address account, uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(account != address(0));
        mintAmount = bound(mintAmount, 1, type(uint128).max);
        burnAmount = bound(burnAmount, 0, mintAmount);
        
        vm.startPrank(service);
        token.mint(account, mintAmount);
        token.burn(account, burnAmount);
        vm.snapshotGasLastCall("SimpleToken_burn_fuzz");
        vm.stopPrank();
        
        assertEq(token.balanceOf(account), mintAmount - burnAmount);
    }
    
    // Gas Benchmark Tests
    function test_GasBenchmark_MintBurnSequence() public {
        vm.startPrank(service);
        
        // Benchmark different mint patterns
        token.mint(alice, 1000e18);
        vm.snapshotGasLastCall("SimpleToken_mint_first");
        
        token.mint(alice, 1000e18);
        vm.snapshotGasLastCall("SimpleToken_mint_toExisting");
        
        token.mint(keccak256("KEY1"), bob, 1000e18);
        vm.snapshotGasLastCall("SimpleToken_mint_idempotent_newAccount");
        
        // Benchmark burn patterns
        token.burn(alice, 500e18);
        vm.snapshotGasLastCall("SimpleToken_burn_partial");
        
        token.burn(alice, 1500e18);
        vm.snapshotGasLastCall("SimpleToken_burn_all");
        
        vm.stopPrank();
    }
}