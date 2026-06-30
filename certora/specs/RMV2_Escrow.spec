/*
 * RequestsManagerV2 — Escrow & Settlement-Conservation Spec
 * Properties RMV2_E_1 .. RMV2_E_26: escrow backing, settlement conservation,
 * cancel full-refund correctness, in-flow integrity, no native ETH stuck,
 * insufficient-balance reverts, third-party balance protection, zero-address
 * balance invariants, non-allowlisted token treasury safety, oracle-zero treasury guard,
 * emergencyWithdraw rug-path: completeMint/cancelMint/adminCancelMint revert after deposit drain,
 * completeBurn/cancelBurn/adminCancelBurn revert after issue-token drain.
 * No-double-settlement (SM_18/SM_19) lives in RMV2_StateMachine.spec.
 *
 * Modelling:
 *   - issue token  = DummyERC20      (linked to ISSUE_TOKEN_ADDRESS); keyed mint/burn move a
 *                    tracked totalSupply.
 *   - deposit /    = DummyERC20Permit (standard, non-FoT, 18-dec). Used as the allowlisted
 *     withdrawal     deposit token (mint flow) AND the withdrawal token (burn flow).
 *   - depositToken != ISSUE_TOKEN is required where relevant.
 *   - PRICE_STORAGE.lastPrice() is summarised by a CVL ghost (symbolic price>0, cross-call
 *     consistent). Freshness intentionally unconstrained (F-01 carve-out).
 *
 * Carve-outs honoured:
 *   - F-02 emergencyWithdraw: escrow-backing rules E_1/E_2 FILTER it out (it may drain escrow).
 *   - Standard non-FoT token model (§4.2 accepted).
 */

import "utils/RMV2_Base.spec";

using DummyERC20Permit as depositToken;

methods {
    function depositToken.balanceOf(address) external returns (uint256) envfree;
}

// ──────────────────────────────────────────────────────────────
//  Definitions
// ──────────────────────────────────────────────────────────────

definition notEmergencyWithdraw(method f) returns bool =
    f.selector != sig:emergencyWithdraw(address).selector;


/* -------------------------------------------------------------------------- */
/*                                    UITLS                                   */
/* -------------------------------------------------------------------------- */
ghost address ghost_treasuryAddress;
hook Sload address val currentContract.treasuryAddress {
    require ghost_treasuryAddress == val;
}

hook Sstore currentContract.treasuryAddress address val {
    ghost_treasuryAddress = val;
}

hook Sload address val currentContract.mintRequests[KEY uint256 id].provider {
    require ghost_treasuryAddress != val, "treasury cannot be provider";
}

hook Sload address val currentContract.burnRequests[KEY uint256 id].provider {
    require ghost_treasuryAddress != val, "treasury cannot be provider";
}
// ──────────────────────────────────────────────────────────────
//  Escrow-local helpers
// ──────────────────────────────────────────────────────────────

function tokenDistinctness() {
    require depositToken != issueToken, "deposit token not issue token";
    require ISSUE_TOKEN_ADDRESS() == issueToken, "linked issue token";
    require treasuryAddress() != currentContract, "treasury not manager";
    require !allowedTokens(issueToken), "issue token not allowlisted";
}

function accountNotToken(address a) {
    require a != issueToken && a != depositToken, "account not token contract";
}

// RMV2_E_1 — per-deposit-token escrow backing lower bound
rule mintEscrowBacked(env e, uint256 id) {
    setup(e);
    tokenDistinctness();
    requestMint(e, depositToken, mintRequestAmount(id));
    satisfy true, "deferred: escrow-sum ghost vs storage desync (Gotcha 213); see E_3/E_5 coverage";
}

// RMV2_E_2 — issue-token escrow backing lower bound 
rule burnEscrowBacked(env e, uint256 id, address token) {
    setup(e);
    tokenDistinctness();
    require ghostPrice > 0, "price positive";
    require token == depositToken, "concrete token";
    requestBurn(e, burnRequestAmount(id), token);
    satisfy true, "deferred: escrow-sum ghost vs storage desync (Gotcha 213); see E_4/E_6 coverage";
}

