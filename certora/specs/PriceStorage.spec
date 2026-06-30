/*
 * PriceStorage.spec — Certora CVL specification for PriceStorage (oracle producer).
 *
 * Covers consolidated properties P-1..P-19 (see certora/invariants.md, PriceStorage section).
 * Target: certora/harness/PriceStorageHarness.sol (extends src/PriceStorage.sol).
 *
 * Known-issue carve-outs (do NOT formalize): F-01 oracle staleness / cumulative drift
 * across many keys is ACCEPTED — only the per-update bound (P-2/P-3) + write-once (P-1)
 * are proven here. No staleness or cumulative-drift rule is written.
 */

methods {
    // ---- harness getters ----
    function getPriceValue(bytes32) external returns (uint128) envfree;
    function getPriceTimestamp(bytes32) external returns (uint128) envfree;
    function getLastPriceValue() external returns (uint128) envfree;
    function getLastPriceTimestamp() external returns (uint128) envfree;
    function getInitializedVersion() external returns (uint64) envfree;
    function isInitialized() external returns (bool) envfree;

    // ---- config ----
    function upperBoundPercentage() external returns (uint128) envfree;
    function lowerBoundPercentage() external returns (uint128) envfree;

    // ---- access control ----
    function SERVICE_ROLE() external returns (bytes32) envfree;
    function DEFAULT_ADMIN_ROLE() external returns (bytes32) envfree;
    function hasRole(bytes32, address) external returns (bool) envfree;
    function getRoleAdmin(bytes32) external returns (bytes32) envfree;
}

/* -------------------------------------------------------------------------- */
/*                                 DEFINITIONS                                */
/* -------------------------------------------------------------------------- */

// CVL ^ is exponentiation; matches BOUND_PERCENTAGE_DENOMINATOR == 1e18.
definition DENOM() returns mathint = 10^18;

// Real block.timestamp fits in 2^40; 2^128 is unreachable in practice.
definition TWO_128() returns mathint = 2^128;

definition commonFilters(method f) returns bool =
    f.contract == currentContract && !f.isView;

definition isInitialize(method f) returns bool =
    f.selector == sig:initialize(uint128,uint128).selector;

definition isAdminTransferPath(method f) returns bool =
    f.selector == sig:initialize(uint128,uint128).selector
    || f.selector == sig:acceptDefaultAdminTransfer().selector;

/* -------------------------------------------------------------------------- */
/*                                 PROPERTIES                                 */
/* -------------------------------------------------------------------------- */

// P-1 — Once prices[key] is written (timestamp != 0), neither field ever changes.
rule priceKeyWriteOnce(env e, method f, calldataarg args, bytes32 key)
    filtered { f -> commonFilters(f) } {
    uint128 tsBefore = getPriceTimestamp(key);
    uint128 pxBefore = getPriceValue(key);
    require tsBefore != 0, "price already written";

    f(e, args);

    assert getPriceTimestamp(key) == tsBefore && getPriceValue(key) == pxBefore,
        "an already-set price key was overwritten";
}

// P-2 — lastPrice.price never exceeds prev * (1 + upperBoundPercentage / 1e18).
rule setPriceUpwardBound(env e, bytes32 key, uint128 px) {
    uint128 prev = getLastPriceValue();
    uint128 upPct = upperBoundPercentage();
    require prev != 0, "previous price set";

    setPrice(e, key, px);

    mathint upper = to_mathint(prev) + (to_mathint(prev) * to_mathint(upPct)) / DENOM();
    assert to_mathint(getLastPriceValue()) <= upper,
        "lastPrice exceeded upper bound after setPrice";
}

// P-3 — lastPrice.price never falls below prev * (1 - lowerBoundPercentage / 1e18).
rule setPriceDownwardBound(env e, bytes32 key, uint128 px) {
    uint128 prev = getLastPriceValue();
    uint128 loPct = lowerBoundPercentage();
    require prev != 0, "previous price set";

    setPrice(e, key, px);

    mathint lower = to_mathint(prev) - (to_mathint(prev) * to_mathint(loPct)) / DENOM();
    assert to_mathint(getLastPriceValue()) >= lower,
        "lastPrice fell below lower bound after setPrice";
}

