/*
 * SimpleToken — ERC-20 Spec (properties ST_ERC20_1 .. ST_ERC20_14)
 *
 * Verified contract: SimpleTokenHarness (extends SimpleToken).
 * SimpleToken = ERC20PermitUpgradeable + AccessControlDefaultAdminRulesUpgradeable
 * (OZ v5, ERC-7201 namespaced storage). Keyed/keyless mint/burn.
 */

methods {
    // ERC20 envfree views (inherited OZ implementation)
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function allowance(address, address) external returns (uint256) envfree;
}

/* -------------------------------------------------------------------------- */
/*  Ghosts + hooks: sum-of-balances over the ERC-7201 _balances mapping       */
/* -------------------------------------------------------------------------- */

ghost mathint sumOfBalances {
    init_state axiom sumOfBalances == 0;
}

// _balances lives inside OZ's ERC-7201 ERC20Storage struct; bare-name hooks don't
// resolve (Gotcha 196). Hook the raw slot — ERC20StorageLocation IS the _balances
// mapping slot (first field of the struct).
// keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
hook Sload uint256 balance
    (slot 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00)[KEY address addr] {
    require sumOfBalances >= to_mathint(balance), "ghost consistent";
}

hook Sstore
    (slot 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00)[KEY address addr]
    uint256 newValue (uint256 oldValue) {
    sumOfBalances = sumOfBalances - oldValue + newValue;
}

/* -------------------------------------------------------------------------- */
/*  Filters                                                                    */
/* -------------------------------------------------------------------------- */

definition commonFilters(method f) returns bool =
    f.contract == currentContract
    && f.selector != sig:initialize(string,string).selector;

definition INFINITE() returns mathint = to_mathint(max_uint256);

// ST_ERC20_1 — sum(balanceOf) == totalSupply at every reachable state.
invariant totalSupplyIsSumOfBalances()
    to_mathint(totalSupply()) == sumOfBalances
    filtered { f -> f.selector != sig:initialize(string,string).selector }

// ST_ERC20_2 — totalSupply changes only via the four mint/burn overloads.
rule totalSupplyChangesOnlyViaMintBurn(env e, method f, calldataarg args)
    filtered { f -> commonFilters(f) } {
    requireInvariant totalSupplyIsSumOfBalances();

    uint256 before = totalSupply();
    f(e, args);
    uint256 after = totalSupply();

    assert after != before =>
        ( f.selector == sig:mint(address,uint256).selector
       || f.selector == sig:mint(bytes32,address,uint256).selector
       || f.selector == sig:burn(address,uint256).selector
       || f.selector == sig:burn(bytes32,address,uint256).selector ),
        "totalSupply changed by a function other than the four mint/burn overloads";
}

// ST_ERC20_3 — balanceOf(a) <= totalSupply for every account.
invariant balanceLeTotalSupply(address a)
    to_mathint(balanceOf(a)) <= to_mathint(totalSupply())
    filtered { f -> f.selector != sig:initialize(string,string).selector }
    {
        preserved {
            requireInvariant totalSupplyIsSumOfBalances();
            require sumOfBalances >= to_mathint(balanceOf(a)), "ghost consistent";
        }
    }

// ST_ERC20_4 — transfer conserves totalSupply and moves exactly amt from sender to receiver.
rule transferConservesSupply(env e, address to, uint256 amt) {
    requireInvariant totalSupplyIsSumOfBalances();
    address from = e.msg.sender;
    require from != to, "no self-transfer";

    uint256 supplyBefore = totalSupply();
    mathint fromBefore = to_mathint(balanceOf(from));
    mathint toBefore = to_mathint(balanceOf(to));

    transfer(e, to, amt);

    assert totalSupply() == supplyBefore, "transfer must conserve totalSupply";
    assert to_mathint(balanceOf(from)) == fromBefore - to_mathint(amt),
        "transfer must decrease sender balance by amt";
    assert to_mathint(balanceOf(to)) == toBefore + to_mathint(amt),
        "transfer must increase receiver balance by amt";
}

// ST_ERC20_5 — transferFrom conserves totalSupply and moves exactly amt from/to.
rule transferFromConservesSupply(env e, address from, address to, uint256 amt) {
    requireInvariant totalSupplyIsSumOfBalances();
    require from != to, "no self-transfer";

    uint256 supplyBefore = totalSupply();
    mathint fromBefore = to_mathint(balanceOf(from));
    mathint toBefore = to_mathint(balanceOf(to));

    transferFrom(e, from, to, amt);

    assert totalSupply() == supplyBefore, "transferFrom must conserve totalSupply";
    assert to_mathint(balanceOf(from)) == fromBefore - to_mathint(amt),
        "transferFrom must decrease from balance by amt";
    assert to_mathint(balanceOf(to)) == toBefore + to_mathint(amt),
        "transferFrom must increase to balance by amt";
}

// ST_ERC20_6 — self-transfer leaves sender balance unchanged.
rule selfTransferIdentity(env e, uint256 amt) {
    requireInvariant totalSupplyIsSumOfBalances();
    address who = e.msg.sender;
    mathint balBefore = to_mathint(balanceOf(who));
    transfer(e, who, amt);
    assert to_mathint(balanceOf(who)) == balBefore,
        "self-transfer must leave sender balance unchanged";
}

