// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPriceStorage {
  struct Price {
    uint128 price;
    uint128 timestamp;
  }

  event PriceSet(bytes32 indexed key, uint128 price, uint128 timestamp);
  event UpperBoundPercentageSet(uint128 upperBoundPercentage);
  event LowerBoundPercentageSet(uint128 lowerBoundPercentage);

  error PriceAlreadySet(bytes32 key);
  error InvalidPrice();
  error InvalidKey();
  error InvalidUpperBoundPercentage();
  error InvalidLowerBoundPercentage();
  error InvalidPriceRange(uint128 price, uint128 lowerBound, uint128 upperBound);

  function setPrice(bytes32 _key, uint128 _price) external;

  function setUpperBoundPercentage(uint128 _upperBoundPercentage) external;

  function setLowerBoundPercentage(uint128 _lowerBoundPercentage) external;

  function lastPrice() external view returns (uint128 price, uint128 timestamp);

  function prices(bytes32 _key) external view returns (uint128 price, uint128 timestamp);
}
