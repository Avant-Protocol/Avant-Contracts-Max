/*
 * SimpleToken — Core Spec (properties ST_CORE_1 .. ST_CORE_28)
 *
 * Verified contract: SimpleTokenHarness (extends SimpleToken).
 *
 * Idempotency (ST_CORE_1..ST_CORE_13), Access Control (ST_CORE_14..ST_CORE_23),
 * Signatures (ST_CORE_24..ST_CORE_26), Initializer (ST_CORE_27..ST_CORE_28).
 *
 * mintIds/burnIds are private SimpleToken-local mappings, hookable by name at the
 * storage-slot level (Gotcha 206). They are mirrored into ghosts and read via the
 * CVL helpers mintIdsUsedCVL(key) / burnIdsUsedCVL(key).
 *
 * Overloaded mint/burn are always referenced by full signature (Guardrail 1).
 */

methods {
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function allowance(address, address) external returns (uint256) envfree;
    function nonces(address) external returns (uint256) envfree;
    function SERVICE_ROLE() external returns (bytes32) envfree;
    function DEFAULT_ADMIN_ROLE() external returns (bytes32) envfree;
    function hasRole(bytes32, address) external returns (bool) envfree;
    function getRoleAdmin(bytes32) external returns (bytes32) envfree;
    function isInitialized() external returns (bool) envfree;
    function defaultAdmin() external returns (address) envfree;
    function pendingDefaultAdmin() external returns (address, uint48) envfree;
}

/* -------------------------------------------------------------------------- */
/*  Ghosts + hooks: mirror private mintIds / burnIds mappings                  */
/* -------------------------------------------------------------------------- */

persistent ghost mapping(bytes32 => bool) ghostMintIds {
    init_state axiom forall bytes32 k. ghostMintIds[k] == false;
}
persistent ghost mapping(bytes32 => bool) ghostBurnIds {
    init_state axiom forall bytes32 k. ghostBurnIds[k] == false;
}

hook Sload bool val mintIds[KEY bytes32 key] {
    require ghostMintIds[key] == val;
}
hook Sstore mintIds[KEY bytes32 key] bool val {
    ghostMintIds[key] = val;
}

hook Sload bool val burnIds[KEY bytes32 key] {
    require ghostBurnIds[key] == val;
}
hook Sstore burnIds[KEY bytes32 key] bool val {
    ghostBurnIds[key] = val;
}

function mintIdsUsedCVL(bytes32 key) returns bool {
    return ghostMintIds[key];
}
function burnIdsUsedCVL(bytes32 key) returns bool {
    return ghostBurnIds[key];
}

/* -------------------------------------------------------------------------- */
/*  Filters                                                                    */
/* -------------------------------------------------------------------------- */

definition commonFilters(method f) returns bool =
    f.contract == currentContract
    && f.selector != sig:initialize(string,string).selector;

// ST_CORE_1 — mintIds[key] once set to true is never reset.
rule mintIdsMonotonic(env e, method f, calldataarg args, bytes32 key)
    filtered { f -> commonFilters(f) } {
    bool before = mintIdsUsedCVL(key);
    f(e, args);
    assert before => mintIdsUsedCVL(key),
        "mintIds[key] must never be reset from true to false";
}

// ST_CORE_2 — burnIds[key] once set to true is never reset.
rule burnIdsMonotonic(env e, method f, calldataarg args, bytes32 key)
    filtered { f -> commonFilters(f) } {
    bool before = burnIdsUsedCVL(key);
    f(e, args);
    assert before => burnIdsUsedCVL(key),
        "burnIds[key] must never be reset from true to false";
}

// ST_CORE_3 — keyed mint with an already-used key reverts.
rule keyedMintUsedKeyReverts(env e, bytes32 key, address account, uint256 amt) {
    require e.msg.value == 0, "no ETH";
    require hasRole(SERVICE_ROLE(), e.msg.sender), "caller has SERVICE_ROLE";
    require mintIdsUsedCVL(key), "key already used";

    mint@withrevert(e, key, account, amt);
    assert lastReverted, "keyed mint with an already-used key must revert";
}

// ST_CORE_4 — keyed burn with an already-used key reverts.
rule keyedBurnUsedKeyReverts(env e, bytes32 key, address account, uint256 amt) {
    require e.msg.value == 0, "no ETH";
    require hasRole(SERVICE_ROLE(), e.msg.sender), "caller has SERVICE_ROLE";
    require burnIdsUsedCVL(key), "key already used";

    burn@withrevert(e, key, account, amt);
    assert lastReverted, "keyed burn with an already-used key must revert";
}