// ST_ERC20_7 — transferFrom decrements allowance by amt unless infinite.
rule transferFromDecrementsAllowance(env e, address from, address to, uint256 amt) {
    requireInvariant totalSupplyIsSumOfBalances();
    address spender = e.msg.sender;
    mathint allowBefore = to_mathint(allowance(from, spender));

    transferFrom(e, from, to, amt);

    mathint allowAfter = to_mathint(allowance(from, spender));
    assert allowBefore == INFINITE()
        ? allowAfter == allowBefore
        : allowAfter == allowBefore - to_mathint(amt),
        "transferFrom must decrement allowance by amt unless infinite approval";
}

// ST_ERC20_8 — transfer reverts when to or from is the zero address.
rule transferRejectsZeroAddress(env e, address to, uint256 amt) {
    require e.msg.value == 0, "no ETH";
    transfer@withrevert(e, to, amt);
    bool reverted = lastReverted;
    assert (to == 0 || e.msg.sender == 0) => reverted,
        "transfer must revert when to (or from) is the zero address";
}

// ST_ERC20_9 — transferFrom reverts when from or to is the zero address.
rule transferFromRejectsZeroAddress(env e, address from, address to, uint256 amt) {
    require e.msg.value == 0, "no ETH";
    transferFrom@withrevert(e, from, to, amt);
    bool reverted = lastReverted;
    assert (from == 0 || to == 0) => reverted,
        "transferFrom must revert when from or to is the zero address";
}

// ST_ERC20_10 — keyless mint raises balanceOf(account) and totalSupply each by amt; reverts if account == 0.
rule keylessMintEffect(env e, address account, uint256 amt) {
    requireInvariant totalSupplyIsSumOfBalances();
    mathint supplyBefore = to_mathint(totalSupply());
    mathint balBefore = to_mathint(balanceOf(account));

    mint(e, account, amt);

    assert account != 0, "mint must revert when account is the zero address";
    assert to_mathint(totalSupply()) == supplyBefore + to_mathint(amt),
        "mint must raise totalSupply by amt";
    assert to_mathint(balanceOf(account)) == balBefore + to_mathint(amt),
        "mint must raise balanceOf(account) by amt";
}

// ST_ERC20_11 — keyed mint raises balanceOf(account) and totalSupply each by amt; reverts if account == 0.
rule keyedMintEffect(env e, bytes32 key, address account, uint256 amt) {
    requireInvariant totalSupplyIsSumOfBalances();
    mathint supplyBefore = to_mathint(totalSupply());
    mathint balBefore = to_mathint(balanceOf(account));

    mint(e, key, account, amt);

    assert account != 0, "keyed mint must revert when account is the zero address";
    assert to_mathint(totalSupply()) == supplyBefore + to_mathint(amt),
        "keyed mint must raise totalSupply by amt";
    assert to_mathint(balanceOf(account)) == balBefore + to_mathint(amt),
        "keyed mint must raise balanceOf(account) by amt";
}

// ST_ERC20_12 — keyless burn lowers balanceOf(account) and totalSupply each by amt; reverts if account == 0.
rule keylessBurnEffect(env e, address account, uint256 amt) {
    requireInvariant totalSupplyIsSumOfBalances();
    mathint supplyBefore = to_mathint(totalSupply());
    mathint balBefore = to_mathint(balanceOf(account));

    burn(e, account, amt);

    assert account != 0, "burn must revert when account is the zero address";
    assert to_mathint(totalSupply()) == supplyBefore - to_mathint(amt),
        "burn must lower totalSupply by amt";
    assert to_mathint(balanceOf(account)) == balBefore - to_mathint(amt),
        "burn must lower balanceOf(account) by amt";
}

// ST_ERC20_13 — keyed burn lowers balanceOf(account) and totalSupply each by amt; reverts if account == 0.
rule keyedBurnEffect(env e, bytes32 key, address account, uint256 amt) {
    requireInvariant totalSupplyIsSumOfBalances();
    mathint supplyBefore = to_mathint(totalSupply());
    mathint balBefore = to_mathint(balanceOf(account));

    burn(e, key, account, amt);

    assert account != 0, "keyed burn must revert when account is the zero address";
    assert to_mathint(totalSupply()) == supplyBefore - to_mathint(amt),
        "keyed burn must lower totalSupply by amt";
    assert to_mathint(balanceOf(account)) == balBefore - to_mathint(amt),
        "keyed burn must lower balanceOf(account) by amt";
}

// ST_ERC20_14 — burn reverts when account == 0 or amt > balance.
rule burnRejectsInsufficientBalance(env e, address account, uint256 amt) {
    require e.msg.value == 0, "no ETH";
    requireInvariant totalSupplyIsSumOfBalances();
    mathint balBefore = to_mathint(balanceOf(account));

    burn@withrevert(e, account, amt);
    bool reverted = lastReverted;

    assert (account == 0 || to_mathint(amt) > balBefore) => reverted,
        "burn must revert when account is zero or amt exceeds balance";
}
