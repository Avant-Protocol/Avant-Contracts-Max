// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title DummyERC20Permit
/// @notice Minimal standard 18-decimal ERC-20 with EIP-2612 permit, used as a linkable
///         deposit / withdrawal token for Certora verification of RequestsManagerV2's
///         permit entrypoints. Plain, non-fee-on-transfer, non-rebasing, no-hook token.
contract DummyERC20Permit is ERC20, ERC20Permit {
    constructor() ERC20("DummyERC20Permit", "DUMP") ERC20Permit("DummyERC20Permit") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
