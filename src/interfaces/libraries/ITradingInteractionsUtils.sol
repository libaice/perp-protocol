// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../types/ITradingInteractions.sol";
import "../types/ITradingStorage.sol";
import "../libraries/IUpdateLeverageUtils.sol";
import "../libraries/IUpdatePositionSizeUtils.sol";

/**
 * @dev Interface for GNSTradingInteractions facet (inherits types and also contains functions, events, and custom errors)
 */
interface ITradingInteractionsUtils is ITradingInteractions, IUpdateLeverageUtils, IUpdatePositionSizeUtils {
    /**
     * @dev Initializes the trading facet
     * @param _marketOrdersTimeoutBlocks The number of blocks after which a market order is considered timed out
     */
    function initializeTrading(uint16 _marketOrdersTimeoutBlocks, address[] memory _usersByPassTriggerLink) external;

    /**
     * @dev Updates marketOrdersTimeoutBlocks
     * @param _valueBlocks blocks after which a market order times out
     */
    function updateMarketOrdersTimeoutBlocks(uint16 _valueBlocks) external;

    /**
     * @dev Updates the users that can bypass the link cost of triggerOrder
     * @param _users array of addresses that can bypass the link cost of triggerOrder
     * @param _shouldByPass whether each user should bypass the link cost
     */
    function updateByPassTriggerLink(address[] memory _users, bool[] memory _shouldByPass) external;

    /**
     * @dev Sets _delegate as the new delegate of caller (can call delegatedAction)
     * @param _delegate the new delegate address
     */
    function setTradingDelegate(address _delegate) external;

    /**
     * @dev Removes the delegate of caller (can't call delegatedAction)
     */
    function removeTradingDelegate() external;

    /**
     * @dev Caller executes a trading action on behalf of _trader using delegatecall
     * @param _trader the trader address to execute the trading action for
     * @param _callData the data to be executed (open trade/close trade, etc.)
     */
    function delegatedTradingAction(address _trader, bytes calldata _callData) external returns (bytes memory);

    /**
     * @dev Opens a new trade/limit order/stop order
     * @param _trade the trade to be opened
     * @param _maxSlippageP the maximum allowed slippage % when open the trade (1e3 precision)
     * @param _referrer the address of the referrer (can only be set once for a trader)
     */
    function openTrade(ITradingStorage.Trade memory _trade, uint16 _maxSlippageP, address _referrer) external;

    /**
     * @dev Wraps native token and opens a new trade/limit order/stop order
     * @param _trade the trade to be opened
     * @param _maxSlippageP the maximum allowed slippage % when open the trade (1e3 precision)
     * @param _referrer the address of the referrer (can only be set once for a trader)
     */
    function openTradeNative(ITradingStorage.Trade memory _trade, uint16 _maxSlippageP, address _referrer)
        external
        payable;

    function batchCloseTradeMarket(uint32[] memory _indexList) external;

    /**
     * @dev Closes an open trade (market order) for caller
     * @param _index the index of the trade of caller
     */
    function closeTradeMarket(uint32 _index) external;

    /**
     * @dev Updates an existing limit/stop order for caller
     * @param _index index of limit/stop order of caller
     * @param _triggerPrice new trigger price of limit/stop order (1e10 precision)
     * @param _tp new tp of limit/stop order (1e10 precision)
     * @param _sl new sl of limit/stop order (1e10 precision)
     * @param _maxSlippageP new max slippage % of limit/stop order (1e3 precision)
     */
    function updateOpenOrder(uint32 _index, uint64 _triggerPrice, uint64 _tp, uint64 _sl, uint16 _maxSlippageP)
        external;

    /**
     * @dev Cancels an open limit/stop order for caller
     * @param _index index of limit/stop order of caller
     */
    function cancelOpenOrder(uint32 _index) external;

    /**
     * @dev Updates the tp of an open trade for caller
     * @param _index index of open trade of caller
     * @param _newTp new tp of open trade (1e10 precision)
     */
    function updateTp(uint32 _index, uint64 _newTp) external;

    /**
     * @dev Updates the sl of an open trade for caller
     * @param _index index of open trade of caller
     * @param _newSl new sl of open trade (1e10 precision)
     */
    function updateSl(uint32 _index, uint64 _newSl) external;

    /**
     * @dev Initiates a new trigger order (for tp/sl/liq/limit/stop orders)
     * @param _packed the packed data of the trigger order (orderType, trader, index)
     */
    function triggerOrder(uint256 _packed) external;

    /**
     * @dev Safety function in case oracles don't answer in time, allows caller to cancel a pending order and if relevant claim back any stuck collateral
     * @dev Only allowed for MARKET_OPEN, MARKET_CLOSE, UPDATE_LEVERAGE, MARKET_PARTIAL_OPEN, and MARKET_PARTIAL_CLOSE orders
     * @param _orderIndex the id of the pending order to cancel
     */
    function cancelOrderAfterTimeout(uint32 _orderIndex) external;

    /**
     * @dev Update trade leverage
     * @param _index index of trade
     * @param _newLeverage new leverage (1e3)
     */
    function updateLeverage(uint32 _index, uint24 _newLeverage) external;

