// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {AddressesWhitelist} from "../src/AddressesWhitelist.sol";
import {PriceStorage} from "../src/PriceStorage.sol";
import {RequestsManager} from "../src/RequestsManager.sol";
import {SimpleToken} from "../src/SimpleToken.sol";

contract DeploymentScript is Script {
  // ┌─────────────────────────────────────────────────────────────┐
  // | Config                                                      |
  // └─────────────────────────────────────────────────────────────┘

  string TOKEN_NAME = "avETH MAX";
  string TOKEN_SYMBOL = "avETHx";

  uint128 PRICE_UPDATE_UPPER_BOUND_PERCENTAGE = .05 ether; // 5%
  uint128 PRICE_UPDATE_LOWER_BOUND_PERCENTAGE = .33 ether; // 33%

  address INPUT_TOKEN = 0x9469470C9878bf3d6d0604831d9A3A366156f7EE; // avETH on Ethereum
  address MINT_DEPOSIT_VAULT = 0xdD71CDd615f677E98C604bFF5679294cC7a6089b; // MAX avETH - Mint Deposit Vault (avETH Workspace)
  address MINT_REDEEM_SERVICE_WALLET = 0xAF6fd55A83B0F85b4f330E2B25512C2b669786D2; // Avant Bot (avETH Workspace)
  address PRICE_UPDATE_SERVICE_WALLET = 0xAF6fd55A83B0F85b4f330E2B25512C2b669786D2; // Avant Bot (avETH Workspace)

  // address INPUT_TOKEN = 0xfd2c2A98009d0cBed715882036e43d26C4289053; // avBTC on Avalanche
  // address MINT_DEPOSIT_VAULT = 0xC8fc3Ff83479b78E21a989807FB10D0E3D840ddf; // MAX avBTC - Mint Deposit Vault
  // address MINT_REDEEM_SERVICE_WALLET = 0xD5456b9AB991768601bEdF1159C51009D43C698D; // Avant Bot
  // address PRICE_UPDATE_SERVICE_WALLET = 0xD5456b9AB991768601bEdF1159C51009D43C698D; // Avant Bot

  // address INPUT_TOKEN = 0x24dE8771bC5DdB3362Db529Fc3358F2df3A0E346; // avUSD on Avalanche
  // address MINT_DEPOSIT_VAULT = 0xFCc1ab0aEf7e92eEf7AcdDbF187aCDD227aAC081; // MAX avUSD - Mint Deposit Vault
  // address MINT_REDEEM_SERVICE_WALLET = 0xD5456b9AB991768601bEdF1159C51009D43C698D; // Avant Bot
  // address PRICE_UPDATE_SERVICE_WALLET = 0xD5456b9AB991768601bEdF1159C51009D43C698D; // Avant Bot

  // ┌─────────────────────────────────────────────────────────────┐
  // | Script                                                      |
  // └─────────────────────────────────────────────────────────────┘

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployerAddress = vm.addr(deployerPrivateKey);
    uint256 deployerBalance = deployerAddress.balance;
    console.log("Deployer -> %s", deployerAddress);
    console.log("Balance -> %s", deployerBalance);

    vm.startBroadcast(deployerPrivateKey);

    console.log("Deploying %s token...", TOKEN_SYMBOL);
    address tokenProxy = Upgrades.deployUUPSProxy(
      "SimpleToken.sol",
      abi.encodeCall(SimpleToken.initialize, (TOKEN_NAME, TOKEN_SYMBOL))
    );
    console.log("%s (proxy) deployed to %s", TOKEN_SYMBOL, address(tokenProxy));

    console.log("Deploying PriceStorage...");
    address priceStorageProxy = Upgrades.deployUUPSProxy(
      "PriceStorage.sol",
      abi.encodeCall(PriceStorage.initialize, (PRICE_UPDATE_UPPER_BOUND_PERCENTAGE, PRICE_UPDATE_LOWER_BOUND_PERCENTAGE))
    );
    console.log("PriceStorage (proxy) deployed to %s", address(priceStorageProxy));
    console.log("Setting SERVICE_ROLE address on PriceStorage...");
    PriceStorage priceStorage = PriceStorage(priceStorageProxy);
    priceStorage.grantRole(priceStorage.SERVICE_ROLE(), PRICE_UPDATE_SERVICE_WALLET);

    console.log("Deploying AddressesWhitelist...");
    AddressesWhitelist addressesWhitelist = new AddressesWhitelist();
    console.log("AddressesWhitelist deployed to %s", address(addressesWhitelist));

    console.log("Deploying RequestsManager...");
    address[] memory inputTokens = new address[](1);
    inputTokens[0] = INPUT_TOKEN;
    RequestsManager requestsManager = new RequestsManager(address(tokenProxy), MINT_DEPOSIT_VAULT, address(addressesWhitelist), inputTokens);
    console.log("RequestsManager deployed to %s", address(requestsManager));
    console.log("Setting SERVICE_ROLE address on RequestsManager...");
    requestsManager.grantRole(requestsManager.SERVICE_ROLE(), MINT_REDEEM_SERVICE_WALLET);

    console.log("Setting SERVICE_ROLE address on %s...", TOKEN_SYMBOL);
    SimpleToken token = SimpleToken(tokenProxy);
    token.grantRole(token.SERVICE_ROLE(), address(requestsManager));

    vm.stopBroadcast();
  }
}