// ST_CORE_5 — keyed mint is one-shot: a second call with the same key always reverts.
rule keyedMintOneShot(env e, env e2, bytes32 key, address a, uint256 x, address b, uint256 y) {
    require e.msg.value == 0 && e2.msg.value == 0, "no ETH";
    require hasRole(SERVICE_ROLE(), e.msg.sender), "caller has SERVICE_ROLE";
    require hasRole(SERVICE_ROLE(), e2.msg.sender), "e2 has SERVICE_ROLE";

    mint(e, key, a, x);
    mint@withrevert(e2, key, b, y);
    assert lastReverted, "a second keyed mint with the same key must revert";
}

// ST_CORE_6 — keyed burn is one-shot: a second call with the same key always reverts.
rule keyedBurnOneShot(env e, env e2, bytes32 key, address a, uint256 x, address b, uint256 y) {
    require e.msg.value == 0 && e2.msg.value == 0, "no ETH";
    require hasRole(SERVICE_ROLE(), e.msg.sender), "caller has SERVICE_ROLE";
    require hasRole(SERVICE_ROLE(), e2.msg.sender), "e2 has SERVICE_ROLE";

    burn(e, key, a, x);
    burn@withrevert(e2, key, b, y);
    assert lastReverted, "a second keyed burn with the same key must revert";
}

// ST_CORE_7 — keyed mint writes exactly its own mintIds key; no collateral writes.
rule keyedMintWriteIsolation(env e, bytes32 key, address account, uint256 amt, bytes32 k) {
    require k != key, "different key";
    bool otherBefore = mintIdsUsedCVL(k);

    mint(e, key, account, amt);

    assert mintIdsUsedCVL(key), "keyed mint must set its own key";
    assert mintIdsUsedCVL(k) == otherBefore, "keyed mint must not write any other mintIds key";
}

// ST_CORE_8 — keyed burn writes exactly its own burnIds key; no collateral writes.
rule keyedBurnWriteIsolation(env e, bytes32 key, address account, uint256 amt, bytes32 k) {
    require k != key, "different key";
    bool otherBefore = burnIdsUsedCVL(k);

    burn(e, key, account, amt);

    assert burnIdsUsedCVL(key), "keyed burn must set its own key";
    assert burnIdsUsedCVL(k) == otherBefore, "keyed burn must not write any other burnIds key";
}

// ST_CORE_9 — keyed mint never writes burnIds.
rule keyedMintDoesNotTouchBurnIds(env e, bytes32 key, address account, uint256 amt, bytes32 k) {
    bool burnBefore = burnIdsUsedCVL(k);
    mint(e, key, account, amt);
    assert burnIdsUsedCVL(k) == burnBefore, "keyed mint must never write burnIds";
}

// ST_CORE_10 — keyed burn never writes mintIds.
rule keyedBurnDoesNotTouchMintIds(env e, bytes32 key, address account, uint256 amt, bytes32 k) {
    bool mintBefore = mintIdsUsedCVL(k);
    burn(e, key, account, amt);
    assert mintIdsUsedCVL(k) == mintBefore, "keyed burn must never write mintIds";
}

// ST_CORE_11 — the same key value is independently consumable across the mint and burn namespaces.
rule sameKeyReusableAcrossNamespaces(env e, env e2, bytes32 key, address a, uint256 x, address c, uint256 y) {
    require e.msg.value == 0 && e2.msg.value == 0, "no ETH";
    require hasRole(SERVICE_ROLE(), e.msg.sender), "caller has SERVICE_ROLE";
    require hasRole(SERVICE_ROLE(), e2.msg.sender), "e2 has SERVICE_ROLE";
    require !mintIdsUsedCVL(key), "mint key unused";
    require !burnIdsUsedCVL(key), "burn key unused";

    mint(e, key, a, x);
    assert !burnIdsUsedCVL(key), "keyed mint must leave burnIds[key] free";

    burn@withrevert(e2, key, c, y);
    satisfy !lastReverted, "the same key value must be independently usable for burn after mint";
}

// ST_CORE_12 — mintIds[key] may change only via keyed mint(bytes32,address,uint256).
rule mintIdsWrittenOnlyByKeyedMint(env e, method f, calldataarg args, bytes32 key)
    filtered { f -> commonFilters(f) } {
    bool before = mintIdsUsedCVL(key);
    f(e, args);
    assert mintIdsUsedCVL(key) != before =>
        f.selector == sig:mint(bytes32,address,uint256).selector,
        "mintIds[key] may change only via keyed mint(bytes32,address,uint256)";
}

