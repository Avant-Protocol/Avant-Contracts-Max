// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title DummyERC20
/// @notice Minimal standard 18-decimal ERC-20 used as a linkable token for Certora
///         verification of RequestsManagerV2. It is a plain, non-fee-on-transfer,
///         non-rebasing, no-hook token — matching the protocol's allowlist assumption.
///
///         In addition to the standard ERC-20 surface it exposes the keyed
///         `mint(bytes32,address,uint256)` / `burn(bytes32,address,uint256)` overloads of
///         ISimpleToken so it can stand in as the ISSUE_TOKEN for completeMint/completeBurn
///         and move a tracked totalSupply (R-1/R-2/R-65/R-66). The key is ignored here —
///         SimpleToken idempotency is verified separately in its own spec (S-9..S-15).
contract DummyERC20 is ERC20 {
    constructor() ERC20("DummyERC20", "DUM") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // Standard supply hooks (used in tests / harness setup).
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    // ISimpleToken keyed overloads — the RequestsManagerV2 calls these on the issue token.
    // The idempotency key is intentionally unused here (modelled in SimpleToken's own spec).
    function mint(bytes32, address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(bytes32, address account, uint256 amount) external {
        _burn(account, amount);
    }
}
