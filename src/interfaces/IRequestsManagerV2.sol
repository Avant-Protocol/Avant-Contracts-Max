// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceStorage} from "./IPriceStorage.sol";

/// @title IRequestsManagerV2
/// @notice Interface for the mint/burn request manager. Amounts are derived on-chain from
///         PriceStorage; SERVICE_ROLE only triggers settlement, it never supplies an amount.
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
    error MintRequestExpired(uint256 id, uint40 createdAt, uint64 ttl);
    error BurnCancelWindowClosed(uint256 id, uint40 createdAt, uint64 window);
    error ZeroAmountOut(uint256 id);
    error PriceNotSet();
    error FeeTooHigh(uint64 fee);

    // ──────────────────────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────────────────────

    event MintRequestCreated(uint256 indexed id, address indexed provider, address depositToken, uint256 amount);
    event MintRequestCompleted(
        uint256 indexed id,
        address indexed provider,
        uint256 depositAmount,
        uint256 mintedAmount,
        uint128 price,
        uint64 fee
    );
    event MintRequestCancelled(uint256 indexed id, address indexed provider);
    event MintRequestAdminCancelled(uint256 indexed id, address indexed provider, address indexed cancelledBy);

    event BurnRequestCreated(
        uint256 indexed id,
        address indexed provider,
        address withdrawalTokenAddress,
        uint256 issueTokenAmount,
        uint128 price,
        uint64 fee
    );
    event BurnRequestCompleted(
        uint256 indexed id,
        address indexed provider,
        uint256 burnedAmount,
        uint256 withdrawalAmount,
        uint128 price,
        uint64 fee
    );
    event BurnRequestCancelled(uint256 indexed id, address indexed provider);
    event BurnRequestAdminCancelled(uint256 indexed id, address indexed provider, address indexed cancelledBy);

    event TreasurySet(address indexed treasuryAddress);
    event AllowedTokenAdded(address indexed tokenAddress);
    event AllowedTokenRemoved(address indexed tokenAddress);
    event EmergencyWithdrawn(address indexed tokenAddress, address indexed recipient, uint256 amount);
    event BurnRequestTTLSet(uint64 ttl);
    event MintRequestTTLSet(uint64 ttl);
    event BurnCancelWindowSet(uint64 window);
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

    /// @notice Mint request. Price and the live mintFee are determined at completion time from
    ///         PriceStorage.lastPrice() — neither is locked at request time (unlike burns).
    ///         createdAt bounds the request-to-completion interval via mintRequestTTL, so a
    ///         stale mint cannot be settled against an arbitrary far-future price. Settlement
    ///         within the window still uses the latest price; cancelMint refunds an expired
    ///         (or any pending) request.
    /// @dev Packed into 3 storage slots:
    ///      Slot 0: provider (20) + state (1) + createdAt (5) = 26 bytes
    ///      Slot 1: token (20 bytes)
    ///      Slot 2: amount (32 bytes)
    struct MintRequest {
        address provider; // 20 bytes ─┐
        State state; //  1 byte        │ slot 0
        uint40 createdAt; //  5 bytes ─┘
        address token; // 20 bytes ───── slot 1
        uint256 amount; // 32 bytes ──── slot 2
    }

    /// @notice Burn request. The request-time price is captured as a ceiling on the settlement
    ///         rate and the fee is locked; completeBurn settles at the lower of that price and
    ///         the completion-time price.
    /// @dev Packed into 4 storage slots:
    ///      Slot 0: provider (20) + state (1) + createdAt (5) = 26 bytes
    ///      Slot 1: price (16) + fee (8) = 24 bytes
    ///      Slot 2: token (20 bytes)
    ///      Slot 3: amount (32 bytes)
    struct BurnRequest {
        address provider; // 20 bytes ─┐
        State state; //  1 byte        │ slot 0
        uint40 createdAt; //  5 bytes ─┘
        uint128 price; // 16 bytes ────┐ slot 1
        uint64 fee; //  8 bytes ───────┘
        address token; // 20 bytes ───── slot 2
        uint256 amount; // 32 bytes ──── slot 3
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
    function setMintRequestTTL(uint64 _ttl) external;
    function setBurnCancelWindow(uint64 _window) external;
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
    function mintRequestTTL() external view returns (uint64);
    function burnCancelWindow() external view returns (uint64);
    function mintFee() external view returns (uint64);
    function burnFee() external view returns (uint64);
    function mintRequestsCounter() external view returns (uint256);
    function burnRequestsCounter() external view returns (uint256);

    function PRECISION() external view returns (uint256);
    function MAX_FEE() external view returns (uint256);

    function mintRequests(uint256 _id)
        external
        view
        returns (address provider, State state, uint40 createdAt, address token, uint256 amount);

    function burnRequests(uint256 _id)
        external
        view
        returns (
            address provider,
            State state,
            uint40 createdAt,
            uint128 price,
            uint64 fee,
            address token,
            uint256 amount
        );
}
