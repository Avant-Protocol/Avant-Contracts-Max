// RMV2_Base.spec — shared using / methods / definitions / helpers imported by all RMV2_ specs.

using SimpleTokenHarness as issueToken;
using DummyERC20Permit as withdrawalToken;
using DummyERC20A as tokenA;

methods {
    // ── mint request field getters ──
    function mintRequestState(uint256) external returns (IRequestsManagerV2.State) envfree;
    function mintRequestProvider(uint256) external returns (address) envfree;
    function mintRequestCreatedAt(uint256) external returns (uint40) envfree;
    function mintRequestToken(uint256) external returns (address) envfree;
    function mintRequestAmount(uint256) external returns (uint256) envfree;

    // ── burn request field getters ──
    function burnRequestState(uint256) external returns (IRequestsManagerV2.State) envfree;
    function burnRequestProvider(uint256) external returns (address) envfree;
    function burnRequestCreatedAt(uint256) external returns (uint40) envfree;
    function burnRequestPrice(uint256) external returns (uint128) envfree;
    function burnRequestFee(uint256) external returns (uint64) envfree;
    function burnRequestToken(uint256) external returns (address) envfree;
    function burnRequestAmount(uint256) external returns (uint256) envfree;

    // ── counters ──
    function mintRequestsCounter() external returns (uint256) envfree;
    function burnRequestsCounter() external returns (uint256) envfree;

    // ── config ──
    function PRECISION() external returns (uint256) envfree;
    function MAX_FEE() external returns (uint256) envfree;
    function mintFee() external returns (uint64) envfree;
    function burnFee() external returns (uint64) envfree;
    function treasuryAddress() external returns (address) envfree;
    function ISSUE_TOKEN_ADDRESS() external returns (address) envfree;
    function allowedTokens(address) external returns (bool) envfree;
    function paused() external returns (bool) envfree;
    function mintRequestTTL() external returns (uint64) envfree;
    function burnRequestTTL() external returns (uint64) envfree;
    function burnCancelWindow() external returns (uint64) envfree;

    // ── access control ──
    function hasRole(bytes32, address) external returns (bool) envfree;
    function DEFAULT_ADMIN_ROLE() external returns (bytes32) envfree;

    // ── compute helpers (harness) ──
    function computeMintAmount(uint256, uint128, uint64) external returns (uint256) envfree;
    function computeBurnAmount(uint256, uint128, uint64) external returns (uint256) envfree;

    // ── linked token views ──
    function _.balanceOf(address) external  => DISPATCHER(true);
    function issueToken.balanceOf(address) external returns (uint256) envfree;
    function issueToken.totalSupply() external returns (uint256) envfree;
    function tokenA.balanceOf(address) external returns (uint256) envfree;

    // ── PRICE_STORAGE summary: symbolic price > 0, cross-call consistent ──
    function _.lastPrice() external => priceSummary() expect (uint128, uint128);

    // ── permit summary: NONDET so *WithPermit wrappers can reach a success path ──
    function _.permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external => NONDET;

    // ── SafeERC20 internal summaries: route internal safeTransfer/safeTransferFrom to
    //    the concrete linked token so token flows stay on real OZ storage (Gotcha 155/198) ──
    function SafeERC20.safeTransfer(address token, address to, uint256 value) internal with (env e)
        => cvlSafeTransferFrom(e, token, calledContract, to, value);
    function SafeERC20.safeTransferFrom(address token, address from, address to, uint256 value) internal with (env e)
        => cvlSafeTransferFrom(e, token, from, to, value);
}

// ── Definitions ──

definition CREATED()   returns uint8 = assert_uint8(IRequestsManagerV2.State.CREATED);
definition COMPLETED() returns uint8 = assert_uint8(IRequestsManagerV2.State.COMPLETED);
definition CANCELLED() returns uint8 = assert_uint8(IRequestsManagerV2.State.CANCELLED);

// Restrict parametric rules to this contract's own methods.
definition commonFilters(method f) returns bool = f.contract == currentContract && !f.isView;

// ── Price summary ghost ──

persistent ghost uint128 ghostPrice;
persistent ghost uint128 ghostPriceTs;

function priceSummary() returns (uint128, uint128) {
    return (ghostPrice, ghostPriceTs);
}

// ── ERC-20 balance and total-supply tracking ghosts ──────────────────────────
//
// issueToken (SimpleTokenHarness) uses OZ v5 ERC-7201 namespaced storage.
//   _balances  : keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20"))-1)) & ~0xff
//   _totalSupply: base slot + 2
//
// withdrawalToken (DummyERC20Permit) and tokenA (DummyERC20A) use regular
// non-upgradeable OZ v5 ERC20 storage (_balances=slot0, _totalSupply=slot2).

// ── issueToken ──

