### L-01 RequestsManagerV2::completeMint and RequestsManagerV2::completeBurn forwards de-allowlisted deposit tokens to treasury {#l-01}

\renewcommand{\arraystretch}{1.4}
\begin{table}[h]
\centering
\begin{tabularx}{\textwidth}{|Z|X|X|X|}
\hline

\rowcolor[HTML]{E6E6E6}
Severity  & Files & Status & Properties Violated \\ \hline
\cellcolor{yellow!30} Low & RequestsManagerV2 & Acknowledged & \hyperref[e-14]{E-14}\\ \hline
\end{tabularx}
\end{table}

**Description:**

`removeAllowedToken` (`src/RequestsManagerV2.sol:149`) de-lists a deposit or withdrawal token immediately without checking whether any `CREATED` requests referencing that token are still open. Neither `completeMint` (`src/RequestsManagerV2.sol:274`) nor `completeBurn` (`src/RequestsManagerV2.sol:392`) carries an `allowedToken` guard at settlement time — the allowlist check is applied only at request creation via the `allowedToken` modifier on `requestMint` (line 210) and `requestBurn` (line 314).

This creates two reachable violation paths:

**Path 1 — `completeMint`:** treasury receives a de-allowlisted deposit token.

1. A provider calls `requestMint(tokenA, amount)` while `tokenA` is in the allowlist. The deposit is escrowed in the contract.
2. `DEFAULT_ADMIN_ROLE` calls `removeAllowedToken(tokenA)`. The mapping entry is set to `false` with no guard on pending requests.
3. `SERVICE_ROLE` calls `completeMint(id)`. The call succeeds — `IERC20(token).safeTransfer()` (`src/RequestsManagerV2.sol:298`) transfers the de-allowlisted deposit token to the treasury, increasing its balance.

**Path 2 — `completeBurn`:** treasury is drained of a de-allowlisted withdrawal token.

1. A provider calls `requestBurn(amount, tokenA)` while `tokenA` is in the allowlist. Issue tokens are escrowed.
2. `DEFAULT_ADMIN_ROLE` calls `removeAllowedToken(tokenA)`.
3. `SERVICE_ROLE` calls `completeBurn(id)`. The call succeeds — `IERC20(token).safeTransferFrom()` (`src/RequestsManagerV2.sol:425`) pulls the de-allowlisted withdrawal token out of the treasury, decreasing its balance.

In both cases the treasury balance of a token that is no longer in the allowlist changes, violating property E-14.

**Recommended Mitigation:**

Add an `allowedToken(request.token)` check at the top of both `completeMint` and `completeBurn` so that settlement reverts if the token has been de-allowlisted since the request was created:

```solidity
function completeMint(uint256 _id) external onlyRole(SERVICE_ROLE) whenNotPaused mintRequestExist(_id) {
    MintRequest storage request = mintRequests[_id];
    _assertState(State.CREATED, request.state);
+   if (!allowedTokens[request.token]) revert TokenNotAllowed(request.token);
    ...
}

function completeBurn(uint256 _id) external onlyRole(SERVICE_ROLE) whenNotPaused burnRequestExist(_id) {
    BurnRequest storage request = burnRequests[_id];
    _assertState(State.CREATED, request.state);
+   if (!allowedTokens[request.token]) revert TokenNotAllowed(request.token);
    ...
}
```

Alternatively, `removeAllowedToken` can be made to revert if any `CREATED` mint or burn requests reference the token being de-listed. However, this requires an on-chain index of open requests per token and is significantly more expensive to implement.

**Violated Property:**

```cvl
//!VIOLATED
// RMV2_E_14 — treasury balance of a non-allowlisted token never changes.
rule treasuryNonAllowedTokenBalancePersists(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) }
{
    setup(e);
    require !allowedTokens(tokenA), "tokenA not in allowlist";
    address treasury = treasuryAddress();
    mathint balBefore = to_mathint(tokenA.balanceOf(treasury));
    f(e, args);
    assert to_mathint(tokenA.balanceOf(treasury)) == balBefore,
        "treasury balance of a non-allowlisted token must not change";
}
```

**Violated Run Link:** \href{\ELinkViolated}{RMV2\_Escrow.conf}

**Status:**

Acknowledged.

\pagebreak