// ST_CORE_13 — burnIds[key] may change only via keyed burn(bytes32,address,uint256).
rule burnIdsWrittenOnlyByKeyedBurn(env e, method f, calldataarg args, bytes32 key)
    filtered { f -> commonFilters(f) } {
    bool before = burnIdsUsedCVL(key);
    f(e, args);
    assert burnIdsUsedCVL(key) != before =>
        f.selector == sig:burn(bytes32,address,uint256).selector,
        "burnIds[key] may change only via keyed burn(bytes32,address,uint256)";
}

// ST_CORE_14 — totalSupply may increase only when caller holds SERVICE_ROLE.
rule supplyIncreaseRequiresServiceRole(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) } {
    uint256 before = totalSupply();
    f(e, args);
    assert totalSupply() > before => hasRole(SERVICE_ROLE(), e.msg.sender),
        "totalSupply may increase (mint) only when caller holds SERVICE_ROLE";
}

// ST_CORE_15 — totalSupply may decrease only when caller holds SERVICE_ROLE.
rule supplyDecreaseRequiresServiceRole(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) } {
    uint256 before = totalSupply();
    f(e, args);
    assert totalSupply() < before => hasRole(SERVICE_ROLE(), e.msg.sender),
        "totalSupply may decrease (burn) only when caller holds SERVICE_ROLE";
}

// ST_CORE_16 — getRoleAdmin(SERVICE_ROLE) is immutable; _setRoleAdmin never succeeds in SimpleToken.
rule serviceRoleAdminNeverChanges(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) } {
    bytes32 adminBefore = getRoleAdmin(SERVICE_ROLE());
    f(e, args);
    assert getRoleAdmin(SERVICE_ROLE()) == adminBefore,
        "getRoleAdmin(SERVICE_ROLE) must never change";
}

// ST_CORE_17 — getRoleAdmin(SERVICE_ROLE) == DEFAULT_ADMIN_ROLE invariant (inductive; _setRoleAdmin never called).
invariant serviceRoleAdminIsDefaultAdmin()
    getRoleAdmin(SERVICE_ROLE()) == DEFAULT_ADMIN_ROLE()
    filtered { f -> f.selector != sig:initialize(string,string).selector }

// ST_CORE_18 — hasRole(DEFAULT_ADMIN_ROLE, a) <=> (a != 0 && a == defaultAdmin()) OZ coupling invariant.
invariant defaultAdminRoleCoupledToSlot(address a)
    hasRole(DEFAULT_ADMIN_ROLE(), a) <=> (a != 0 && a == defaultAdmin())
    filtered { f -> f.selector != sig:initialize(string,string).selector }
    {
        preserved with (env eInv) {
            requireInvariant defaultAdminRoleCoupledToSlot(defaultAdmin());
            address pendingAdmin;
            uint48 pendingSchedule;
            pendingAdmin, pendingSchedule = pendingDefaultAdmin();
            requireInvariant defaultAdminRoleCoupledToSlot(pendingAdmin);

            require eInv.msg.sender != 0,
                "safe: address(0) can never be msg.sender of a real transaction";
        }
    }

// ST_CORE_19 — at most one DEFAULT_ADMIN_ROLE holder at any time.
invariant atMostOneDefaultAdmin(address x, address y)
    (x != y && x != 0 && y != 0)
        => !(hasRole(DEFAULT_ADMIN_ROLE(), x) && hasRole(DEFAULT_ADMIN_ROLE(), y))
    filtered { f -> f.selector != sig:initialize(string,string).selector }
    {
        preserved {
            requireInvariant defaultAdminRoleCoupledToSlot(x);
            requireInvariant defaultAdminRoleCoupledToSlot(y);
        }
    }

// ST_CORE_20 — grantRole(DEFAULT_ADMIN_ROLE, ...) always reverts (DefaultAdminRules).
rule grantDefaultAdminReverts(env e, address account) {
    grantRole@withrevert(e, DEFAULT_ADMIN_ROLE(), account);
    assert lastReverted, "grantRole(DEFAULT_ADMIN_ROLE, ...) must revert (DefaultAdminRules)";
}

// ST_CORE_21 — revokeRole(DEFAULT_ADMIN_ROLE, ...) always reverts (DefaultAdminRules).
rule revokeDefaultAdminReverts(env e, address account) {
    revokeRole@withrevert(e, DEFAULT_ADMIN_ROLE(), account);
    assert lastReverted, "revokeRole(DEFAULT_ADMIN_ROLE, ...) must revert (DefaultAdminRules)";
}

