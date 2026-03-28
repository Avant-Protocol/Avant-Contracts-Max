// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPriceStorage} from "./interfaces/IPriceStorage.sol";
import {IRequestsManagerV2} from "./interfaces/IRequestsManagerV2.sol";
import {ISimpleToken} from "./interfaces/ISimpleToken.sol";

/// @title RequestsManagerV2
/// @notice Manages mint/burn requests for the Avant Protocol with on-chain price computation.
///
/// Architecture overview:
///   - Mints use the LATEST price from PriceStorage at completion time (executed within minutes).
///   - Burns lock in the price VALUE at REQUEST time (stored in the struct), settling days later.
///   - SERVICE_ROLE can only trigger execution — it cannot influence the computed amounts.
///   - All tokens must be 18 decimals. Price = value of 1 issue token in deposit token terms.
///   - Compatible with the existing V1 PriceStorage contract (no PriceStorageV2 needed).
///
/// Migration note:
///   Request counters start at 10,000 to avoid ID collisions with the V1 RequestsManager,
///   which has fewer than 10,000 existing orders across all deployments.
contract RequestsManagerV2 is IRequestsManagerV2, AccessControlDefaultAdminRules, Pausable {
  using SafeERC20 for IERC20;

  bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  uint256 public constant PRECISION = 1e18;
  uint256 public constant MAX_FEE = 0.05e18; // 5%
  uint256 private constant INITIAL_COUNTER = 10_000;

  address public immutable ISSUE_TOKEN_ADDRESS;
  IPriceStorage public immutable PRICE_STORAGE;

  address public treasuryAddress;

  mapping(address token => bool isAllowed) public allowedTokens;

  /// @dev Packed into a single storage slot (64 * 3 = 192 bits).
  uint64 public burnRequestTTL;
  uint64 public mintFee; // scaled by PRECISION, e.g. 0.01e18 = 1%
  uint64 public burnFee;

  uint256 public mintRequestsCounter;
  mapping(uint256 id => MintRequest request) public mintRequests;

  uint256 public burnRequestsCounter;
  mapping(uint256 id => BurnRequest request) public burnRequests;

  // ──────────────────────────────────────────────────────────────
  //  Modifiers
  // ──────────────────────────────────────────────────────────────

  modifier mintRequestExist(uint256 _id) {
    if (mintRequests[_id].provider == address(0)) {
      revert MintRequestNotExist(_id);
    }
    _;
  }

  modifier burnRequestExist(uint256 _id) {
    if (burnRequests[_id].provider == address(0)) {
      revert BurnRequestNotExist(_id);
    }
    _;
  }

  modifier allowedToken(address _tokenAddress) {
    _assertNonZero(_tokenAddress);
    if (!allowedTokens[_tokenAddress]) {
      revert TokenNotAllowed(_tokenAddress);
    }
    _;
  }

  // ──────────────────────────────────────────────────────────────
  //  Constructor
  // ──────────────────────────────────────────────────────────────

  constructor(
    address _issueTokenAddress,
    address _priceStorageAddress,
    address _treasuryAddress,
    address[] memory _allowedTokenAddresses,
    uint64 _burnRequestTTL
  ) AccessControlDefaultAdminRules(1 days, msg.sender) {
    ISSUE_TOKEN_ADDRESS = _assertNonZero(_issueTokenAddress);
    treasuryAddress = _assertNonZero(_treasuryAddress);

    _assertNonZero(_priceStorageAddress);
    if (_priceStorageAddress.code.length == 0) revert InvalidContractAddress(_priceStorageAddress);
    PRICE_STORAGE = IPriceStorage(_priceStorageAddress);

    for (uint256 i; i < _allowedTokenAddresses.length; i++) {
      _addAllowedToken(_allowedTokenAddresses[i]);
    }

    burnRequestTTL = _burnRequestTTL;

    mintRequestsCounter = INITIAL_COUNTER;
    burnRequestsCounter = INITIAL_COUNTER;
  }

  // ──────────────────────────────────────────────────────────────
  //  Admin functions
  // ──────────────────────────────────────────────────────────────

  function setTreasury(address _treasuryAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _assertNonZero(_treasuryAddress);
    treasuryAddress = _treasuryAddress;
    emit TreasurySet(_treasuryAddress);
  }

  function addAllowedToken(address _allowedTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _addAllowedToken(_allowedTokenAddress);
  }

  function removeAllowedToken(address _allowedTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _assertNonZero(_allowedTokenAddress);
    allowedTokens[_allowedTokenAddress] = false;
    emit AllowedTokenRemoved(_allowedTokenAddress);
  }

  function pause() external onlyRole(PAUSER_ROLE) {
    Pausable._pause();
  }

  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
    Pausable._unpause();
  }

  function setBurnRequestTTL(uint64 _ttl) external onlyRole(DEFAULT_ADMIN_ROLE) {
    burnRequestTTL = _ttl;
    emit BurnRequestTTLSet(_ttl);
  }

  /// @notice Sets the mint fee. Applies to all pending mint requests completed after this change.
  function setMintFee(uint64 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_fee > MAX_FEE) revert FeeTooHigh(_fee);
    mintFee = _fee;
    emit MintFeeSet(_fee);
  }

  /// @notice Sets the burn fee. WARNING: this applies retroactively to all pending burn requests
  ///         since fees are evaluated at completion time, not request time. Change fees only after
  ///         all pending burn requests have been completed, or notify affected users.
  function setBurnFee(uint64 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_fee > MAX_FEE) revert FeeTooHigh(_fee);
    burnFee = _fee;
    emit BurnFeeSet(_fee);
  }

  // ──────────────────────────────────────────────────────────────
  //  Mint functions
  // ──────────────────────────────────────────────────────────────

  function requestMint(
    address _depositTokenAddress,
    uint256 _amount
  ) public allowedToken(_depositTokenAddress) whenNotPaused {
    _assertAmount(_amount);

    IERC20(_depositTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);

    uint256 id = mintRequestsCounter;
    mintRequests[id] = MintRequest({
      provider: msg.sender,
      state: State.CREATED,
      token: _depositTokenAddress,
      amount: _amount
    });

    unchecked { mintRequestsCounter++; }

    emit MintRequestCreated(id, msg.sender, _depositTokenAddress, _amount);
  }

  function requestMintWithPermit(
    address _depositTokenAddress,
    uint256 _amount,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external {
    // try/catch tolerates permit frontrunning — if permit was already consumed, we proceed
    // with an existing allowance.
    try IERC20Permit(_depositTokenAddress).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s) {} catch {}
    requestMint(_depositTokenAddress, _amount);
  }

  function cancelMint(uint256 _id) external mintRequestExist(_id) {
    MintRequest storage request = mintRequests[_id];
    _assertAddressMatch(request.provider, msg.sender);
    _assertState(State.CREATED, request.state);

    request.state = State.CANCELLED;

    IERC20(request.token).safeTransfer(msg.sender, request.amount);

    emit MintRequestCancelled(_id, msg.sender);
  }

  function adminCancelMint(uint256 _id) external onlyRole(DEFAULT_ADMIN_ROLE) mintRequestExist(_id) {
    MintRequest storage request = mintRequests[_id];
    _assertState(State.CREATED, request.state);

    request.state = State.CANCELLED;

    IERC20(request.token).safeTransfer(request.provider, request.amount);

    emit MintRequestAdminCancelled(_id, request.provider, msg.sender);
  }

  /// @notice Completes a mint request using the latest price from PriceStorage.
  ///         mintAmount = depositAmount * PRECISION / price, minus fee.
  ///         The rate is whatever the current price is at completion time. Price updates
  ///         between request and completion change the computed amount, bounded by
  ///         PriceStorage's per-update percentage limits.
  function completeMint(uint256 _id) external onlyRole(SERVICE_ROLE) mintRequestExist(_id) {
    MintRequest storage request = mintRequests[_id];
    _assertState(State.CREATED, request.state);

    (uint128 price,) = PRICE_STORAGE.lastPrice();
    if (price == 0) revert PriceNotSet(0);

    // Cache before state change to avoid extra SLOADs after external calls
    address provider = request.provider;
    address token = request.token;
    uint256 depositAmount = request.amount;

    // price = value of 1 issue token in deposit token terms
    // Integer division truncates — rounding favors the protocol (user receives less).
    uint256 mintAmount = (depositAmount * PRECISION) / price;

    // Fee is always applied; when mintFee == 0, this is a no-op (multiplies by 1).
    // Division truncates — again favoring the protocol.
    mintAmount = (mintAmount * (PRECISION - mintFee)) / PRECISION;

    request.state = State.COMPLETED;

    IERC20(token).safeTransfer(treasuryAddress, depositAmount);

    bytes32 idempotencyKey = keccak256(abi.encodePacked("mint", _id));
    ISimpleToken(ISSUE_TOKEN_ADDRESS).mint(idempotencyKey, provider, mintAmount);

    emit MintRequestCompleted(_id, provider, depositAmount, mintAmount, price, mintFee);
  }

  // ──────────────────────────────────────────────────────────────
  //  Burn functions
  // ──────────────────────────────────────────────────────────────

  /// @notice Requests a burn. The current price value is captured in the struct so
  ///         the withdrawal amount is determined at request time, not completion time.
  ///         This prevents users from exploiting price movements during the settlement delay.
  function requestBurn(
    uint256 _issueTokenAmount,
    address _withdrawalTokenAddress
  ) public allowedToken(_withdrawalTokenAddress) whenNotPaused {
    _assertAmount(_issueTokenAmount);

    IERC20(ISSUE_TOKEN_ADDRESS).safeTransferFrom(msg.sender, address(this), _issueTokenAmount);

    (uint128 price,) = PRICE_STORAGE.lastPrice();
    if (price == 0) revert PriceNotSet(0);

    uint256 id = burnRequestsCounter;
    burnRequests[id] = BurnRequest({
      provider: msg.sender,
      state: State.CREATED,
      createdAt: uint40(block.timestamp),
      price: price,
      token: _withdrawalTokenAddress,
      amount: _issueTokenAmount
    });

    unchecked { burnRequestsCounter++; }

    emit BurnRequestCreated(id, msg.sender, _withdrawalTokenAddress, _issueTokenAmount, price);
  }

  function requestBurnWithPermit(
    uint256 _issueTokenAmount,
    address _withdrawalTokenAddress,
    uint256 _deadline,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external {
    try IERC20Permit(ISSUE_TOKEN_ADDRESS).permit(msg.sender, address(this), _issueTokenAmount, _deadline, _v, _r, _s) {} catch {}
    requestBurn(_issueTokenAmount, _withdrawalTokenAddress);
  }

  function cancelBurn(uint256 _id) external burnRequestExist(_id) {
    BurnRequest storage request = burnRequests[_id];
    _assertAddressMatch(request.provider, msg.sender);
    _assertState(State.CREATED, request.state);

    request.state = State.CANCELLED;

    IERC20(ISSUE_TOKEN_ADDRESS).safeTransfer(msg.sender, request.amount);

    emit BurnRequestCancelled(_id, msg.sender);
  }

  function adminCancelBurn(uint256 _id) external onlyRole(DEFAULT_ADMIN_ROLE) burnRequestExist(_id) {
    BurnRequest storage request = burnRequests[_id];
    _assertState(State.CREATED, request.state);

    request.state = State.CANCELLED;

    IERC20(ISSUE_TOKEN_ADDRESS).safeTransfer(request.provider, request.amount);

    emit BurnRequestAdminCancelled(_id, request.provider, msg.sender);
  }

  /// @notice Completes a burn request using the price locked at request time.
  ///         withdrawalAmount = burnAmount * price / PRECISION, minus fee.
  ///         The treasury must have approved this contract for the withdrawal token.
  function completeBurn(uint256 _id) external onlyRole(SERVICE_ROLE) burnRequestExist(_id) {
    BurnRequest storage request = burnRequests[_id];
    _assertState(State.CREATED, request.state);

    if (burnRequestTTL > 0 && block.timestamp > uint256(request.createdAt) + burnRequestTTL) {
      revert BurnRequestExpired(_id, request.createdAt, burnRequestTTL);
    }

    // Cache before state change
    address provider = request.provider;
    address token = request.token;
    uint256 burnAmount = request.amount;
    uint128 price = request.price; // locked at request time — no external call needed

    // Integer division truncates — rounding favors the protocol (user receives less).
    uint256 withdrawalAmount = (burnAmount * price) / PRECISION;

    // Fee is always applied; when burnFee == 0, this is a no-op.
    // Division truncates — again favoring the protocol.
    withdrawalAmount = (withdrawalAmount * (PRECISION - burnFee)) / PRECISION;

    request.state = State.COMPLETED;

    bytes32 idempotencyKey = keccak256(abi.encodePacked("burn", _id));
    ISimpleToken(ISSUE_TOKEN_ADDRESS).burn(idempotencyKey, address(this), burnAmount);

    // slither-disable-next-line arbitrary-send-erc20
    IERC20(token).safeTransferFrom(treasuryAddress, provider, withdrawalAmount);

    emit BurnRequestCompleted(_id, provider, burnAmount, withdrawalAmount, price, burnFee);
  }

  // ──────────────────────────────────────────────────────────────
  //  Emergency
  // ──────────────────────────────────────────────────────────────

  /// @notice Withdraws the entire balance of a token held by this contract.
  ///         WARNING: this includes tokens locked by pending mint and burn requests.
  ///         Users with pending requests would be unable to cancel until the contract
  ///         is re-funded. Use only in genuine emergencies (e.g. token migration, exploit
  ///         response). This function is gated by DEFAULT_ADMIN_ROLE (multisig with
  ///         1-day transfer delay) and cannot be called by SERVICE_ROLE or PAUSER_ROLE.
  function emergencyWithdraw(IERC20 _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 balance = _token.balanceOf(address(this));
    _token.safeTransfer(msg.sender, balance);

    emit EmergencyWithdrawn(address(_token), msg.sender, balance);
  }

  // ──────────────────────────────────────────────────────────────
  //  Internal
  // ──────────────────────────────────────────────────────────────

  function _addAllowedToken(address _tokenAddress) internal {
    _assertNonZero(_tokenAddress);
    if (_tokenAddress.code.length == 0) revert InvalidTokenAddress(_tokenAddress);
    if (_tokenAddress == ISSUE_TOKEN_ADDRESS) revert InvalidTokenAddress(_tokenAddress);

    uint8 decimals = IERC20Metadata(_tokenAddress).decimals();
    if (decimals != 18) revert InvalidTokenDecimals(_tokenAddress, decimals);

    allowedTokens[_tokenAddress] = true;
    emit AllowedTokenAdded(_tokenAddress);
  }

  function _assertNonZero(address _address) internal pure returns (address) {
    if (_address == address(0)) revert ZeroAddress();
    return _address;
  }

  function _assertState(State _expected, State _current) internal pure {
    if (_expected != _current) revert IllegalState(_expected, _current);
  }

  function _assertAddressMatch(address _expected, address _actual) internal pure {
    if (_expected != _actual) revert IllegalAddress(_expected, _actual);
  }

  function _assertAmount(uint256 _amount) internal pure {
    if (_amount == 0) revert InvalidAmount(_amount);
  }
}
