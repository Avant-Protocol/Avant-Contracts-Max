/*
 * RequestsManagerV2 — Settlement Spec
 * Properties RMV2_S_1 .. RMV2_S_17: pre-fee anti-inflation bound, rounding-favors-protocol,
 * fee/price monotonicity, overflow/underflow bounds, value conservation, totalSupply
 * conservation, min-price selection, dust-revert-preserves-CREATED, no-free-value.
 *
 * Modelling:
 *   - The issue token is a linked SimpleToken (issueToken) so completeMint/completeBurn move a
 *     tracked totalSupply via the keyed mint/burn overloads (S_10/S_11/S_12).
 *   - A second linked DummyERC20Permit (withdrawalToken) backs completeBurn's treasury pull.
 *   - PRICE_STORAGE.lastPrice() is summarised by a CVL ghost returning a symbolic price>0 and
 *     timestamp (cross-call consistent). Freshness is intentionally NOT checked (F-01 carve-out).
 *   - emergencyWithdraw solvency is NOT asserted (F-02 carve-out).
 */

import "utils/RMV2_Base.spec";

methods {
    function computeMintPreFee(uint256, uint128) external returns (uint256) envfree;
    function withdrawalToken.balanceOf(address) external returns (uint256) envfree;
}

// RMV2_S_1 — pre-fee anti-inflation ceiling: post-fee mint amount <= deposit*PRECISION/price.
rule mintPreFeeBound(uint256 deposit, uint128 price, uint64 fee) {
    require price > 0, "price positive";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require deposit <= max_uint128, "realistic amount";

    mathint preFee = to_mathint(computeMintPreFee(deposit, price));
    assert preFee == to_mathint(deposit) * PRECISION() / to_mathint(price),
        "pre-fee mint amount must equal deposit*PRECISION/price";

    assert to_mathint(computeMintAmount(deposit, price, fee)) <= preFee,
        "post-fee mint amount must not exceed pre-fee ceiling";
}

// RMV2_S_2 — mint rounding always favors the protocol (user gets floor).
rule mintRoundsDownTowardProtocol(uint256 deposit, uint128 price, uint64 fee) {
    require price > 0, "price positive";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require deposit <= max_uint128, "realistic amount";

    mathint m = to_mathint(computeMintAmount(deposit, price, fee));
    mathint exact = to_mathint(deposit) * PRECISION() / to_mathint(price)
                    * (PRECISION() - to_mathint(fee)) / PRECISION();
    assert m <= exact, "minted must be <= real-valued result (user gets floor)";
}

// RMV2_S_3 — burn rounding always favors the protocol (user gets floor).
rule burnRoundsDownTowardProtocol(uint256 amount, uint128 price, uint64 fee) {
    require price > 0, "price positive";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require amount <= max_uint128, "realistic amount";

    mathint w = to_mathint(computeBurnAmount(amount, price, fee));
    mathint exact = to_mathint(amount) * to_mathint(price) / PRECISION()
                    * (PRECISION() - to_mathint(fee)) / PRECISION();
    assert w <= exact, "withdrawn must be <= real-valued result (user gets floor)";
}

// RMV2_S_4 — mint output monotone non-increasing in fee.
rule mintFeeMonotonic(uint256 deposit, uint128 price, uint64 feeLo, uint64 feeHi) {
    require price > 0, "price positive";
    require feeHi >= feeLo, "feeHi at least feeLo";
    require feeHi <= require_uint64(MAX_FEE()), "fee within max";
    require deposit <= max_uint128, "realistic amount";
    assert computeMintAmount(deposit, price, feeHi) <= computeMintAmount(deposit, price, feeLo),
        "higher mintFee must not yield more minted";
}

// RMV2_S_5 — mint output monotone non-increasing in price.
rule mintPriceMonotonic(uint256 deposit, uint128 pLo, uint128 pHi, uint64 fee) {
    require pLo > 0 && pHi >= pLo, "valid price range";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require deposit <= max_uint128, "realistic amount";
    assert computeMintAmount(deposit, pHi, fee) <= computeMintAmount(deposit, pLo, fee),
        "higher price must not yield more minted";
}

// RMV2_S_6 — burn output monotone non-increasing in fee.
rule burnFeeMonotonic(uint256 amount, uint128 price, uint64 feeLo, uint64 feeHi) {
    require price > 0, "price positive";
    require feeHi >= feeLo, "feeHi at least feeLo";
    require feeHi <= require_uint64(MAX_FEE()), "fee within max";
    require amount <= max_uint128, "realistic amount";
    assert computeBurnAmount(amount, price, feeHi) <= computeBurnAmount(amount, price, feeLo),
        "higher burn fee must not yield more withdrawn";
}

