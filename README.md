# Avant MAX Contracts

Smart contracts for the Avant Protocol's MAX product line — a managed mint/burn system for yield-bearing vault tokens (avUSDx, avBTCx, avETHx). Users deposit base assets (avUSD, avBTC, avETH) and receive issue tokens representing their share of the vault, with the exchange rate determined by an on-chain price oracle.

Deployed on Avalanche (avUSDx, avBTCx) and Ethereum (avETHx).

## Contracts

### SimpleToken

`src/SimpleToken.sol`

ERC-20 token with role-gated minting and burning. Each product has one SimpleToken instance (e.g., avETHx). Only addresses with `SERVICE_ROLE` — typically the RequestsManager contract — can mint or burn tokens.

Supports both idempotent (keyed) and non-idempotent mint/burn operations. The idempotent variants use a `bytes32` key to prevent duplicate processing.

### PriceStorage

`src/PriceStorage.sol`

Stores the exchange rate between base and issue tokens. Prices are set by a `SERVICE_ROLE` address (the backend bot) and are write-once per key. Each new price must fall within configurable percentage bounds of the previous price (e.g., +5% / -33%), preventing sudden large price manipulations.

Returns the latest price via `lastPrice()` as a `(uint128 price, uint128 timestamp)` tuple. Price represents the value of 1 issue token in base token terms (e.g., 1 avETHx = 1.05 avETH).

### RequestsManager (V1)

`src/RequestsManager.sol`

The original mint/burn request manager. Uses an asynchronous Request-Execute lifecycle:

1. User calls `requestMint` or `requestBurn`, locking their tokens in the contract
2. The `SERVICE_ROLE` (backend bot) calls `completeMint` or `completeBurn`, specifying the final amount to transfer

The fundamental limitation of V1 is that the `SERVICE_ROLE` directly specifies the output amount as a function parameter. This means a compromised service key can mint or burn arbitrary amounts, regardless of the actual deposit.

### RequestsManagerV2

`src/RequestsManagerV2.sol`

The hardened replacement for RequestsManager. All output amounts are computed on-chain from PriceStorage data rather than passed as parameters. The `SERVICE_ROLE` can only trigger execution — it cannot influence the computed amounts.

