/*
 * RequestsManagerV2 — Structural Spec
 * Properties RMV2_STR_1 .. RMV2_STR_17: counter monotonicity + exactly-0-or-1 increment,
 * no id reuse / fresh-slot, write-targeting, per-request field immutability,
 * non-existent request revert guard, counter >= INITIAL_COUNTER (V1 id-separation
 * invariant), per-request amount non-zero invariants, immutable constants, setter
 * side-effect isolation.
 *
 * Parametric over all RMV2 methods with commonFilters. PRICE_STORAGE.lastPrice() is summarised
 * via ghostPrice (unconstrained; rules that need completeBurn/requestBurn to succeed add
 * require ghostPrice > 0). Issue token, withdrawal token, and tokenA are linked so token
 * transfers resolve concretely.
 */

import "utils/RMV2_Base.spec";

methods {
    function PRICE_STORAGE() external returns (address) envfree;
}


/* -------------------------------------------------------------------------- */
/*                                    UTILS                                   */
/* -------------------------------------------------------------------------- */

/// @dev change this value if INITIAL_COUNTER is changed during development 
definition INITIAL_COUNTER_VALUE() returns uint256 = 100000;

/* -------------------------------------------------------------------------- */
/*                                 PROPERTIES                                 */
/* -------------------------------------------------------------------------- */
// RMV2_STR_1 — mintRequestsCounter never decreases and increases by at most 1 per call.
rule mintCounterMonotonic(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    mathint before = to_mathint(mintRequestsCounter());
    require before < max_uint256, "counter fits uint256";
    f(e, args);
    mathint after = to_mathint(mintRequestsCounter());
    assert after >= before, "mintRequestsCounter never decreases";
    assert after <= before + 1, "mintRequestsCounter increases by at most 1";
    assert after > before => f.selector == sig:requestMint(address,uint256).selector
        || f.selector == sig:requestMintWithPermit(address,uint256,uint256,uint8,bytes32,bytes32).selector,
        "only requestMint(/WithPermit) increments mintRequestsCounter";
}

// RMV2_STR_2 — burnRequestsCounter never decreases and increases by at most 1 per call.
rule burnCounterMonotonic(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    mathint before = to_mathint(burnRequestsCounter());
    require before < max_uint256, "counter fits uint256";
    f(e, args);
    mathint after = to_mathint(burnRequestsCounter());
    assert after >= before, "burnRequestsCounter never decreases";
    assert after <= before + 1, "burnRequestsCounter increases by at most 1";
    assert after > before => f.selector == sig:requestBurn(uint256,address).selector
        || f.selector == sig:requestBurnWithPermit(uint256,address,uint256,uint8,bytes32,bytes32).selector,
        "only requestBurn(/WithPermit) increments burnRequestsCounter";
}

// RMV2_STR_3 — any id >= mintRequestsCounter has an empty slot (no mint id reuse).
invariant mintFreshSlot(uint256 id)
    to_mathint(id) >= to_mathint(mintRequestsCounter()) => mintRequestProvider(id) == 0
    filtered { f -> commonFilters(f) }
    { preserved with (env e) { require mintRequestsCounter() < max_uint256; } }

// RMV2_STR_4 — any id >= burnRequestsCounter has an empty slot (no burn id reuse).
invariant burnFreshSlot(uint256 id)
    to_mathint(id) >= to_mathint(burnRequestsCounter()) => burnRequestProvider(id) == 0
    filtered { f -> commonFilters(f) }
    { preserved with (env e) { require burnRequestsCounter() < max_uint256; } }

// RMV2_STR_5 — requestMint writes only the pre-call counter slot, sets it CREATED/msg.sender, increments counter by one, touches no other id.
rule requestMintWriteTargeting(env e, address token, uint256 amount, uint256 otherId) {
    requireInvariant mintFreshSlot(require_uint256(mintRequestsCounter()));
    uint256 id0 = mintRequestsCounter();
    require to_mathint(id0) < max_uint256, "counter fits uint256";
    require otherId != id0, "distinct slot";

    address otherProviderBefore = mintRequestProvider(otherId);
    uint8   otherStateBefore = assert_uint8(mintRequestState(otherId));
    address otherTokenBefore = mintRequestToken(otherId);
    uint256 otherAmountBefore = mintRequestAmount(otherId);

    requestMint(e, token, amount);

    assert mintRequestProvider(id0) == e.msg.sender, "target slot provider == msg.sender";
    assert assert_uint8(mintRequestState(id0)) == CREATED(), "target slot state == CREATED";
    assert mintRequestToken(id0) == token, "target slot token == deposit token";
    assert mintRequestAmount(id0) == amount, "target slot amount == requested amount";
    assert mintRequestCreatedAt(id0) == require_uint40(e.block.timestamp), "target slot createdAt == block.timestamp";
    assert to_mathint(mintRequestsCounter()) == to_mathint(id0) + 1, "counter incremented by exactly one";

    assert mintRequestProvider(otherId) == otherProviderBefore, "other slot provider untouched";
    assert assert_uint8(mintRequestState(otherId)) == otherStateBefore, "other slot state untouched";
    assert mintRequestToken(otherId) == otherTokenBefore, "other slot token untouched";
    assert mintRequestAmount(otherId) == otherAmountBefore, "other slot amount untouched";
}

