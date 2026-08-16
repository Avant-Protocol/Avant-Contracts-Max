// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DeployAvETHPlusV2} from "../script/DeployAvETHPlusV2.s.sol";
import {IPriceStorage} from "../src/interfaces/IPriceStorage.sol";
import {IRequestsManagerV2} from "../src/interfaces/IRequestsManagerV2.sol";
import {RequestsManagerV2} from "../src/RequestsManagerV2.sol";
import {SimpleToken} from "../src/SimpleToken.sol";

/// @notice Fork test for the avETH+ re-platforming (new legacy-ABI PriceStorage + V2 manager).
///         Must run under FOUNDRY_PROFILE=artifact-deploy: the vendored PriceStorage/proxy artifacts
///         are cancun builds, so the EVM has to be lifted to cancun to execute them.
contract DeployAvETHPlusV2Test is Test {
    // avETH+ (Ethereum) — live addresses.
    address constant ISSUE_TOKEN = 0x570e73AF4A8635751E6C65c7B1596dC94be277F1;
    address constant DEPOSIT_TOKEN = 0x9469470C9878bf3d6d0604831d9A3A366156f7EE; // avETH
    address constant TREASURY = 0xE6d92b7505C80a2563DD7C9406D56EfcA1710462;
    address constant SERVICE_WALLET = 0xAF6fd55A83B0F85b4f330E2B25512C2b669786D2;
    address constant FORDEFI = 0xd4d23209aaE8630bf386b7393763a5b7865e57cb;
    address constant OLD_PRICE_STORAGE = 0xBE6807581294f5F6Fe67a250a3FA1A76875DD25E;

    // Reference deployments the new bytecode must match.
    address constant AVETHX_PS_IMPL = 0x511c025Ed8C04e363D398c21d165563adddbEe99;
    address constant AVETHX_PS_PROXY = 0x985b5eF57dBE19B4EE1eD43b9AdEB1A61f2f6f23;
    address constant AVETHX_V2_MANAGER = 0x9362B7986E162E99e5d28969214e5797682D7a39;

    bytes32 constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    DeployAvETHPlusV2 script;
    address deployer;

    address newPriceStorage;
    address newPriceStorageImpl;
    RequestsManagerV2 manager;

    function setUp() public {
        string memory rpcUrl;
        try vm.envString("ETH_RPC_URL") returns (string memory url) {
            rpcUrl = url;
        } catch {
            revert("ETH_RPC_URL is not set - add it to .env or export it (e.g. an Alchemy mainnet RPC URL)");
        }
        vm.createSelectFork(rpcUrl);

        uint256 pk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        deployer = vm.addr(pk);
        vm.deal(deployer, 10 ether);
        vm.setEnv("PRIVATE_KEY", vm.toString(bytes32(pk)));
        vm.setEnv("PRODUCT", "avETHPLUS");
        vm.setEnv("NETWORK", "ethereum");

        script = new DeployAvETHPlusV2();
        vm.recordLogs();
        script.run();

        (newPriceStorageImpl, newPriceStorage, manager) = _parseDeployment();
    }

    /// @dev Recovers the three deployed addresses from the recorded logs: the proxy emits
    ///      Upgraded(impl) and RoleGranted, the manager emits Paused/RoleGranted.
    function _parseDeployment() internal returns (address impl, address proxy, RequestsManagerV2 mgr) {
        // The deployer's nonce ordering is deterministic: impl, proxy, manager.
        uint64 nonce = vm.getNonce(deployer);
        // 3 CREATEs + 3 role-granting CALLs were made; CREATE addresses are nonce-derived.
        impl = vm.computeCreateAddress(deployer, nonce - 6);
        proxy = vm.computeCreateAddress(deployer, nonce - 5);
        mgr = RequestsManagerV2(vm.computeCreateAddress(deployer, nonce - 3));
    }

    // ── The point of the exercise: bytecode parity with the other products ──

    function test_NewPriceStorage_IsByteIdenticalToOtherProducts() public view {
        assertEq(newPriceStorageImpl.codehash, AVETHX_PS_IMPL.codehash, "impl bytecode differs from avETHx");
        assertEq(newPriceStorage.codehash, AVETHX_PS_PROXY.codehash, "proxy bytecode differs from avETHx");
        assertTrue(
            newPriceStorageImpl.codehash != OLD_PRICE_STORAGE.codehash, "must not match the old uint128 instance"
        );
    }

    function test_NewPriceStorage_ExposesLegacyUint256Abi() public {
        // The legacy uint256 ABI is present...
        vm.prank(SERVICE_WALLET);
        (bool ok,) = newPriceStorage.call(abi.encodeWithSignature("setPrice(bytes32,uint256)", bytes32("k1"), 1 ether));
        assertTrue(ok, "setPrice(bytes32,uint256) should exist");

        // ...and the uint128 variant the avETH+ instance had is gone (no fallback on the impl).
        vm.prank(SERVICE_WALLET);
        (bool ok128,) =
            newPriceStorage.call(abi.encodeWithSignature("setPrice(bytes32,uint128)", bytes32("k2"), uint128(1 ether)));
        assertFalse(ok128, "setPrice(bytes32,uint128) must not exist on the new storage");
    }

    function test_NewPriceStorage_Config() public view {
        assertEq(_readUint(newPriceStorage, "upperBoundPercentage()"), 0.05 ether);
        assertEq(_readUint(newPriceStorage, "lowerBoundPercentage()"), 0.33 ether);
        assertTrue(_hasRole(newPriceStorage, SERVICE_ROLE, SERVICE_WALLET), "price bot needs SERVICE_ROLE");
        assertTrue(_hasRole(newPriceStorage, DEFAULT_ADMIN_ROLE, deployer), "deployer holds admin until handoff");
        (uint128 price,) = IPriceStorage(newPriceStorage).lastPrice();
        assertEq(price, 0, "new storage starts unseeded");
    }

    // ── Manager wiring ──

    function test_Manager_WiringAndRoles() public view {
        assertEq(address(manager).code.length, AVETHX_V2_MANAGER.code.length, "manager code length differs");
        assertEq(manager.ISSUE_TOKEN_ADDRESS(), ISSUE_TOKEN);
        assertEq(address(manager.PRICE_STORAGE()), newPriceStorage, "must point at the NEW storage");
        assertTrue(address(manager.PRICE_STORAGE()) != OLD_PRICE_STORAGE);
        assertEq(manager.treasuryAddress(), TREASURY);
        assertTrue(manager.allowedTokens(DEPOSIT_TOKEN));
        assertEq(manager.burnRequestTTL(), 30 days);
        assertEq(manager.burnCancelWindow(), 30 days);
        assertEq(manager.mintRequestTTL(), 1 days);
        assertEq(manager.mintFee(), 0);
        assertEq(manager.burnFee(), 0);
        assertTrue(manager.paused(), "deploys paused");
        assertTrue(manager.hasRole(SERVICE_ROLE, SERVICE_WALLET));
        assertTrue(manager.hasRole(manager.PAUSER_ROLE(), SERVICE_WALLET));
        assertTrue(manager.hasRole(DEFAULT_ADMIN_ROLE, deployer), "deployer holds admin until handoff");
    }

    function test_V1IsUndisturbed() public view {
        // V1 keeps its SERVICE_ROLE on the token until the cutover step; the new stack does not
        // touch it, so avETH+ keeps running on V1 while the checklist is worked through.
        assertTrue(SimpleToken(ISSUE_TOKEN).hasRole(SERVICE_ROLE, 0xf66B0d7A0C1c182e530816CdeE6Ea062B63E35e9));
    }

    // ── End-to-end: mint and burn on the new stack after the checklist steps ──

    function test_EndToEnd_MintAndBurn() public {
        uint128 carriedPrice;
        (carriedPrice,) = IPriceStorage(OLD_PRICE_STORAGE).lastPrice();
        assertGt(carriedPrice, 0);

        // [step 2] price bot seeds the new storage over the legacy ABI
        vm.prank(SERVICE_WALLET);
        (bool ok,) = newPriceStorage.call(
            abi.encodeWithSignature("setPrice(bytes32,uint256)", keccak256("seed"), uint256(carriedPrice))
        );
        assertTrue(ok);

        // [step 3] Fordefi grants the new manager SERVICE_ROLE on the issue token
        vm.prank(FORDEFI);
        SimpleToken(ISSUE_TOKEN).grantRole(SERVICE_ROLE, address(manager));

        // [step 4] treasury approves the manager for the withdrawal token
        deal(DEPOSIT_TOKEN, TREASURY, 100 ether);
        vm.prank(TREASURY);
        IERC20(DEPOSIT_TOKEN).approve(address(manager), type(uint256).max);

        // [step 5] unpause (deployer still admin at this point in the runbook)
        vm.prank(deployer);
        manager.unpause();

        // Mint: 10 avETH in -> 10e18 * 1e18 / price out
        address user = makeAddr("user");
        deal(DEPOSIT_TOKEN, user, 10 ether);
        vm.startPrank(user);
        IERC20(DEPOSIT_TOKEN).approve(address(manager), 10 ether);
        manager.requestMint(DEPOSIT_TOKEN, 10 ether);
        vm.stopPrank();

        uint256 mintId = manager.mintRequestsCounter() - 1;
        vm.prank(SERVICE_WALLET);
        manager.completeMint(mintId);

        uint256 expectedIssued = (10 ether * 1e18) / uint256(carriedPrice);
        assertEq(SimpleToken(ISSUE_TOKEN).balanceOf(user), expectedIssued, "issued amount");
        assertEq(IERC20(DEPOSIT_TOKEN).balanceOf(TREASURY), 100 ether + 10 ether, "deposit swept to treasury");

        // Burn the whole position back out.
        vm.startPrank(user);
        IERC20(ISSUE_TOKEN).approve(address(manager), expectedIssued);
        manager.requestBurn(expectedIssued, DEPOSIT_TOKEN);
        vm.stopPrank();
        uint256 burnId = manager.burnRequestsCounter() - 1;
        vm.prank(SERVICE_WALLET);
        manager.completeBurn(burnId);

        assertEq(SimpleToken(ISSUE_TOKEN).balanceOf(user), 0, "issue tokens burned");
        assertApproxEqAbs(
            IERC20(DEPOSIT_TOKEN).balanceOf(user), 10 ether, 1e6, "round-trip returns the deposit (minus rounding)"
        );
    }

    // ── Handoff ──

    function test_AdminHandoffToFordefi() public {
        vm.startPrank(deployer);
        (bool a,) = newPriceStorage.call(abi.encodeWithSignature("beginDefaultAdminTransfer(address)", FORDEFI));
        assertTrue(a);
        manager.beginDefaultAdminTransfer(FORDEFI);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(FORDEFI);
        (bool b,) = newPriceStorage.call(abi.encodeWithSignature("acceptDefaultAdminTransfer()"));
        assertTrue(b);
        manager.acceptDefaultAdminTransfer();
        vm.stopPrank();

        assertTrue(_hasRole(newPriceStorage, DEFAULT_ADMIN_ROLE, FORDEFI));
        assertTrue(manager.hasRole(DEFAULT_ADMIN_ROLE, FORDEFI));
        assertFalse(_hasRole(newPriceStorage, DEFAULT_ADMIN_ROLE, deployer));
        assertFalse(manager.hasRole(DEFAULT_ADMIN_ROLE, deployer));
    }

    // ── helpers ──

    function _readUint(address target, string memory sig) internal view returns (uint256) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(sig));
        require(ok, "staticcall failed");
        return abi.decode(data, (uint256));
    }

    function _hasRole(address target, bytes32 role, address account) internal view returns (bool) {
        (bool ok, bytes memory data) =
            target.staticcall(abi.encodeWithSignature("hasRole(bytes32,address)", role, account));
        require(ok, "hasRole failed");
        return abi.decode(data, (bool));
    }
}
