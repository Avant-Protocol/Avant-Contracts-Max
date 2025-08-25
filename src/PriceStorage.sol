// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

import {IPriceStorage} from "./interfaces/IPriceStorage.sol";

contract PriceStorage is IPriceStorage, AccessControlDefaultAdminRulesUpgradeable {
  bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
  uint128 public constant BOUND_PERCENTAGE_DENOMINATOR = 1e18;

  mapping(bytes32 key => Price price) public prices;
  Price public lastPrice;

  uint128 public upperBoundPercentage;
  uint128 public lowerBoundPercentage;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(uint128 _upperBoundPercentage, uint128 _lowerBoundPercentage) public initializer {
    __AccessControlDefaultAdminRules_init(1 days, msg.sender);
    setUpperBoundPercentage(_upperBoundPercentage);
    setLowerBoundPercentage(_lowerBoundPercentage);
  }

  function setPrice(bytes32 _key, uint128 _price) external onlyRole(SERVICE_ROLE) {
    if (_key == bytes32(0)) revert InvalidKey();
    if (_price == 0) revert InvalidPrice();
    if (prices[_key].timestamp != 0) revert PriceAlreadySet(_key);

    uint128 lastPriceValue = lastPrice.price;
    if (lastPriceValue != 0) {
      uint128 upperBound = lastPriceValue + ((lastPriceValue * upperBoundPercentage) / BOUND_PERCENTAGE_DENOMINATOR);
      uint128 lowerBound = lastPriceValue - ((lastPriceValue * lowerBoundPercentage) / BOUND_PERCENTAGE_DENOMINATOR);
      if (_price > upperBound || _price < lowerBound) {
        revert InvalidPriceRange(_price, lowerBound, upperBound);
      }
    }

    uint128 currentTime = uint128(block.timestamp);
    Price memory price = Price({price: _price, timestamp: currentTime});
    prices[_key] = price;
    lastPrice = price;

    emit PriceSet(_key, _price, currentTime);
  }

  function setUpperBoundPercentage(uint128 _upperBoundPercentage) public onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_upperBoundPercentage == 0 || _upperBoundPercentage > BOUND_PERCENTAGE_DENOMINATOR)
      revert InvalidUpperBoundPercentage();

    upperBoundPercentage = _upperBoundPercentage;
    emit UpperBoundPercentageSet(_upperBoundPercentage);
  }

  function setLowerBoundPercentage(uint128 _lowerBoundPercentage) public onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_lowerBoundPercentage == 0 || _lowerBoundPercentage > BOUND_PERCENTAGE_DENOMINATOR)
      revert InvalidLowerBoundPercentage();

    lowerBoundPercentage = _lowerBoundPercentage;
    emit LowerBoundPercentageSet(_lowerBoundPercentage);
  }
}
