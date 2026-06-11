// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPriceStorage} from "./interfaces/IPriceStorage.sol";
import {IRequestsManagerV2} from "./interfaces/IRequestsManagerV2.sol";
import {ISimpleToken} from "./interfaces/ISimpleToken.sol";

/// @title RequestsManagerV2
/// @notice Mint/burn request manager with on-chain price computation. Users open requests and
///         escrow the input; SERVICE_ROLE completes them but only ever triggers settlement —
///         every amount is derived on-chain from PriceStorage, never supplied by the caller.
///
/// Pricing:
///   - Mints settle at the latest PriceStorage price at completion, minus the live mintFee.
///     mintRequestTTL bounds the request-to-completion interval; an expired mint is refundable.
///   - Burns settle at min(request-time price, completion-time price) minus the fee locked at
///     request time: a price fall is borne by the redeemer, a rise cannot be arbitraged. The
///     provider may self-cancel only within burnCancelWindow, so the ceiling can't be re-rolled.
///     Price freshness is not checked on-chain (lastPrice's timestamp is ignored).
///
/// Tokens: the allowlist is admin-curated and must contain only standard 18-decimal ERC-20s
/// (no fee-on-transfer, rebasing, or transfer hooks) that share the issue token's price
/// denomination — a single global price values them all. Only the 18-decimal check is on-chain.
///
/// Reentrancy: no guard. Request state leaves CREATED before any transfer, and completion and
/// cancellation are role- or provider-gated, so a re-entrant caller (e.g. a misbehaving
/// allowlisted token) can only ever move its own escrow. Do not allowlist a hook token.
///
/// Idempotency: the SimpleToken key is derived on-chain as keccak256("mint"|"burn", id); it must
/// stay distinct from any other minter authorised on the issue token.
contract RequestsManagerV2 is IRequestsManagerV2, AccessControlDefaultAdminRules, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_FEE = 0.05e18; // 5%
    uint256 private constant INITIAL_COUNTER = 100_000; // request ids start here (offset for migration id-separation)

    address public immutable ISSUE_TOKEN_ADDRESS;
    IPriceStorage public immutable PRICE_STORAGE;

    address public treasuryAddress;

    mapping(address token => bool isAllowed) public allowedTokens;

    /// @dev burnRequestTTL..burnFee pack into one slot (64 * 4 = 256 bits); mintRequestTTL
    ///      starts the next slot.
    uint64 public burnRequestTTL; // 0 = no burn expiry; bounds the request->completion interval
    uint64 public burnCancelWindow; // window after a request during which the provider may cancelBurn
    uint64 public mintFee; // scaled by PRECISION, e.g. 0.01e18 = 1%
    uint64 public burnFee;

    uint64 public mintRequestTTL; // 0 = no mint expiry; bounds the request->completion interval

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
        uint64 _burnRequestTTL,
        uint64 _burnCancelWindow,
        uint64 _mintRequestTTL
    ) AccessControlDefaultAdminRules(1 days, msg.sender) {
        _assertNonZero(_issueTokenAddress);
        if (_issueTokenAddress.code.length == 0) revert InvalidContractAddress(_issueTokenAddress);
        ISSUE_TOKEN_ADDRESS = _issueTokenAddress;
        treasuryAddress = _assertNonZero(_treasuryAddress);

        _assertNonZero(_priceStorageAddress);
        if (_priceStorageAddress.code.length == 0) revert InvalidContractAddress(_priceStorageAddress);
        PRICE_STORAGE = IPriceStorage(_priceStorageAddress);

        for (uint256 i; i < _allowedTokenAddresses.length; i++) {
            _addAllowedToken(_allowedTokenAddresses[i]);
        }

        burnRequestTTL = _burnRequestTTL;
        burnCancelWindow = _burnCancelWindow;
        mintRequestTTL = _mintRequestTTL;

        mintRequestsCounter = INITIAL_COUNTER;
        burnRequestsCounter = INITIAL_COUNTER;

        // Start paused; admin unpauses after granting this contract SERVICE_ROLE on the issue
        // token, so a deposit can't be escrowed while requests are still uncompletable.
        _pause();
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

    /// @notice Pauses request and completion. Cancellation paths stay enabled so pending
    ///         requests can always be unwound while paused.
    function pause() external onlyRole(PAUSER_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._unpause();
    }

    /// @notice Max request-to-completion interval for burns; completion past createdAt + ttl
    ///         reverts (refundable via adminCancelBurn). 0 disables expiry.
    function setBurnRequestTTL(uint64 _ttl) external onlyRole(DEFAULT_ADMIN_ROLE) {
        burnRequestTTL = _ttl;
        emit BurnRequestTTLSet(_ttl);
    }

    /// @notice Max request-to-completion interval for mints; completion past createdAt + ttl
    ///         reverts (refundable via cancelMint). 0 disables expiry.
    function setMintRequestTTL(uint64 _ttl) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintRequestTTL = _ttl;
        emit MintRequestTTLSet(_ttl);
    }

    /// @notice Window from request time in which the provider may cancelBurn (0 = admin-cancel
    ///         only). Keep it well below the typical burn request-to-completion delay, and below
    ///         the oracle update interval, so a provider can't wait for a fresh price and
    ///         cancel-and-re-request to re-roll the completeBurn price ceiling.
    function setBurnCancelWindow(uint64 _window) external onlyRole(DEFAULT_ADMIN_ROLE) {
        burnCancelWindow = _window;
        emit BurnCancelWindowSet(_window);
    }

    /// @notice Sets the mint fee (capped at MAX_FEE), applied live at completion — not locked
    ///         per-request, unlike the burn fee.
    function setMintFee(uint64 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_fee > MAX_FEE) revert FeeTooHigh(_fee);
        mintFee = _fee;
        emit MintFeeSet(_fee);
    }

    /// @notice Sets the burn fee (capped at MAX_FEE) for new requests; pending burns keep the
    ///         fee locked at request time.
    function setBurnFee(uint64 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_fee > MAX_FEE) revert FeeTooHigh(_fee);
        burnFee = _fee;
        emit BurnFeeSet(_fee);
    }

    // ──────────────────────────────────────────────────────────────
    //  Mint functions
    // ──────────────────────────────────────────────────────────────

    function requestMint(address _depositTokenAddress, uint256 _amount)
        public
        allowedToken(_depositTokenAddress)
        whenNotPaused
    {
        _assertAmount(_amount);

        // CEI: record the request before pulling funds.
        uint256 id = mintRequestsCounter;
        mintRequests[id] = MintRequest({
            provider: msg.sender,
            state: State.CREATED,
            createdAt: uint40(block.timestamp),
            token: _depositTokenAddress,
            amount: _amount
        });

        unchecked {
            mintRequestsCounter++;
        }

        IERC20(_depositTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);

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
        // Tolerate a front-run permit: if it reverts we fall through to any existing allowance,
        // which still reverts in requestMint if the approval is genuinely missing.
        try IERC20Permit(_depositTokenAddress).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s) {}
            catch {}
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

    /// @notice Settles a mint at the latest price: mintAmount = depositAmount * PRECISION / price,
    ///         minus mintFee. Reverts if the request is older than mintRequestTTL.
    function completeMint(uint256 _id) external onlyRole(SERVICE_ROLE) whenNotPaused mintRequestExist(_id) {
        MintRequest storage request = mintRequests[_id];
        _assertState(State.CREATED, request.state);

        if (mintRequestTTL > 0 && block.timestamp > uint256(request.createdAt) + mintRequestTTL) {
            revert MintRequestExpired(_id, request.createdAt, mintRequestTTL);
        }

        (uint128 price,) = PRICE_STORAGE.lastPrice();
        if (price == 0) revert PriceNotSet();

        address provider = request.provider;
        address token = request.token;
        uint256 depositAmount = request.amount;

        // price = deposit-token value of 1 issue token; truncation favors the protocol.
        uint256 mintAmount = (depositAmount * PRECISION) / price;
        mintAmount = (mintAmount * (PRECISION - mintFee)) / PRECISION;

        // Dust that rounds to 0 would consume the deposit for nothing; revert (still refundable).
        if (mintAmount == 0) revert ZeroAmountOut(_id);

        request.state = State.COMPLETED;

        IERC20(token).safeTransfer(treasuryAddress, depositAmount);

        // On-chain idempotency key for SimpleToken (prevents double-completion).
        bytes32 idempotencyKey = keccak256(abi.encodePacked("mint", _id));
        ISimpleToken(ISSUE_TOKEN_ADDRESS).mint(idempotencyKey, provider, mintAmount);

        emit MintRequestCompleted(_id, provider, depositAmount, mintAmount, price, mintFee);
    }

    // ──────────────────────────────────────────────────────────────
    //  Burn functions
    // ──────────────────────────────────────────────────────────────

    /// @notice Opens a burn, capturing the current price as a settlement ceiling and locking the fee.
    function requestBurn(uint256 _issueTokenAmount, address _withdrawalTokenAddress)
        public
        allowedToken(_withdrawalTokenAddress)
        whenNotPaused
    {
        _assertAmount(_issueTokenAmount);

        (uint128 price,) = PRICE_STORAGE.lastPrice();
        if (price == 0) revert PriceNotSet();

        uint64 fee = burnFee;

        // CEI: record the request before pulling funds.
        uint256 id = burnRequestsCounter;
        burnRequests[id] = BurnRequest({
            provider: msg.sender,
            state: State.CREATED,
            createdAt: uint40(block.timestamp),
            price: price,
            fee: fee,
            token: _withdrawalTokenAddress,
            amount: _issueTokenAmount
        });

        unchecked {
            burnRequestsCounter++;
        }

        IERC20(ISSUE_TOKEN_ADDRESS).safeTransferFrom(msg.sender, address(this), _issueTokenAmount);

        emit BurnRequestCreated(id, msg.sender, _withdrawalTokenAddress, _issueTokenAmount, price, fee);
    }

    function requestBurnWithPermit(
        uint256 _issueTokenAmount,
        address _withdrawalTokenAddress,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        // Same front-run-tolerant permit pattern as requestMintWithPermit.
        try IERC20Permit(ISSUE_TOKEN_ADDRESS)
            .permit(msg.sender, address(this), _issueTokenAmount, _deadline, _v, _r, _s) {}
            catch {}
        requestBurn(_issueTokenAmount, _withdrawalTokenAddress);
    }

    /// @notice Provider-cancels a burn within burnCancelWindow (afterwards only adminCancelBurn),
    ///         returning the issue tokens. The window stops re-rolling to escape the price ceiling.
    function cancelBurn(uint256 _id) external burnRequestExist(_id) {
        BurnRequest storage request = burnRequests[_id];
        _assertAddressMatch(request.provider, msg.sender);
        _assertState(State.CREATED, request.state);

        if (block.timestamp > uint256(request.createdAt) + burnCancelWindow) {
            revert BurnCancelWindowClosed(_id, request.createdAt, burnCancelWindow);
        }

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

    /// @notice Settles a burn at min(lockedPrice, currentPrice): withdrawalAmount =
    ///         burnAmount * price / PRECISION, minus the locked fee. Pulls from the treasury,
    ///         which must keep an approval to this contract.
    function completeBurn(uint256 _id) external onlyRole(SERVICE_ROLE) whenNotPaused burnRequestExist(_id) {
        BurnRequest storage request = burnRequests[_id];
        _assertState(State.CREATED, request.state);

        if (burnRequestTTL > 0 && block.timestamp > uint256(request.createdAt) + burnRequestTTL) {
            revert BurnRequestExpired(_id, request.createdAt, burnRequestTTL);
        }

        address provider = request.provider;
        address token = request.token;
        uint256 burnAmount = request.amount;
        uint64 fee = request.fee;
        uint128 lockedPrice = request.price;

        // Settle at the lower of locked and current — a NAV fall is borne by the redeemer.
        (uint128 currentPrice,) = PRICE_STORAGE.lastPrice();
        if (currentPrice == 0) revert PriceNotSet();
        uint128 price = currentPrice < lockedPrice ? currentPrice : lockedPrice;

        // Truncation favors the protocol; fee was locked at request time.
        uint256 withdrawalAmount = (burnAmount * price) / PRECISION;
        withdrawalAmount = (withdrawalAmount * (PRECISION - fee)) / PRECISION;

        // Dust that rounds to 0 would burn the issue tokens for nothing; revert (still refundable).
        if (withdrawalAmount == 0) revert ZeroAmountOut(_id);

        request.state = State.COMPLETED;

        // On-chain idempotency key for SimpleToken (prevents double-completion).
        bytes32 idempotencyKey = keccak256(abi.encodePacked("burn", _id));
        ISimpleToken(ISSUE_TOKEN_ADDRESS).burn(idempotencyKey, address(this), burnAmount);

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(token).safeTransferFrom(treasuryAddress, provider, withdrawalAmount);

        emit BurnRequestCompleted(_id, provider, burnAmount, withdrawalAmount, price, fee);
    }

    // ──────────────────────────────────────────────────────────────
    //  Emergency
    // ──────────────────────────────────────────────────────────────

    /// @notice Admin-only escape hatch: withdraws this contract's full balance of a token —
    ///         including amounts escrowed by pending requests — to the caller. Emergency use only.
    function emergencyWithdraw(IERC20 _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = _token.balanceOf(address(this));
        _token.safeTransfer(msg.sender, balance);

        emit EmergencyWithdrawn(address(_token), msg.sender, balance);
    }

    // ──────────────────────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────────────────────

    /// @dev Only the 18-decimal check is enforced on-chain. Admin must also ensure each allowed
    ///      token is a standard ERC-20 (no fee-on-transfer, rebasing, or transfer hooks) and
    ///      shares the issue token's price denomination — a single global price values them all,
    ///      so a mismatched token would settle at the wrong rate.
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