// RMV2_STR_6 — requestBurn writes only the pre-call counter slot, sets it CREATED/msg.sender, increments counter by one, touches no other id.
rule requestBurnWriteTargeting(env e, uint256 amount, address token, uint256 otherId) {
    requireInvariant burnFreshSlot(require_uint256(burnRequestsCounter()));
    uint256 id0 = burnRequestsCounter();
    require to_mathint(id0) < max_uint256, "counter fits uint256";
    require otherId != id0, "distinct slot";

    address otherProviderBefore = burnRequestProvider(otherId);
    uint8   otherStateBefore = assert_uint8(burnRequestState(otherId));
    address otherTokenBefore = burnRequestToken(otherId);
    uint256 otherAmountBefore = burnRequestAmount(otherId);
    require ghostPrice > 0, "price positive";

    requestBurn(e, amount, token);

    assert burnRequestProvider(id0) == e.msg.sender, "target slot provider == msg.sender";
    assert assert_uint8(burnRequestState(id0)) == CREATED(), "target slot state == CREATED";
    assert burnRequestToken(id0) == token, "target slot token == withdrawal token";
    assert burnRequestAmount(id0) == amount, "target slot amount == requested amount";
    assert burnRequestCreatedAt(id0) == require_uint40(e.block.timestamp), "target slot createdAt == block.timestamp";
    assert burnRequestPrice(id0) == ghostPrice, "target slot price must equal current oracle price at creation";
    assert burnRequestFee(id0) == burnFee(), "target slot fee must equal current burnFee at creation";
    assert to_mathint(burnRequestsCounter()) == to_mathint(id0) + 1, "counter incremented by exactly one";

    assert burnRequestProvider(otherId) == otherProviderBefore, "other slot provider untouched";
    assert assert_uint8(burnRequestState(otherId)) == otherStateBefore, "other slot state untouched";
    assert burnRequestToken(otherId) == otherTokenBefore, "other slot token untouched";
    assert burnRequestAmount(otherId) == otherAmountBefore, "other slot amount untouched";
}

// RMV2_STR_7 — provider/createdAt/token/amount of a mint request are fixed after creation; only state may change.
rule mintFieldImmutability(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    requireInvariant mintFreshSlot(id);
    require to_mathint(mintRequestsCounter()) < max_uint256, "counter fits uint256";
    require mintRequestProvider(id) != 0, "request exists";      

    address providerBefore = mintRequestProvider(id);
    uint40  createdAtBefore = mintRequestCreatedAt(id);
    address tokenBefore = mintRequestToken(id);
    uint256 amountBefore = mintRequestAmount(id);

    f(e, args);

    assert mintRequestProvider(id) == providerBefore, "provider immutable after creation";
    assert mintRequestCreatedAt(id) == createdAtBefore, "createdAt immutable after creation";
    assert mintRequestToken(id) == tokenBefore, "token immutable after creation";
    assert mintRequestAmount(id) == amountBefore, "amount immutable after creation";
}