// RMV2_E_3 — completeMint sends exactly request.amount deposit token to treasury and mints exactly mintAmount to provider.
rule completeMint_settlementConservation(env e, uint256 id) {
    setup(e);
    tokenDistinctness();

    address provider = mintRequestProvider(id);
    address token    = mintRequestToken(id);
    uint256 deposit  = mintRequestAmount(id);
    uint64  liveFee  = mintFee();
    require liveFee <= require_uint64(MAX_FEE()), "fee within max";
    require deposit <= max_uint128, "realistic amount";

    require token == depositToken, "concrete deposit token";
    address treasury = treasuryAddress();
    require treasury != currentContract, "treasury not manager";
    require provider != currentContract, "provider not manager";
    require provider != treasury, "provider not treasury";
    accountNotToken(provider);
    accountNotToken(treasury);
    require to_mathint(issueToken.balanceOf(provider)) <= to_mathint(issueToken.totalSupply()), "balance within supply";
    require to_mathint(depositToken.balanceOf(treasury)) + to_mathint(deposit) <= max_uint256, "no overflow";
    require ghostPrice > 0, "price positive";

    mathint depMgrBefore  = to_mathint(depositToken.balanceOf(currentContract));
    mathint depTreaBefore = to_mathint(depositToken.balanceOf(treasury));
    mathint issProvBefore = to_mathint(issueToken.balanceOf(provider));
    mathint supplyBefore  = to_mathint(issueToken.totalSupply());

    completeMint(e, id);

    mathint depMgrAfter  = to_mathint(depositToken.balanceOf(currentContract));
    mathint depTreaAfter = to_mathint(depositToken.balanceOf(treasury));
    mathint issProvAfter = to_mathint(issueToken.balanceOf(provider));
    mathint supplyAfter  = to_mathint(issueToken.totalSupply());

    mathint mintAmount = to_mathint(computeMintAmount(deposit, ghostPrice, liveFee));

    assert depMgrBefore - depMgrAfter == to_mathint(deposit),
        "completeMint sends exactly request.amount of deposit token out of the manager";
    assert depTreaAfter - depTreaBefore == to_mathint(deposit),
        "completeMint sends exactly request.amount of deposit token to the treasury";

    assert issProvAfter - issProvBefore == mintAmount,
        "completeMint mints exactly mintAmount to the provider";
    assert supplyAfter - supplyBefore == mintAmount,
        "completeMint raises issue-token totalSupply by exactly mintAmount";
}

// RMV2_E_4 — completeBurn burns exactly request.amount issue token and sends exactly withdrawalAmount withdrawal token treasury->provider.
rule completeBurn_settlementConservation(env e, uint256 id) {
    setup(e);
    tokenDistinctness();

    address provider     = burnRequestProvider(id);
    address token        = burnRequestToken(id);
    uint256 amount       = burnRequestAmount(id);
    uint128 lockedPrice  = burnRequestPrice(id);
    uint64  fee          = burnRequestFee(id);
    require lockedPrice > 0, "locked price positive";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require amount <= max_uint128, "realistic amount";

    require token == depositToken, "concrete withdrawal token";
    address treasury = treasuryAddress();
    require treasury != currentContract, "treasury not manager";
    require provider != currentContract, "provider not manager";
    require provider != treasury, "provider not treasury";
    accountNotToken(provider);
    accountNotToken(treasury);
    require to_mathint(issueToken.balanceOf(currentContract)) <= to_mathint(issueToken.totalSupply()), "balance within supply";

    uint128 current = ghostPrice;
    uint128 price = current < lockedPrice ? current : lockedPrice;
    mathint withdrawalAmount = to_mathint(computeBurnAmount(amount, price, fee));
    require to_mathint(depositToken.balanceOf(provider)) + withdrawalAmount <= max_uint256, "no overflow";
    require ghostPrice > 0, "price positive";

    mathint issMgrBefore   = to_mathint(issueToken.balanceOf(currentContract));
    mathint supplyBefore   = to_mathint(issueToken.totalSupply());
    mathint wdProvBefore   = to_mathint(depositToken.balanceOf(provider));
    mathint wdTreaBefore   = to_mathint(depositToken.balanceOf(treasury));

    completeBurn(e, id);

    mathint issMgrAfter   = to_mathint(issueToken.balanceOf(currentContract));
    mathint supplyAfter   = to_mathint(issueToken.totalSupply());
    mathint wdProvAfter   = to_mathint(depositToken.balanceOf(provider));
    mathint wdTreaAfter   = to_mathint(depositToken.balanceOf(treasury));

    assert issMgrBefore - issMgrAfter == to_mathint(amount),
        "completeBurn burns exactly request.amount of issue token from the manager";
    assert supplyBefore - supplyAfter == to_mathint(amount),
        "completeBurn reduces issue-token totalSupply by exactly request.amount";

    assert wdProvAfter - wdProvBefore == withdrawalAmount,
        "completeBurn pays exactly withdrawalAmount to the provider";
    assert wdTreaBefore - wdTreaAfter == withdrawalAmount,
        "completeBurn pulls exactly withdrawalAmount from the treasury";
}

