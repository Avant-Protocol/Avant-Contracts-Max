// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DummyERC20} from "./DummyERC20.sol";

/// @title DummyERC20A
/// @notice Second linkable ERC-20 harness token, identical to DummyERC20, used when a
///         spec needs two independent token instances simultaneously (e.g. AC_41 uses this
///         as a deposit token distinct from the DummyERC20Permit already linked elsewhere).
contract DummyERC20A is DummyERC20 {}
