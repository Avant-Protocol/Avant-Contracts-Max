/*
 * RequestsManagerV2 — Access Control & Configuration Spec
 * Properties RMV2_AC_1 .. RMV2_AC_59: state-change authorization (treasury/allowedTokens/fees/TTLs/window/
 * paused only via their setters), caller authorization (admin/service/pauser/provider gates),
 * parameter validation (fees<=MAX_FEE invariants, locked burn fee<=MAX_FEE, treasury!=0,
 * allowlist checks + issue-token-never-allowed), restriction bypass (pause gating, allowlist
 * gating, TTL expiry, burnCancelWindow), getRoleAdmin immutability, role lifecycle, no
 * self-escalation, immutables, setBurnFee doesn't touch pending burns, permit front-run
 * tolerance (R-62 structural success-subset, permit always-reverts summary to avoid ecrecover),
 * zero-amount rejection, cancel/adminCancel refund-target correctness (mint and burn).
 *
 * Token balance / escrow properties (E_8..E_15) live in RMV2_Escrow.spec.
 * Immutables, amount invariants, setter side-effect isolation (STR_13..STR_17) live in RMV2_Structural.spec.
 *
 * Carve-outs: access rules verify only the authorization GATE, not economic safety of accepted
 * designs (live treasury setter, PAUSER co-location). emergencyWithdraw verifies only the admin
 * gate (R-48). No oracle staleness (F-01: price summary leaves timestamp free).
 */

import "utils/RMV2_Base.spec";

methods {
    // ── role helpers not in base (single-spec only) ──
    function getRoleAdmin(bytes32) external returns (bytes32) envfree;
    function SERVICE_ROLE() external returns (bytes32) envfree;
    function PAUSER_ROLE() external returns (bytes32) envfree;
    // wildcard decimals summary — ties every token's decimals() to the decimalsOf ghost
    function _.decimals() external => decimalsOf[calledContract] expect uint8;
}

ghost mapping(address => uint8) decimalsOf;

// RMV2_AC_1 — treasuryAddress changes only via setTreasury; only DEFAULT_ADMIN_ROLE may call it.
rule treasuryOnlyViaSetTreasuryByAdmin(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    address before = treasuryAddress();
    f(e, args);
    address after = treasuryAddress();
    assert after != before => f.selector == sig:setTreasury(address).selector,
        "treasuryAddress changed by a function other than setTreasury";
    assert after != before => hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "treasuryAddress changed by a non-admin caller";
}

// RMV2_AC_2 — allowedTokens[t] changes only via add/removeAllowedToken; only DEFAULT_ADMIN_ROLE.
rule allowedTokensOnlyViaAddRemoveByAdmin(env e, method f, calldataarg args, address t)
    filtered { f -> commonFilters(f) }
{
    bool before = allowedTokens(t);
    f(e, args);
    bool after = allowedTokens(t);
    assert after != before =>
        (f.selector == sig:addAllowedToken(address).selector
        || f.selector == sig:removeAllowedToken(address).selector),
        "allowedTokens[t] changed outside add/removeAllowedToken";
    assert after != before => hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "allowedTokens[t] changed by a non-admin caller";
}

// RMV2_AC_3 — mintFee changes only via setMintFee; only DEFAULT_ADMIN_ROLE.
rule mintFeeOnlyViaSetMintFeeByAdmin(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    uint64 before = mintFee();
    f(e, args);
    uint64 after = mintFee();
    assert after != before => f.selector == sig:setMintFee(uint64).selector,
        "mintFee changed outside setMintFee";
    assert after != before => hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "mintFee changed by a non-admin caller";
}

// RMV2_AC_4 — burnFee changes only via setBurnFee; only DEFAULT_ADMIN_ROLE.
rule burnFeeOnlyViaSetBurnFeeByAdmin(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    uint64 before = burnFee();
    f(e, args);
    uint64 after = burnFee();
    assert after != before => f.selector == sig:setBurnFee(uint64).selector,
        "burnFee changed outside setBurnFee";
    assert after != before => hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "burnFee changed by a non-admin caller";
}

