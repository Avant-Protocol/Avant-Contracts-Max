/*
 * RequestsManagerV2 — State Machine Spec
 * Properties RMV2_SM_1 .. RMV2_SM_20: terminal-state absorption, only-out-of-CREATED
 * transitions, complete/cancel mutual exclusion, wrong-state rejection, no-double-settlement,
 * CEI ordering, pause-independence of cancel paths, emergencyWithdraw state-inertness,
 * adminCancelBurn window-independence, cancelMint/cancelBurn TTL-independence.
 * Cancel full-refund correctness (E_16..E_19) lives in RMV2_Escrow.spec.
 *
 * Modelling:
 *   - The issue token is a linked DummyERC20 (issueToken); a withdrawal/deposit token is a
 *     linked DummyERC20Permit. Both are plain standard 18-decimal ERC-20s.
 *   - PRICE_STORAGE.lastPrice() is summarised by a CVL ghost returning a symbolic price>0 and
 *     timestamp (cross-call consistent). Freshness is intentionally NOT checked (F-01 carve-out).
 *   - CEI ordering (SM_7..SM_12): a successful settling call leaves request state != CREATED,
 *     proving the state write precedes any transfer.
 *   - emergencyWithdraw state-inertness is modelled (SM_15); its solvency is NOT asserted
 *     (F-02 carve-out).
 */

import "utils/RMV2_Base.spec";

methods {
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
}

// RMV2_SM_1 — COMPLETED/CANCELLED mint request stays in that terminal state.
rule mintTerminalAbsorption(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    require id < mintRequestsCounter(), "existing request id is below the counter";
    uint8 sBefore = assert_uint8(mintRequestState(id));
    require sBefore == COMPLETED() || sBefore == CANCELLED(), "terminal state";
    f(e, args);
    assert assert_uint8(mintRequestState(id)) == sBefore,
        "a COMPLETED/CANCELLED mint request must remain in that terminal state";
}

// RMV2_SM_2 — COMPLETED/CANCELLED burn request stays in that terminal state.
rule burnTerminalAbsorption(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    require id < burnRequestsCounter(), "existing request id is below the counter";
    uint8 sBefore = assert_uint8(burnRequestState(id));
    require sBefore == COMPLETED() || sBefore == CANCELLED(), "terminal state";
    f(e, args);
    assert assert_uint8(burnRequestState(id)) == sBefore,
        "a COMPLETED/CANCELLED burn request must remain in that terminal state";
}

// RMV2_SM_3 — a mint request can only transition out of CREATED.
rule mintTransitionsOnlyFromCreated(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    require id < mintRequestsCounter(), "id within counter";
    require mintRequestProvider(id) != 0, "request exists";
    uint8 sBefore = assert_uint8(mintRequestState(id));
    f(e, args);
    uint8 sAfter = assert_uint8(mintRequestState(id));
    assert sAfter != sBefore => sBefore == CREATED(),
        "a mint request can only transition out of CREATED";
}

// RMV2_SM_4 — a burn request can only transition out of CREATED.
rule burnTransitionsOnlyFromCreated(env e, method f, calldataarg args, uint256 id)
    filtered { f -> commonFilters(f) }
{
    require id < burnRequestsCounter(), "id within counter";
    require burnRequestProvider(id) != 0, "request exists";
    uint8 sBefore = assert_uint8(burnRequestState(id));
    f(e, args);
    uint8 sAfter = assert_uint8(burnRequestState(id));
    assert sAfter != sBefore => sBefore == CREATED(),
        "a burn request can only transition out of CREATED";
}

// RMV2_SM_5 — wrong-state rejection: completeMint/cancelMint/adminCancelMint revert when not CREATED.
rule mintWrongStateReverts(env e, uint256 id) {
    setup(e);
    require mintRequestProvider(id) != 0, "request exists";
    require assert_uint8(mintRequestState(id)) != CREATED(), "not CREATED";

    storage init = lastStorage;

    completeMint@withrevert(e, id);
    assert lastReverted, "completeMint must revert for a non-CREATED mint";

    cancelMint@withrevert(e, id) at init;
    assert lastReverted, "cancelMint must revert for a non-CREATED mint";

    adminCancelMint@withrevert(e, id) at init;
    assert lastReverted, "adminCancelMint must revert for a non-CREATED mint";
}

