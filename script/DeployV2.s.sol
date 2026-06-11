// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {RequestsManagerV2} from "../src/RequestsManagerV2.sol";

/// @title DeployV2
/// @notice Deploys RequestsManagerV2 for a single product, reusing the existing PriceStorage
///         and SimpleToken contracts. The manager deploys paused; the script prints the full
///         post-deployment checklist (role grants, treasury approval, unpause, migration,
///         admin handoff) — that printed checklist is the single source of truth.
///
/// Usage:
///   PRODUCT=avUSD NETWORK=fuji     forge script DeployV2 --broadcast --rpc-url $RPC_URL
///   PRODUCT=avBTC NETWORK=fuji     forge script DeployV2 --broadcast --rpc-url $RPC_URL
///   PRODUCT=avETH NETWORK=sepolia  forge script DeployV2 --broadcast --rpc-url $RPC_URL
///   PRODUCT=avUSD NETWORK=avalanche forge script DeployV2 --broadcast --rpc-url $RPC_URL
///   PRODUCT=avBTC NETWORK=avalanche forge script DeployV2 --broadcast --rpc-url $RPC_URL
///   PRODUCT=avETH NETWORK=ethereum  forge script DeployV2 --broadcast --rpc-url $RPC_URL
contract DeployV2 is Script {
    uint64 constant BURN_TTL = 30 days;
    uint64 constant BURN_CANCEL_WINDOW = 2 days;
    uint64 constant MINT_TTL = 1 days; // mints are expected within minutes; this is generous headroom

    function run() public {
        string memory product = vm.envString("PRODUCT");
        string memory network = vm.envString("NETWORK");

        (address issueToken, address priceStorage, address treasury, address depositToken, address serviceWallet) =
            _getConfig(product, network);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer: %s", deployer);
        console.log("Product:  %s", product);
        console.log("Network:  %s", network);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy RequestsManagerV2
        address[] memory allowedTokens = new address[](1);
        allowedTokens[0] = depositToken;

        RequestsManagerV2 manager = new RequestsManagerV2(
            issueToken, priceStorage, treasury, allowedTokens, BURN_TTL, BURN_CANCEL_WINDOW, MINT_TTL
        );
        console.log("RequestsManagerV2 deployed: %s", address(manager));

        // Grant roles
        manager.grantRole(manager.SERVICE_ROLE(), serviceWallet);
        console.log("SERVICE_ROLE granted to: %s", serviceWallet);

        manager.grantRole(manager.PAUSER_ROLE(), serviceWallet);
        console.log("PAUSER_ROLE granted to: %s", serviceWallet);

        vm.stopBroadcast();

        console.log("");
        console.log("=== POST-DEPLOYMENT STEPS (multisig required for 1 and 7) ===");
        console.log("");
        console.log("NOTE: RequestsManagerV2 deploys PAUSED. Unpause (step 3) ONLY after steps 1-2,");
        console.log("      so no request is escrowed before it can be completed.");
        console.log("");
        console.log("1. [MULTISIG] Grant SERVICE_ROLE on SimpleToken to RequestsManagerV2:");
        console.log("   Target:   %s", issueToken);
        console.log("   Function: grantRole(bytes32,address)");
        console.log("   Args:     role=%s  account=%s", vm.toString(manager.SERVICE_ROLE()), address(manager));
        console.log("");
        console.log("2. [TREASURY] Approve RequestsManagerV2 to spend the withdrawal token");
        console.log("   (completeBurn pulls from the treasury via this standing allowance):");
        console.log("   Target:   %s", depositToken);
        console.log("   Function: approve(address,uint256)");
        console.log("   Args:     spender=%s  amount=<standing allowance>", address(manager));
        console.log("");
        console.log("3. [ADMIN] Unpause RequestsManagerV2: manager.unpause()");
        console.log("4. Switch frontend to use RequestsManagerV2 at %s", address(manager));
        console.log("5. Stop backend from completing new V1 requests");
        console.log("6. Wait for all pending V1 burn requests to settle");
        console.log("");
        console.log("7. [MULTISIG] Revoke SERVICE_ROLE from old V1 RequestsManager on SimpleToken:");
        console.log("   Target:   %s", issueToken);
        console.log("   Function: revokeRole(bytes32,address)");
        console.log("   Args:     role=%s  account=<V1_REQUESTS_MANAGER_ADDRESS>", vm.toString(manager.SERVICE_ROLE()));
        console.log("");
        console.log("8. [ADMIN -> MULTISIG] Hand off DEFAULT_ADMIN_ROLE from the deployer EOA to the");
        console.log("   Fordefi admin: beginDefaultAdminTransfer(fordefiAdmin), then after the 1-day");
        console.log("   delay acceptDefaultAdminTransfer() from the Fordefi admin.");
        console.log("9. (Optional) Grant PAUSER_ROLE to a dedicated security-monitoring address");
    }

    function _getConfig(string memory product, string memory network)
        internal
        pure
        returns (
            address issueToken,
            address priceStorage,
            address treasury,
            address depositToken,
            address serviceWallet
        )
    {
        bytes32 key = keccak256(abi.encodePacked(product, "-", network));

        // ── Avalanche Mainnet ──────────────────────────────────────

        if (key == keccak256("avUSD-avalanche")) {
            return (
                0xDd1cDFA52E7D8474d434cd016fd346701db6B3B9, // avUSDx SimpleToken
                0x7b4e8103bdDD5bcA79513Fda22892BEE53bA9777, // PriceStorage
                0xFCc1ab0aEf7e92eEf7AcdDbF187aCDD227aAC081, // Treasury
                0x24dE8771bC5DdB3362Db529Fc3358F2df3A0E346, // avUSD deposit token
                0xD5456b9AB991768601bEdF1159C51009D43C698D // Service wallet
            );
        }

        if (key == keccak256("avBTC-avalanche")) {
            return (
                0xa7C10C510df4B1702E1F36451dd29D7C3EDC760C, // avBTCx SimpleToken
                0x40B418cF176731089B2537D027A14c78a86F2166, // PriceStorage
                0xC8fc3Ff83479b78E21a989807FB10D0E3D840ddf, // Treasury
                0xfd2c2A98009d0cBed715882036e43d26C4289053, // avBTC deposit token
                0xD5456b9AB991768601bEdF1159C51009D43C698D // Service wallet
            );
        }

        // ── Ethereum Mainnet ───────────────────────────────────────

        if (key == keccak256("avETH-ethereum")) {
            return (
                0x2E8b7190eE84E7AC757Ddff42Ba14d4EAe24B865, // avETHx SimpleToken
                0x985b5eF57dBE19B4EE1eD43b9AdEB1A61f2f6f23, // PriceStorage
                0xdD71CDd615f677E98C604bFF5679294cC7a6089b, // Treasury
                0x9469470C9878bf3d6d0604831d9A3A366156f7EE, // avETH deposit token
                0xAF6fd55A83B0F85b4f330E2B25512C2b669786D2 // Service wallet
            );
        }

        // ── Fuji Testnet (Avalanche) ───────────────────────────────

        if (key == keccak256("avUSD-fuji")) {
            return (
                0x37f9E8DA2312673C82894E377f27dc750210116C, // avUSDx SimpleToken
                0xC02C907B8Dc68f6bCE5C2dE23c49fD8432b201b7, // PriceStorage
                0x19596e1D6cd97916514B5DBaA4730781eFE49975, // Treasury
                0xF1c0DB770e77a961efde9DD11216e3833ad5c588, // avUSD deposit token
                0x19596e1D6cd97916514B5DBaA4730781eFE49975 // Service wallet
            );
        }

        if (key == keccak256("avBTC-fuji")) {
            return (
                0x7d678d136F310589BA814566D5a91D646852fE52, // avBTCx SimpleToken
                0xbB518F65b3425d2779477f83BDd502cbc9B7Ce4D, // PriceStorage
                0x19596e1D6cd97916514B5DBaA4730781eFE49975, // Treasury
                0xBD9BEBcbAE2851381E1d248b973D8598f0408658, // avBTC deposit token
                0x19596e1D6cd97916514B5DBaA4730781eFE49975 // Service wallet
            );
        }

        // ── Sepolia Testnet (Ethereum) ─────────────────────────────

        if (key == keccak256("avETH-sepolia")) {
            return (
                0xBBc28A113b2827876E1DdB62494eC9030d7229Ae, // avETHx SimpleToken
                0x5dA81E9a6943f2C14D31CB2355849F0EaB31f0Aa, // PriceStorage
                0x19596e1D6cd97916514B5DBaA4730781eFE49975, // Treasury
                0x835229F09c2A9B99D53515ef27b975F61e867353, // avETH deposit token
                0x19596e1D6cd97916514B5DBaA4730781eFE49975 // Service wallet
            );
        }

        revert(string.concat("Unknown product/network: ", product, "-", network));
    }
}