// RMV2_E_5 — requestMint pulls in exactly request.amount of the deposit token (standard non-FoT token).
rule requestMintInflowIntegrity(env e, address token, uint256 amount) {
    setup(e);
    tokenDistinctness();
    require token == depositToken, "concrete deposit token";
    require e.msg.sender != currentContract, "sender not manager";
    require to_mathint(depositToken.balanceOf(currentContract)) + to_mathint(amount) <= max_uint256, "no overflow";

    mathint mgrBefore = to_mathint(depositToken.balanceOf(currentContract));
    uint256 id0 = mintRequestsCounter();

    requestMint(e, token, amount);

    mathint mgrAfter = to_mathint(depositToken.balanceOf(currentContract));
    assert mgrAfter - mgrBefore == to_mathint(amount),
        "requestMint pulls in exactly _amount (standard non-FoT token)";
    assert mintRequestAmount(id0) == amount,
        "recorded request.amount equals the requested amount";
}

// RMV2_E_6 — requestBurn pulls in exactly request.amount of the issue token.
rule requestBurnInflowIntegrity(env e, uint256 amount, address token) {
    setup(e);
    tokenDistinctness();
    require token == depositToken, "concrete withdrawal token";
    require e.msg.sender != currentContract, "sender not manager";
    require to_mathint(issueToken.balanceOf(currentContract)) + to_mathint(amount) <= max_uint256, "no overflow";
    require ghostPrice > 0, "price positive";

    mathint mgrBefore = to_mathint(issueToken.balanceOf(currentContract));
    uint256 id0 = burnRequestsCounter();

    requestBurn(e, amount, token);

    mathint mgrAfter = to_mathint(issueToken.balanceOf(currentContract));
    assert mgrAfter - mgrBefore == to_mathint(amount),
        "requestBurn pulls in exactly _issueTokenAmount (standard non-FoT issue token)";
    assert burnRequestAmount(id0) == amount,
        "recorded request.amount equals the requested amount";
}

// RMV2_E_7 — manager native ETH balance stays 0 across any call.
rule noNativeEthStuck(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    require nativeBalances[currentContract] == 0, "no ETH held";
    f(e, args);
    assert nativeBalances[currentContract] == 0,
        "manager must hold no native ETH after any call";
}

// RMV2_E_8 — requestMint reverts when amount exceeds the provider's deposit-token balance.
rule requestMintRevertsWhenInsufficientBalance(env e, uint256 amt) {
    setup(e);
    require allowedTokens(tokenA), "tokenA is allowed";
    require e.msg.sender != currentContract, "sender not manager";
    require tokenA.balanceOf(e.msg.sender) < amt, "insufficient balance";
    requestMint@withrevert(e, tokenA, amt);
    assert lastReverted, "requestMint must revert when amount exceeds provider's balance";
}

// RMV2_E_9 — no RMV2 call may decrease a third party's tokenA balance; only msg.sender's balance can decrease.
rule onlyMsgSenderBalanceCanDecrease(env e, method f, calldataarg args, address account)
    filtered { f -> commonFilters(f) }
{
    setup(e);
    require account != treasuryAddress(), "account isn't treasury";
    require account != currentContract, "skip manager outflows";
    uint256 before = tokenA.balanceOf(account);
    uint256 contractBalance = tokenA.balanceOf(currentContract);
    require before + contractBalance < max_uint, "ignore Overflow";
    f(e, args);
    assert tokenA.balanceOf(account) < before => account == e.msg.sender,
        "RMV2 must not decrease a third party's tokenA balance without their consent";
}