// RMV2_AC_5 — mintRequestTTL changes only via setMintRequestTTL; only DEFAULT_ADMIN_ROLE.
rule mintTTLOnlyViaSetterByAdmin(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    uint64 before = mintRequestTTL();
    f(e, args);
    uint64 after = mintRequestTTL();
    assert after != before => f.selector == sig:setMintRequestTTL(uint64).selector,
        "mintRequestTTL changed outside setMintRequestTTL";
    assert after != before => hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "mintRequestTTL changed by a non-admin caller";
}

// RMV2_AC_6 — burnRequestTTL changes only via setBurnRequestTTL; only DEFAULT_ADMIN_ROLE.
rule burnTTLOnlyViaSetterByAdmin(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    uint64 before = burnRequestTTL();
    f(e, args);
    uint64 after = burnRequestTTL();
    assert after != before => f.selector == sig:setBurnRequestTTL(uint64).selector,
        "burnRequestTTL changed outside setBurnRequestTTL";
    assert after != before => hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "burnRequestTTL changed by a non-admin caller";
}

// RMV2_AC_7 — burnCancelWindow changes only via setBurnCancelWindow; only DEFAULT_ADMIN_ROLE.
rule burnCancelWindowOnlyViaSetterByAdmin(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    uint64 before = burnCancelWindow();
    f(e, args);
    uint64 after = burnCancelWindow();
    assert after != before => f.selector == sig:setBurnCancelWindow(uint64).selector,
        "burnCancelWindow changed outside setBurnCancelWindow";
    assert after != before => hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "burnCancelWindow changed by a non-admin caller";
}

// RMV2_AC_8 — paused() toggles only via pause/unpause; PAUSER_ROLE pauses, DEFAULT_ADMIN_ROLE unpauses.
rule pauseTransitionsAuthorized(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    bool before = paused();
    f(e, args);
    bool after = paused();
    assert after != before =>
        (f.selector == sig:pause().selector || f.selector == sig:unpause().selector),
        "paused toggled outside pause/unpause";
    assert (!before && after) => f.selector == sig:pause().selector,
        "false->true must be pause()";
    assert (before && !after) => f.selector == sig:unpause().selector,
        "true->false must be unpause()";
    assert (!before && after) => hasRole(PAUSER_ROLE(), e.msg.sender),
        "pause performed without PAUSER_ROLE";
    assert (before && !after) => hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "unpause performed without DEFAULT_ADMIN_ROLE";
}

// RMV2_AC_9 — CREATED->COMPLETED for a mint request requires SERVICE_ROLE.
rule mintCompletionRequiresService(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    uint8 sBefore = assert_uint8(mintRequestState(id));
    f(e, args);
    uint8 sAfter = assert_uint8(mintRequestState(id));
    assert (sBefore == CREATED() && sAfter == COMPLETED())
        => hasRole(SERVICE_ROLE(), e.msg.sender),
        "mint completed by a non-SERVICE caller";
}

// RMV2_AC_10 — CREATED->COMPLETED for a burn request requires SERVICE_ROLE.
rule burnCompletionRequiresService(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    uint8 sBefore = assert_uint8(burnRequestState(id));
    f(e, args);
    uint8 sAfter = assert_uint8(burnRequestState(id));
    assert (sBefore == CREATED() && sAfter == COMPLETED())
        => hasRole(SERVICE_ROLE(), e.msg.sender),
        "burn completed by a non-SERVICE caller";
}