// P-4 — lastPrice.timestamp equals block.timestamp on every write and never decreases.
rule lastPriceTimestampMonotonicOnWrite(env e, bytes32 key, uint128 px) {
    require to_mathint(e.block.timestamp) < TWO_128(), "timestamp fits uint128";
    require e.block.timestamp > 0, "non-zero timestamp";
    uint128 tsBefore = getLastPriceTimestamp();
    require to_mathint(tsBefore) <= to_mathint(e.block.timestamp), "timestamp non-decreasing";

    setPrice(e, key, px);

    assert to_mathint(getLastPriceTimestamp()) == to_mathint(e.block.timestamp),
        "lastPrice.timestamp not set to block.timestamp on write";
    assert to_mathint(getLastPriceTimestamp()) >= to_mathint(tsBefore),
        "lastPrice.timestamp decreased on write";
}

// P-5 — Only setPrice may mutate lastPrice.timestamp (parametric complement to P-4).
rule lastPriceTimestampOnlySetPrice(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) } {
    uint128 tsBefore = getLastPriceTimestamp();

    f(e, args);

    assert getLastPriceTimestamp() != tsBefore
        => f.selector == sig:setPrice(bytes32,uint128).selector,
        "lastPrice.timestamp changed by a function other than setPrice";
}

// P-6 — After setPrice, lastPrice mirrors the key written in the same call.
rule lastPriceMirrorsWrittenKey(env e, bytes32 key, uint128 px) {
    setPrice(e, key, px);

    assert getLastPriceValue() == getPriceValue(key)
        && getLastPriceValue() == px,
        "lastPrice.price desynchronized from the key written this call";
    assert getLastPriceTimestamp() == getPriceTimestamp(key),
        "lastPrice.timestamp desynchronized from the key written this call";
}

// P-7 — prices[key].price is never zero once the slot is written.
invariant priceNonZeroWhenSet(bytes32 key)
    getPriceTimestamp(key) != 0 => getPriceValue(key) != 0
    filtered { f -> !isInitialize(f) }

// P-8 — lastPrice fields are either both zero or both non-zero.
invariant lastPriceZeroIffUnwritten()
    (getLastPriceValue() == 0) <=> (getLastPriceTimestamp() == 0)
    filtered { f -> !isInitialize(f) }
    {
        preserved setPrice(bytes32 key, uint128 px) with (env e) {
            require e.block.timestamp > 0, "non-zero timestamp";
            require to_mathint(e.block.timestamp) < TWO_128(), "timestamp fits uint128";
        }
    }

// P-9 — Any mutation to prices or lastPrice requires SERVICE_ROLE.
rule onlyServiceRoleWritesPrice(env e, method f, calldataarg args, bytes32 key)
    filtered { f -> commonFilters(f) } {
    require e.msg.sender != currentContract, "sender not self";

    uint128 tsBefore = getPriceTimestamp(key);
    uint128 pxBefore = getPriceValue(key);
    uint128 lpvBefore = getLastPriceValue();
    uint128 lptBefore = getLastPriceTimestamp();
    bool senderHasService = hasRole(SERVICE_ROLE(), e.msg.sender);

    f(e, args);

    bool changed = getPriceTimestamp(key) != tsBefore
        || getPriceValue(key) != pxBefore
        || getLastPriceValue() != lpvBefore
        || getLastPriceTimestamp() != lptBefore;

    assert changed => senderHasService,
        "price state changed without SERVICE_ROLE";
}

// P-10 — Changing upperBoundPercentage or lowerBoundPercentage requires DEFAULT_ADMIN_ROLE.
rule onlyAdminChangesBounds(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) && !isInitialize(f) } {
    require e.msg.sender != currentContract, "sender not self";

    uint128 upBefore = upperBoundPercentage();
    uint128 loBefore = lowerBoundPercentage();
    bool senderHasAdmin = hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender);

    f(e, args);

    bool changed = upperBoundPercentage() != upBefore
        || lowerBoundPercentage() != loBefore;

    assert changed => senderHasAdmin,
        "bounds changed without DEFAULT_ADMIN_ROLE";
}