    /**
     * @dev Increase trade position size
     * @param _index index of trade
     * @param _collateralDelta collateral to add (collateral precision)
     * @param _leverageDelta partial trade leverage (1e3)
     * @param _expectedPrice expected price of execution (1e10 precision)
     * @param _maxSlippageP max slippage % (1e3)
     */
    function increasePositionSize(
        uint32 _index,
        uint120 _collateralDelta,
        uint24 _leverageDelta,
        uint64 _expectedPrice,
        uint16 _maxSlippageP
    ) external;

    /**
     * @dev Decrease trade position size
     * @param _index index of trade
     * @param _collateralDelta collateral to remove (collateral precision)
     * @param _leverageDelta leverage to reduce by (1e3)
     */
    function decreasePositionSize(uint32 _index, uint120 _collateralDelta, uint24 _leverageDelta) external;

    /**
     * @dev Returns the wrapped native token or address(0) if the current chain, or the wrapped token, is not supported.
     */
    function getWrappedNativeToken() external view returns (address);

    /**
     * @dev Returns true if the token is the wrapped native token for the current chain, where supported.
     * @param _token token address
     */
    function isWrappedNativeToken(address _token) external view returns (bool);

    /**
     * @dev Returns the address a trader delegates his trading actions to
     * @param _trader address of the trader
     */
    function getTradingDelegate(address _trader) external view returns (address);

    /**
     * @dev Returns the current marketOrdersTimeoutBlocks value
     */
    function getMarketOrdersTimeoutBlocks() external view returns (uint16);

    /**
     * @dev Returns whether a user bypasses trigger link costs
     * @param _user address of the user
     */
    function getByPassTriggerLink(address _user) external view returns (bool);

    /**
     * @dev Emitted when marketOrdersTimeoutBlocks is updated
     * @param newValueBlocks the new value of marketOrdersTimeoutBlocks
     */
    event MarketOrdersTimeoutBlocksUpdated(uint256 newValueBlocks);

    /**
     * @dev Emitted when a user is allowed/disallowed to bypass the link cost of triggerOrder
     * @param user address of the user
     * @param bypass whether the user can bypass the link cost of triggerOrder
     */
    event ByPassTriggerLinkUpdated(address indexed user, bool bypass);

    /**
     * @dev Emitted when a market order is initiated
     * @param orderId price aggregator order id of the pending market order
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param open whether the market order is for opening or closing a trade
     */
    event MarketOrderInitiated(ITradingStorage.Id orderId, address indexed trader, uint16 indexed pairIndex, bool open);

    /**
     * @dev Emitted when a new limit/stop order is placed
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param index index of the open limit order for caller
     */
    event OpenOrderPlaced(address indexed trader, uint16 indexed pairIndex, uint32 index);

    /**
     *
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param index index of the open limit/stop order for caller
     * @param newPrice new trigger price (1e10 precision)
     * @param newTp new tp (1e10 precision)
     * @param newSl new sl (1e10 precision)
     * @param maxSlippageP new max slippage % (1e3 precision)
     */
    event OpenLimitUpdated(
        address indexed trader,
        uint16 indexed pairIndex,
        uint32 index,
        uint64 newPrice,
        uint64 newTp,
        uint64 newSl,
        uint64 maxSlippageP
    );

    /**
     * @dev Emitted when a limit/stop order is canceled (collateral sent back to trader)
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param index index of the open limit/stop order for caller
     */
    event OpenLimitCanceled(address indexed trader, uint16 indexed pairIndex, uint32 index);

    /**
     * @dev Emitted when a trigger order is initiated (tp/sl/liq/limit/stop orders)
     * @param orderId price aggregator order id of the pending trigger order
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param byPassesLinkCost whether the caller bypasses the link cost
     */
    event TriggerOrderInitiated(
        ITradingStorage.Id orderId, address indexed trader, uint16 indexed pairIndex, bool byPassesLinkCost
    );

    /**
     * @dev Emitted when a pending market order is canceled due to timeout
     * @param pendingOrderId id of the pending order
     * @param pairIndex index of the trading pair
     */
    event ChainlinkCallbackTimeout(ITradingStorage.Id pendingOrderId, uint256 indexed pairIndex);

    /**
     * @dev Emitted when a pending market order is canceled due to timeout and new closeTradeMarket() call failed
     * @param trader address of the trader
     * @param pairIndex index of the trading pair
     * @param index index of the open trade for caller
     */
    event CouldNotCloseTrade(address indexed trader, uint16 indexed pairIndex, uint32 index);

    /**
     * @dev Emitted when a native token is wrapped
     * @param trader address of the trader
     * @param nativeTokenAmount amount of native token wrapped
     */
    event NativeTokenWrapped(address indexed trader, uint256 nativeTokenAmount);

    error NotWrappedNativeToken();
    error DelegateNotApproved();
    error PriceZero();
    error AboveExposureLimits();
    error CollateralNotActive();
    error PriceImpactTooHigh();
    error NoTrade();
    error NoOrder();
    error WrongOrderType();
    error AlreadyBeingMarketClosed();
    error ConflictingPendingOrder(ITradingStorage.PendingOrderType);
    error WrongLeverage();
    error WrongTp();
    error WrongSl();
    error WaitTimeout();
    error PendingTrigger();
    error NoSl();
    error NoTp();
    error NotYourOrder();
    error DelegatedActionNotAllowed();
    error InsufficientCollateral();
}
