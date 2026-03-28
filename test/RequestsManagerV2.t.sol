// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RequestsManagerV2} from "../src/RequestsManagerV2.sol";
import {IRequestsManagerV2} from "../src/interfaces/IRequestsManagerV2.sol";
import {PriceStorage} from "../src/PriceStorage.sol";
import {SimpleToken} from "../src/SimpleToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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
            address(issueTokenImpl),
            abi.encodeWithSelector(SimpleToken.initialize.selector, "avETH MAX", "avETHx")
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
            address(issueToken),
            address(priceStorage),
            treasury,
            allowedTokens,
            BURN_TTL
        );

        manager.grantRole(SERVICE_ROLE, service);
        manager.grantRole(PAUSER_ROLE, admin);
        issueToken.grantRole(SERVICE_ROLE, address(manager));

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
        assertEq(manager.mintRequestsCounter(), 10_000);
        assertEq(manager.burnRequestsCounter(), 10_000);
        assertEq(manager.mintFee(), 0);
        assertEq(manager.burnFee(), 0);
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
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.PriceNotSet.selector, 0));
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

    function test_CompleteBurn_PriceLocked_AtRequestTime() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        _setPrice(1000 + 1 days, 1.05e18);

        vm.warp(1000 + 7 days);
        vm.prank(service);
        manager.completeBurn(id);

        // Gets 100 (price=1.0), not 105 (price=1.05)
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
        vm.expectRevert(abi.encodeWithSelector(
            IRequestsManagerV2.IllegalState.selector,
            IRequestsManagerV2.State.CREATED,
            IRequestsManagerV2.State.COMPLETED
        ));
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

    function test_Pause_AllowsCompleteMint() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        _setPrice(1001, 1e18);

        vm.prank(admin);
        manager.pause();

        vm.warp(1002);
        vm.prank(service);
        manager.completeMint(id);

        assertEq(issueToken.balanceOf(alice), 100e18);
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

        // Gets 100 (locked price=1.0), not 110 (current price=1.1)
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

        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);

        uint256 expectedMint = (amount * PRECISION) / price;
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

        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);

        uint256 preFee = (amount * PRECISION) / price;
        uint256 expectedMint = (preFee * (PRECISION - fee)) / PRECISION;
        assertEq(issueToken.balanceOf(alice), expectedMint);
    }

    function testFuzz_CompleteBurn_ArithmeticSafety(uint256 amount, uint128 price) public {
        amount = bound(amount, 1, 1_000_000e18);
        price = uint128(bound(price, 0.01e18, 1000e18));

        _setPrice(1000, price);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, amount);

        uint256 expectedWithdrawal = (amount * price) / PRECISION;
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
        manager.cancelMint(10_000);
        assertEq(depositToken.balanceOf(address(manager)), 30e18);

        // Complete the other — balance goes to zero (transferred to treasury)
        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(10_001);
        assertEq(depositToken.balanceOf(address(manager)), 0);
    }

    // ──────────────────────────────────────────────────────────────
    //  F-13: Edge case tests
    // ──────────────────────────────────────────────────────────────

    function test_CompleteMint_DustAmountRoundsToZero() public {
        // 1 wei deposit at a high price — mintAmount rounds to 0
        _setPrice(1000, 1000e18); // 1 issue token = 1000 deposit tokens
        vm.warp(1000);

        depositToken.mint(alice, 1);
        uint256 id = _requestMint(alice, 1); // 1 wei

        vm.warp(1001);
        vm.prank(service);
        manager.completeMint(id);

        // 1 * 1e18 / 1000e18 = 0 — user gets nothing, protocol keeps the 1 wei
        assertEq(issueToken.balanceOf(alice), 0);
    }

    function test_CancelMint_RevertAlreadyCancelled() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestMint(alice, 100e18);

        vm.prank(alice);
        manager.cancelMint(id);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(
            IRequestsManagerV2.IllegalState.selector,
            IRequestsManagerV2.State.CREATED,
            IRequestsManagerV2.State.CANCELLED
        ));
        manager.cancelMint(id);
    }

    function test_CancelBurn_RevertAlreadyCancelled() public {
        _setPrice(1000, 1e18);
        vm.warp(1000);
        uint256 id = _requestBurn(alice, 100e18);

        vm.prank(alice);
        manager.cancelBurn(id);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(
            IRequestsManagerV2.IllegalState.selector,
            IRequestsManagerV2.State.CREATED,
            IRequestsManagerV2.State.CANCELLED
        ));
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
        vm.expectRevert(abi.encodeWithSelector(IRequestsManagerV2.PriceNotSet.selector, 0));
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
        vm.expectRevert(abi.encodeWithSelector(
            IRequestsManagerV2.IllegalState.selector,
            IRequestsManagerV2.State.CREATED,
            IRequestsManagerV2.State.COMPLETED
        ));
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
        vm.expectRevert(abi.encodeWithSelector(
            IRequestsManagerV2.IllegalState.selector,
            IRequestsManagerV2.State.CREATED,
            IRequestsManagerV2.State.COMPLETED
        ));
        manager.completeBurn(id);
    }
}