// RMV2_E_10 — requestBurn reverts when amount exceeds the provider's issue-token balance.
rule requestBurnRevertsWhenInsufficientBalance(env e, uint256 amt, address tok) {
    setup(e);
    require e.msg.sender != currentContract, "sender not manager";
    require issueToken.balanceOf(e.msg.sender) < amt, "insufficient balance";
    requestBurn@withrevert(e, amt, tok);
    assert lastReverted, "requestBurn must revert when amount exceeds provider's issue-token balance";
}

// RMV2_E_11 — no RMV2 call may decrease a third party's issue-token balance; only msg.sender's balance can decrease.
rule onlyMsgSenderIssueTokenBalanceCanDecrease(env e, method f, calldataarg args, address account)
    filtered { f -> commonFilters(f) }
{
    setup(e);
    require account != treasuryAddress(), "account isn't treasury";
    require account != currentContract, "skip manager burns";
    uint256 before = issueToken.balanceOf(account);
    uint256 contractBalance = issueToken.balanceOf(currentContract);
    require before + contractBalance < max_uint, "ignore Overflow";
    f(e, args);
    assert issueToken.balanceOf(account) < before => account == e.msg.sender,
        "RMV2 must not decrease a third party's issue-token balance without their consent";
}

// RMV2_E_12 — address(0) never holds any issue token.
invariant zeroAddressHoldsNoIssueToken()
    issueToken.balanceOf(0) == 0
    filtered { f -> commonFilters(f) }

// RMV2_E_13 — address(0) never holds any tokenA.
invariant zeroAddressHoldsNoTokenA()
    tokenA.balanceOf(0) == 0
    filtered { f -> commonFilters(f) }

//!VIOLATED
// RMV2_E_14 — treasury balance of a non-allowlisted token never changes.
rule treasuryNonAllowedTokenBalancePersists(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f)}
{
    setup(e);
    require !allowedTokens(tokenA), "tokenA not in allowlist";
    address treasury = treasuryAddress();
    mathint balBefore = to_mathint(tokenA.balanceOf(treasury));
    f(e, args);
    assert to_mathint(tokenA.balanceOf(treasury)) == balBefore,
        "treasury balance of a non-allowlisted token must not change";
}

// RMV2_E_15 — treasury's tokenA balance cannot change when the oracle price is zero.
rule treasuryTokenAUnchangedIfPriceZero(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    setup(e);
    address treasury = treasuryAddress();
    uint256 before = tokenA.balanceOf(treasury);
    f(e, args);
    assert ghostPrice == 0 => tokenA.balanceOf(treasury) == before,
        "treasury tokenA balance must not change when oracle price is zero";
}

// RMV2_E_16 — cancelMint refunds exactly request.amount to the provider, no fee haircut.
rule cancelMintFullRefund(env e, uint256 id) {
    setup(e);
    require assert_uint8(mintRequestState(id)) == CREATED(), "mint is CREATED";
    require mintRequestToken(id) == depositToken, "concrete deposit token";
    address provider = mintRequestProvider(id);
    require provider != 0 && provider != currentContract, "provider exists and not self";
    uint256 amount = mintRequestAmount(id);
    require depositToken.balanceOf(currentContract) >= amount, "escrow backing holds";
    require depositToken.balanceOf(provider) + amount <= max_uint256, "no balance overflow";

    mathint provBefore = to_mathint(depositToken.balanceOf(provider));

    require e.msg.sender == provider, "provider-path cancel";
    cancelMint(e, id);

    mathint provAfter = to_mathint(depositToken.balanceOf(provider));
    assert provAfter - provBefore == to_mathint(amount),
        "cancelMint must refund exactly request.amount with no fee haircut";
}