// RMV2_STR_8 — provider/createdAt/token/amount/price/fee of a burn request are fixed after creation; only state may change.
rule burnFieldImmutability(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    requireInvariant burnFreshSlot(id);
    require to_mathint(burnRequestsCounter()) < max_uint256, "counter fits uint256";
    require burnRequestProvider(id) != 0, "request exists";

    address providerBefore = burnRequestProvider(id);
    uint40  createdAtBefore = burnRequestCreatedAt(id);
    uint128 priceBefore = burnRequestPrice(id);
    uint64  feeBefore = burnRequestFee(id);
    address tokenBefore = burnRequestToken(id);
    uint256 amountBefore = burnRequestAmount(id);

    f(e, args);

    assert burnRequestProvider(id) == providerBefore, "provider immutable after creation";
    assert burnRequestCreatedAt(id) == createdAtBefore, "createdAt immutable after creation";
    assert burnRequestPrice(id) == priceBefore, "locked price immutable after creation";
    assert burnRequestFee(id) == feeBefore, "locked fee immutable after creation";
    assert burnRequestToken(id) == tokenBefore, "token immutable after creation";
    assert burnRequestAmount(id) == amountBefore, "amount immutable after creation";
}

// RMV2_STR_9 — completeMint/cancelMint/adminCancelMint revert when the mint request does not exist (provider == 0).
rule mintNonExistentRequestReverts(env e, uint256 id) {
    setup(e);
    require mintRequestProvider(id) == 0, "request absent";

    storage init = lastStorage;

    completeMint@withrevert(e, id);
    assert lastReverted, "completeMint must revert for a non-existent mint request";

    cancelMint@withrevert(e, id) at init;
    assert lastReverted, "cancelMint must revert for a non-existent mint request";

    adminCancelMint@withrevert(e, id) at init;
    assert lastReverted, "adminCancelMint must revert for a non-existent mint request";
}

// RMV2_STR_10 — completeBurn/cancelBurn/adminCancelBurn revert when the burn request does not exist (provider == 0).
rule burnNonExistentRequestReverts(env e, uint256 id) {
    setup(e);
    require burnRequestProvider(id) == 0, "request absent";

    storage init = lastStorage;

    completeBurn@withrevert(e, id);
    assert lastReverted, "completeBurn must revert for a non-existent burn request";

    cancelBurn@withrevert(e, id) at init;
    assert lastReverted, "cancelBurn must revert for a non-existent burn request";

    adminCancelBurn@withrevert(e, id) at init;
    assert lastReverted, "adminCancelBurn must revert for a non-existent burn request";
}

// RMV2_STR_11 — mintRequestsCounter never falls below INITIAL_COUNTER, preserving V1 id-separation.
invariant mintCounterAtLeastInitial()
    to_mathint(mintRequestsCounter()) >= to_mathint(INITIAL_COUNTER_VALUE())
    filtered { f -> commonFilters(f) }
    { preserved { require to_mathint(mintRequestsCounter()) < max_uint256; } }

// RMV2_STR_12 — burnRequestsCounter never falls below INITIAL_COUNTER, preserving V1 id-separation.
invariant burnCounterAtLeastInitial()
    to_mathint(burnRequestsCounter()) >= to_mathint(INITIAL_COUNTER_VALUE())
    filtered { f -> commonFilters(f) }
    { preserved { require to_mathint(burnRequestsCounter()) < max_uint256; } }

// RMV2_STR_13 — every existing mint request (provider != 0) has a non-zero amount.
invariant mintRequestAmountNonZero(uint256 id)
    mintRequestProvider(id) != 0 => mintRequestAmount(id) != 0
    filtered { f -> commonFilters(f) }

// RMV2_STR_14 — every existing burn request (provider != 0) has a non-zero amount.
invariant burnRequestAmountNonZero(uint256 id)
    burnRequestProvider(id) != 0 => burnRequestAmount(id) != 0
    filtered { f -> commonFilters(f) }

// RMV2_STR_15 — ISSUE_TOKEN_ADDRESS never changes after construction.
rule immutablesNeverChange(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    address itok = ISSUE_TOKEN_ADDRESS();
    f(e, args);
    assert ISSUE_TOKEN_ADDRESS() == itok, "ISSUE_TOKEN_ADDRESS changed after construction";
}

// RMV2_STR_16 — PRICE_STORAGE never changes after construction.
rule priceStorageImmutable(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    address ps = PRICE_STORAGE();
    f(e, args);
    assert PRICE_STORAGE() == ps, "PRICE_STORAGE changed after construction";
}

// RMV2_STR_17 — setBurnFee does not mutate locked fees of already-created burn requests.
rule setBurnFeeDoesNotTouchPendingBurns(env e, uint64 newFee, uint256 id) {
    setup(e);
    uint64 lockedBefore = burnRequestFee(id);
    require burnRequestProvider(id) != 0, "request exists";
    setBurnFee(e, newFee);
    assert burnRequestFee(id) == lockedBefore,
        "setBurnFee mutated a pending burn request's locked fee";
}