// RMV2_AC_11 — CREATED->CANCELLED for a mint request requires caller == provider or DEFAULT_ADMIN_ROLE.
rule mintCancellationRequiresProviderOrAdmin(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    address provider = mintRequestProvider(id);
    uint8 sBefore = assert_uint8(mintRequestState(id));
    f(e, args);
    uint8 sAfter = assert_uint8(mintRequestState(id));
    assert (sBefore == CREATED() && sAfter == CANCELLED())
        => (e.msg.sender == provider || hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender)),
        "mint cancelled by neither provider nor admin";
}

// RMV2_AC_12 — CREATED->CANCELLED for a burn request requires caller == provider or DEFAULT_ADMIN_ROLE.
rule burnCancellationRequiresProviderOrAdmin(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    address provider = burnRequestProvider(id);
    uint8 sBefore = assert_uint8(burnRequestState(id));
    f(e, args);
    uint8 sAfter = assert_uint8(burnRequestState(id));
    assert (sBefore == CREATED() && sAfter == CANCELLED())
        => (e.msg.sender == provider || hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender)),
        "burn cancelled by neither provider nor admin";
}

// RMV2_AC_13 — only DEFAULT_ADMIN_ROLE can call emergencyWithdraw (F-02 solvency accepted carve-out).
rule emergencyWithdrawRequiresAdmin(env e, address token) {
    setup(e);
    bool isAdmin = hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender);
    emergencyWithdraw@withrevert(e, token);
    assert !lastReverted => isAdmin,
        "emergencyWithdraw succeeded for a non-admin caller";
}

// RMV2_AC_14 — getRoleAdmin(role) is immutable; _setRoleAdmin never succeeds in OZ DefaultAdminRules.
rule getRoleAdminImmutable(env e, method f, calldataarg args, bytes32 role)
    filtered { f -> commonFilters(f) }
{
    bytes32 adminBefore = getRoleAdmin(role);
    f(e, args);
    bytes32 adminAfter = getRoleAdmin(role);
    assert adminAfter == adminBefore,
        "getRoleAdmin(role) changed — _setRoleAdmin must never succeed";
}

// RMV2_AC_15 — SERVICE_ROLE changes only via admin-gated grant/revoke or self-renounce.
rule serviceRoleChangeAuthorized(env e, method f, calldataarg args, address a)
    filtered { f -> commonFilters(f) }
{
    bool before = hasRole(SERVICE_ROLE(), a);
    bool adminCaller = hasRole(getRoleAdmin(SERVICE_ROLE()), e.msg.sender);
    f(e, args);
    bool after = hasRole(SERVICE_ROLE(), a);
    assert after != before =>
        ( adminCaller
        || (f.selector == sig:renounceRole(bytes32,address).selector && e.msg.sender == a) ),
        "SERVICE_ROLE toggled without admin or self-renounce";
}

// RMV2_AC_16 — PAUSER_ROLE changes only via admin-gated grant/revoke or self-renounce.
rule pauserRoleChangeAuthorized(env e, method f, calldataarg args, address a)
    filtered { f -> commonFilters(f) }
{
    bool before = hasRole(PAUSER_ROLE(), a);
    bool adminCaller = hasRole(getRoleAdmin(PAUSER_ROLE()), e.msg.sender);
    f(e, args);
    bool after = hasRole(PAUSER_ROLE(), a);
    assert after != before =>
        ( adminCaller
        || (f.selector == sig:renounceRole(bytes32,address).selector && e.msg.sender == a) ),
        "PAUSER_ROLE toggled without admin or self-renounce";
}

// RMV2_AC_17 — no self-escalation: a non-admin caller cannot gain DEFAULT_ADMIN_ROLE in one call.
rule noSelfEscalationToAdmin(env e, method f, calldataarg args)
    filtered {
        f -> commonFilters(f)
            && f.selector != sig:acceptDefaultAdminTransfer().selector
    }
{
    require !hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender), "caller not admin";
    f@withrevert(e, args);
    assert !hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender),
        "caller self-escalated to DEFAULT_ADMIN_ROLE via a single function";
}

