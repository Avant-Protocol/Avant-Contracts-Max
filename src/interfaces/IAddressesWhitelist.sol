// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAddressesWhitelist {
  error ZeroAddress();

  event AccountAdded(address account);
  event AccountRemoved(address account);

  function isAllowedAccount(address _account) external view returns (bool isAllowed);
}