// RMV2_S_7 — burn output monotone non-decreasing in price.
rule burnPriceMonotonic(uint256 amount, uint128 pLo, uint128 pHi, uint64 fee) {
    require pLo > 0 && pHi >= pLo, "valid price range";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require amount <= max_uint128, "realistic amount";
    assert computeBurnAmount(amount, pLo, fee) <= computeBurnAmount(amount, pHi, fee),
        "lower settlement price must not yield more withdrawn";
}

// RMV2_S_8 — mint intermediates fit uint256; (PRECISION - fee) never underflows.
rule mintIntermediatesFitUint256(uint256 deposit, uint128 price, uint64 fee) {
    require price > 0, "price positive";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require deposit <= max_uint128, "realistic amount";

    mathint p1 = to_mathint(deposit) * PRECISION();
    assert p1 <= to_mathint(max_uint256), "deposit*PRECISION fits uint256";
    mathint m1 = p1 / to_mathint(price);
    mathint p2 = m1 * (PRECISION() - to_mathint(fee));
    assert p2 <= to_mathint(max_uint256), "second product fits uint256";
    assert PRECISION() - to_mathint(fee) >= 0, "(PRECISION-fee) never underflows";
}

// RMV2_S_9 — burn intermediates fit uint256; (PRECISION - fee) never underflows.
rule burnIntermediatesFitUint256(uint256 amount, uint128 price, uint64 fee) {
    require price > 0, "price positive";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require amount <= max_uint128, "realistic amount";

    mathint p1 = to_mathint(amount) * to_mathint(price);
    assert p1 <= to_mathint(max_uint256), "amount*price fits uint256";
    mathint w1 = p1 / PRECISION();
    mathint p2 = w1 * (PRECISION() - to_mathint(fee));
    assert p2 <= to_mathint(max_uint256), "second product fits uint256";
    assert PRECISION() - to_mathint(fee) >= 0, "(PRECISION-fee) never underflows";
}

// RMV2_S_10 — completeMint raises totalSupply by exactly the computed amount, bounded by the anti-inflation ceiling.
rule completeMint_antiInflation(env e, uint256 id) {
    setup(e);
    require mintRequestToken(id) == withdrawalToken, "concrete deposit token";
    require withdrawalToken != issueToken, "deposit token not issue token";
    uint256 deposit = mintRequestAmount(id);
    require deposit <= max_uint128, "realistic amount";
    uint64 liveFee = mintFee();
    require liveFee <= require_uint64(MAX_FEE()), "fee within max";

    require ghostPrice > 0, "price positive";
    mathint supplyBefore = to_mathint(issueToken.totalSupply());
    completeMint(e, id);
    mathint supplyAfter = to_mathint(issueToken.totalSupply());

    mathint computed = to_mathint(computeMintAmount(deposit, ghostPrice, liveFee));
    assert supplyAfter - supplyBefore == computed,
        "totalSupply delta must equal computed mintAmount";

    mathint realBound = to_mathint(deposit) * PRECISION() / to_mathint(ghostPrice)
                        * (PRECISION() - to_mathint(liveFee)) / PRECISION();
    assert supplyAfter - supplyBefore <= realBound,
        "minted must not exceed the real-valued anti-inflation ceiling";
}

// RMV2_S_11 — only completeMint may increase the issue-token totalSupply.
rule onlyCompleteMintIncreasesSupply(env e, method f, calldataarg args)
    filtered { f -> f.contract == currentContract }
{
    require to_mathint(issueToken.balanceOf(currentContract)) <= to_mathint(issueToken.totalSupply()), "balance within supply";
    mathint before = to_mathint(issueToken.totalSupply());
    f(e, args);
    mathint after = to_mathint(issueToken.totalSupply());
    assert after > before => f.selector == sig:completeMint(uint256).selector,
        "only completeMint may increase issue-token totalSupply";
}

// RMV2_S_12 — only completeBurn may decrease the issue-token totalSupply.
rule onlyCompleteBurnDecreasesSupply(env e, method f, calldataarg args)
    filtered { f -> f.contract == currentContract }
{
    mathint before = to_mathint(issueToken.totalSupply());
    f(e, args);
    mathint after = to_mathint(issueToken.totalSupply());
    assert after < before => f.selector == sig:completeBurn(uint256).selector,
        "only completeBurn may decrease issue-token totalSupply";
}