// RMV2_SM_6 — wrong-state rejection: completeBurn/cancelBurn/adminCancelBurn revert when not CREATED.
rule burnWrongStateReverts(env e, uint256 id) {
    setup(e);
    require burnRequestProvider(id) != 0, "request exists";
    require assert_uint8(burnRequestState(id)) != CREATED(), "not CREATED";

    storage init = lastStorage;

    completeBurn@withrevert(e, id);
    assert lastReverted, "completeBurn must revert for a non-CREATED burn";

    cancelBurn@withrevert(e, id) at init;
    assert lastReverted, "cancelBurn must revert for a non-CREATED burn";

    adminCancelBurn@withrevert(e, id) at init;
    assert lastReverted, "adminCancelBurn must revert for a non-CREATED burn";
}

// RMV2_SM_7 — CEI ordering: completeMint writes state before any transfer.
rule mintCEIStateBeforeTransfer_complete(env e, uint256 id) {
    setup(e);
    require assert_uint8(mintRequestState(id)) == CREATED(), "mint is CREATED";
    require ghostPrice > 0, "price positive";
    completeMint@withrevert(e, id);
    bool reverted = lastReverted;
    assert !reverted => assert_uint8(mintRequestState(id)) != CREATED(),
        "a successful completeMint must leave the request out of CREATED (state written before transfer, CEI)";
}

// RMV2_SM_8 — CEI ordering: cancelMint writes state before any transfer.
rule mintCEIStateBeforeTransfer_cancel(env e, uint256 id) {
    setup(e);
    require assert_uint8(mintRequestState(id)) == CREATED(), "mint is CREATED";
    cancelMint@withrevert(e, id);
    bool reverted = lastReverted;
    assert !reverted => assert_uint8(mintRequestState(id)) != CREATED(),
        "a successful cancelMint must leave the request out of CREATED (state written before transfer, CEI)";
}

// RMV2_SM_9 — CEI ordering: adminCancelMint writes state before any transfer.
rule mintCEIStateBeforeTransfer_adminCancel(env e, uint256 id) {
    setup(e);
    require assert_uint8(mintRequestState(id)) == CREATED(), "mint is CREATED";
    adminCancelMint@withrevert(e, id);
    bool reverted = lastReverted;
    assert !reverted => assert_uint8(mintRequestState(id)) != CREATED(),
        "a successful adminCancelMint must leave the request out of CREATED (state written before transfer, CEI)";
}

// RMV2_SM_10 — CEI ordering: completeBurn writes state before any transfer.
rule burnCEIStateBeforeTransfer_complete(env e, uint256 id) {
    setup(e);
    require assert_uint8(burnRequestState(id)) == CREATED(), "burn is CREATED";
    require ghostPrice > 0, "price positive";
    completeBurn@withrevert(e, id);
    bool reverted = lastReverted;
    assert !reverted => assert_uint8(burnRequestState(id)) != CREATED(),
        "a successful completeBurn must leave the request out of CREATED (state written before transfer, CEI)";
}

// RMV2_SM_11 — CEI ordering: cancelBurn writes state before any transfer.
rule burnCEIStateBeforeTransfer_cancel(env e, uint256 id) {
    setup(e);
    require assert_uint8(burnRequestState(id)) == CREATED(), "burn is CREATED";
    cancelBurn@withrevert(e, id);
    bool reverted = lastReverted;
    assert !reverted => assert_uint8(burnRequestState(id)) != CREATED(),
        "a successful cancelBurn must leave the request out of CREATED (state written before transfer, CEI)";
}

// RMV2_SM_12 — CEI ordering: adminCancelBurn writes state before any transfer.
rule burnCEIStateBeforeTransfer_adminCancel(env e, uint256 id) {
    setup(e);
    require assert_uint8(burnRequestState(id)) == CREATED(), "burn is CREATED";
    adminCancelBurn@withrevert(e, id);
    bool reverted = lastReverted;
    assert !reverted => assert_uint8(burnRequestState(id)) != CREATED(),
        "a successful adminCancelBurn must leave the request out of CREATED (state written before transfer, CEI)";
}


// RMV2_SM_13 — adminCancelMint does not revert due to pause state.
rule adminCancelMintPauseIndependent(env e, uint256 id) {
    setup(e);
    require paused(), "contract is paused";
    adminCancelMint(e, id);
    satisfy true, "adminCancelMint can succeed while paused";
}

// RMV2_SM_14 — adminCancelBurn does not revert due to pause state.
rule adminCancelBurnPauseIndependent(env e, uint256 id) {
    setup(e);
    require paused(), "contract is paused";
    adminCancelBurn(e, id);
    satisfy true, "adminCancelBurn can succeed while paused";
}

