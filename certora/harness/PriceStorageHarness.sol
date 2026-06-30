// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PriceStorage} from "../../src/PriceStorage.sol";

/// @title PriceStorageHarness
/// @notice Certora verification harness for PriceStorage. Exposes envfree getters
///         for the Price-struct fields held inside a mapping/struct (CVL cannot read
///         struct fields inside a mapping directly — Gotcha 46), plus a helper to read
///         the OZ Initializable ERC-7201 namespaced `_initialized` slot (Gotcha 50).
contract PriceStorageHarness is PriceStorage {
    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE =
        0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /// @notice prices[key].price
    function getPriceValue(bytes32 key) external view returns (uint128) {
        return prices[key].price;
    }

    /// @notice prices[key].timestamp
    function getPriceTimestamp(bytes32 key) external view returns (uint128) {
        return prices[key].timestamp;
    }

    /// @notice lastPrice.price
    function getLastPriceValue() external view returns (uint128) {
        return lastPrice.price;
    }

    /// @notice lastPrice.timestamp
    function getLastPriceTimestamp() external view returns (uint128) {
        return lastPrice.timestamp;
    }

    /// @notice Raw `_initialized` version field from the OZ Initializable namespaced storage.
    function getInitializedVersion() public view returns (uint64 initialized) {
        bytes32 slot = INITIALIZABLE_STORAGE;
        assembly {
            // InitializableStorage layout: { uint64 _initialized; bool _initializing; }
            // both packed into the first slot; _initialized occupies the low 64 bits.
            let data := sload(slot)
            initialized := and(data, 0xffffffffffffffff)
        }
    }

    /// @notice True once `initialize` has run (version >= 1). Pre-init the field is 0.
    function isInitialized() external view returns (bool) {
        return getInitializedVersion() >= 1;
    }
}