See the [V1 to V2 Migration](#v1-to-v2-migration) section for full details.

### AddressesWhitelist

`src/AddressesWhitelist.sol`

Simple allowlist contract used by V1 to optionally restrict which addresses can create requests. Not used by V2 — access control for users is handled off-chain by the backend (which decides whether to complete a request), and on-chain by the `pause()` mechanism for emergencies.

## V1 to V2 Migration

### Motivation: on-chain amount computation

In V1, the `SERVICE_ROLE` specifies the output amount as a direct parameter:

```solidity
// V1 — SERVICE_ROLE specifies the amount
function completeMint(bytes32 _idempotencyKey, uint256 _id, uint256 _mintAmount) external onlyRole(SERVICE_ROLE)
```

While operationally functional, this design places the entire economic integrity of the protocol on the off-chain service key. If that key were compromised, the contract would have no on-chain guardrails to prevent minting or burning arbitrary amounts. V2 hardens this by moving amount computation on-chain:

```solidity
// V2 — amount computed on-chain, SERVICE_ROLE only triggers execution
function completeMint(uint256 _id) external onlyRole(SERVICE_ROLE)
```

Internally, `completeMint` reads the latest price from `PriceStorage` and calculates:

```
mintAmount = depositAmount * PRECISION / price
```

The `SERVICE_ROLE` cannot influence this calculation. Even a fully compromised service key can only trigger the completion of existing requests at the current on-chain price — it cannot inflate the amount.

### Mint vs burn price semantics

The protocol's asynchronous lifecycle creates different timing requirements for mints and burns:

**Mints** are completed within minutes of the request. The contract uses the latest price from `PriceStorage.lastPrice()` at completion time. Since prices update weekly, the "latest price" is simply the current protocol price. There is no time-lag arbitrage risk because the user does not control when `completeMint` is called.

**Burns** have a 7-day settlement delay (enforced off-chain by the backend). If the contract used the price at completion time, users could exploit price movements during the delay — requesting a burn before a price increase, then receiving more base tokens than they should. V2 prevents this by capturing the price value directly in the `BurnRequest` struct at the moment `requestBurn` is called. The `completeBurn` function uses this stored price, making the withdrawal amount immune to post-request price changes.

### Removed features

**Idempotency key parameter.** V1 required the caller to provide a `bytes32` idempotency key for each completion. V2 derives it internally from the request ID (`keccak256(abi.encodePacked("mint", _id))`), eliminating a parameter the backend had to generate and track. The state machine (`CREATED → COMPLETED`) already prevents double-completion; the derived key is a redundant safety net at the SimpleToken level.

**Minimum expected amount (slippage protection).** V1 let users specify a `minExpectedAmount` floor. V2 removes this because mints complete within minutes using the current price, and burn prices are locked at request time and cannot change. With deterministic pricing, slippage protection adds no value — and a failed request would force the user to cancel, re-request, and wait through the cooldown again.

**Whitelist.** V1 optionally restricted which addresses could create requests via an `AddressesWhitelist` contract. V2 removes it — the backend already gatekeeps by choosing whether to complete requests, and `adminCancelMint`/`adminCancelBurn` can return funds from unwanted requests.

### New features

**Admin cancel.** `adminCancelMint` and `adminCancelBurn` allow the `DEFAULT_ADMIN_ROLE` to cancel stuck or failed requests, returning funds to the original provider. Previously, only the user could cancel, leaving abandoned requests in the contract indefinitely.

**PAUSER_ROLE.** The `pause()` function is separated from `DEFAULT_ADMIN_ROLE` onto a dedicated `PAUSER_ROLE`. This allows security monitoring services to pause the protocol within a single block of detecting anomalous activity, without waiting for a multisig quorum. `unpause()` remains on `DEFAULT_ADMIN_ROLE`.

**Configurable fees.** `setMintFee` and `setBurnFee` allow the admin to set fees up to 5% (`MAX_FEE`). Fees are applied as a discount on the output amount — they reduce what the user receives, and the difference stays in the system as over-collateralization (mints) or retained treasury balance (burns). Fees start at 0.

**Burn TTL.** `burnRequestTTL` sets a maximum age for burn requests (default 30 days). Expired requests cannot be completed by the service, but can still be cancelled by the user or admin.

**18-decimal enforcement.** `addAllowedToken` verifies the token has 18 decimals, preventing cross-decimal arithmetic errors.

**Issue token guard.** `addAllowedToken` rejects the issue token address, preventing a configuration error where the issue token is added as a deposit token.

### Co-existence with V1

V1 and V2 RequestsManagers co-exist during migration:

1. Deploy V2 and grant `SERVICE_ROLE` on SimpleToken to the V2 contract (multisig transaction)
2. Switch the frontend to route all new requests to V2
3. Stop the backend from completing new V1 requests
4. Wait for all pending V1 burn requests to settle
5. Revoke `SERVICE_ROLE` from V1 on SimpleToken (multisig transaction)

V1 is not paused during migration — it remains accessible for direct contract interactions, but the backend will not complete new V1 requests. Users who interact with V1 directly can cancel their requests to recover their funds.

V2 request counters start at 10,000 to avoid ID collisions with V1 (which has fewer than 10,000 existing orders).

### Trust model

The protocol is a managed system, not a trustless DEX. Users trust the admin multisig (`DEFAULT_ADMIN_ROLE` with 1-day transfer delay via `AccessControlDefaultAdminRules`). The admin can:

- Change the treasury address (`setTreasury`)
- Change fees retroactively on pending burns (`setBurnFee`)
- Cancel any request (`adminCancelMint`, `adminCancelBurn`)
- Withdraw all contract-held tokens (`emergencyWithdraw`)
- Set prices within bounds via the service wallet

What the admin **cannot** do (and what V2 specifically prevents):

- Mint arbitrary amounts of tokens — amounts are computed from bounded on-chain prices
- Bypass the price bounds in PriceStorage — each update is constrained to ±5%/±33% of the previous price
- Steal user funds via `completeMint`/`completeBurn` — output amounts are deterministic

## Auditor Reference

### Formulas

`price` = value of 1 issue token in base token terms (e.g., 1.05e18 means 1 avETHx = 1.05 avETH). All tokens are 18 decimals. `PRECISION` = 1e18.

| Operation | Formula | Rounding |
|-----------|---------|----------|
| Mint | `mintAmount = (depositAmount * PRECISION / price) * (PRECISION - mintFee) / PRECISION` | Truncates — user receives less (favors protocol) |
| Burn | `withdrawalAmount = (burnAmount * price / PRECISION) * (PRECISION - burnFee) / PRECISION` | Truncates — user receives less (favors protocol) |

Two sequential divisions means two truncation steps. Maximum error is < 2 wei at 18-decimal precision.

### State machine

```
requestMint/requestBurn
         │
         ▼
      CREATED ──── completeMint/completeBurn ───► COMPLETED
         │
         └──── cancelMint/cancelBurn ───► CANCELLED
              adminCancelMint/adminCancelBurn
```

All transitions are one-way. No path from COMPLETED or CANCELLED back to CREATED.

### Role permissions

| Function | DEFAULT_ADMIN_ROLE | SERVICE_ROLE | PAUSER_ROLE | Anyone |
|----------|:--:|:--:|:--:|:--:|
| completeMint, completeBurn | | X | | |
| pause | | | X | |
| unpause | X | | | |
| setTreasury, setMintFee, setBurnFee, setBurnRequestTTL, addAllowedToken, removeAllowedToken | X | | | |
| adminCancelMint, adminCancelBurn, emergencyWithdraw | X | | | |
| requestMint, requestBurn, cancelMint, cancelBurn | | | | X |

`DEFAULT_ADMIN_ROLE` uses `AccessControlDefaultAdminRules` with a 1-day transfer delay.

### External dependencies (trusted)

| Contract | Trust assumption |
|----------|-----------------|
| **PriceStorage** | Returns honest prices. Bounds (±5%/±33%) limit per-update manipulation. Write-once semantics prevent retroactive changes. |
| **SimpleToken** | Mints/burns only when called by SERVICE_ROLE holders. RequestsManagerV2 is granted this role. |
| **Deposit tokens** | Standard ERC-20 with 18 decimals. Non-rebasing, non-fee-on-transfer. |

### Known limitations / accepted risks

| Risk | Severity | Rationale for acceptance |
|------|----------|------------------------|
| `emergencyWithdraw` can drain tokens locked by pending requests | Medium | Admin is a multisig with 1-day transfer delay. The same admin already controls treasury, fees, and price oracle — removing this one capability doesn't meaningfully change the trust profile. |
| `setBurnFee` applies retroactively to pending burns | Low | Documented in natspec. Operational procedure: change fees only after pending burns are settled. |
| `setTreasury` can redirect funds mid-flight | Low | Pending `completeBurn` calls pull from the new treasury (which may not have approved). Operational constraint on admin. |
| Dust deposits can round to zero mint amount | Informational | 1 wei deposit at high price yields 0 issue tokens. Protocol keeps the dust. Economically irrelevant. |
| SERVICE_ROLE can censor (refuse to complete) | Informational | Inherent to async architecture. Users can always `cancel` to exit. |

## Development

### Build

```shell
forge install
forge build
```

### Test

```shell
forge test
```

### Deploy

```shell
# Testnet
PRODUCT=avUSD NETWORK=fuji     PRIVATE_KEY=... forge script DeployV2 --broadcast --rpc-url $FUJI_RPC
PRODUCT=avBTC NETWORK=fuji     PRIVATE_KEY=... forge script DeployV2 --broadcast --rpc-url $FUJI_RPC
PRODUCT=avETH NETWORK=sepolia  PRIVATE_KEY=... forge script DeployV2 --broadcast --rpc-url $SEPOLIA_RPC

# Mainnet
PRODUCT=avUSD NETWORK=avalanche PRIVATE_KEY=... forge script DeployV2 --broadcast --rpc-url $AVAX_RPC
PRODUCT=avBTC NETWORK=avalanche PRIVATE_KEY=... forge script DeployV2 --broadcast --rpc-url $AVAX_RPC
PRODUCT=avETH NETWORK=ethereum  PRIVATE_KEY=... forge script DeployV2 --broadcast --rpc-url $ETH_RPC
```