persistent ghost mapping(address => mathint) ghostIssueBalance {
    init_state axiom forall address a. ghostIssueBalance[a] == 0;
    axiom forall address a. forall address b. ghostIssueBalance[a] + ghostIssueBalance[b] <= ghostIssueSupply;
}
persistent ghost mathint ghostIssueSupply {
    init_state axiom ghostIssueSupply == 0;
    axiom ghostIssueSupply <= max_uint;
}

hook Sload uint256 bal
    issueToken.(slot 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00)[KEY address addr] {
    require ghostIssueBalance[addr] == to_mathint(bal);
}
hook Sstore
    issueToken.(slot 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00)[KEY address addr]
    uint256 newVal (uint256 oldVal) {
    ghostIssueBalance[addr] = ghostIssueBalance[addr] - to_mathint(oldVal) + to_mathint(newVal);
}

hook Sload uint256 sup
    issueToken.(slot 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace02) {
    require ghostIssueSupply == to_mathint(sup);
}
hook Sstore
    issueToken.(slot 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace02)
    uint256 newVal (uint256 oldVal) {
    ghostIssueSupply = ghostIssueSupply - to_mathint(oldVal) + to_mathint(newVal);
}

// ── withdrawalToken ──

persistent ghost mapping(address => mathint) ghostWithdrawalBalance {
    init_state axiom forall address a. ghostWithdrawalBalance[a] == 0;
    axiom forall address a. forall address b. ghostWithdrawalBalance[a] + ghostWithdrawalBalance[b] <= ghostWithdrawalSupply;
}
persistent ghost mathint ghostWithdrawalSupply {
    init_state axiom ghostWithdrawalSupply == 0;
    axiom ghostWithdrawalSupply <= max_uint;
}

hook Sload uint256 bal withdrawalToken.(slot 0)[KEY address addr] {
    require ghostWithdrawalBalance[addr] == to_mathint(bal);
}
hook Sstore withdrawalToken.(slot 0)[KEY address addr] uint256 newVal (uint256 oldVal) {
    ghostWithdrawalBalance[addr] = ghostWithdrawalBalance[addr] - to_mathint(oldVal) + to_mathint(newVal);
}

hook Sload uint256 sup withdrawalToken.(slot 2) {
    require ghostWithdrawalSupply == to_mathint(sup);
}
hook Sstore withdrawalToken.(slot 2) uint256 newVal (uint256 oldVal) {
    ghostWithdrawalSupply = ghostWithdrawalSupply - to_mathint(oldVal) + to_mathint(newVal);
}

// ── tokenA ──

persistent ghost mapping(address => mathint) ghostTokenABalance {
    init_state axiom forall address a. ghostTokenABalance[a] == 0;
    axiom forall address a. forall address b. ghostTokenABalance[a] + ghostTokenABalance[b] <= ghostTokenASupply;
}
persistent ghost mathint ghostTokenASupply {
    init_state axiom ghostTokenASupply == 0;
    axiom ghostTokenASupply <= max_uint;
}

hook Sload uint256 bal tokenA.(slot 0)[KEY address addr] {
    require ghostTokenABalance[addr] == to_mathint(bal);
}
hook Sstore tokenA.(slot 0)[KEY address addr] uint256 newVal (uint256 oldVal) {
    ghostTokenABalance[addr] = ghostTokenABalance[addr] - to_mathint(oldVal) + to_mathint(newVal);
}

hook Sload uint256 sup tokenA.(slot 2) {
    require ghostTokenASupply == to_mathint(sup);
}
hook Sstore tokenA.(slot 2) uint256 newVal (uint256 oldVal) {
    ghostTokenASupply = ghostTokenASupply - to_mathint(oldVal) + to_mathint(newVal);
}

// ── Shared helpers ──

function setup(env e) {
    require e.msg.value == 0, "no ETH";
    require e.msg.sender != 0, "non-zero sender";
    require e.msg.sender != currentContract, "sender not self";
    require currentContract != treasuryAddress(), "This contract different address than treasury";
    require e.msg.sender != treasuryAddress(), "msg.sender different address than treasury";
}

function cvlSafeTransfer(env e, address token, address to, uint256 value) {
    env e2;
    require e2.msg.sender == currentContract, "SAFE: the caller of safeTransfer is only this contract";
    if      (token == issueToken)      { issueToken.transfer(e2, to, value); }
    else if (token == withdrawalToken) { withdrawalToken.transfer(e2, to, value); }
    else if (token == tokenA)          { tokenA.transfer(e2, to, value); }
}

function cvlSafeTransferFrom(env e, address token, address from, address to, uint256 value) {
    if      (token == issueToken)      { issueToken.transferFrom(e, from, to, value); }
    else if (token == withdrawalToken) { withdrawalToken.transferFrom(e, from, to, value); }
    else if (token == tokenA)          { tokenA.transferFrom(e, from, to, value); }
}