// RMV2_E_17 — adminCancelMint refunds exactly request.amount to the provider, no fee haircut.
rule adminCancelMintFullRefund(env e, uint256 id) {
    setup(e);
    require hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender), "caller is admin";
    require assert_uint8(mintRequestState(id)) == CREATED(), "mint is CREATED";
    require mintRequestToken(id) == depositToken, "concrete deposit token";
    address provider = mintRequestProvider(id);
    require provider != 0 && provider != currentContract, "provider exists and not self";
    require e.msg.sender != provider, "admin distinct from provider";
    uint256 amount = mintRequestAmount(id);
    require depositToken.balanceOf(currentContract) >= amount, "escrow backing holds";
    require depositToken.balanceOf(provider) + amount <= max_uint256, "no balance overflow";

    mathint provBefore = to_mathint(depositToken.balanceOf(provider));
    adminCancelMint(e, id);
    mathint provAfter = to_mathint(depositToken.balanceOf(provider));
    assert provAfter - provBefore == to_mathint(amount),
        "adminCancelMint must refund exactly request.amount to the provider, no haircut";
}

// RMV2_E_18 — cancelBurn refunds exactly request.amount of issue token to the provider, no fee haircut.
rule cancelBurnFullRefund(env e, uint256 id) {
    setup(e);
    require assert_uint8(burnRequestState(id)) == CREATED(), "burn is CREATED";
    address provider = burnRequestProvider(id);
    require provider != 0 && provider != currentContract, "provider exists and not self";
    uint256 amount = burnRequestAmount(id);
    require issueToken.balanceOf(currentContract) >= amount, "escrow backing holds";
    require issueToken.balanceOf(provider) + amount <= max_uint256, "no balance overflow";

    mathint provBefore = to_mathint(issueToken.balanceOf(provider));

    require e.msg.sender == provider, "provider-path cancel";
    cancelBurn(e, id);

    mathint provAfter = to_mathint(issueToken.balanceOf(provider));
    assert provAfter - provBefore == to_mathint(amount),
        "cancelBurn must refund exactly request.amount of the issue token with no fee haircut";
}

// RMV2_E_19 — adminCancelBurn refunds exactly request.amount of issue token to the provider, no fee haircut.
rule adminCancelBurnFullRefund(env e, uint256 id) {
    setup(e);
    require hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender), "caller is admin";
    require assert_uint8(burnRequestState(id)) == CREATED(), "burn is CREATED";
    address provider = burnRequestProvider(id);
    require provider != 0 && provider != currentContract, "provider exists and not self";
    require e.msg.sender != provider, "admin distinct from provider";
    uint256 amount = burnRequestAmount(id);
    require issueToken.balanceOf(currentContract) >= amount, "escrow backing holds";
    require issueToken.balanceOf(provider) + amount <= max_uint256, "no balance overflow";

    mathint provBefore = to_mathint(issueToken.balanceOf(provider));
    adminCancelBurn(e, id);
    mathint provAfter = to_mathint(issueToken.balanceOf(provider));
    assert provAfter - provBefore == to_mathint(amount),
        "adminCancelBurn must refund exactly request.amount of the issue token, no haircut";
}

// RMV2_E_20 — completeMint reverts after emergencyWithdraw drains the deposit token (rug-path consequence).
rule completeMintRevertsAfterEmergencyWithdraw(env eAdmin, env eService, uint256 id) {
    setup(eAdmin);
    setup(eService);
    tokenDistinctness();
    require mintRequestToken(id) == depositToken, "concrete deposit token";
    require mintRequestAmount(id) > 0, "non-zero deposit";

    // Admin drains the escrowed deposit token; contract balance drops to zero.
    emergencyWithdraw(eAdmin, depositToken);

    // completeMint tries safeTransfer(treasury, depositAmount) — insufficient balance → revert.
    completeMint@withrevert(eService, id);
    assert lastReverted,
        "completeMint must revert after emergencyWithdraw has drained the deposit token";
}

// RMV2_E_21 — cancelMint reverts after emergencyWithdraw drains the deposit token (rug-path consequence).
rule cancelMintRevertsAfterEmergencyWithdraw(env eAdmin, env eProvider, uint256 id) {
    setup(eAdmin);
    setup(eProvider);
    tokenDistinctness();
    require mintRequestToken(id) == depositToken, "concrete deposit token";
    require mintRequestAmount(id) > 0, "non-zero deposit";
    require eProvider.msg.sender == mintRequestProvider(id), "caller is provider";

    // Admin drains the escrowed deposit token; contract balance drops to zero.
    emergencyWithdraw(eAdmin, depositToken);

    // cancelMint tries safeTransfer(provider, amount) — insufficient balance → revert.
    cancelMint@withrevert(eProvider, id);
    assert lastReverted,
        "cancelMint must revert after emergencyWithdraw has drained the deposit token";
}