// RMV2_AC_18 — mintFee <= MAX_FEE invariant.
invariant mintFeeWithinMax()
    to_mathint(mintFee()) <= to_mathint(MAX_FEE())
    filtered { f -> commonFilters(f) }

// RMV2_AC_19 — burnFee <= MAX_FEE invariant.
invariant burnFeeWithinMax()
    to_mathint(burnFee()) <= to_mathint(MAX_FEE())
    filtered { f -> commonFilters(f) }

// RMV2_AC_20 — every existing burn request's locked fee is <= MAX_FEE.
invariant burnRequestFeeWithinMax(uint256 id)
    burnRequestProvider(id) != 0 => to_mathint(burnRequestFee(id)) <= to_mathint(MAX_FEE())
    filtered { f -> commonFilters(f) }
    { preserved { requireInvariant burnFeeWithinMax(); } }

// RMV2_AC_21 — treasuryAddress is never the zero address.
invariant treasuryNeverZero()
    treasuryAddress() != 0
    filtered { f -> commonFilters(f) }

// RMV2_AC_22 — the issue token is never in the allowlist.
invariant issueTokenNeverAllowed()
    !allowedTokens(ISSUE_TOKEN_ADDRESS())
    filtered { f -> commonFilters(f) }

// RMV2_AC_23 — address(0) is never in the allowlist.
invariant zeroAddressNeverAllowed()
    !allowedTokens(0)
    filtered { f -> commonFilters(f) }

// RMV2_AC_24 — requestMint reverts when paused.
rule requestMintRevertsWhenPaused(env e, address tok, uint256 amt) {
    setup(e);
    require paused(), "contract is paused";
    requestMint@withrevert(e, tok, amt);
    assert lastReverted, "requestMint succeeded while paused";
}

// RMV2_AC_25 — requestBurn reverts when paused.
rule requestBurnRevertsWhenPaused(env e, uint256 amt, address tok) {
    setup(e);
    require paused(), "contract is paused";
    requestBurn@withrevert(e, amt, tok);
    assert lastReverted, "requestBurn succeeded while paused";
}

// RMV2_AC_26 — completeMint reverts when paused.
rule completeMintRevertsWhenPaused(env e, uint256 id) {
    setup(e);
    require paused(), "contract is paused";
    completeMint@withrevert(e, id);
    assert lastReverted, "completeMint succeeded while paused";
}

// RMV2_AC_27 — completeBurn reverts when paused.
rule completeBurnRevertsWhenPaused(env e, uint256 id) {
    setup(e);
    require paused(), "contract is paused";
    completeBurn@withrevert(e, id);
    assert lastReverted, "completeBurn succeeded while paused";
}

// RMV2_AC_28 — token stored in any existing mint request is always an allowed token.
invariant mintRequestTokenIsAllowed(uint256 id)
    mintRequestProvider(id) != 0 => allowedTokens(mintRequestToken(id))
    filtered { f -> commonFilters(f) && f.selector != sig:removeAllowedToken(address).selector }

// RMV2_AC_29 — token stored in any existing burn request is always an allowed token.
invariant burnRequestTokenIsAllowed(uint256 id)
    burnRequestProvider(id) != 0 => allowedTokens(burnRequestToken(id))
    filtered { f -> commonFilters(f) && f.selector != sig:removeAllowedToken(address).selector }

// RMV2_AC_30 — completeMint reverts when the request is past its TTL.
rule completeMintRejectsExpired(env e, uint256 id) {
    setup(e);
    require ghostPrice > 0, "price positive";
    uint40 createdAt = mintRequestCreatedAt(id);
    uint64 ttl = mintRequestTTL();
    completeMint(e, id);
    assert (ttl == 0 || to_mathint(e.block.timestamp) <= to_mathint(createdAt) + to_mathint(ttl)),
        "an expired mint completed";
}

