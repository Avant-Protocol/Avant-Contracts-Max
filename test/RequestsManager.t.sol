// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RequestsManager} from "../src/RequestsManager.sol";
import {IRequestsManager} from "../src/interfaces/IRequestsManager.sol";
import {SimpleToken} from "../src/SimpleToken.sol";
import {ISimpleToken} from "../src/interfaces/ISimpleToken.sol";
import {AddressesWhitelist} from "../src/AddressesWhitelist.sol";
import {IAddressesWhitelist} from "../src/interfaces/IAddressesWhitelist.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RequestsManagerTest is Test {
    RequestsManager public manager;
    SimpleToken public issueToken;
    AddressesWhitelist public whitelist;
    ERC20Mock public usdc;
    ERC20Mock public weth;
    ERC20Mock public nonAllowedToken;
    
    address public admin;
    address public service;
    address public treasury;
    address public alice;
    address public bob;
    
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    
    function setUp() public {
        admin = makeAddr("admin");
        service = makeAddr("service");
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        
        vm.startPrank(admin);
        
        // Deploy issue token
        SimpleToken issueTokenImpl = new SimpleToken();
        bytes memory issueTokenInitData = abi.encodeWithSelector(
            SimpleToken.initialize.selector,
            "Issue Token",
            "ISSUE"
        );
        ERC1967Proxy issueTokenProxy = new ERC1967Proxy(address(issueTokenImpl), issueTokenInitData);
        issueToken = SimpleToken(address(issueTokenProxy));
        
        // Deploy whitelist
        whitelist = new AddressesWhitelist();
        whitelist.addAccount(alice);
        whitelist.addAccount(bob);
        
        // Deploy mock tokens
        usdc = new ERC20Mock();
        usdc.mint(alice, 10000e18);
        usdc.mint(bob, 10000e18);
        usdc.mint(treasury, 100000e18);
        
        weth = new ERC20Mock();
        weth.mint(alice, 100e18);
        weth.mint(bob, 100e18);
        weth.mint(treasury, 1000e18);
        
        nonAllowedToken = new ERC20Mock();
        nonAllowedToken.mint(alice, 10000e18);
        
        // Deploy RequestsManager
        address[] memory allowedTokens = new address[](2);
        allowedTokens[0] = address(usdc);
        allowedTokens[1] = address(weth);
        
        manager = new RequestsManager(
            address(issueToken),
            treasury,
            address(whitelist),
            allowedTokens
        );
        
        // Setup roles
        manager.grantRole(SERVICE_ROLE, service);
        issueToken.grantRole(SERVICE_ROLE, address(manager));
        issueToken.grantRole(SERVICE_ROLE, service);
        
        // Setup approvals for users
        vm.stopPrank();
        
        vm.prank(alice);
        usdc.approve(address(manager), type(uint256).max);
        vm.prank(alice);
        weth.approve(address(manager), type(uint256).max);
        
        vm.prank(bob);
        usdc.approve(address(manager), type(uint256).max);
        vm.prank(bob);
        weth.approve(address(manager), type(uint256).max);
        
        vm.prank(treasury);
        usdc.approve(address(manager), type(uint256).max);
        vm.prank(treasury);
        weth.approve(address(manager), type(uint256).max);
    }
    
    // Constructor Tests
    function test_Constructor() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        RequestsManager newManager = new RequestsManager(
            address(issueToken),
            treasury,
            address(whitelist),
            tokens
        );
        vm.snapshotGasLastCall("RequestsManager_constructor");
        
        assertEq(newManager.ISSUE_TOKEN_ADDRESS(), address(issueToken));
        assertEq(newManager.treasuryAddress(), treasury);
        assertEq(address(newManager.providersWhitelist()), address(whitelist));
        assertTrue(newManager.allowedTokens(address(usdc)));
        assertFalse(newManager.isWhitelistEnabled());
    }
    
    function test_Constructor_RevertZeroIssueToken() public {
        address[] memory tokens = new address[](0);
        vm.expectRevert(IRequestsManager.ZeroAddress.selector);
        new RequestsManager(address(0), treasury, address(whitelist), tokens);
    }
    
    function test_Constructor_RevertZeroTreasury() public {
        address[] memory tokens = new address[](0);
        vm.expectRevert(IRequestsManager.ZeroAddress.selector);
        new RequestsManager(address(issueToken), address(0), address(whitelist), tokens);
    }
    
    function test_Constructor_RevertZeroWhitelist() public {
        address[] memory tokens = new address[](0);
        vm.expectRevert(IRequestsManager.ZeroAddress.selector);
        new RequestsManager(address(issueToken), treasury, address(0), tokens);
    }
    
    function test_Constructor_RevertInvalidTokenAddress() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0x123); // EOA, not contract
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.InvalidTokenAddress.selector, address(0x123)));
        new RequestsManager(address(issueToken), treasury, address(whitelist), tokens);
    }
    
    // Admin Functions Tests
    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.TreasurySet(newTreasury);
        manager.setTreasury(newTreasury);
        vm.snapshotGasLastCall("RequestsManager_setTreasury");
        
        assertEq(manager.treasuryAddress(), newTreasury);
    }
    
    function test_SetTreasury_RevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRequestsManager.ZeroAddress.selector);
        manager.setTreasury(address(0));
    }
    
    function test_SetTreasury_RevertNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        manager.setTreasury(makeAddr("newTreasury"));
    }
    
    function test_SetProvidersWhitelist() public {
        AddressesWhitelist newWhitelist = new AddressesWhitelist();
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.ProvidersWhitelistSet(address(newWhitelist));
        manager.setProvidersWhitelist(address(newWhitelist));
        vm.snapshotGasLastCall("RequestsManager_setProvidersWhitelist");
        
        assertEq(address(manager.providersWhitelist()), address(newWhitelist));
    }
    
    function test_SetProvidersWhitelist_RevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRequestsManager.ZeroAddress.selector);
        manager.setProvidersWhitelist(address(0));
    }
    
    function test_SetProvidersWhitelist_RevertNotContract() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.InvalidProvidersWhitelist.selector, address(0x123)));
        manager.setProvidersWhitelist(address(0x123));
    }
    
    function test_SetWhitelistEnabled() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.WhitelistEnabledSet(true);
        manager.setWhitelistEnabled(true);
        vm.snapshotGasLastCall("RequestsManager_setWhitelistEnabled");
        
        assertTrue(manager.isWhitelistEnabled());
        
        // Now non-whitelisted user should be rejected
        vm.prank(makeAddr("unknown"));
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.UnknownProvider.selector, makeAddr("unknown")));
        manager.requestMint(address(usdc), 100e18, 90e18);
    }
    
    function test_AddAllowedToken() public {
        ERC20Mock newToken = new ERC20Mock();
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.AllowedTokenAdded(address(newToken));
        manager.addAllowedToken(address(newToken));
        vm.snapshotGasLastCall("RequestsManager_addAllowedToken");
        
        assertTrue(manager.allowedTokens(address(newToken)));
    }
    
    function test_AddAllowedToken_RevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRequestsManager.ZeroAddress.selector);
        manager.addAllowedToken(address(0));
    }
    
    function test_AddAllowedToken_RevertNotContract() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.InvalidTokenAddress.selector, address(0x123)));
        manager.addAllowedToken(address(0x123));
    }
    
    function test_RemoveAllowedToken() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.AllowedTokenRemoved(address(usdc));
        manager.removeAllowedToken(address(usdc));
        vm.snapshotGasLastCall("RequestsManager_removeAllowedToken");
        
        assertFalse(manager.allowedTokens(address(usdc)));
    }
    
    function test_Pause() public {
        vm.prank(admin);
        manager.pause();
        vm.snapshotGasLastCall("RequestsManager_pause");
        
        vm.prank(alice);
        vm.expectRevert();
        manager.requestMint(address(usdc), 100e18, 90e18);
    }
    
    function test_Unpause() public {
        vm.prank(admin);
        manager.pause();
        
        vm.prank(admin);
        manager.unpause();
        vm.snapshotGasLastCall("RequestsManager_unpause");
        
        // Should work again
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
    }
    
    // Mint Request Tests
    function test_RequestMint_Success() public {
        uint256 balanceBefore = usdc.balanceOf(alice);
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.MintRequestCreated(0, alice, address(usdc), 100e18, 90e18);
        manager.requestMint(address(usdc), 100e18, 90e18);
        vm.snapshotGasLastCall("RequestsManager_requestMint");
        
        (uint256 id, address provider, IRequestsManager.State state, uint256 amount, address token, uint256 minExpected) = manager.mintRequests(0);
        assertEq(id, 0);
        assertEq(provider, alice);
        assertEq(uint8(state), uint8(IRequestsManager.State.CREATED));
        assertEq(amount, 100e18);
        assertEq(token, address(usdc));
        assertEq(minExpected, 90e18);
        
        assertEq(usdc.balanceOf(alice), balanceBefore - 100e18);
        assertEq(usdc.balanceOf(address(manager)), 100e18);
        assertEq(manager.mintRequestsCounter(), 1);
    }
    
    function test_RequestMint_RevertNotAllowedToken() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.TokenNotAllowed.selector, address(nonAllowedToken)));
        manager.requestMint(address(nonAllowedToken), 100e18, 90e18);
    }
    
    function test_RequestMint_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.InvalidAmount.selector, 0));
        manager.requestMint(address(usdc), 0, 0);
    }
    
    function test_RequestMint_RevertWhitelistEnabled() public {
        vm.prank(admin);
        manager.setWhitelistEnabled(true);
        
        vm.prank(makeAddr("unknown"));
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.UnknownProvider.selector, makeAddr("unknown")));
        manager.requestMint(address(usdc), 100e18, 90e18);
    }
    
    function test_RequestMintWithPermit() public {
        // This would need a permit-enabled token mock
        // For now, test that it calls requestMint internally
        vm.prank(alice);
        manager.requestMintWithPermit(address(usdc), 100e18, 90e18, block.timestamp + 1, 0, bytes32(0), bytes32(0));
        vm.snapshotGasLastCall("RequestsManager_requestMintWithPermit");
        
        assertEq(manager.mintRequestsCounter(), 1);
    }
    
    function test_CancelMint_Success() public {
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
        
        uint256 balanceBefore = usdc.balanceOf(alice);
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.MintRequestCancelled(0);
        manager.cancelMint(0);
        vm.snapshotGasLastCall("RequestsManager_cancelMint");
        
        (,, IRequestsManager.State state,,,) = manager.mintRequests(0);
        assertEq(uint8(state), uint8(IRequestsManager.State.CANCELLED));
        
        assertEq(usdc.balanceOf(alice), balanceBefore + 100e18);
        assertEq(usdc.balanceOf(address(manager)), 0);
    }
    
    function test_CancelMint_RevertNotProvider() public {
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
        
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.IllegalAddress.selector, alice, bob));
        manager.cancelMint(0);
    }
    
    function test_CancelMint_RevertNotExist() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.IllegalAddress.selector, address(0x0), alice));
        manager.cancelMint(999);
    }
    
    function test_CancelMint_RevertWrongState() public {
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
        
        vm.prank(alice);
        manager.cancelMint(0);
        
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(
            IRequestsManager.IllegalState.selector,
            IRequestsManager.State.CREATED,
            IRequestsManager.State.CANCELLED
        ));
        manager.cancelMint(0);
    }
    
    function test_CompleteMint_Success() public {
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
        
        uint256 aliceIssueBefore = issueToken.balanceOf(alice);
        uint256 treasuryUsdcBefore = usdc.balanceOf(treasury);
        
        bytes32 idempotencyKey = keccak256("COMPLETE_MINT_1");
        
        vm.prank(service);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.MintRequestCompleted(idempotencyKey, 0, 95e18);
        manager.completeMint(idempotencyKey, 0, 95e18);
        vm.snapshotGasLastCall("RequestsManager_completeMint");
        
        (,, IRequestsManager.State state,,,) = manager.mintRequests(0);
        assertEq(uint8(state), uint8(IRequestsManager.State.COMPLETED));
        
        assertEq(issueToken.balanceOf(alice), aliceIssueBefore + 95e18);
        assertEq(usdc.balanceOf(treasury), treasuryUsdcBefore + 100e18);
        assertEq(usdc.balanceOf(address(manager)), 0);
    }
    
    function test_CompleteMint_RevertInsufficientAmount() public {
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
        
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.InsufficientMintAmount.selector, 89e18, 90e18));
        manager.completeMint(keccak256("KEY"), 0, 89e18);
    }
    
    function test_CompleteMint_RevertNotServiceRole() public {
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
        
        vm.prank(alice);
        vm.expectRevert();
        manager.completeMint(keccak256("KEY"), 0, 95e18);
    }
    
    // Burn Request Tests
    function test_RequestBurn_Success() public {
        // Setup: mint issue tokens to alice
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        uint256 balanceBefore = issueToken.balanceOf(alice);
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.BurnRequestCreated(0, alice, address(usdc), 100e18, 90e18);
        manager.requestBurn(100e18, address(usdc), 90e18);
        vm.snapshotGasLastCall("RequestsManager_requestBurn");
        
        (uint256 id, address provider, IRequestsManager.State state, uint256 amount, address token, uint256 minExpected) = manager.burnRequests(0);
        assertEq(id, 0);
        assertEq(provider, alice);
        assertEq(uint8(state), uint8(IRequestsManager.State.CREATED));
        assertEq(amount, 100e18);
        assertEq(token, address(usdc));
        assertEq(minExpected, 90e18);
        
        assertEq(issueToken.balanceOf(alice), balanceBefore - 100e18);
        assertEq(issueToken.balanceOf(address(manager)), 100e18);
        assertEq(manager.burnRequestsCounter(), 1);
    }
    
    function test_RequestBurnWithPermit() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(alice);
        manager.requestBurnWithPermit(100e18, address(usdc), 90e18, block.timestamp + 1, 0, bytes32(0), bytes32(0));
        vm.snapshotGasLastCall("RequestsManager_requestBurnWithPermit");
        
        assertEq(manager.burnRequestsCounter(), 1);
    }
    
    function test_CancelBurn_Success() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(alice);
        manager.requestBurn(100e18, address(usdc), 90e18);
        
        uint256 balanceBefore = issueToken.balanceOf(alice);
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.BurnRequestCancelled(0);
        manager.cancelBurn(0);
        vm.snapshotGasLastCall("RequestsManager_cancelBurn");
        
        (,, IRequestsManager.State state,,,) = manager.burnRequests(0);
        assertEq(uint8(state), uint8(IRequestsManager.State.CANCELLED));
        
        assertEq(issueToken.balanceOf(alice), balanceBefore + 100e18);
        assertEq(issueToken.balanceOf(address(manager)), 0);
    }
    
    function test_CancelBurn_RevertNotExist() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.IllegalAddress.selector, address(0x0), alice));
        manager.cancelBurn(999);
    }
    
    function test_CompleteBurn_Success() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(alice);
        manager.requestBurn(100e18, address(usdc), 90e18);
        
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 treasuryUsdcBefore = usdc.balanceOf(treasury);
        uint256 issueSupplyBefore = issueToken.totalSupply();
        
        bytes32 idempotencyKey = keccak256("COMPLETE_BURN_1");
        
        vm.prank(service);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.BurnRequestCompleted(0, 100e18, 95e18);
        manager.completeBurn(idempotencyKey, 0, 95e18);
        vm.snapshotGasLastCall("RequestsManager_completeBurn");
        
        (,, IRequestsManager.State state,,,) = manager.burnRequests(0);
        assertEq(uint8(state), uint8(IRequestsManager.State.COMPLETED));
        
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + 95e18);
        assertEq(usdc.balanceOf(treasury), treasuryUsdcBefore - 95e18);
        assertEq(issueToken.totalSupply(), issueSupplyBefore - 100e18);
    }
    
    function test_CompleteBurn_RevertInsufficientAmount() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(alice);
        manager.requestBurn(100e18, address(usdc), 90e18);
        
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.InsufficientWithdrawalAmount.selector, 89e18, 90e18));
        manager.completeBurn(keccak256("KEY"), 0, 89e18);
    }
    
    // Emergency Withdraw Test
    function test_EmergencyWithdraw() public {
        // Setup: get some tokens stuck in contract
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
        
        uint256 adminBalanceBefore = usdc.balanceOf(admin);
        
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManager.EmergencyWithdrawn(address(usdc), 100e18);
        manager.emergencyWithdraw(usdc);
        vm.snapshotGasLastCall("RequestsManager_emergencyWithdraw");
        
        assertEq(usdc.balanceOf(admin), adminBalanceBefore + 100e18);
        assertEq(usdc.balanceOf(address(manager)), 0);
    }
    
    function test_EmergencyWithdraw_RevertNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        manager.emergencyWithdraw(usdc);
    }

    function test_SetProvidersWhitelist_RevertNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        manager.setProvidersWhitelist(address(whitelist));
    }

    function test_SetWhitelistEnabled_RevertNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        manager.setWhitelistEnabled(true);
    }

    function test_AddAllowedToken_RevertNotAdmin() public {
        ERC20Mock newToken = new ERC20Mock();
        vm.prank(alice);
        vm.expectRevert();
        manager.addAllowedToken(address(newToken));
    }

    function test_RemoveAllowedToken_RevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRequestsManager.ZeroAddress.selector);
        manager.removeAllowedToken(address(0));
    }

    function test_RemoveAllowedToken_RevertNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        manager.removeAllowedToken(address(usdc));
    }

    function test_Pause_RevertNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        manager.pause();
    }

    function test_Unpause_RevertNotAdmin() public {
        vm.prank(admin);
        manager.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        manager.unpause();
    }

    function test_RequestMint_RevertPaused() public {
        vm.prank(admin);
        manager.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        manager.requestMint(address(usdc), 100e18, 90e18);
    }

    function test_RequestBurn_RevertPaused() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(admin);
        manager.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        manager.requestBurn(100e18, address(usdc), 90e18);
    }

    function test_RequestBurn_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.InvalidAmount.selector, 0));
        manager.requestBurn(0, address(usdc), 0);
    }

    function test_RequestBurn_RevertNotAllowedToken() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.TokenNotAllowed.selector, address(nonAllowedToken)));
        manager.requestBurn(100e18, address(nonAllowedToken), 90e18);
    }

    function test_RequestBurn_RevertWhitelistEnabled() public {
        vm.prank(admin);
        manager.setWhitelistEnabled(true);
        
        vm.prank(service);
        issueToken.mint(makeAddr("unknown"), 1000e18);
        vm.prank(makeAddr("unknown"));
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(makeAddr("unknown"));
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.UnknownProvider.selector, makeAddr("unknown")));
        manager.requestBurn(100e18, address(usdc), 90e18);
    }

    function test_CompleteMint_RevertNotExist() public {
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.MintRequestNotExist.selector, 999));
        manager.completeMint(keccak256("KEY"), 999, 100e18);
    }

    function test_CompleteMint_RevertWrongState() public {
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
        
        vm.prank(alice);
        manager.cancelMint(0);
        
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(
            IRequestsManager.IllegalState.selector,
            IRequestsManager.State.CREATED,
            IRequestsManager.State.CANCELLED
        ));
        manager.completeMint(keccak256("KEY"), 0, 95e18);
    }

    function test_CompleteBurn_RevertNotExist() public {
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.BurnRequestNotExist.selector, 999));
        manager.completeBurn(keccak256("KEY"), 999, 100e18);
    }

    function test_CompleteBurn_RevertWrongState() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(alice);
        manager.requestBurn(100e18, address(usdc), 90e18);
        
        vm.prank(alice);
        manager.cancelBurn(0);
        
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(
            IRequestsManager.IllegalState.selector,
            IRequestsManager.State.CREATED,
            IRequestsManager.State.CANCELLED
        ));
        manager.completeBurn(keccak256("KEY"), 0, 95e18);
    }

    function test_CompleteBurn_RevertNotServiceRole() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(alice);
        manager.requestBurn(100e18, address(usdc), 90e18);
        
        vm.prank(alice);
        vm.expectRevert();
        manager.completeBurn(keccak256("KEY"), 0, 95e18);
    }

    function test_CancelBurn_RevertNotProvider() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(alice);
        manager.requestBurn(100e18, address(usdc), 90e18);
        
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManager.IllegalAddress.selector, alice, bob));
        manager.cancelBurn(0);
    }

    function test_CancelBurn_RevertWrongState() public {
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        vm.prank(alice);
        manager.requestBurn(100e18, address(usdc), 90e18);
        
        vm.prank(alice);
        manager.cancelBurn(0);
        
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(
            IRequestsManager.IllegalState.selector,
            IRequestsManager.State.CREATED,
            IRequestsManager.State.CANCELLED
        ));
        manager.cancelBurn(0);
    }    
    
    // Integration Tests
    function test_FullMintLifecycle() public {
        // Request mint
        vm.prank(alice);
        manager.requestMint(address(usdc), 100e18, 90e18);
        
        // Complete mint
        vm.prank(service);
        manager.completeMint(keccak256("MINT1"), 0, 95e18);
        
        assertEq(issueToken.balanceOf(alice), 95e18);
        assertEq(usdc.balanceOf(treasury), 100100e18); // Initial 100000 + 100
    }
    
    function test_FullBurnLifecycle() public {
        // Setup: mint tokens
        vm.prank(service);
        issueToken.mint(alice, 1000e18);
        vm.prank(alice);
        issueToken.approve(address(manager), type(uint256).max);
        
        // Request burn
        vm.prank(alice);
        manager.requestBurn(100e18, address(usdc), 90e18);
        
        // Complete burn
        vm.prank(service);
        manager.completeBurn(keccak256("BURN1"), 0, 95e18);
        
        assertEq(issueToken.balanceOf(alice), 900e18);
        assertEq(usdc.balanceOf(alice), 10095e18); // Initial 10000 + 95
    }
    
    // Fuzz Tests
    function testFuzz_RequestMint(uint256 amount, uint256 minAmount) public {
        amount = bound(amount, 1, 10000e18);
        minAmount = bound(minAmount, 0, amount);
        
        vm.prank(alice);
        manager.requestMint(address(usdc), amount, minAmount);
        vm.snapshotGasLastCall("RequestsManager_requestMint_fuzz");
        
        (,, IRequestsManager.State state, uint256 reqAmount,, uint256 minExpected) = manager.mintRequests(0);
        assertEq(uint8(state), uint8(IRequestsManager.State.CREATED));
        assertEq(reqAmount, amount);
        assertEq(minExpected, minAmount);
    }
}