definition isAcceptDefaultAdmin(method f) returns bool =
    f.selector == sig:acceptDefaultAdminTransfer().selector;

// ST_CORE_22 — SERVICE_ROLE holder cannot self-escalate to DEFAULT_ADMIN_ROLE in one call.
rule serviceRoleNoEscalation(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) && !isAcceptDefaultAdmin(f) } {
    require hasRole(SERVICE_ROLE(), e.msg.sender), "caller has SERVICE_ROLE";
    require !hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender), "caller not admin";
    f@withrevert(e, args);
    assert !hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "SERVICE_ROLE holder must not self-escalate to DEFAULT_ADMIN_ROLE in one call";
}

// ST_CORE_23 — acceptDefaultAdminTransfer can only grant DEFAULT_ADMIN_ROLE to the scheduled pendingDefaultAdmin.
rule acceptOnlyGrantsToScheduledPendingAdmin(env e) {
    require e.msg.value == 0, "no ETH";
    require !hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender), "caller not admin";

    address pendingBefore;
    uint48 scheduleBefore;
    pendingBefore, scheduleBefore = pendingDefaultAdmin();

    acceptDefaultAdminTransfer(e);

    assert hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender) =>
        e.msg.sender == pendingBefore,
        "acceptDefaultAdminTransfer may only grant DEFAULT_ADMIN_ROLE to the scheduled pendingDefaultAdmin";
}

// ST_CORE_24 — permit reverts once block.timestamp > deadline.
rule permitRespectsDeadline(env e, address owner, address spender, uint256 value,
                            uint256 deadline, uint8 v, bytes32 r, bytes32 s) {
    require e.msg.value == 0, "no ETH";
    permit@withrevert(e, owner, spender, value, deadline, v, r, s);
    assert !lastReverted => e.block.timestamp <= deadline,
        "permit must revert once block.timestamp exceeds deadline";
}

// ST_CORE_25 — successful permit sets allowance == value and increments nonces(owner) by exactly 1.
rule permitSuccessPostCondition(env e, address owner, address spender, uint256 value,
                                uint256 deadline, uint8 v, bytes32 r, bytes32 s) {
    mathint nonceBefore = to_mathint(nonces(owner));
    require nonceBefore < max_uint256,
        "safe: 2^256-1 permits for a single owner is physically unreachable (Gotcha 164)";

    permit@withrevert(e, owner, spender, value, deadline, v, r, s);
    bool reverted = lastReverted;

    assert !reverted => allowance(owner, spender) == value,
        "successful permit must set allowance(owner, spender) == value";
    assert !reverted => to_mathint(nonces(owner)) == nonceBefore + 1,
        "successful permit must increment nonces(owner) by exactly 1";
    assert !reverted => e.block.timestamp <= deadline,
        "successful permit implies the deadline was not exceeded";
}

// ST_CORE_26 — nonces(owner) is monotonic non-decreasing and changes only via permit.
rule nonceMonotonicAndOnlyPermit(env e, method f, calldataarg args, address owner)
    filtered { f -> commonFilters(f) } {
    mathint before = to_mathint(nonces(owner));
    require before < max_uint256,
        "safe: 2^256-1 permits for a single owner is physically unreachable (Gotcha 164)";
    f(e, args);
    mathint after = to_mathint(nonces(owner));
    assert after >= before, "nonces(owner) must be non-decreasing";
    assert after != before => f.selector == sig:permit(address,address,uint256,uint256,uint8,bytes32,bytes32).selector,
        "nonces(owner) may change only via permit";
}

// ST_CORE_27 — initialize is callable at most once (sequential form).
rule initializeAtMostOnce(
    env e,
    env e2,
    string name,
    string symbol,
    string name2,
    string symbol2
) {
    require e.msg.value == 0 && e2.msg.value == 0, "no ETH";
    initialize(e, name, symbol);
    initialize@withrevert(e2, name2, symbol2);
    assert lastReverted, "a second initialize must revert";
}

// ST_CORE_28 — initialize reverts when the contract is already initialized.
rule initializeRevertsWhenInitialized(env e, string name, string symbol) {
    require e.msg.value == 0, "no ETH";
    require isInitialized(), "already initialized";
    initialize@withrevert(e, name, symbol);
    assert lastReverted, "initialize must revert once the contract is initialized";
}
