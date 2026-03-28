// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceStorage} from "./IPriceStorage.sol";

/// @title IRequestsManagerV2
/// @notice Interface for the hardened mint/burn request manager. Prices are determined on-chain
///         via PriceStorage — the SERVICE_ROLE cannot influence amounts, only trigger execution.
interface IRequestsManagerV2 {
  // ──────────────────────────────────────────────────────────────
  //  Errors
  // ──────────────────────────────────────────────────────────────

  error InvalidAmount(uint256 amount);
  error ZeroAddress();
  error IllegalState(State expected, State current);
  error IllegalAddress(address expected, address actual);
  error MintRequestNotExist(uint256 id);
  error BurnRequestNotExist(uint256 id);
  error TokenNotAllowed(address token);
  error InvalidContractAddress(address addr);
  error InvalidTokenAddress(address token);
  error InvalidTokenDecimals(address token, uint8 decimals);
  error BurnRequestExpired(uint256 id, uint40 createdAt, uint64 ttl);
  error PriceNotSet(uint256 context);
  error FeeTooHigh(uint64 fee);

  // ──────────────────────────────────────────────────────────────
  //  Events
  // ──────────────────────────────────────────────────────────────

  event MintRequestCreated(
    uint256 indexed id,
    address indexed provider,
    address depositToken,
    uint256 amount
  );
  event MintRequestCompleted(uint256 indexed id, address indexed provider, uint256 depositAmount, uint256 mintedAmount, uint128 price, uint64 fee);
  event MintRequestCancelled(uint256 indexed id, address indexed provider);
  event MintRequestAdminCancelled(uint256 indexed id, address indexed provider, address indexed cancelledBy);

  event BurnRequestCreated(
    uint256 indexed id,
    address indexed provider,
    address withdrawalTokenAddress,
    uint256 issueTokenAmount,
    uint128 price
  );
  event BurnRequestCompleted(uint256 indexed id, address indexed provider, uint256 burnedAmount, uint256 withdrawalAmount, uint128 price, uint64 fee);
  event BurnRequestCancelled(uint256 indexed id, address indexed provider);
  event BurnRequestAdminCancelled(uint256 indexed id, address indexed provider, address indexed cancelledBy);

  event TreasurySet(address indexed treasuryAddress);
  event AllowedTokenAdded(address indexed tokenAddress);
  event AllowedTokenRemoved(address indexed tokenAddress);
  event EmergencyWithdrawn(address indexed tokenAddress, address indexed recipient, uint256 amount);
  event BurnRequestTTLSet(uint64 ttl);
  event MintFeeSet(uint64 fee);
  event BurnFeeSet(uint64 fee);

  // ──────────────────────────────────────────────────────────────
  //  Types
  // ──────────────────────────────────────────────────────────────

  enum State {
    CREATED,
    COMPLETED,
    CANCELLED
  }

  /// @notice Mint request. Price is determined at completion time from PriceStorage.lastPrice().
  /// @dev Packed into 3 storage slots:
  ///      Slot 0: provider (20) + state (1) = 21 bytes
  ///      Slot 1: token (20 bytes)
  ///      Slot 2: amount (32 bytes)
  struct MintRequest {
    address provider;           // 20 bytes ─┐
    State state;                //  1 byte  ─┘ slot 0
    address token;              // 20 bytes ── slot 1
    uint256 amount;             // 32 bytes ── slot 2
  }

  /// @notice Burn request. Price value is captured at request time from PriceStorage.lastPrice().
  /// @dev Packed into 4 storage slots:
  ///      Slot 0: provider (20) + state (1) + createdAt (5) = 26 bytes
  ///      Slot 1: price (16 bytes)
  ///      Slot 2: token (20 bytes)
  ///      Slot 3: amount (32 bytes)
  struct BurnRequest {
    address provider;           // 20 bytes ─┐
    State state;                //  1 byte   │ slot 0
    uint40 createdAt;           //  5 bytes ─┘
    uint128 price;              // 16 bytes ── slot 1
    address token;              // 20 bytes ── slot 2
    uint256 amount;             // 32 bytes ── slot 3
  }

  // ──────────────────────────────────────────────────────────────
  //  Admin functions
  // ──────────────────────────────────────────────────────────────

  function setTreasury(address _treasuryAddress) external;
  function addAllowedToken(address _allowedTokenAddress) external;
  function removeAllowedToken(address _allowedTokenAddress) external;
  function pause() external;
  function unpause() external;
  function setBurnRequestTTL(uint64 _ttl) external;
  function setMintFee(uint64 _fee) external;
  function setBurnFee(uint64 _fee) external;
  function emergencyWithdraw(IERC20 _token) external;

  // ──────────────────────────────────────────────────────────────
  //  Mint functions
  // ──────────────────────────────────────────────────────────────

  function requestMint(address _depositTokenAddress, uint256 _amount) external;
  function requestMintWithPermit(
    address _depositTokenAddress,
    uint256 _amount,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external;
  function cancelMint(uint256 _id) external;
  function adminCancelMint(uint256 _id) external;
  function completeMint(uint256 _id) external;

  // ──────────────────────────────────────────────────────────────
  //  Burn functions
  // ──────────────────────────────────────────────────────────────

  function requestBurn(uint256 _issueTokenAmount, address _withdrawalTokenAddress) external;
  function requestBurnWithPermit(
    uint256 _issueTokenAmount,
    address _withdrawalTokenAddress,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external;
  function cancelBurn(uint256 _id) external;
  function adminCancelBurn(uint256 _id) external;
  function completeBurn(uint256 _id) external;

  // ──────────────────────────────────────────────────────────────
  //  View functions
  // ──────────────────────────────────────────────────────────────

  function ISSUE_TOKEN_ADDRESS() external view returns (address);
  function PRICE_STORAGE() external view returns (IPriceStorage);
  function SERVICE_ROLE() external view returns (bytes32);
  function PAUSER_ROLE() external view returns (bytes32);
  function treasuryAddress() external view returns (address);
  function allowedTokens(address _token) external view returns (bool);
  function burnRequestTTL() external view returns (uint64);
  function mintFee() external view returns (uint64);
  function burnFee() external view returns (uint64);
  function mintRequestsCounter() external view returns (uint256);
  function burnRequestsCounter() external view returns (uint256);
}
