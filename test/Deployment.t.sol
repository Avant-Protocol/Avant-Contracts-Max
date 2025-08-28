// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {DeploymentScript} from "../script/Deployment.s.sol";
import {SimpleToken} from "../src/SimpleToken.sol";
import {PriceStorage} from "../src/PriceStorage.sol";
import {RequestsManager} from "../src/RequestsManager.sol";
import {AddressesWhitelist} from "../src/AddressesWhitelist.sol";

contract DeploymentTest is Test {
    DeploymentScript public deploymentScript;
    
    // Expected configuration values from the script
    string constant TOKEN_NAME = "avETH MAX";
    string constant TOKEN_SYMBOL = "avETHx";
    uint256 constant PRICE_UPDATE_UPPER_BOUND_PERCENTAGE = 0.05 ether;
    uint256 constant PRICE_UPDATE_LOWER_BOUND_PERCENTAGE = 0.33 ether;
    address constant INPUT_TOKEN = 0x9469470C9878bf3d6d0604831d9A3A366156f7EE;
    address constant MINT_DEPOSIT_VAULT = 0xdD71CDd615f677E98C604bFF5679294cC7a6089b;
    address constant MINT_REDEEM_SERVICE_WALLET = 0xAF6fd55A83B0F85b4f330E2B25512C2b669786D2;
    address constant PRICE_UPDATE_SERVICE_WALLET = 0xAF6fd55A83B0F85b4f330E2B25512C2b669786D2;
    
    bytes32 constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    
    address deployer;
    
    function setUp() public {
        // Fork mainnet - use try/catch for RPC URL
        string memory rpcUrl;
        try vm.envString("ETH_RPC_URL") returns (string memory url) {
            rpcUrl = url;
        } catch {
            rpcUrl = "https://eth.llamarpc.com";
        }
        vm.createSelectFork(rpcUrl);
        
        // Set up deployer from private key
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        deployer = vm.addr(deployerPrivateKey);
        vm.deal(deployer, 10 ether);
        
        // Set environment variable
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        
        deploymentScript = new DeploymentScript();
    }
    
    function test_DeploymentScript_Run() public {
        // Record logs to capture deployed addresses
        vm.recordLogs();
        
        // Actually run the deployment script - this generates coverage
        deploymentScript.run();
        
        // Get recorded logs to find deployed contract addresses
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Parse deployed addresses from events
        address tokenProxy;
        address priceStorageProxy;
        address addressesWhitelist;
        address requestsManager;
        
        // Find proxy addresses from Upgraded events
        uint256 upgradeCount = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Upgraded(address)")) {
                if (upgradeCount == 0) {
                    tokenProxy = logs[i].emitter;
                } else if (upgradeCount == 1) {
                    priceStorageProxy = logs[i].emitter;
                }
                upgradeCount++;
            }
        }
        
        // Find AddressesWhitelist - it's the only Ownable contract deployed
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("OwnershipTransferred(address,address)")) {
                address from = address(uint160(uint256(logs[i].topics[1])));
                address to = address(uint160(uint256(logs[i].topics[2])));
                if (from == address(0) && to == deployer) {
                    addressesWhitelist = logs[i].emitter;
                    break;
                }
            }
        }
        
        // Find RequestsManager - it grants SERVICE_ROLE to MINT_REDEEM_SERVICE_WALLET
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("RoleGranted(bytes32,address,address)")) {
                bytes32 role = logs[i].topics[1];
                address account = address(uint160(uint256(logs[i].topics[2])));
                if (role == SERVICE_ROLE && account == MINT_REDEEM_SERVICE_WALLET) {
                    address emitter = logs[i].emitter;
                    // Check it's not one of the proxies
                    if (emitter != tokenProxy && emitter != priceStorageProxy) {
                        requestsManager = emitter;
                        break;
                    }
                }
            }
        }
        
        // Validate deployments
        assertTrue(tokenProxy != address(0), "Token proxy not found");
        assertTrue(priceStorageProxy != address(0), "PriceStorage proxy not found");
        assertTrue(addressesWhitelist != address(0), "AddressesWhitelist not found");
        assertTrue(requestsManager != address(0), "RequestsManager not found");
        
        // Validate configurations
        SimpleToken token = SimpleToken(tokenProxy);
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        
        PriceStorage priceStorage = PriceStorage(priceStorageProxy);
        assertEq(priceStorage.upperBoundPercentage(), PRICE_UPDATE_UPPER_BOUND_PERCENTAGE);
        assertEq(priceStorage.lowerBoundPercentage(), PRICE_UPDATE_LOWER_BOUND_PERCENTAGE);
        
        AddressesWhitelist whitelist = AddressesWhitelist(addressesWhitelist);
        assertEq(whitelist.owner(), deployer);
        
        RequestsManager manager = RequestsManager(requestsManager);
        assertEq(manager.ISSUE_TOKEN_ADDRESS(), tokenProxy);
        assertEq(manager.treasuryAddress(), MINT_DEPOSIT_VAULT);
        assertTrue(manager.allowedTokens(INPUT_TOKEN));
        
        // Validate roles
        assertTrue(token.hasRole(SERVICE_ROLE, requestsManager));
        assertTrue(priceStorage.hasRole(SERVICE_ROLE, PRICE_UPDATE_SERVICE_WALLET));
        assertTrue(manager.hasRole(SERVICE_ROLE, MINT_REDEEM_SERVICE_WALLET));
        
        console2.log("Deployment script executed and validated successfully");
    }
}