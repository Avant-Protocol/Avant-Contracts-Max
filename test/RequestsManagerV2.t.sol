// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RequestsManagerV2} from "../src/RequestsManagerV2.sol";
import {IRequestsManagerV2} from "../src/interfaces/IRequestsManagerV2.sol";
import {PriceStorage} from "../src/PriceStorage.sol";
import {SimpleToken} from "../src/SimpleToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract RequestsManagerV2Test is Test {
    RequestsManagerV2 public manager;
    SimpleToken public issueToken;
    PriceStorage public priceStorage;
    ERC20Mock public depositToken;

    address public admin;
    address public service;
    address public priceService;
    address public treasury;
    address public alice;
    address public bob;

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 constant PRECISION = 1e18;

    uint64 constant BURN_TTL = 30 days;
    uint64 constant BURN_CANCEL_WINDOW = 2 days;
    uint64 constant MINT_TTL = 1 days;

    function setUp() public {
        admin = makeAddr("admin");
        service = makeAddr("service");
        priceService = makeAddr("priceService");
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(admin);

        SimpleToken issueTokenImpl = new SimpleToken();
        ERC1967Proxy issueTokenProxy = new ERC1967Proxy(
            address(issueTokenImpl), abi.encodeWithSelector(SimpleToken.initialize.selector, "avETH MAX", "avETHx")
        );
        issueToken = SimpleToken(address(issueTokenProxy));

        PriceStorage priceStorageImpl = new PriceStorage();
        ERC1967Proxy priceStorageProxy = new ERC1967Proxy(
            address(priceStorageImpl),
            abi.encodeWithSelector(PriceStorage.initialize.selector, uint128(0.05e18), uint128(0.33e18))
        );
        priceStorage = PriceStorage(address(priceStorageProxy));
        priceStorage.grantRole(SERVICE_ROLE, priceService);

        depositToken = new ERC20Mock();
        depositToken.mint(alice, 100_000e18);
        depositToken.mint(bob, 100_000e18);
        depositToken.mint(treasury, 1_000_000e18);

        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = address(depositToken);

        manager = new RequestsManagerV2(
            address(issueToken), address(priceStorage), treasury, allowedTokens, BURN_TTL, BURN_CANCEL_WINDOW, MINT_TTL
        );

        manager.grantRole(SERVICE_ROLE, service);
        manager.grantRole(PAUSER_ROLE, admin);
        issueToken.grantRole(SERVICE_ROLE, address(manager));

        // RequestsManagerV2 deploys paused; unpause now that wiring is complete.
        manager.unpause();

        vm.stopPrank();

        vm.prank(alice);
        depositToken.approve(address(manager), type(uint256).max);
        vm.prank(bob);
        depositToken.approve(address(manager), type(uint256).max);
        vm.prank(treasury);
        depositToken.approve(address(manager), type(uint256).max);
    }

    // ──────────────────────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────────────────────

    function _setPrice(uint256 timestamp, uint128 price) internal {
        vm.warp(timestamp);
        vm.prank(priceService);
        // V1 PriceStorage takes a bytes32 key — use the timestamp as a unique key
        priceStorage.setPrice(bytes32(timestamp), price);
    }

    function _requestMint(address user, uint256 amount) internal returns (uint256 id) {
        id = manager.mintRequestsCounter();
        vm.prank(user);
        manager.requestMint(address(depositToken), amount);
    }

    function _requestBurn(address user, uint256 amount) internal returns (uint256 id) {
        vm.prank(admin);
        issueToken.grantRole(SERVICE_ROLE, admin);
        vm.prank(admin);
        issueToken.mint(user, amount);

        vm.prank(user);
        issueToken.approve(address(manager), amount);

        id = manager.burnRequestsCounter();
        vm.prank(user);
        manager.requestBurn(amount, address(depositToken));
    }

    // ──────────────────────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────────────────────

    function test_Constructor() public view {
        assertEq(manager.ISSUE_TOKEN_ADDRESS(), address(issueToken));
        assertEq(address(manager.PRICE_STORAGE()), address(priceStorage));
        assertEq(manager.treasuryAddress(), treasury);
        assertTrue(manager.allowedTokens(address(depositToken)));
        assertEq(manager.burnRequestTTL(), BURN_TTL);
        assertEq(manager.burnCancelWindow(), BURN_CANCEL_WINDOW);
        assertEq(manager.mintRequestTTL(), MINT_TTL);
        assertEq(manager.mintRequestsCounter(), 100_000);
        assertEq(manager.burnRequestsCounter(), 100_000);
        assertEq(manager.mintFee(), 0);
        assertEq(manager.burnFee(), 0);
    }

    function test_Constructor_StartsPaused() public {
        // A freshly deployed manager must be paused so deposits cannot be escrowed before
        // the admin grants it SERVICE_ROLE on the issue token.
        address[] memory tokens = new address[](1);
        tokens[0] = address(depositToken);
        vm.prank(admin);
        RequestsManagerV2 fresh = new RequestsManagerV2(
            address(issueToken), address(priceStorage), treasury, tokens, BURN_TTL, BURN_CANCEL_WINDOW, MINT_TTL
        );

        assertTrue(fresh.paused());

        vm.prank(alice);
        vm.expectRevert();
        fresh.requestMint(address(depositToken), 100e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Mint flow
    // ──────────────────────────────────────────────────────────────

    function test_CompleteMint_BasicFlow() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        _setPrice(1001, 1e18);
        vm.warp(1002);
        vm.prank(service);
        manager.completeMint(id);

        assertEq(issueToken.balanceOf(alice), 100e18);
        assertEq(depositToken.balanceOf(treasury), 1_000_000e18 + 100e18);
    }

    function test_CompleteMint_WithAppreciatedPrice() public {
        _setPrice(1000, 1e18);
        _setPrice(1100, 1.05e18);

        vm.warp(1100);
        uint256 id = _requestMint(alice, 105e18);

        _setPrice(1101, 1.05e18);
        vm.warp(1102);
        vm.prank(service);
        manager.completeMint(id);

        // 105e18 * 1e18 / 1.05e18 = 100e18
        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    function test_CompleteMint_WithFee() public {
        vm.prank(admin);
        manager.setMintFee(0.01e18); // 1%

        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        _setPrice(1001, 1e18);
        vm.warp(1002);
        vm.prank(service);
        manager.completeMint(id);

        // 100 * 0.99 = 99
        assertEq(issueToken.balanceOf(alice), 99e18);
    }

    function test_CompleteMint_ZeroFeeNoOpFormula() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        _setPrice(1001, 1e18);
        vm.warp(1002);
        vm.prank(service);
        manager.completeMint(id);

        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    function test_CompleteMint_UsesOlderPrice() public {
        // Price set days before the request — still valid
        _setPrice(1000, 1e18);
        vm.warp(1000 + 7 days);
        uint256 id = _requestMint(alice, 100e18);

        vm.warp(1000 + 7 days + 1);
        vm.prank(service);
        manager.completeMint(id);

        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    function test_CompleteMint_RevertNoPriceSet() public {
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.warp(1002);
        vm.prank(service);
        vm.expectRevert(IRequestsManagerV2.PriceNotSet.selector);
        manager.completeMint(id);
    }

    function test_CompleteMint_UsesLatestPriceSetAtRequestTime() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);

        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Burn flow
    // ──────────────────────────────────────────────────────────────

    function test_CompleteBurn_BasicFlow() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        assertEq(depositToken.balanceOf(alice), 100_000e18 + 100e18);
    }

    function test_CompleteBurn_PriceRose_SettlesAtCeiling() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        // NAV rises during the settlement delay
        _setPrice(1000 + 1 days, 1.05e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        // Settles at the locked ceiling 1.0, not the higher 1.05 — no upside arbitrage
        assertEq(depositToken.balanceOf(alice), 100_000e18 + 100e18);
    }

    function test_CompleteBurn_WithFee() public {
        vm.prank(admin);
        manager.setBurnFee(0.02e18); // 2%

        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        // 100 * 0.98 = 98
        assertEq(depositToken.balanceOf(alice), 100_000e18 + 98e18);
    }

    function test_CompleteBurn_FeeLockedAtRequestTime() public {
        vm.prank(admin);
        manager.setBurnFee(0.02e18); // 2% at request time

        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        // Admin changes fee to 5% after the request — should not affect this burn
        vm.prank(admin);
        manager.setBurnFee(0.05e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        // User gets 98 (2% fee locked at request time), not 95 (current 5%)
        assertEq(depositToken.balanceOf(alice), 100_000e18 + 98e18);
    }

    function test_CompleteBurn_FeeZeroAtRequestTimeIgnoresLaterFee() public {
        // No fee at request time
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        // Admin sets 3% fee after the request
        vm.prank(admin);
        manager.setBurnFee(0.03e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        // User gets full 100 — fee was 0 at request time
        assertEq(depositToken.balanceOf(alice), 100_000e18 + 100e18);
    }

    function test_CompleteBurn_AtExactTTLBoundary() public {
        // The boundary instant is inclusive: completion succeeds at exactly createdAt + ttl.
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + BURN_TTL);
        vm.prank(service);
        manager.completeBurn(id);
        assertEq(depositToken.balanceOf(alice), 100_000e18 + 100e18);
    }

    function test_CompleteBurn_RevertExpired() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + BURN_TTL + 1);
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.BurnRequestExpired.selector, id, 1000, BURN_TTL));
        manager.completeBurn(id);
    }

    // ──────────────────────────────────────────────────────────────
    //  Cancel
    // ──────────────────────────────────────────────────────────────

    function test_CancelMint_ByProvider() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        uint256 balanceBefore = depositToken.balanceOf(alice);

        vm.prank(alice);
        manager.cancelMint(id);

        assertEq(depositToken.balanceOf(alice), balanceBefore + 100e18);
    }

    function test_CancelMint_RevertWrongProvider() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.IllegalAddress.selector, alice, bob));
        manager.cancelMint(id);
    }

    function test_AdminCancelMint() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        uint256 aliceBalanceBefore = depositToken.balanceOf(alice);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManagerV2.MintRequestAdminCancelled(id, alice, admin);
        manager.adminCancelMint(id);

        assertEq(depositToken.balanceOf(alice), aliceBalanceBefore + 100e18);
    }

    function test_AdminCancelMint_RevertNotAdmin() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.prank(service);
        vm.expectRevert();
        manager.adminCancelMint(id);
    }

    function test_AdminCancelMint_RevertAlreadyCompleted() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        _setPrice(1001, 1e18);
        vm.warp(1002);
        vm.prank(service);
        manager.completeMint(id);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRequestsManagerV2.IllegalState.selector,
                IRequestsManagerV2.State.CREATED,
                IRequestsManagerV2.State.COMPLETED
            )
        );
        manager.adminCancelMint(id);
    }

    function test_AdminCancelBurn() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        uint256 aliceBalanceBefore = issueToken.balanceOf(alice);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRequestsManagerV2.BurnRequestAdminCancelled(id, alice, admin);
        manager.adminCancelBurn(id);

        assertEq(issueToken.balanceOf(alice), aliceBalanceBefore + 100e18);
    }

    function test_CancelBurn_ByProvider() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.prank(alice);
        manager.cancelBurn(id);

        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Fee configuration
    // ──────────────────────────────────────────────────────────────

    function test_SetMintFee() public {
        vm.prank(admin);
        manager.setMintFee(0.05e18);
        assertEq(manager.mintFee(), 0.05e18);
    }

    function test_SetBurnFee() public {
        vm.prank(admin);
        manager.setBurnFee(0.03e18);
        assertEq(manager.burnFee(), 0.03e18);
    }

    function test_SetFee_RevertTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.FeeTooHigh.selector, 0.11e18));
        manager.setMintFee(0.11e18);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.FeeTooHigh.selector, 0.11e18));
        manager.setBurnFee(0.11e18);
    }

    function test_SetFee_RevertUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert();
        manager.setMintFee(0.01e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  TTL configuration
    // ──────────────────────────────────────────────────────────────

    function test_SetBurnRequestTTL() public {
        vm.prank(admin);
        manager.setBurnRequestTTL(60 days);
        assertEq(manager.burnRequestTTL(), 60 days);
    }

    // ──────────────────────────────────────────────────────────────
    //  Pause
    // ──────────────────────────────────────────────────────────────

    function test_Pause_BlocksNewRequests() public {
        vm.prank(admin);
        manager.pause();

        vm.prank(alice);
        vm.expectRevert();
        manager.requestMint(address(depositToken), 100e18);
    }

    function test_Pause_BlocksCompleteMint() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        _setPrice(1001, 1e18);

        vm.prank(admin);
        manager.pause();

        vm.warp(1002);
        vm.prank(service);
        vm.expectRevert();
        manager.completeMint(id);
    }

    function test_Pause_BlocksCompleteBurn() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.prank(admin);
        manager.pause();

        vm.warp(1000 + 7 days);
        vm.prank(service);
        vm.expectRevert();
        manager.completeBurn(id);
    }

    function test_Pause_AllowsCancelAndAdminCancel() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id1 = _requestMint(alice, 50e18);
        uint256 id2 = _requestMint(alice, 50e18);

        vm.prank(admin);
        manager.pause();

        vm.prank(alice);
        manager.cancelMint(id1);

        vm.prank(admin);
        manager.adminCancelMint(id2);
    }

    function test_Pause_AllowsCancelBurnWithinWindow() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.prank(admin);
        manager.pause();

        vm.prank(alice);
        manager.cancelBurn(id);
        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Emergency & Admin
    // ──────────────────────────────────────────────────────────────

    function test_EmergencyWithdraw() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        _requestMint(alice, 100e18);

        assertEq(depositToken.balanceOf(address(manager)), 100e18);

        vm.prank(admin);
        manager.emergencyWithdraw(depositToken);

        assertEq(depositToken.balanceOf(address(manager)), 0);
        assertEq(depositToken.balanceOf(admin), 100e18);
    }

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        vm.prank(admin);
        manager.setTreasury(newTreasury);
        assertEq(manager.treasuryAddress(), newTreasury);
    }

    function test_SetTreasury_RevertZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRequestsManagerV2.ZeroAddress.selector);
        manager.setTreasury(address(0));
    }

    // ──────────────────────────────────────────────────────────────
    //  Security: arbitrary amount attack vectors
    // ──────────────────────────────────────────────────────────────

    function test_Security_CannotMintArbitraryAmount() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        _setPrice(1001, 1e18);
        vm.warp(1002);
        vm.prank(service);
        manager.completeMint(id);

        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    function test_Security_BurnCannotDrainTreasury() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        assertEq(depositToken.balanceOf(alice), 100_000e18 + 100e18);
    }

    function test_TimeLagArbitrage_BurnPriceLockedAtRequestTime() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        _setPrice(1000 + 1 days, 1.05e18);
        _setPrice(1000 + 2 days, 1.1e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        // Settles at the locked ceiling 1.0, not 110 — a price rise cannot be arbitraged
        assertEq(depositToken.balanceOf(alice), 100_000e18 + 100e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  PriceStorage: lastPrice() combined getter
    // ──────────────────────────────────────────────────────────────

    function test_PriceStorage_LastPrice() public {
        _setPrice(1000, 1.5e18);

        (uint128 price, uint256 timestamp) = priceStorage.lastPrice();
        assertEq(price, 1.5e18);
        assertEq(timestamp, 1000);
    }

    // ──────────────────────────────────────────────────────────────
    //  F-11: Fuzz tests — arithmetic safety
    // ──────────────────────────────────────────────────────────────

    function testFuzz_CompleteMint_ArithmeticSafety(uint256 amount, uint128 price) public {
        // Bound to realistic ranges: amount > 0, price in [0.01, 1000] tokens
        amount = bound(amount, 1, 1_000_000e18);
        price = uint128(bound(price, 0.01e18, 1000e18));

        depositToken.mint(alice, amount);

        _setPrice(1000, price);
        vm.warp(1000);
        uint256 id = _requestMint(alice, amount);

        // Sub-rounding-threshold dust would revert with ZeroAmountOut; that path is
        // covered by test_CompleteMint_RevertZeroOutput.
        uint256 expectedMint = (amount * PRECISION) / price;
        vm.assume(expectedMint > 0);

        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);

        // Rounding favors protocol: user gets <= expected pre-fee amount
        assertLe(issueToken.balanceOf(alice), expectedMint);
    }

    function testFuzz_CompleteMint_WithFee(uint256 amount, uint128 price, uint64 fee) public {
        amount = bound(amount, 1, 1_000_000e18);
        price = uint128(bound(price, 0.01e18, 1000e18));
        fee = uint64(bound(fee, 1, 0.05e18)); // 0 < fee <= 5%

        depositToken.mint(alice, amount);

        vm.prank(admin);
        manager.setMintFee(fee);

        _setPrice(1000, price);
        vm.warp(1000);
        uint256 id = _requestMint(alice, amount);

        uint256 preFee = (amount * PRECISION) / price;
        uint256 expectedMint = (preFee * (PRECISION - fee)) / PRECISION;
        vm.assume(expectedMint > 0); // dust path covered by test_CompleteMint_RevertZeroOutput

        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);

        assertEq(issueToken.balanceOf(alice), expectedMint);
    }

    function testFuzz_CompleteBurn_ArithmeticSafety(uint256 amount, uint128 price) public {
        amount = bound(amount, 1, 1_000_000e18);
        price = uint128(bound(price, 0.01e18, 1000e18));

        _setPrice(1000, price);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, amount);

        uint256 expectedWithdrawal = (amount * price) / PRECISION;
        vm.assume(expectedWithdrawal > 0); // dust path covered by test_CompleteBurn_RevertZeroOutput
        depositToken.mint(treasury, expectedWithdrawal); // ensure treasury has enough

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        // Rounding favors protocol: user gets <= expected pre-fee amount
        assertLe(depositToken.balanceOf(alice) - 100_000e18, expectedWithdrawal);
    }

    function testFuzz_CompleteBurn_WithFee(uint256 amount, uint128 price, uint64 fee) public {
        amount = bound(amount, 1, 1_000_000e18);
        price = uint128(bound(price, 0.01e18, 1000e18));
        fee = uint64(bound(fee, 1, 0.05e18)); // 0 < fee <= 5%

        vm.prank(admin);
        manager.setBurnFee(fee);

        _setPrice(1000, price);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, amount);

        uint256 preFeAmount = (amount * price) / PRECISION;
        uint256 expectedWithdrawal = (preFeAmount * (PRECISION - fee)) / PRECISION;
        vm.assume(expectedWithdrawal > 0); // dust path covered by test_CompleteBurn_RevertZeroOutput
        depositToken.mint(treasury, preFeAmount); // ensure treasury has enough

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        uint256 aliceReceived = depositToken.balanceOf(alice) - 100_000e18;
        assertEq(aliceReceived, expectedWithdrawal);
    }

    // ──────────────────────────────────────────────────────────────
    //  F-12: Invariant tests — state machine properties
    // ──────────────────────────────────────────────────────────────

    function test_Invariant_CountersOnlyIncrease() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);

        uint256 mintCounter0 = manager.mintRequestsCounter();
        _requestMint(alice, 10e18);
        uint256 mintCounter1 = manager.mintRequestsCounter();
        _requestMint(alice, 10e18);
        uint256 mintCounter2 = manager.mintRequestsCounter();

        assertEq(mintCounter1, mintCounter0 + 1);
        assertEq(mintCounter2, mintCounter1 + 1);

        uint256 burnCounter0 = manager.burnRequestsCounter();
        _requestBurn(alice, 10e18);
        uint256 burnCounter1 = manager.burnRequestsCounter();

        assertEq(burnCounter1, burnCounter0 + 1);
    }

    function test_Invariant_StateTransitionsAreOneWay() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);

        // Completed request cannot be cancelled
        uint256 id1 = _requestMint(alice, 10e18);
        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id1);
        vm.prank(alice);
        vm.expectRevert();
        manager.cancelMint(id1);

        // Cancelled request cannot be completed
        vm.warp(1001);
        uint256 id2 = _requestMint(alice, 10e18);
        vm.prank(alice);
        manager.cancelMint(id2);
        vm.prank(service);
        vm.expectRevert();
        manager.completeMint(id2);

        // Cancelled request cannot be cancelled again
        vm.prank(alice);
        vm.expectRevert();
        manager.cancelMint(id2);
    }

    function test_Invariant_MintBalanceAccounting() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);

        uint256 contractBalanceBefore = depositToken.balanceOf(address(manager));
        assertEq(contractBalanceBefore, 0);

        _requestMint(alice, 50e18);
        _requestMint(bob, 30e18);
        assertEq(depositToken.balanceOf(address(manager)), 80e18);

        // Cancel one — balance decreases by that request's amount
        vm.prank(alice);
        manager.cancelMint(100_000);
        assertEq(depositToken.balanceOf(address(manager)), 30e18);

        // Complete the other — balance goes to zero (transferred to treasury)
        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(100_001);
        assertEq(depositToken.balanceOf(address(manager)), 0);
    }

    // ──────────────────────────────────────────────────────────────
    //  F-13: Edge case tests
    // ──────────────────────────────────────────────────────────────

    function test_CompleteMint_RevertZeroOutput() public {
        // 1 wei deposit at a high price would round mintAmount to 0 — completeMint must
        // revert rather than consume the deposit for nothing.
        _setPrice(1000, 1000e18); // 1 issue token = 1000 deposit tokens
        vm.warp(1000);

        depositToken.mint(alice, 1);
        uint256 id = _requestMint(alice, 1); // 1 wei

        vm.warp(1001);
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.ZeroAmountOut.selector, id));
        manager.completeMint(id);
    }

    function test_CompleteBurn_RevertZeroOutput() public {
        // A burn so small that withdrawalAmount rounds to 0 must revert rather than burn
        // the issue tokens for nothing.
        _setPrice(1000, 0.01e18); // 1 issue token = 0.01 deposit token
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 1); // 1 wei issue token -> 1*0.01e18/1e18 = 0

        vm.warp(1000 + 7 days);
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.ZeroAmountOut.selector, id));
        manager.completeBurn(id);
    }

    function test_CancelMint_RevertAlreadyCancelled() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.prank(alice);
        manager.cancelMint(id);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRequestsManagerV2.IllegalState.selector,
                IRequestsManagerV2.State.CREATED,
                IRequestsManagerV2.State.CANCELLED
            )
        );
        manager.cancelMint(id);
    }

    function test_CancelBurn_RevertAlreadyCancelled() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.prank(alice);
        manager.cancelBurn(id);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRequestsManagerV2.IllegalState.selector,
                IRequestsManagerV2.State.CREATED,
                IRequestsManagerV2.State.CANCELLED
            )
        );
        manager.cancelBurn(id);
    }

    function test_RequestBurn_RevertNoPriceSet() public {
        // Fresh deployment, no price ever set
        vm.prank(admin);
        issueToken.grantRole(SERVICE_ROLE, admin);
        vm.prank(admin);
        issueToken.mint(alice, 100e18);
        vm.prank(alice);
        issueToken.approve(address(manager), 100e18);

        vm.prank(alice);
        vm.expectRevert(IRequestsManagerV2.PriceNotSet.selector);
        manager.requestBurn(100e18, address(depositToken));
    }

    function test_EmergencyWithdraw_ZeroBalance() public {
        // Should succeed even with zero balance — no revert
        vm.prank(admin);
        manager.emergencyWithdraw(depositToken);

        assertEq(depositToken.balanceOf(admin), 0);
    }

    function test_CompleteMint_RevertAlreadyCompleted() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);

        vm.prank(service);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRequestsManagerV2.IllegalState.selector,
                IRequestsManagerV2.State.CREATED,
                IRequestsManagerV2.State.COMPLETED
            )
        );
        manager.completeMint(id);
    }

    function test_CompleteBurn_RevertAlreadyCompleted() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        vm.prank(service);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRequestsManagerV2.IllegalState.selector,
                IRequestsManagerV2.State.CREATED,
                IRequestsManagerV2.State.COMPLETED
            )
        );
        manager.completeBurn(id);
    }

    // ──────────────────────────────────────────────────────────────
    //  Burn settlement at min(locked, current) price
    // ──────────────────────────────────────────────────────────────

    function test_CompleteBurn_PriceDropped_SettlesAtLowerPrice() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        // NAV falls during the settlement delay
        _setPrice(1000 + 1 days, 0.9e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        // Settles at 0.9 (current), not 1.0 (locked) — the loss is borne by the redeemer
        assertEq(depositToken.balanceOf(alice), 100_000e18 + 90e18);
    }

    function test_CompleteBurn_PriceDropped_WithFee() public {
        vm.prank(admin);
        manager.setBurnFee(0.02e18); // 2%

        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        _setPrice(1000 + 1 days, 0.9e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        // 100 * 0.9 (min price) * 0.98 (locked fee) = 88.2
        assertEq(depositToken.balanceOf(alice), 100_000e18 + 88.2e18);
    }

    function testFuzz_CompleteBurn_SettlesAtMinPrice(uint256 amount, uint128 reqPrice, uint128 compPrice) public {
        amount = bound(amount, 1, 1_000_000e18);
        reqPrice = uint128(bound(reqPrice, 1e18, 1000e18));
        // Completion price kept within PriceStorage's per-update bounds (-33% / +5%)
        compPrice = uint128(bound(compPrice, (uint256(reqPrice) * 68) / 100, (uint256(reqPrice) * 104) / 100));

        _setPrice(1000, reqPrice);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, amount);

        _setPrice(1000 + 1 days, compPrice);

        uint128 expectedPrice = compPrice < reqPrice ? compPrice : reqPrice;
        uint256 expectedWithdrawal = (amount * expectedPrice) / PRECISION;
        vm.assume(expectedWithdrawal > 0); // dust path covered by test_CompleteBurn_RevertZeroOutput
        depositToken.mint(treasury, expectedWithdrawal); // ensure treasury has enough

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        assertEq(depositToken.balanceOf(alice) - 100_000e18, expectedWithdrawal);
    }

    // ──────────────────────────────────────────────────────────────
    //  Burn cancel window
    // ──────────────────────────────────────────────────────────────

    function test_CancelBurn_WithinWindow() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + BURN_CANCEL_WINDOW - 1);
        vm.prank(alice);
        manager.cancelBurn(id);

        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    function test_CancelBurn_AtExactWindowBoundary() public {
        // The boundary instant is inclusive: cancel succeeds at exactly createdAt + window.
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + BURN_CANCEL_WINDOW);
        vm.prank(alice);
        manager.cancelBurn(id);
        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    function test_CancelBurn_RevertAfterWindowClosed() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + BURN_CANCEL_WINDOW + 1);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IRequestsManagerV2.BurnCancelWindowClosed.selector, id, 1000, BURN_CANCEL_WINDOW)
        );
        manager.cancelBurn(id);
    }

    function test_AdminCancelBurn_AfterWindowClosed() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        // adminCancelBurn is not bound by the user cancel window
        vm.warp(1000 + BURN_CANCEL_WINDOW + 1 days);
        uint256 balanceBefore = issueToken.balanceOf(alice);
        vm.prank(admin);
        manager.adminCancelBurn(id);

        assertEq(issueToken.balanceOf(alice), balanceBefore + 100e18);
    }

    function test_SetBurnCancelWindow() public {
        vm.prank(admin);
        manager.setBurnCancelWindow(3 days);
        assertEq(manager.burnCancelWindow(), 3 days);
    }

    // ──────────────────────────────────────────────────────────────
    //  Mint TTL
    // ──────────────────────────────────────────────────────────────

    function test_CompleteMint_RevertExpired() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.warp(1000 + MINT_TTL + 1);
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.MintRequestExpired.selector, id, 1000, MINT_TTL));
        manager.completeMint(id);
    }

    function test_CompleteMint_WithinTTL() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.warp(1000 + MINT_TTL - 1);
        vm.prank(service);
        manager.completeMint(id);
        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    function test_CompleteMint_AtExactTTLBoundary() public {
        // The boundary instant is inclusive: completion succeeds at exactly createdAt + ttl.
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.warp(1000 + MINT_TTL);
        vm.prank(service);
        manager.completeMint(id);
        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    function test_CompleteMint_ExpiredIsRefundable() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);
        uint256 balBefore = depositToken.balanceOf(alice);

        // Past the TTL completion reverts, but the deposit is still refundable.
        vm.warp(1000 + MINT_TTL + 1);
        vm.prank(alice);
        manager.cancelMint(id);
        assertEq(depositToken.balanceOf(alice), balBefore + 100e18);
    }

    function test_SetMintRequestTTL() public {
        vm.prank(admin);
        manager.setMintRequestTTL(2 days);
        assertEq(manager.mintRequestTTL(), 2 days);
    }

    function test_MintRequestTTL_ZeroDisablesExpiry() public {
        vm.prank(admin);
        manager.setMintRequestTTL(0);

        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.warp(1000 + 3650 days);
        vm.prank(service);
        manager.completeMint(id);
        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    function test_SetBurnRequestTTL_ZeroDisablesExpiry() public {
        vm.prank(admin);
        manager.setBurnRequestTTL(0);

        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.warp(1000 + 3650 days);
        vm.prank(service);
        manager.completeBurn(id);
        assertEq(depositToken.balanceOf(alice), 100_000e18 + 100e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Unlocked mint fee (vs locked burn fee)
    // ──────────────────────────────────────────────────────────────

    function test_CompleteMint_UsesLiveFeeNotRequestTimeFee() public {
        vm.prank(admin);
        manager.setMintFee(0.01e18); // 1% at request time

        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        // Mint fee is NOT locked: admin raises it after the request, completion uses the new value.
        vm.prank(admin);
        manager.setMintFee(0.02e18);

        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);

        // 100 * 0.98 = 98 (live 2%), not 99 (request-time 1%)
        assertEq(issueToken.balanceOf(alice), 98e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Permit paths
    // ──────────────────────────────────────────────────────────────

    function _signPermit(uint256 pk, address token, address owner, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 permitTypehash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        uint256 nonce = IERC20Permit(token).nonces(owner);
        bytes32 structHash = keccak256(abi.encode(permitTypehash, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IERC20Permit(token).DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(pk, digest);
    }

    function test_RequestMintWithPermit() public {
        (address user, uint256 pk) = makeAddrAndKey("permitMinter");
        ERC20PermitMock permitToken = new ERC20PermitMock();
        permitToken.mint(user, 100e18);

        vm.prank(admin);
        manager.addAllowedToken(address(permitToken));
        _setPrice(1000, 1e18);
        vm.warp(1000);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(pk, address(permitToken), user, address(manager), 100e18, deadline);

        // No prior approval — the permit grants the allowance inside the call.
        uint256 id = manager.mintRequestsCounter();
        vm.prank(user);
        manager.requestMintWithPermit(address(permitToken), 100e18, deadline, v, r, s);

        assertEq(permitToken.balanceOf(address(manager)), 100e18);
        (address p,,,,) = manager.mintRequests(id);
        assertEq(p, user);
    }

    function test_RequestMintWithPermit_AlreadyApproved_EmptyCatchProceeds() public {
        (address user,) = makeAddrAndKey("permitMinter2");
        ERC20PermitMock permitToken = new ERC20PermitMock();
        permitToken.mint(user, 100e18);
        vm.prank(user);
        permitToken.approve(address(manager), 100e18);

        vm.prank(admin);
        manager.addAllowedToken(address(permitToken));
        _setPrice(1000, 1e18);
        vm.warp(1000);

        // Bogus signature + future deadline => permit() reverts, is caught, the standing allowance is used.
        vm.prank(user);
        manager.requestMintWithPermit(
            address(permitToken), 100e18, block.timestamp + 1 hours, 27, bytes32(0), bytes32(0)
        );
        assertEq(permitToken.balanceOf(address(manager)), 100e18);
    }

    function test_RequestMintWithPermit_NoPermitNoAllowance_Reverts() public {
        (address user,) = makeAddrAndKey("permitMinter3");
        ERC20PermitMock permitToken = new ERC20PermitMock();
        permitToken.mint(user, 100e18);

        vm.prank(admin);
        manager.addAllowedToken(address(permitToken));
        _setPrice(1000, 1e18);
        vm.warp(1000);

        // Bogus permit AND no allowance => safeTransferFrom inside requestMint reverts the whole call.
        vm.prank(user);
        vm.expectRevert();
        manager.requestMintWithPermit(
            address(permitToken), 100e18, block.timestamp + 1 hours, 27, bytes32(0), bytes32(0)
        );
    }

    function test_RequestBurnWithPermit() public {
        (address user, uint256 pk) = makeAddrAndKey("permitBurner");

        vm.prank(admin);
        issueToken.grantRole(SERVICE_ROLE, admin);
        vm.prank(admin);
        issueToken.mint(user, 100e18);

        _setPrice(1000, 1e18);
        vm.warp(1000);

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(pk, address(issueToken), user, address(manager), 100e18, deadline);

        uint256 id = manager.burnRequestsCounter();
        vm.prank(user);
        manager.requestBurnWithPermit(100e18, address(depositToken), deadline, v, r, s);

        assertEq(issueToken.balanceOf(address(manager)), 100e18);
        (address p,,,,,,) = manager.burnRequests(id);
        assertEq(p, user);
    }

    // ──────────────────────────────────────────────────────────────
    //  Allowlist management
    // ──────────────────────────────────────────────────────────────

    function test_AddAllowedToken_RevertNon18Decimals() public {
        SixDecimalToken six = new SixDecimalToken();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.InvalidTokenDecimals.selector, address(six), 6));
        manager.addAllowedToken(address(six));
    }

    function test_AddAllowedToken_RevertIssueToken() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.InvalidTokenAddress.selector, address(issueToken)));
        manager.addAllowedToken(address(issueToken));
    }

    function test_AddAllowedToken_RevertEOA() public {
        address eoa = makeAddr("eoaToken");
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.InvalidTokenAddress.selector, eoa));
        manager.addAllowedToken(eoa);
    }

    function test_AddAllowedToken_RevertZero() public {
        vm.prank(admin);
        vm.expectRevert(IRequestsManagerV2.ZeroAddress.selector);
        manager.addAllowedToken(address(0));
    }

    function test_AddAllowedToken_RevertNotAdmin() public {
        SixDecimalToken six = new SixDecimalToken();
        vm.prank(alice);
        vm.expectRevert();
        manager.addAllowedToken(address(six));
    }

    function test_RemoveAllowedToken_BlocksNewButHonorsPending() public {
        ERC20Mock token2 = new ERC20Mock();
        token2.mint(alice, 1000e18);
        vm.prank(alice);
        token2.approve(address(manager), type(uint256).max);
        vm.prank(admin);
        manager.addAllowedToken(address(token2));

        _setPrice(1000, 1e18);
        vm.warp(1000);

        uint256 id = manager.mintRequestsCounter();
        vm.prank(alice);
        manager.requestMint(address(token2), 100e18);

        vm.prank(admin);
        manager.removeAllowedToken(address(token2));

        // New requests with the delisted token revert...
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.TokenNotAllowed.selector, address(token2)));
        manager.requestMint(address(token2), 50e18);

        // ...but the already-pending request still completes.
        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);
        assertEq(issueToken.balanceOf(alice), 100e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Request revert paths
    // ──────────────────────────────────────────────────────────────

    function test_RequestMint_RevertNotAllowedToken() public {
        ERC20Mock other = new ERC20Mock();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.TokenNotAllowed.selector, address(other)));
        manager.requestMint(address(other), 100e18);
    }

    function test_RequestMint_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.InvalidAmount.selector, uint256(0)));
        manager.requestMint(address(depositToken), 0);
    }

    function test_CompleteMint_RevertNonExistentId() public {
        vm.prank(service);
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.MintRequestNotExist.selector, uint256(999_999)));
        manager.completeMint(999_999);
    }

    // ──────────────────────────────────────────────────────────────
    //  Pause / unpause role separation
    // ──────────────────────────────────────────────────────────────

    function test_Pause_PauserCannotUnpause() public {
        vm.prank(admin);
        manager.grantRole(PAUSER_ROLE, bob); // bob is pauser, NOT admin

        vm.prank(bob);
        manager.pause();
        assertTrue(manager.paused());

        vm.prank(bob);
        vm.expectRevert();
        manager.unpause();

        vm.prank(admin);
        manager.unpause();
        assertFalse(manager.paused());
    }

    function test_Pause_NonPauserCannotPause() public {
        vm.prank(alice);
        vm.expectRevert();
        manager.pause();
    }

    // ──────────────────────────────────────────────────────────────
    //  completeBurn treasury dependency
    // ──────────────────────────────────────────────────────────────

    function test_CompleteBurn_RevertWhenTreasuryApprovalRevoked() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.prank(treasury);
        depositToken.approve(address(manager), 0);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        vm.expectRevert();
        manager.completeBurn(id);

        // Request remains CREATED and refundable via adminCancelBurn.
        uint256 balBefore = issueToken.balanceOf(alice);
        vm.prank(admin);
        manager.adminCancelBurn(id);
        assertEq(issueToken.balanceOf(alice), balBefore + 100e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Cross-contract idempotency-key collision (defensive)
    // ──────────────────────────────────────────────────────────────

    function test_CompleteMint_RevertOnIdempotencyKeyCollision() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        // Simulate another SERVICE_ROLE holder having already consumed V2's exact key on the
        // shared SimpleToken (in production V1's keys are structurally disjoint; this forces it).
        bytes32 key = keccak256(abi.encodePacked("mint", id));
        vm.prank(admin);
        issueToken.grantRole(SERVICE_ROLE, admin);
        vm.prank(admin);
        issueToken.mint(key, bob, 1);

        vm.warp(1001);
        vm.prank(service);
        vm.expectRevert(); // IdempotencyKeyAlreadyExist bubbles from SimpleToken
        manager.completeMint(id);

        // The deposit is still refundable — the collision is a liveness issue, not a loss.
        uint256 balBefore = depositToken.balanceOf(alice);
        vm.prank(admin);
        manager.adminCancelMint(id);
        assertEq(depositToken.balanceOf(alice), balBefore + 100e18);
    }

    // ──────────────────────────────────────────────────────────────
    //  Reentrancy — a malicious allowlisted token cannot steal
    // ──────────────────────────────────────────────────────────────

    function test_Reentrancy_MaliciousTokenCannotDoubleSpend() public {
        ReentrantToken evil = new ReentrantToken();
        evil.mint(alice, 1000e18);
        vm.prank(alice);
        evil.approve(address(manager), type(uint256).max);
        vm.prank(admin);
        manager.addAllowedToken(address(evil));

        _setPrice(1000, 1e18);
        vm.warp(1000);

        uint256 id = manager.mintRequestsCounter();
        vm.prank(alice);
        manager.requestMint(address(evil), 100e18);
        assertEq(evil.balanceOf(address(manager)), 100e18);

        // During completeMint's transfer to treasury the token reenters cancelMint(id).
        evil.setAttack(manager, id);

        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);

        // Reentrant cancel rejected on caller mismatch (the token is not the provider; the
        // request is also already COMPLETED): single settlement, no double-spend.
        assertEq(issueToken.balanceOf(alice), 100e18);
        assertEq(evil.balanceOf(treasury), 100e18);
        assertEq(evil.balanceOf(address(manager)), 0);
    }
}

// ──────────────────────────────────────────────────────────────────
//  Test mocks
// ──────────────────────────────────────────────────────────────────

contract ERC20PermitMock is ERC20Permit {
    constructor() ERC20("Permit Deposit", "pDEP") ERC20Permit("Permit Deposit") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SixDecimalToken is ERC20 {
    constructor() ERC20("Six", "SIX") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @dev On every transfer (once armed) reenters cancelMint(targetId) on the manager.
contract ReentrantToken is ERC20 {
    RequestsManagerV2 public mgr;
    uint256 public targetId;

    constructor() ERC20("Reentrant", "RE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setAttack(RequestsManagerV2 _mgr, uint256 _id) external {
        mgr = _mgr;
        targetId = _id;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (address(mgr) != address(0)) {
            try mgr.cancelMint(targetId) {} catch {}
        }
    }
}
