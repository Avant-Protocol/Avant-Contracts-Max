// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IPriceStorage} from "../src/interfaces/IPriceStorage.sol";
import {RequestsManagerV2} from "../src/RequestsManagerV2.sol";

/// @title DeployAvETHPlusV2
/// @notice Re-platforms avETH+ (Ethereum) onto the standard MAX stack:
///           1. a NEW PriceStorage byte-identical to avUSDx / avBTCx / avETHx / avkBTCx
///              (legacy uint256 ABI), replacing the one-off uint128-packed instance that
///              avETH+ was deployed with in April 2026;
///           2. RequestsManagerV2, replacing the V1 RequestsManager, wired to that new
///              PriceStorage and to the existing avETH+ SimpleToken.
///
///         The existing SimpleToken is REUSED (not redeployed) — avETH+ has live supply.
///         V1 never reads PriceStorage (it takes amounts as parameters), so swapping the
///         price oracle cannot disturb the running V1 while the cutover is prepared.
///
///         Every deployed byte comes from the vendored artifacts in script/artifacts/
///         (vm.getCode), never from this script's own compilation:
///           - PriceStorageLegacy / ERC1967ProxyLegacy: built from commit 1e2f0ad
///             (solc 0.8.28, runs=200, evm_version=cancun). Runtime code verified equal
///             on-chain to the live avETHx PriceStorage impl (0x511C025…EE99) and proxy.
///             This is the whole point of the exercise: the new storage keeps the uint256
///             setPrice ABI shared by every other product.
///           - RequestsManagerV2Pinned: the default-profile HEAD build (solc 0.8.28,
///             runs=1000, evm_version=shanghai) — the same bytecode as the live avBTCx and
///             avETHx V2 managers, modulo immutables.
///         Runtime code is asserted against pinned hashes/lengths after each CREATE.
///
///         The manager deploys paused. Post-deploy, the deployer EOA's only action is
///         beginDefaultAdminTransfer on the two new contracts; everything else (token role
///         grant, treasury approval, unpause, V1 teardown) is a Fordefi/multisig action.
///         The printed checklist is the single source of truth.
///
/// Usage (the artifact-deploy profile lifts the simulator's EVM to cancun so it accepts the
/// cancun-built legacy artifacts; deployed bytes are unaffected — all of them come from
/// script/artifacts/*.json):
///   FOUNDRY_PROFILE=artifact-deploy PRODUCT=avETHPLUS NETWORK=ethereum \
///     forge script DeployAvETHPlusV2 --rpc-url $ETH_RPC_URL
contract DeployAvETHPlusV2 is Script {
    uint64 constant BURN_TTL = 30 days;
    uint64 constant BURN_CANCEL_WINDOW = 30 days;
    uint64 constant MINT_TTL = 1 days; // mints are expected within minutes; this is generous headroom

    // Same bounds as every live PriceStorage (and as the avETH+ storage being replaced):
    // +5% / -33% per update. Legacy ABI => uint256.
    uint256 constant PRICE_UPPER_BOUND_PERCENTAGE = 0.05 ether;
    uint256 constant PRICE_LOWER_BOUND_PERCENTAGE = 0.33 ether;

    // Runtime-code fingerprints of the vendored artifacts (keccak256, or length where
    // immutables make the hash deployment-specific).
    bytes32 constant PS_IMPL_CODEHASH = 0x48743f9bd1570dc3c5529a6809a462e8549ab1e9133affd31a249fef84f23069;
    bytes32 constant PROXY_CODEHASH = 0x1033b0546e6c3867f953449d682939d0ca464dbcd3763fca8e34a26b77266105;
    uint256 constant MANAGER_CODE_LENGTH = 13213;

    bytes32 constant SERVICE_ROLE = keccak256("SERVICE_ROLE");

    struct Config {
        uint256 chainId;
        address issueToken; // existing avETH+ SimpleToken proxy — REUSED
        address depositToken;
        address treasury;
        address serviceWallet; // mint/redeem bot (also granted PAUSER_ROLE on the manager)
        address priceServiceWallet; // price-update bot (SERVICE_ROLE on PriceStorage)
        address fordefiAdmin; // final DEFAULT_ADMIN_ROLE holder (handoff via checklist)
        address v1Manager; // RequestsManager V1 being retired
        address oldPriceStorage; // the uint128-ABI instance being replaced
    }

    function run() public {
        Config memory cfg = _getConfig(vm.envString("PRODUCT"), vm.envString("NETWORK"));

        if (block.chainid != cfg.chainId) revert("wrong chain for NETWORK");
        require(cfg.issueToken.code.length > 0, "issue token has no code");
        require(cfg.depositToken.code.length > 0, "deposit token has no code");

        // Carry-over reference: the price the new storage must be seeded with.
        (uint128 oldPrice, uint128 oldTimestamp) = IPriceStorage(cfg.oldPriceStorage).lastPrice();
        require(oldPrice != 0, "old PriceStorage has no price");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:      %s", deployer);
        console.log("Issue token:   %s (existing avETH+ SimpleToken)", cfg.issueToken);
        console.log("Old PriceStorage (uint128 ABI): %s", cfg.oldPriceStorage);
        console.log("  lastPrice: %s  timestamp: %s", uint256(oldPrice), uint256(oldTimestamp));

        vm.startBroadcast(deployerPrivateKey);

        // 1. New PriceStorage from the vendored audited artifact (uint256 ABI).
        address psImpl = _create(vm.getCode("script/artifacts/PriceStorageLegacy.json"));
        require(psImpl.codehash == PS_IMPL_CODEHASH, "PriceStorage impl code mismatch");
        address psProxy = _deployProxy(
            psImpl,
            abi.encodeWithSignature(
                "initialize(uint256,uint256)", PRICE_UPPER_BOUND_PERCENTAGE, PRICE_LOWER_BOUND_PERCENTAGE
            )
        );
        console.log("NEW PriceStorage impl:  %s", psImpl);
        console.log("NEW PriceStorage proxy: %s", psProxy);

        IAccessControl(psProxy).grantRole(SERVICE_ROLE, cfg.priceServiceWallet);
        console.log("PriceStorage SERVICE_ROLE granted to: %s", cfg.priceServiceWallet);

        // 2. RequestsManagerV2 (pinned HEAD build; deploys paused), pointing at the NEW storage.
        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = cfg.depositToken;
        RequestsManagerV2 manager = RequestsManagerV2(
            _create(
                abi.encodePacked(
                    vm.getCode("script/artifacts/RequestsManagerV2Pinned.json"),
                    abi.encode(
                        cfg.issueToken, psProxy, cfg.treasury, allowedTokens, BURN_TTL, BURN_CANCEL_WINDOW, MINT_TTL
                    )
                )
            )
        );
        require(address(manager).code.length == MANAGER_CODE_LENGTH, "manager code length mismatch");
        require(manager.ISSUE_TOKEN_ADDRESS() == cfg.issueToken, "manager issue token mismatch");
        require(address(manager.PRICE_STORAGE()) == psProxy, "manager price storage mismatch");
        require(manager.paused(), "manager should deploy paused");
        console.log("RequestsManagerV2:      %s", address(manager));

        // 3. Roles the deployer can grant (it is DEFAULT_ADMIN on both new contracts).
        manager.grantRole(SERVICE_ROLE, cfg.serviceWallet);
        manager.grantRole(manager.PAUSER_ROLE(), cfg.serviceWallet);
        console.log("Manager SERVICE_ROLE + PAUSER_ROLE granted to: %s", cfg.serviceWallet);

        vm.stopBroadcast();

        console.log("");
        console.log("=== POST-DEPLOYMENT STEPS ===");
        console.log("");
        console.log("NOTE: RequestsManagerV2 deploys PAUSED. Unpause LAST, and only after the token");
        console.log("      role grant, the treasury approval and the first price are all in place.");
        console.log("      The hot deployer EOA's only remaining action is step 1.");
        console.log("");
        console.log("1. [DEPLOYER -> FORDEFI] Hand off DEFAULT_ADMIN_ROLE on BOTH new contracts");
        console.log("   (PriceStorage %s, manager %s):", psProxy, address(manager));
        console.log("   beginDefaultAdminTransfer(%s)", cfg.fordefiAdmin);
        console.log("   then after the 1-day delay: acceptDefaultAdminTransfer() from Fordefi");
        console.log("");
        console.log("2. [PRICE BOT] Seed the NEW PriceStorage with the current price:");
        console.log("   Target:   %s", psProxy);
        console.log("   Function: setPrice(bytes32,uint256)   <-- uint256, NOT the uint128 ABI");
        console.log("   Value:    %s (carry over from the old storage)", uint256(oldPrice));
        console.log("   The first price on a fresh storage is unbounded; every later update is");
        console.log("   bound-checked (+5%% / -33%%). Point the price bot at this address.");
        console.log("");
        console.log("3. [FORDEFI] Grant SERVICE_ROLE on the avETH+ SimpleToken to the new manager:");
        console.log("   Target:   %s", cfg.issueToken);
        console.log("   Function: grantRole(bytes32,address)");
        console.log("   Args:     role=%s  account=%s", vm.toString(SERVICE_ROLE), address(manager));
        console.log("");
        console.log("4. [TREASURY] Approve RequestsManagerV2 to spend the withdrawal token");
        console.log("   (completeBurn pulls from the treasury via this standing allowance):");
        console.log("   Target:   %s", cfg.depositToken);
        console.log("   Function: approve(address,uint256)");
        console.log("   Args:     spender=%s  amount=<standing allowance>", address(manager));
        console.log("   From:     %s (treasury)", cfg.treasury);
        console.log("");
        console.log("5. [FORDEFI] Unpause RequestsManagerV2: manager.unpause()");
        console.log("6. Switch frontend/backend to the new manager; smoke test mint AND burn");
        console.log("7. Stop completing new V1 requests; wait for pending V1 burns to settle");
        console.log("");
        console.log("8. [FORDEFI] Retire V1: pause it and revoke its SERVICE_ROLE on the token:");
        console.log("   Target:   %s", cfg.issueToken);
        console.log("   Function: revokeRole(bytes32,address)");
        console.log("   Args:     role=%s  account=%s", vm.toString(SERVICE_ROLE), cfg.v1Manager);
        console.log("");
        console.log("9. [FORDEFI] Retire the old uint128 PriceStorage %s:", cfg.oldPriceStorage);
        console.log("   revokeRole(SERVICE_ROLE, %s) so nothing can keep writing to it.", cfg.priceServiceWallet);
        console.log("10. (Optional) Grant PAUSER_ROLE to a dedicated security-monitoring address");
    }

    /// @dev Deploys the audited ERC1967Proxy artifact in front of `implementation`.
    function _deployProxy(address implementation, bytes memory initData) internal returns (address proxy) {
        proxy = _create(
            abi.encodePacked(
                vm.getCode("script/artifacts/ERC1967ProxyLegacy.json"), abi.encode(implementation, initData)
            )
        );
        require(proxy.codehash == PROXY_CODEHASH, "proxy code mismatch");
    }

    function _create(bytes memory creationCode) internal returns (address addr) {
        assembly {
            addr := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(addr != address(0) && addr.code.length > 0, "create failed");
    }

    function _getConfig(string memory product, string memory network) internal pure returns (Config memory) {
        bytes32 key = keccak256(abi.encodePacked(product, "-", network));

        // ── Ethereum Mainnet ───────────────────────────────────────

        if (key == keccak256("avETHPLUS-ethereum")) {
            return Config({
                chainId: 1,
                issueToken: 0x570e73AF4A8635751E6C65c7B1596dC94be277F1, // avETH+ SimpleToken proxy
                depositToken: 0x9469470C9878bf3d6d0604831d9A3A366156f7EE, // avETH on Ethereum
                treasury: 0xE6d92b7505C80a2563DD7C9406D56EfcA1710462, // PLUS avETH - Mint Deposit Vault
                serviceWallet: 0xAF6fd55A83B0F85b4f330E2B25512C2b669786D2, // Avant Bot (avETH Workspace)
                priceServiceWallet: 0xAF6fd55A83B0F85b4f330E2B25512C2b669786D2, // Avant Bot (avETH Workspace)
                fordefiAdmin: 0xd4d23209aaE8630bf386b7393763a5b7865e57cb, // Fordefi admin (same as all chains)
                v1Manager: 0xf66B0d7A0C1c182e530816CdeE6Ea062B63E35e9, // avETH+ RequestsManager V1
                oldPriceStorage: 0xBE6807581294f5F6Fe67a250a3FA1A76875DD25E // uint128-ABI PriceStorage being replaced
            });
        }

        revert(string.concat("Unknown product/network: ", product, "-", network));
    }
}