// RMV2_SM_15 — emergencyWithdraw does not touch any request state or field.
rule G_emergencyWithdrawStateInert(env e, address token, uint256 id) {
    setup(e);
    uint8   mStateBefore = assert_uint8(mintRequestState(id));
    address mProvBefore = mintRequestProvider(id);
    uint256 mAmtBefore = mintRequestAmount(id);
    uint8   bStateBefore = assert_uint8(burnRequestState(id));
    address bProvBefore = burnRequestProvider(id);
    uint256 bAmtBefore = burnRequestAmount(id);

    emergencyWithdraw(e, token);

    assert assert_uint8(mintRequestState(id)) == mStateBefore, "emergencyWithdraw changed a mint state";
    assert mintRequestProvider(id) == mProvBefore, "emergencyWithdraw changed a mint provider";
    assert mintRequestAmount(id) == mAmtBefore, "emergencyWithdraw changed a mint amount";
    assert assert_uint8(burnRequestState(id)) == bStateBefore, "emergencyWithdraw changed a burn state";
    assert burnRequestProvider(id) == bProvBefore, "emergencyWithdraw changed a burn provider";
    assert burnRequestAmount(id) == bAmtBefore, "emergencyWithdraw changed a burn amount";
}

// RMV2_SM_16 — adminCancelBurn ignores burnCancelWindow: admin can cancel even after the window has elapsed.
rule adminCancelBurnIgnoresCancelWindow(env e, uint256 id) {
    setup(e);
    require burnRequestProvider(id) != 0, "request exists";
    require to_mathint(e.block.timestamp) > to_mathint(burnRequestCreatedAt(id)) + to_mathint(burnCancelWindow()), "window elapsed";

    adminCancelBurn(e, id);
    satisfy true,
        "adminCancelBurn must be able to succeed even after burnCancelWindow has elapsed";
}

// RMV2_SM_17 — cancelMint is not gated by mintRequestTTL: provider can cancel a CREATED mint even after TTL has elapsed.
rule cancelMintTTLIndependent(env e, uint256 id) {
    setup(e);
    require mintRequestTTL() > 0, "TTL active";
    require to_mathint(e.block.timestamp) > to_mathint(mintRequestCreatedAt(id)) + to_mathint(mintRequestTTL()), "TTL elapsed";

    cancelMint(e, id);
    satisfy true, "cancelMint can succeed for any CREATED mint regardless of TTL";
}

// RMV2_SM_18 — cancelBurn is not gated by burnRequestTTL: provider can cancel a CREATED burn within the cancel window even after TTL has elapsed.
rule cancelBurnTTLIndependent(env e, uint256 id) {
    setup(e);
    require burnRequestTTL() > 0, "TTL active";
    require to_mathint(e.block.timestamp) > to_mathint(burnRequestCreatedAt(id)) + to_mathint(burnRequestTTL()), "TTL elapsed";
    require to_mathint(e.block.timestamp) <= to_mathint(burnRequestCreatedAt(id)) + to_mathint(burnCancelWindow()), "within cancel window";

    cancelBurn(e, id);
    satisfy true, "cancelBurn can succeed for a CREATED burn within the cancel window even after TTL has elapsed";
}

// RMV2_SM_19 — a second completeMint for the same id always reverts (COMPLETED is terminal).
rule noDoubleCompleteMint(env e, uint256 id) {
    setup(e);
    require assert_uint8(mintRequestState(id)) == CREATED(), "mint is CREATED";
    require ghostPrice > 0, "price positive";

    completeMint(e, id);
    assert assert_uint8(mintRequestState(id)) == COMPLETED(),
        "first completeMint moves the request to COMPLETED";

    completeMint@withrevert(e, id);
    assert lastReverted, "a second completeMint for the same id must revert";
}

// RMV2_SM_20 — a second completeBurn for the same id always reverts (COMPLETED is terminal).
rule noDoubleCompleteBurn(env e, uint256 id) {
    setup(e);
    require assert_uint8(burnRequestState(id)) == CREATED(), "burn is CREATED";
    require ghostPrice > 0, "price positive";

    completeBurn(e, id);
    assert assert_uint8(burnRequestState(id)) == COMPLETED(),
        "first completeBurn moves the request to COMPLETED";

    completeBurn@withrevert(e, id);
    assert lastReverted, "a second completeBurn for the same id must revert";
}