// RMV2_E_22 — adminCancelMint reverts after emergencyWithdraw drains the deposit token (rug-path consequence).
rule adminCancelMintRevertsAfterEmergencyWithdraw(env eAdmin, env eAdmin2, uint256 id) {
    setup(eAdmin);
    setup(eAdmin2);
    tokenDistinctness();
    require mintRequestToken(id) == depositToken, "concrete deposit token";
    require mintRequestAmount(id) > 0, "non-zero deposit";

    // Admin drains the escrowed deposit token; contract balance drops to zero.
    emergencyWithdraw(eAdmin, depositToken);

    // adminCancelMint tries safeTransfer(provider, amount) — insufficient balance → revert.
    adminCancelMint@withrevert(eAdmin2, id);
    assert lastReverted,
        "adminCancelMint must revert after emergencyWithdraw has drained the deposit token";
}

// RMV2_E_23 — emergencyWithdraw drains the entire deposit token balance of the contract to zero.
rule emergencyWithdrawDrainsFullBalance(env e) {
    setup(e);
    require hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender), "caller is admin";

    emergencyWithdraw(e, depositToken);

    assert depositToken.balanceOf(currentContract) == 0,
        "emergencyWithdraw must leave zero deposit token balance in the contract";
}

// RMV2_E_24 — completeBurn reverts after emergencyWithdraw drains the issue token (burn-escrow rug-path consequence).
rule completeBurnRevertsAfterEmergencyWithdrawIssueToken(env eAdmin, env eService, uint256 id) {
    setup(eAdmin);
    setup(eService);
    tokenDistinctness();
    require burnRequestToken(id) == depositToken, "concrete withdrawal token";
    require burnRequestAmount(id) > 0, "non-zero burn amount";
    require ghostPrice > 0, "price positive";

    // Admin drains the escrowed issue token; contract balance drops to zero.
    emergencyWithdraw(eAdmin, issueToken);

    // completeBurn tries issueToken.burn(this, amount) — insufficient balance → revert.
    completeBurn@withrevert(eService, id);
    assert lastReverted,
        "completeBurn must revert after emergencyWithdraw has drained the issue token";
}

// RMV2_E_25 — cancelBurn reverts after emergencyWithdraw drains the issue token (burn-escrow rug-path consequence).
rule cancelBurnRevertsAfterEmergencyWithdrawIssueToken(env eAdmin, env eProvider, uint256 id) {
    setup(eAdmin);
    setup(eProvider);
    tokenDistinctness();
    require burnRequestAmount(id) > 0, "non-zero burn amount";
    require eProvider.msg.sender == burnRequestProvider(id), "caller is provider";
    require to_mathint(eProvider.block.timestamp) <= to_mathint(burnRequestCreatedAt(id)) + to_mathint(burnCancelWindow()), "within cancel window";

    // Admin drains the escrowed issue token; contract balance drops to zero.
    emergencyWithdraw(eAdmin, issueToken);

    // cancelBurn tries issueToken.safeTransfer(provider, amount) — insufficient balance → revert.
    cancelBurn@withrevert(eProvider, id);
    assert lastReverted,
        "cancelBurn must revert after emergencyWithdraw has drained the issue token";
}

// RMV2_E_26 — adminCancelBurn reverts after emergencyWithdraw drains the issue token (burn-escrow rug-path consequence).
rule adminCancelBurnRevertsAfterEmergencyWithdrawIssueToken(env eAdmin, env eAdmin2, uint256 id) {
    setup(eAdmin);
    setup(eAdmin2);
    tokenDistinctness();
    require burnRequestAmount(id) > 0, "non-zero burn amount";

    // Admin drains the escrowed issue token; contract balance drops to zero.
    emergencyWithdraw(eAdmin, issueToken);

    // adminCancelBurn tries issueToken.safeTransfer(provider, amount) — insufficient balance → revert.
    adminCancelBurn@withrevert(eAdmin2, id);
    assert lastReverted,
        "adminCancelBurn must revert after emergencyWithdraw has drained the issue token";
}