// P-11 — After initialization upperBoundPercentage is in (0, 1e18]. Uses version==1 not isInitialized() because
//        _disableInitializers() sets version=uint64.max with bounds==0, causing a spurious CEX otherwise.
invariant upperBoundInRange()
    getInitializedVersion() == 1 => (to_mathint(upperBoundPercentage()) > 0
        && to_mathint(upperBoundPercentage()) <= DENOM())
    filtered { f -> !isInitialize(f) }

// P-12 — After initialization lowerBoundPercentage is in (0, 1e18] (load-bearing for P-3 no-underflow).
invariant lowerBoundInRange()
    getInitializedVersion() == 1 => (to_mathint(lowerBoundPercentage()) > 0
        && to_mathint(lowerBoundPercentage()) <= DENOM())
    filtered { f -> !isInitialize(f) }

// P-13 — initialize can only be called once; a second call always reverts.
rule initializeAtMostOnce(env e, uint128 up, uint128 lo) {
    require isInitialized(), "already initialized";
    initialize@withrevert(e, up, lo);
    assert lastReverted, "initialize succeeded a second time";
}

// P-14 — initialize sets the version to exactly 1.
rule initializeSetsVersion(env e, uint128 up, uint128 lo) {
    require getInitializedVersion() == 0, "not yet initialized";
    initialize(e, up, lo);
    assert getInitializedVersion() == 1, "initialize did not set version to 1";
}

// P-15 — getRoleAdmin(SERVICE_ROLE) is permanently DEFAULT_ADMIN_ROLE; _setRoleAdmin is never called.
rule serviceRoleAdminNeverChanges(env e, method f, calldataarg args)
    filtered { f -> f.contract == currentContract && !f.isView } {
    bytes32 adminBefore = getRoleAdmin(SERVICE_ROLE());
    f(e, args);
    assert getRoleAdmin(SERVICE_ROLE()) == adminBefore,
        "getRoleAdmin(SERVICE_ROLE) changed";
}


// P-16 — A SERVICE_ROLE-only caller cannot grant DEFAULT_ADMIN_ROLE to any account.
rule noServiceToAdminEscalation(env e, method f, calldataarg args, address account)
    filtered { f -> commonFilters(f) && !isAdminTransferPath(f) } {
    require e.msg.sender != currentContract, "sender not self";
    require hasRole(SERVICE_ROLE(), e.msg.sender), "caller has SERVICE_ROLE";
    require !hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender), "caller not admin";

    bool adminBefore = hasRole(DEFAULT_ADMIN_ROLE(), account);

    f@withrevert(e, args);

    bool adminAfter = hasRole(DEFAULT_ADMIN_ROLE(), account);
    assert (adminAfter && !adminBefore) => false,
        "a SERVICE_ROLE-only caller caused DEFAULT_ADMIN_ROLE to be granted";
}

// P-17 — lastPrice.price can only be changed by setPrice (parametric complement to P-4 which guards the timestamp).
rule lastPriceValueOnlySetPrice(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) } {
    uint128 lpvBefore = getLastPriceValue();

    f(e, args);

    assert getLastPriceValue() != lpvBefore
        => f.selector == sig:setPrice(bytes32,uint128).selector,
        "lastPrice.price changed by a function other than setPrice";
}

// P-18 — When no price has been written yet, setPrice accepts any non-zero price (band check is skipped; closes gap left by P-2/P-3 requiring prev != 0).
rule firstPriceAlwaysAccepted(env e, bytes32 key, uint128 px) {
    require getLastPriceValue() == 0, "no prior price";
    require getPriceTimestamp(key) == 0, "key not yet written";
    require key != to_bytes32(0), "non-zero key";
    require px != 0, "non-zero price";

    setPrice(e, key, px);

    satisfy true, "setPrice must accept any valid first price when lastPrice is unset";
}

// P-19 — prices[bytes32(0)] is never written; the zero key is permanently rejected.
invariant zeroKeyNeverSet()
    getPriceTimestamp(to_bytes32(0)) == 0
    filtered { f -> !isInitialize(f) }
