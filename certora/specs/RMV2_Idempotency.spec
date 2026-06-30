/*
 * RequestsManagerV2 — Idempotency-Key Spec
 * Properties RMV2_IDP_1 .. RMV2_IDP_5 (client FV 5.4):
 *   IDP_1/2  completeMint/completeBurn key injectivity over ids (optimistic_hashing: keccak injective).
 *   IDP_3    mint/burn key disjointness within V2 (tag byte differs: 'm' vs 'b').
 *   IDP_4/5  V2-vs-legacy preimage disjointness: framed on PREIMAGE bytes (tag-case and length
 *            witnesses), NOT a machine-checked keccak-output inequality (keccak injectivity stated).
 *
 * No token model is needed: these are pure harness keccak / preimage helpers.
 *
 * R-70/R-71 use the harness keccak helpers (keyMint/keyBurn). With `optimistic_hashing: true`,
 * keccak is treated as injective by the prover, so keyMint(i)==keyMint(j) => i==j is machine-checked
 * (the abi.encodePacked preimage is fixed-width 36 bytes, no length ambiguity on the id tail).
 *
 * R-72 is framed structurally on the PREIMAGE bytes (length + tag-byte witnesses) because CVL cannot
 * keccak dynamic bytes; keccak injectivity on distinct preimages is a STATED ASSUMPTION (deferral
 * pattern) recorded in the IDP_4/IDP_5 one-liner comments below.
 */

methods {
    // ── idempotency-key helpers (pure, harness-provided) ──
    function keyMint(uint256) external returns (bytes32) envfree;
    function keyBurn(uint256) external returns (bytes32) envfree;
    function keyPreimageLength(uint256) external returns (uint256) envfree;
    function keyMintTagByte() external returns (bytes1) envfree;
    function keyBurnTagByte() external returns (bytes1) envfree;
}

// ──────────────────────────────────────────────────────────────
//  Legacy V1 scheme witnesses (structural — no on-chain source)
//
//  Legacy off-chain key: keccak256(abi.encodePacked(product, "MINT"|"BURN", id)) where
//  product is a non-empty token-address (20 bytes) prefix and the tag is an UPPERCASE 4-byte
//  ascii word. We only need its preimage SHAPE:
//    - length  = len(product) + 4 (tag) + 32 (id)   [>= 36 + len(product), i.e. > 36 if product non-empty]
//    - tag byte = uppercase 'M' (0x4d) / 'B' (0x42), distinct from lowercase 'm'/'b'.
// ──────────────────────────────────────────────────────────────

// Tag-byte literals (bytes1). CVL compares bytes1 by value.
definition LEGACY_MINT_TAG_BYTE() returns bytes1 = to_bytes1(0x4d); // 'M'
definition LEGACY_BURN_TAG_BYTE() returns bytes1 = to_bytes1(0x42); // 'B'
definition V2_PREIMAGE_LEN()      returns mathint = 36;             // tag(4) + id(32)

// RMV2_IDP_1 — keyMint is injective over ids: i != j => keyMint(i) != keyMint(j) (optimistic_hashing; 36-byte fixed-width preimage).
rule mintKeyInjective(uint256 i, uint256 j) {
    require i != j, "distinct ids";
    assert keyMint(i) != keyMint(j),
        "distinct ids must derive distinct mint idempotency keys";
}

// RMV2_IDP_2 — keyBurn is injective over ids: i != j => keyBurn(i) != keyBurn(j) (optimistic_hashing; 36-byte fixed-width preimage).
rule burnKeyInjective(uint256 i, uint256 j) {
    require i != j, "distinct ids";
    assert keyBurn(i) != keyBurn(j),
        "distinct ids must derive distinct burn idempotency keys";
}

// RMV2_IDP_3 — mint and burn V2 keys are disjoint: no keyMint(i) equals any keyBurn(j) (tag byte 'm' 0x6d vs 'b' 0x62 differ at preimage byte 0).
rule mintBurnKeyDisjoint(uint256 i, uint256 j) {
    assert keyMint(i) != keyBurn(j),
        "no mint key may equal any burn key";
    assert keyMintTagByte() != keyBurnTagByte(),
        "mint/burn tag bytes are structurally distinct";
}

// RMV2_IDP_4 — V2-vs-legacy tag-case witness: V2 lowercase tags ('m'/'b') differ from legacy uppercase ('M'/'B') at every id (stated: keccak injective on distinct preimages).
rule v2DisjointFromLegacy_byTagCase(uint256 id) {
    assert keyMintTagByte() != LEGACY_MINT_TAG_BYTE(),
        "V2 lowercase mint tag differs from legacy uppercase MINT tag";
    assert keyBurnTagByte() != LEGACY_BURN_TAG_BYTE(),
        "V2 lowercase burn tag differs from legacy uppercase BURN tag";
    assert keyMintTagByte() != LEGACY_BURN_TAG_BYTE(),
        "V2 mint tag differs from legacy BURN tag";
    assert keyBurnTagByte() != LEGACY_MINT_TAG_BYTE(),
        "V2 burn tag differs from legacy MINT tag";
}

// RMV2_IDP_5 — V2-vs-legacy length witness: V2 preimage is exactly 36 bytes; legacy is strictly longer due to non-empty product prefix (stated: keccak injective on distinct preimages).
rule v2DisjointFromLegacy_byLength(uint256 id, uint256 productLen) {
    require productLen > 0, "non-empty legacy product";
    require productLen <= max_uint128, "realistic bound";
    mathint v2Len     = to_mathint(keyPreimageLength(id));
    mathint legacyLen = to_mathint(productLen) + V2_PREIMAGE_LEN();
    assert v2Len == V2_PREIMAGE_LEN(),
        "V2 preimage length is exactly 36 (tag(4) + id(32))";
    assert legacyLen > v2Len,
        "a non-empty legacy product prefix makes the legacy preimage strictly longer than V2's";
}
