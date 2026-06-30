// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RequestsManagerV2} from "../../src/RequestsManagerV2.sol";
import {IRequestsManagerV2} from "../../src/interfaces/IRequestsManagerV2.sol";

/// @title RequestsManagerV2Harness
/// @notice Certora verification harness for RequestsManagerV2. Adds NOTHING to the contract
///         logic — it only exposes envfree getters for the struct-in-mapping request fields
///         (CVL cannot read struct fields inside mappings, Gotcha 46) and pure helpers that
///         mirror the source settlement math and the on-chain idempotency-key derivation so
///         specs can reason about them directly.
///
///         The constructor forwards its arguments straight to the base constructor; the
///         allowed-token list is left empty so the prover can deploy the harness without a
///         concrete token meeting the decimals()==18 / has-code constructor checks. Tokens
///         are added in-rule via addAllowedToken when a rule needs an allowlisted token.
contract RequestsManagerV2Harness is RequestsManagerV2 {
    constructor(
        address _issueTokenAddress,
        address _priceStorageAddress,
        address _treasuryAddress,
        uint64 _burnRequestTTL,
        uint64 _burnCancelWindow,
        uint64 _mintRequestTTL
    )
        RequestsManagerV2(
            _issueTokenAddress,
            _priceStorageAddress,
            _treasuryAddress,
            new address[](0),
            _burnRequestTTL,
            _burnCancelWindow,
            _mintRequestTTL
        )
    {}

    // ──────────────────────────────────────────────────────────────
    //  Mint request struct-field getters (Gotcha 46)
    // ──────────────────────────────────────────────────────────────

    function mintRequestState(uint256 id) external view returns (IRequestsManagerV2.State) {
        return mintRequests[id].state;
    }

    function mintRequestProvider(uint256 id) external view returns (address) {
        return mintRequests[id].provider;
    }

    function mintRequestCreatedAt(uint256 id) external view returns (uint40) {
        return mintRequests[id].createdAt;
    }

    function mintRequestToken(uint256 id) external view returns (address) {
        return mintRequests[id].token;
    }

    function mintRequestAmount(uint256 id) external view returns (uint256) {
        return mintRequests[id].amount;
    }

    // ──────────────────────────────────────────────────────────────
    //  Burn request struct-field getters (Gotcha 46)
    // ──────────────────────────────────────────────────────────────

    function burnRequestState(uint256 id) external view returns (IRequestsManagerV2.State) {
        return burnRequests[id].state;
    }

    function burnRequestProvider(uint256 id) external view returns (address) {
        return burnRequests[id].provider;
    }

    function burnRequestCreatedAt(uint256 id) external view returns (uint40) {
        return burnRequests[id].createdAt;
    }

    function burnRequestPrice(uint256 id) external view returns (uint128) {
        return burnRequests[id].price;
    }

    function burnRequestFee(uint256 id) external view returns (uint64) {
        return burnRequests[id].fee;
    }

    function burnRequestToken(uint256 id) external view returns (address) {
        return burnRequests[id].token;
    }

    function burnRequestAmount(uint256 id) external view returns (uint256) {
        return burnRequests[id].amount;
    }

    // ──────────────────────────────────────────────────────────────
    //  Settlement math helpers — mirror the source EXACTLY
    // ──────────────────────────────────────────────────────────────

    /// @dev Mirrors completeMint lines 290-291: mintAmount = deposit*PRECISION/price,
    ///      then *(PRECISION-fee)/PRECISION. No ZeroAmountOut revert here (pure math).
    function computeMintAmount(uint256 deposit, uint128 price, uint64 fee) external pure returns (uint256) {
        uint256 mintAmount = (deposit * PRECISION) / price;
        mintAmount = (mintAmount * (PRECISION - fee)) / PRECISION;
        return mintAmount;
    }

    /// @dev Mirrors completeMint line 290 only: the pre-fee ceiling deposit*PRECISION/price.
    function computeMintPreFee(uint256 deposit, uint128 price) external pure returns (uint256) {
        return (deposit * PRECISION) / price;
    }

    /// @dev Mirrors completeBurn lines 412-413: withdrawal = amount*price/PRECISION,
    ///      then *(PRECISION-fee)/PRECISION. `price` is the already-selected settlement price.
    function computeBurnAmount(uint256 amount, uint128 price, uint64 fee) external pure returns (uint256) {
        uint256 withdrawalAmount = (amount * price) / PRECISION;
        withdrawalAmount = (withdrawalAmount * (PRECISION - fee)) / PRECISION;
        return withdrawalAmount;
    }

    // ──────────────────────────────────────────────────────────────
    //  Idempotency-key helpers — mirror the source derivation
    // ──────────────────────────────────────────────────────────────

    /// @dev Mirrors completeMint line 301: keccak256(abi.encodePacked("mint", id)).
    function keyMint(uint256 id) external pure returns (bytes32) {
        return keccak256(abi.encodePacked("mint", id));
    }

    /// @dev Mirrors completeBurn line 421: keccak256(abi.encodePacked("burn", id)).
    function keyBurn(uint256 id) external pure returns (bytes32) {
        return keccak256(abi.encodePacked("burn", id));
    }

    /// @notice The abi.encodePacked preimage bytes of the V2 mint key for `id`
    ///         (tag "mint" || uint256 id). Used to prove preimage disjointness from
    ///         the burn key and from the legacy V1 product-prefixed scheme (R-71/R-72).
    function keyMintPreimage(uint256 id) external pure returns (bytes memory) {
        return abi.encodePacked("mint", id);
    }

    /// @notice The abi.encodePacked preimage bytes of the V2 burn key for `id`
    ///         (tag "burn" || uint256 id).
    function keyBurnPreimage(uint256 id) external pure returns (bytes memory) {
        return abi.encodePacked("burn", id);
    }

    /// @notice Length in bytes of a V2 key preimage: 4 (tag) + 32 (uint256 id) = 36.
    function keyPreimageLength(uint256 id) external pure returns (uint256) {
        return abi.encodePacked("mint", id).length;
    }

    /// @notice First (tag) byte of the V2 mint preimage: 'm' (0x6d, lowercase).
    function keyMintTagByte() external pure returns (bytes1) {
        return bytes(abi.encodePacked("mint"))[0];
    }

    /// @notice First (tag) byte of the V2 burn preimage: 'b' (0x62, lowercase).
    function keyBurnTagByte() external pure returns (bytes1) {
        return bytes(abi.encodePacked("burn"))[0];
    }
}