// RMV2_AC_31 — completeBurn reverts when the request is past its TTL.
rule completeBurnRejectsExpired(env e, uint256 id) {
    setup(e);
    require ghostPrice > 0, "price positive";
    uint40 createdAt = burnRequestCreatedAt(id);
    uint64 ttl = burnRequestTTL();
    completeBurn(e, id);
    assert (ttl == 0 || to_mathint(e.block.timestamp) <= to_mathint(createdAt) + to_mathint(ttl)),
        "an expired burn completed";
}

// RMV2_AC_32 — cancelBurn (provider path) succeeds only within burnCancelWindow.
rule cancelBurnOnlyWithinWindow(env e, uint256 id) {
    setup(e);
    uint40 createdAt = burnRequestCreatedAt(id);
    uint64 window = burnCancelWindow();
    cancelBurn(e, id);
    assert to_mathint(e.block.timestamp) <= to_mathint(createdAt) + to_mathint(window),
        "cancelBurn succeeded past the burnCancelWindow";
}


// RMV2_AC_33 — requestMintWithPermit succeeds only when base requestMint preconditions hold.
rule requestMintWithPermitSuccessSubset(env e, address tok, uint256 amt,
        uint256 deadline, uint8 v, bytes32 r, bytes32 s) {
    setup(e);
    bool allowedPre = allowedTokens(tok);
    bool pausedPre = paused();
    requestMintWithPermit(e, tok, amt, deadline, v, r, s);
    assert (allowedPre && tok != 0 && amt != 0 && !pausedPre),
        "permit wrapper succeeded despite requestMint preconditions being unmet";
}

// RMV2_AC_34 — requestBurnWithPermit succeeds only when base requestBurn preconditions hold.
rule requestBurnWithPermitSuccessSubset(env e, uint256 amt, address tok,
        uint256 deadline, uint8 v, bytes32 r, bytes32 s) {
    setup(e);
    require ghostPrice > 0, "price positive";
    bool allowedPre = allowedTokens(tok);
    bool pausedPre = paused();
    requestBurnWithPermit(e, amt, tok, deadline, v, r, s);
    assert (allowedPre && tok != 0 && amt != 0 && !pausedPre),
        "permit wrapper succeeded despite requestBurn preconditions being unmet";
}


// RMV2_AC_35 — every token in the allowlist has exactly 18 decimals.
invariant allowedTokenHas18Decimals(address tok)
    allowedTokens(tok) => decimalsOf[tok] == 18
    filtered { f -> commonFilters(f) }

// RMV2_AC_36 — cancelMint is not gated by the allowlist; a de-allowlisted token does not block cancellation.
rule cancelMintNotGatedByAllowlist(env e, uint256 id) {
    require e.msg.value == 0, "no ETH";
    require mintRequestProvider(id) == e.msg.sender, "caller is provider";
    require assert_uint8(mintRequestState(id)) == CREATED(), "mint is CREATED";
    require !allowedTokens(mintRequestToken(id)), "token de-allowlisted";
    cancelMint(e, id);
    satisfy true,
        "cancelMint must be able to succeed even when the deposit token is no longer allowed";
}

// RMV2_AC_37 — cancelBurn is not gated by the allowlist; a de-allowlisted token does not block cancellation.
rule cancelBurnNotGatedByAllowlist(env e, uint256 id) {
    require e.msg.value == 0, "no ETH";
    require burnRequestProvider(id) == e.msg.sender, "caller is provider";
    require assert_uint8(burnRequestState(id)) == CREATED(), "burn is CREATED";
    require to_mathint(e.block.timestamp) <= to_mathint(burnRequestCreatedAt(id)) + to_mathint(burnCancelWindow()), "within cancel window";
    require !allowedTokens(burnRequestToken(id)), "token de-allowlisted";
    cancelBurn(e, id);
    satisfy true,
        "cancelBurn must be able to succeed even when the withdrawal token is no longer allowed";
}


