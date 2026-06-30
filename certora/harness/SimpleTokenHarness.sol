// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SimpleToken} from "../../src/SimpleToken.sol";

/// @title SimpleTokenHarness
/// @notice Certora verification harness for SimpleToken.
///
///         `mintIds`/`burnIds` are `private` in SimpleToken, so they cannot be read
///         from this derived contract via Solidity. They ARE SimpleToken-local
///         sequential-slot mappings hookable directly by name in CVL (Gotcha 206), so
///         the spec mirrors them into ghosts via `Sstore`/`Sload` hooks and exposes
///         `mintIdsUsedCVL(key)` / `burnIdsUsedCVL(key)` helper functions backed by
///         those ghosts.
///
///         The inherited ERC20 `_balances`/`_totalSupply`/`_allowances`/`_nonces`
///         live in OZ's ERC-7201 namespaced storage but remain hookable by name at
///         the storage-slot level (Gotcha 206), so no shadow storage is required for
///         the sum-of-balances ghost. `totalSupply()`/`balanceOf()`/`allowance()`/
///         `nonces()` are all envfree views inherited from the OZ implementation.
///
///         This harness exposes only the OZ Initializable ERC-7201 `_initialized`
///         slot helper (Gotcha 50), used by the single-use-initializer rule.
contract SimpleTokenHarness is SimpleToken {
    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE =
        0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

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
