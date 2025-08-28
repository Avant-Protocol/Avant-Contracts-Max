// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PriceStorage} from "../src/PriceStorage.sol";
import {IPriceStorage} from "../src/interfaces/IPriceStorage.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PriceStorageTest is Test {
    PriceStorage public priceStorage;
    PriceStorage public implementation;
    
    address public admin;
    address public service;
    address public alice;
    
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    uint256 public constant BOUND_PERCENTAGE_DENOMINATOR = 1e18;
    
    function setUp() public {
        admin = makeAddr("admin");
        service = makeAddr("service");
        alice = makeAddr("alice");
        
        vm.startPrank(admin);
        
        // Deploy implementation
        implementation = new PriceStorage();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            PriceStorage.initialize.selector,
            0.1e18, // 10% upper bound
            0.05e18 // 5% lower bound
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        priceStorage = PriceStorage(address(proxy));
        
        // Grant service role
        priceStorage.grantRole(SERVICE_ROLE, service);
        
        vm.stopPrank();
    }
    
    // Initialization Tests
    function test_Initialize() public {
        // Deploy new implementation
        PriceStorage newImplementation = new PriceStorage();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            PriceStorage.initialize.selector,
            0.2e18,
            0.1e18
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(newImplementation), initData);
        PriceStorage newStorage = PriceStorage(address(proxy));
        vm.snapshotGasLastCall("PriceStorage_initialize");
        
        assertEq(newStorage.upperBoundPercentage(), 0.2e18);
        assertEq(newStorage.lowerBoundPercentage(), 0.1e18);
        assertTrue(newStorage.hasRole(newStorage.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    function test_Initialize_RevertAlreadyInitialized() public {
        // Try to reinitialize the already initialized proxy
        vm.expectRevert();
        priceStorage.initialize(0.2e18, 0.1e18);
    }
    
    // Constructor Tests
    function test_Constructor_DisablesInitializers() public {
        // Constructor should disable initializers
        // This is tested implicitly by the revert in test_Initialize_RevertAlreadyInitialized
        PriceStorage newStorage = new PriceStorage();
        vm.expectRevert();
        newStorage.initialize(0.2e18, 0.1e18);
    }
    
    // setPrice Tests
    function test_SetPrice_FirstPrice() public {
        bytes32 key = keccak256("TEST_KEY_1");
        uint128 price = 1000e18;
        
        vm.prank(service);
        vm.expectEmit(true, true, true, true);
        emit IPriceStorage.PriceSet(key, price, uint128(block.timestamp));
        priceStorage.setPrice(key, price);
        vm.snapshotGasLastCall("PriceStorage_setPrice_first");
        
        (uint128 storedPrice, uint128 timestamp) = priceStorage.prices(key);
        assertEq(storedPrice, price);
        assertEq(timestamp, block.timestamp);
        
        (uint128 lastPriceValue, uint128 lastPriceTimestamp) = priceStorage.lastPrice();
        assertEq(lastPriceValue, price);
        assertEq(lastPriceTimestamp, block.timestamp);
    }
    
    function test_SetPrice_WithinBounds() public {
        // Set first price
        bytes32 key1 = keccak256("KEY1");
        vm.prank(service);
        priceStorage.setPrice(key1, 1000e18);
        
        // Set second price within bounds (10% up, 5% down)
        bytes32 key2 = keccak256("KEY2");
        vm.prank(service);
        priceStorage.setPrice(key2, 1050e18); // 5% increase - within bounds
        vm.snapshotGasLastCall("PriceStorage_setPrice_withinBounds");
        
        (uint256 price,) = priceStorage.prices(key2);
        assertEq(price, 1050e18);
    }
    
    function test_SetPrice_AtUpperBound() public {
        bytes32 key1 = keccak256("KEY1");
        vm.prank(service);
        priceStorage.setPrice(key1, 1000e18);
        
        bytes32 key2 = keccak256("KEY2");
        vm.prank(service);
        priceStorage.setPrice(key2, 1100e18); // Exactly 10% increase
        
        (uint256 price,) = priceStorage.prices(key2);
        assertEq(price, 1100e18);
    }
    
    function test_SetPrice_AtLowerBound() public {
        bytes32 key1 = keccak256("KEY1");
        vm.prank(service);
        priceStorage.setPrice(key1, 1000e18);
        
        bytes32 key2 = keccak256("KEY2");
        vm.prank(service);
        priceStorage.setPrice(key2, 950e18); // Exactly 5% decrease
        
        (uint256 price,) = priceStorage.prices(key2);
        assertEq(price, 950e18);
    }
    
    function test_SetPrice_RevertInvalidKey() public {
        vm.prank(service);
        vm.expectRevert(IPriceStorage.InvalidKey.selector);
        priceStorage.setPrice(bytes32(0), 1000e18);
    }
    
    function test_SetPrice_RevertInvalidPrice() public {
        vm.prank(service);
        vm.expectRevert(IPriceStorage.InvalidPrice.selector);
        priceStorage.setPrice(keccak256("KEY"), 0);
    }
    
    function test_SetPrice_RevertPriceAlreadySet() public {
        bytes32 key = keccak256("KEY");
        
        vm.startPrank(service);
        priceStorage.setPrice(key, 1000e18);
        
        vm.expectRevert(abi.encodeWithSelector(IPriceStorage.PriceAlreadySet.selector, key));
        priceStorage.setPrice(key, 1100e18);
        vm.stopPrank();
    }
    
    function test_SetPrice_RevertAboveUpperBound() public {
        bytes32 key1 = keccak256("KEY1");
        vm.prank(service);
        priceStorage.setPrice(key1, 1000e18);
        
        bytes32 key2 = keccak256("KEY2");
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(
            IPriceStorage.InvalidPriceRange.selector,
            1101e18, // price
            950e18,  // lower bound
            1100e18  // upper bound
        ));
        priceStorage.setPrice(key2, 1101e18); // 10.1% increase - out of bounds
    }
    
    function test_SetPrice_RevertBelowLowerBound() public {
        bytes32 key1 = keccak256("KEY1");
        vm.prank(service);
        priceStorage.setPrice(key1, 1000e18);
        
        bytes32 key2 = keccak256("KEY2");
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(
            IPriceStorage.InvalidPriceRange.selector,
            949e18,  // price
            950e18,  // lower bound
            1100e18  // upper bound
        ));
        priceStorage.setPrice(key2, 949e18); // 5.1% decrease - out of bounds
    }
    
    function test_SetPrice_RevertNotServiceRole() public {
        vm.prank(alice);
        vm.expectRevert();
        priceStorage.setPrice(keccak256("KEY"), 1000e18);
    }
    
    // setUpperBoundPercentage Tests
    function test_SetUpperBoundPercentage_Success() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IPriceStorage.UpperBoundPercentageSet(0.15e18);
        priceStorage.setUpperBoundPercentage(0.15e18);
        vm.snapshotGasLastCall("PriceStorage_setUpperBoundPercentage");
        
        assertEq(priceStorage.upperBoundPercentage(), 0.15e18);
    }
    
    function test_SetUpperBoundPercentage_RevertZero() public {
        vm.prank(admin);
        vm.expectRevert(IPriceStorage.InvalidUpperBoundPercentage.selector);
        priceStorage.setUpperBoundPercentage(0);
    }
    
    function test_SetUpperBoundPercentage_RevertAbove100Percent() public {
        vm.prank(admin);
        vm.expectRevert(IPriceStorage.InvalidUpperBoundPercentage.selector);
        priceStorage.setUpperBoundPercentage(1e18 + 1);
    }
    
    function test_SetUpperBoundPercentage_RevertNotAdmin() public {
        vm.prank(service);
        vm.expectRevert();
        priceStorage.setUpperBoundPercentage(0.15e18);
    }
    
    // setLowerBoundPercentage Tests
    function test_SetLowerBoundPercentage_Success() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IPriceStorage.LowerBoundPercentageSet(0.08e18);
        priceStorage.setLowerBoundPercentage(0.08e18);
        vm.snapshotGasLastCall("PriceStorage_setLowerBoundPercentage");
        
        assertEq(priceStorage.lowerBoundPercentage(), 0.08e18);
    }
    
    function test_SetLowerBoundPercentage_RevertZero() public {
        vm.prank(admin);
        vm.expectRevert(IPriceStorage.InvalidLowerBoundPercentage.selector);
        priceStorage.setLowerBoundPercentage(0);
    }
    
    function test_SetLowerBoundPercentage_RevertAbove100Percent() public {
        vm.prank(admin);
        vm.expectRevert(IPriceStorage.InvalidLowerBoundPercentage.selector);
        priceStorage.setLowerBoundPercentage(1e18 + 1);
    }
    
    function test_SetLowerBoundPercentage_RevertNotAdmin() public {
        vm.prank(service);
        vm.expectRevert();
        priceStorage.setLowerBoundPercentage(0.08e18);
    }
    
    // Integration Tests
    function test_PriceSequence() public {
        // Test a sequence of price updates
        vm.startPrank(service);
        
        // First price - no bounds check
        priceStorage.setPrice(keccak256("PRICE1"), 1000e18);
        
        // Second price - within bounds
        priceStorage.setPrice(keccak256("PRICE2"), 1050e18);
        
        // Third price - use previous as reference
        priceStorage.setPrice(keccak256("PRICE3"), 1100e18);
        
        vm.stopPrank();
        
        (uint256 lastPrice,) = priceStorage.lastPrice();
        assertEq(lastPrice, 1100e18);
    }
    
    function test_BoundaryChanges() public {
        // Set initial price
        vm.prank(service);
        priceStorage.setPrice(keccak256("PRICE1"), 1000e18);
        
        // Change bounds
        vm.prank(admin);
        priceStorage.setUpperBoundPercentage(0.2e18); // 20%
        
        // Price that would have failed with 10% now succeeds with 20%
        vm.prank(service);
        priceStorage.setPrice(keccak256("PRICE2"), 1150e18); // 15% increase
        
        (uint256 price,) = priceStorage.prices(keccak256("PRICE2"));
        assertEq(price, 1150e18);
    }
    
    // Fuzz Tests
    function testFuzz_SetPrice_WithinBounds(uint128 firstPrice, uint256 percentChange) public {
        firstPrice = uint128(bound(firstPrice, 1, type(uint120).max));
        percentChange = bound(percentChange, 0, 0.05e18); // 0-5% change
        
        vm.prank(service);
        priceStorage.setPrice(keccak256("FIRST"), firstPrice);
        
        uint256 secondPrice = firstPrice + (firstPrice * percentChange / 1e18);
        
        vm.prank(service);
        priceStorage.setPrice(keccak256("SECOND"), uint128(secondPrice));
        vm.snapshotGasLastCall("PriceStorage_setPrice_fuzz");
        
        (uint128 price,) = priceStorage.prices(keccak256("SECOND"));
        assertEq(price, secondPrice);
    }
    
    function testFuzz_SetUpperBoundPercentage(uint128 percentage) public {
        percentage = uint128(bound(percentage, 1, 1e18));
        
        vm.prank(admin);
        priceStorage.setUpperBoundPercentage(percentage);
        
        assertEq(priceStorage.upperBoundPercentage(), percentage);
    }
    
    function testFuzz_SetLowerBoundPercentage(uint128 percentage) public {
        percentage = uint128(bound(percentage, 1, 1e18));
        
        vm.prank(admin);
        priceStorage.setLowerBoundPercentage(percentage);
        
        assertEq(priceStorage.lowerBoundPercentage(), percentage);
    }
    
    // Gas Benchmark Tests
    function test_GasBenchmark_MultiplePrices() public {
        vm.startPrank(service);
        
        for (uint128 i; i < 10; i++) {
            priceStorage.setPrice(keccak256(abi.encode("PRICE", i)), 1000e18 + i * 10e18);
            if (i == 0) vm.snapshotGasLastCall("PriceStorage_setPrice_firstInSequence");
            if (i == 9) vm.snapshotGasLastCall("PriceStorage_setPrice_tenthInSequence");
        }
        
        vm.stopPrank();
    }
}