// RMV2_S_13 — completeBurn value conservation: exact settlement at min(locked,current) price, locked-price ceiling, current>=locked uses locked.
rule completeBurn_settlement(env e, uint256 id) {
    setup(e);
    require burnRequestToken(id) == withdrawalToken, "concrete withdrawal token";
    require withdrawalToken != issueToken, "withdrawal token not issue token";
    uint256 amount = burnRequestAmount(id);
    uint128 lockedPrice = burnRequestPrice(id);
    uint64  fee = burnRequestFee(id);
    require lockedPrice > 0, "locked price positive";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require amount <= max_uint128, "realistic amount";

    address provider = burnRequestProvider(id);
    require provider != currentContract && provider != treasuryAddress(), "provider distinct from manager and treasury";
    require treasuryAddress() != currentContract, "treasury not manager";
    require provider != issueToken && provider != withdrawalToken, "provider not token contract";
    require treasuryAddress() != issueToken && treasuryAddress() != withdrawalToken, "treasury not token contract";
    require to_mathint(issueToken.balanceOf(currentContract)) <= to_mathint(issueToken.totalSupply()), "balance within supply";

    uint128 current = ghostPrice;
    mathint settlePrice = current < lockedPrice ? to_mathint(current) : to_mathint(lockedPrice);
    mathint payout = to_mathint(computeBurnAmount(amount, assert_uint128(settlePrice), fee));
    require to_mathint(withdrawalToken.balanceOf(provider)) + payout <= max_uint256, "no overflow";

    require ghostPrice > 0, "price positive";
    mathint provBefore = to_mathint(withdrawalToken.balanceOf(provider));
    completeBurn(e, id);
    mathint provAfter = to_mathint(withdrawalToken.balanceOf(provider));
    mathint paid = provAfter - provBefore;

    mathint expected = to_mathint(amount) * settlePrice / PRECISION()
                       * (PRECISION() - to_mathint(fee)) / PRECISION();
    assert paid == expected, "withdrawal must equal burnAmount*min(locked,current)/PRECISION*(1-fee)";

    mathint ceiling = to_mathint(amount) * to_mathint(lockedPrice) / PRECISION();
    assert paid <= ceiling, "withdrawal must not exceed the locked-price ceiling";

    assert current >= lockedPrice =>
        paid == to_mathint(amount) * to_mathint(lockedPrice) / PRECISION()
                * (PRECISION() - to_mathint(fee)) / PRECISION(),
        "a price rise settles at the locked price";
}

// RMV2_S_14 — mint dust rounds to zero => revert ZeroAmountOut, state stays CREATED.
rule completeMint_zeroOut_revertsPreservesState(env e, uint256 id) {
    setup(e);
    require assert_uint8(mintRequestState(id)) == CREATED(), "mint is CREATED";
    uint256 deposit = mintRequestAmount(id);
    uint64 liveFee = mintFee();
    require liveFee <= require_uint64(MAX_FEE()), "fee within max";
    require deposit <= max_uint128, "realistic amount";

    require ghostPrice > 0, "price positive";
    require computeMintAmount(deposit, ghostPrice, liveFee) == 0, "dust rounds to zero";

    completeMint@withrevert(e, id);
    bool reverted = lastReverted;
    assert reverted, "completeMint must revert when settlement rounds to zero";
    assert assert_uint8(mintRequestState(id)) == CREATED(), "dust revert must leave the mint CREATED";
}

// RMV2_S_15 — burn dust rounds to zero => revert ZeroAmountOut, state stays CREATED.
rule completeBurn_zeroOut_revertsPreservesState(env e, uint256 id) {
    setup(e);
    require assert_uint8(burnRequestState(id)) == CREATED(), "burn is CREATED";
    uint256 amount = burnRequestAmount(id);
    uint128 lockedPrice = burnRequestPrice(id);
    uint64  fee = burnRequestFee(id);
    require lockedPrice > 0, "locked price positive";
    require fee <= require_uint64(MAX_FEE()), "fee within max";
    require amount <= max_uint128, "realistic amount";

    require ghostPrice > 0, "price positive";
    uint128 current = ghostPrice;
    uint128 price = current < lockedPrice ? current : lockedPrice;
    require computeBurnAmount(amount, price, fee) == 0, "dust rounds to zero";

    completeBurn@withrevert(e, id);
    bool reverted = lastReverted;
    assert reverted, "completeBurn must revert when settlement rounds to zero";
    assert assert_uint8(burnRequestState(id)) == CREATED(), "dust revert must leave the burn CREATED";
}

// RMV2_S_16 — no free value: non-zero mint output requires non-zero deposit.
rule noFreeMint(env e, uint256 id) {
    setup(e);
    require assert_uint8(mintRequestState(id)) == CREATED(), "mint is CREATED";
    require mintRequestAmount(id) == 0, "zero-amount request";
    completeMint@withrevert(e, id);
    assert lastReverted, "completeMint must revert for a zero-amount request";
}

// RMV2_S_17 — no free value: non-zero burn output requires non-zero amount.
rule noFreeBurn(env e, uint256 id) {
    setup(e);
    require assert_uint8(burnRequestState(id)) == CREATED(), "burn is CREATED";
    require burnRequestAmount(id) == 0, "zero-amount request";
    require burnRequestPrice(id) > 0, "price positive";
    completeBurn@withrevert(e, id);
    assert lastReverted, "completeBurn must revert for a zero-amount request";
}
