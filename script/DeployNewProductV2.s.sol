// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {RequestsManagerV2} from "../src/RequestsManagerV2.sol";
import {SimpleToken} from "../src/SimpleToken.sol";

/// @title DeployNewProductV2
/// @notice Deploys the full stack for a brand-new product on a new chain:
///         SimpleToken (UUPS proxy), PriceStorage (UUPS proxy) and RequestsManagerV2.
///         No V1 RequestsManager / AddressesWhitelist — new products start directly on V2.
///
///         Every deployed byte comes from the vendored artifacts in script/artifacts/
///         (vm.getCode), never from this script's own compilation, so compile settings
///         at run time cannot change what lands on-chain:
///           - PriceStorageLegacy / ERC1967ProxyLegacy: built from commit 1e2f0ad
///             (solc 0.8.28, runs=200, evm_version=cancun) — byte-for-byte identical,
///             metadata hash included, to the audited implementations live on Avalanche
///             (avBTCx) and Ethereum (avETHx). The PriceStorage therefore keeps the
///             original uint256 setPrice ABI, not the later uint128 packing refactor.
///           - SimpleTokenPinned / RequestsManagerV2Pinned: the default-profile HEAD
///             build (solc 0.8.28, runs=1000, evm_version=shanghai). RequestsManagerV2
///             matches the deployed avBTCx/avETHx V2 managers modulo immutables;
///             SimpleToken additionally carries the external-audit #11 CEI fix
///             (deliberate choice for new deployments).
///         Runtime code is asserted against pinned hashes/lengths after each CREATE.
///
///         The manager deploys paused; the printed checklist (treasury approval, first
///         price, unpause, Fordefi admin handoff) is the single source of truth for
///         post-deployment steps.
///
/// Usage (the artifact-deploy profile lifts the EVM to cancun so the simulator accepts the
/// cancun-built legacy artifacts; the target chain must support cancun):
///   FOUNDRY_PROFILE=artifact-deploy PRODUCT=avkBTC NETWORK=ink \
///     forge script DeployNewProductV2 --broadcast --rpc-url $RPC_URL
contract DeployNewProductV2 is Script {
    uint64 constant BURN_TTL = 30 days;
    uint64 constant BURN_CANCEL_WINDOW = 30 days;
    uint64 constant MINT_TTL = 1 days; // mints are expected within minutes; this is generous headroom

    // Same bounds as every live PriceStorage: +5% / -33% per update.
    uint256 constant PRICE_UPPER_BOUND_PERCENTAGE = 0.05 ether;
    uint256 constant PRICE_LOWER_BOUND_PERCENTAGE = 0.33 ether;

    // Runtime-code fingerprints of the vendored artifacts (keccak256, or length where
    // immutables make the hash deployment-specific).
    bytes32 constant PS_IMPL_CODEHASH = 0x48743f9bd1570dc3c5529a6809a462e8549ab1e9133affd31a249fef84f23069;
    bytes32 constant PROXY_CODEHASH = 0x1033b0546e6c3867f953449d682939d0ca464dbcd3763fca8e34a26b77266105;
    bytes32 constant TOKEN_IMPL_CODEHASH = 0xce410520d0490d10c252e09288a8473a22b5f26c71735583977c5626e2dbe555;
    uint256 constant MANAGER_CODE_LENGTH = 13213;

    bytes32 constant SERVICE_ROLE = keccak256("SERVICE_ROLE");

    struct Config {
        string tokenName;
        string tokenSymbol;
        uint256 chainId;
        address depositToken;
        address treasury;
        address serviceWallet; // mint/redeem bot (also granted PAUSER_ROLE on the manager)
        address priceServiceWallet; // price-update bot (SERVICE_ROLE on PriceStorage)
        address fordefiAdmin; // final DEFAULT_ADMIN_ROLE holder (handoff via checklist)
    }

    function run() public {
        Config memory cfg = _getConfig(vm.envString("PRODUCT"), vm.envString("NETWORK"));

        if (block.chainid != cfg.chainId) revert("wrong chain for NETWORK");
        require(cfg.depositToken.code.length > 0, "deposit token has no code");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: %s", deployer);
        console.log("Token:    %s (%s)", cfg.tokenName, cfg.tokenSymbol);

        vm.startBroadcast(deployerPrivateKey);

        // 1. SimpleToken (pinned HEAD build) behind the audited ERC1967 proxy.
        address tokenImpl = _create(vm.getCode("script/artifacts/SimpleTokenPinned.json"));
        require(tokenImpl.codehash == TOKEN_IMPL_CODEHASH, "SimpleToken impl code mismatch");
        address tokenProxy = _deployProxy(
            tokenImpl, abi.encodeCall(SimpleToken.initialize, (cfg.tokenName, cfg.tokenSymbol))
        );
        console.log("%s SimpleToken impl:  %s", cfg.tokenSymbol, tokenImpl);
        console.log("%s SimpleToken proxy: %s", cfg.tokenSymbol, tokenProxy);

        // 2. PriceStorage from the vendored audited artifact (uint256 ABI).
        address psImpl = _create(vm.getCode("script/artifacts/PriceStorageLegacy.json"));
        require(psImpl.codehash == PS_IMPL_CODEHASH, "PriceStorage impl code mismatch");
        address psProxy = _deployProxy(
            psImpl,
            abi.encodeWithSignature(
                "initialize(uint256,uint256)", PRICE_UPPER_BOUND_PERCENTAGE, PRICE_LOWER_BOUND_PERCENTAGE
            )
        );
        console.log("PriceStorage impl:  %s", psImpl);
        console.log("PriceStorage proxy: %s", psProxy);

        IAccessControl(psProxy).grantRole(SERVICE_ROLE, cfg.priceServiceWallet);
        console.log("PriceStorage SERVICE_ROLE granted to: %s", cfg.priceServiceWallet);

        // 3. RequestsManagerV2 (pinned HEAD build; deploys paused).
        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = cfg.depositToken;
        RequestsManagerV2 manager = RequestsManagerV2(
            _create(
                abi.encodePacked(
                    vm.getCode("script/artifacts/RequestsManagerV2Pinned.json"),
                    abi.encode(
                        tokenProxy,
                        psProxy,
                        cfg.treasury,
                        allowedTokens,
                        BURN_TTL,
                        BURN_CANCEL_WINDOW,
                        MINT_TTL
                    )
                )
            )
        );
        require(address(manager).code.length == MANAGER_CODE_LENGTH, "manager code length mismatch");
        console.log("RequestsManagerV2:  %s", address(manager));

        // 4. Roles (deployer holds DEFAULT_ADMIN_ROLE on all three until the handoff).
        SimpleToken(tokenProxy).grantRole(SERVICE_ROLE, address(manager));
        manager.grantRole(SERVICE_ROLE, cfg.serviceWallet);
        manager.grantRole(manager.PAUSER_ROLE(), cfg.serviceWallet);
        console.log("Token SERVICE_ROLE granted to manager");
        console.log("Manager SERVICE_ROLE + PAUSER_ROLE granted to: %s", cfg.serviceWallet);

        vm.stopBroadcast();

        console.log("");
        console.log("=== POST-DEPLOYMENT STEPS ===");
        console.log("");
        console.log("NOTE: RequestsManagerV2 deploys PAUSED. Per the agreed rollout order, the admin");
        console.log("      handoff happens FIRST and Fordefi performs the unpause -- the hot deployer");
        console.log("      EOA's only post-deploy action is beginDefaultAdminTransfer.");
        console.log("");
        console.log("1. [DEPLOYER -> FORDEFI] Hand off DEFAULT_ADMIN_ROLE on ALL THREE contracts");
        console.log("   (token, PriceStorage, manager) to the Fordefi admin:");
        console.log("   beginDefaultAdminTransfer(%s)", cfg.fordefiAdmin);
        console.log("   then after the 1-day delay: acceptDefaultAdminTransfer() from Fordefi");
        console.log("");
        console.log("2. [TREASURY] Approve RequestsManagerV2 to spend the withdrawal token");
        console.log("   (completeBurn pulls from the treasury via this standing allowance):");
        console.log("   Target:   %s", cfg.depositToken);
        console.log("   Function: approve(address,uint256)");
        console.log("   Args:     spender=%s  amount=<standing allowance>", address(manager));
        console.log("");
        console.log("3. [PRICE BOT] Set the initial price (completeMint reverts while lastPrice is 0):");
        console.log("   Target:   %s", psProxy);
        console.log("   Function: setPrice(bytes32,uint256)   <-- legacy uint256 ABI");
        console.log("");
        console.log("4. [FORDEFI] Unpause RequestsManagerV2: manager.unpause()");
        console.log("5. Configure frontend/backend with the addresses above; smoke test mint AND burn");
        console.log("6. (Optional) Grant PAUSER_ROLE to a dedicated security-monitoring address");
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

        // ── Ink Mainnet ────────────────────────────────────────────

        if (key == keccak256("avkBTC-ink")) {
            return Config({
                tokenName: "avkBTC MAX",
                tokenSymbol: "avkBTCx",
                chainId: 57073,
                depositToken: 0x8c4774fC52477fE4bDB46a5189bFeccA64BAD5f2, // avkBTC on Ink
                treasury: 0xEbB8261a0019a8bd9786c305356Af12c536ceAF8, // MAX avkBTC - Mint Deposit Vault
                serviceWallet: 0x18cd66C419B89E3204E9C53FBd167244485975B5, // Avant Bot (Ink)
                priceServiceWallet: 0x18cd66C419B89E3204E9C53FBd167244485975B5, // Avant Bot (Ink)
                fordefiAdmin: 0xd4d23209aaE8630bf386b7393763a5b7865e57cb // Fordefi admin (same as all chains)
            });
        }

        revert(string.concat("Unknown product/network: ", product, "-", network));
    }
}
