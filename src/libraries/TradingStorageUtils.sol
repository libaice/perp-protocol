// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../interfaces/IGNSMultiCollatDiamond.sol";

import "./StorageUtils.sol";
import "./AddressStoreUtils.sol";
import "./CollateralUtils.sol";
import "./ChainUtils.sol";
import "./TradingCommonUtils.sol";
import "./ConstantsUtils.sol";

/**
 * @dev GNSTradingStorage facet external library
 */
library TradingStorageUtils {
    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function initializeTradingStorage(
        address _gns,
        address _gnsStaking,
        address[] memory _collaterals,
        address[] memory _gTokens
    ) external {
        if (_gns == address(0) || _gnsStaking == address(0)) revert IGeneralErrors.ZeroAddress();

        if (_collaterals.length < 3) revert ITradingStorageUtils.MissingCollaterals();
        if (_collaterals.length != _gTokens.length) revert IGeneralErrors.WrongLength();

        // Set addresses
        IGNSAddressStore.Addresses storage addresses = AddressStoreUtils.getAddresses();
        addresses.gns = _gns;
        addresses.gnsStaking = _gnsStaking;

        emit IGNSAddressStore.AddressesUpdated(addresses);

        // Add collaterals
        for (uint256 i; i < _collaterals.length; ++i) {
            addCollateral(_collaterals[i], _gTokens[i]);
        }

        // Trading is paused by default for state copy
        updateTradingActivated(ITradingStorage.TradingActivated.PAUSED);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradingActivated(ITradingStorage.TradingActivated _activated) public {
        _getStorage().tradingActivated = _activated;

        emit ITradingStorageUtils.TradingActivatedUpdated(_activated);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function addCollateral(address _collateral, address _gToken) public {
        ITradingStorage.TradingStorage storage s = _getStorage();
        address staking = AddressStoreUtils.getAddresses().gnsStaking;

        if (s.collateralIndex[_collateral] != 0) revert IGeneralErrors.AlreadyExists();
        if (_collateral == address(0) || _gToken == address(0)) revert IGeneralErrors.ZeroAddress();

        CollateralUtils.CollateralConfig memory collateralConfig = CollateralUtils.getCollateralConfig(_collateral);

        uint8 index = ++s.lastCollateralIndex;

        s.collaterals[index] = ITradingStorage.Collateral({
            collateral: _collateral,
            isActive: true,
            __placeholder: 0,
            precision: collateralConfig.precision,
            precisionDelta: collateralConfig.precisionDelta
        });
        s.gTokens[index] = _gToken;

        s.collateralIndex[_collateral] = index;

        // Setup Staking and GToken approvals
        IERC20 collateral = IERC20(_collateral);
        collateral.approve(_gToken, type(uint256).max);
        collateral.approve(staking, type(uint256).max);

        emit ITradingStorageUtils.CollateralAdded(_collateral, index, _gToken);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function toggleCollateralActiveState(uint8 _collateralIndex) external {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Collateral storage collateral = s.collaterals[_collateralIndex];

        if (collateral.precision == 0) revert IGeneralErrors.DoesntExist();

        bool toggled = !collateral.isActive;
        collateral.isActive = toggled;

        emit ITradingStorageUtils.CollateralUpdated(_collateralIndex, toggled);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateGToken(address _collateral, address _gToken) external {
        ITradingStorage.TradingStorage storage s = _getStorage();

        uint8 index = s.collateralIndex[_collateral];

        if (index == 0) revert IGeneralErrors.DoesntExist();
        if (_gToken == address(0)) revert IGeneralErrors.ZeroAddress();

        // Revoke old vault and approve new vault
        IERC20 collateral = IERC20(_collateral);
        collateral.approve(s.gTokens[index], 0);
        collateral.approve(_gToken, type(uint256).max);

        s.gTokens[index] = _gToken;

        emit ITradingStorageUtils.GTokenUpdated(_collateral, index, _gToken);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function storeTrade(ITradingStorage.Trade memory _trade, ITradingStorage.TradeInfo memory _tradeInfo)
        external
        returns (ITradingStorage.Trade memory)
    {
        ITradingStorage.TradingStorage storage s = _getStorage();

        _validateTrade(_trade);

        if (_trade.tradeType != ITradingStorage.TradeType.TRADE && _tradeInfo.maxSlippageP == 0) {
            revert ITradingStorageUtils.MaxSlippageZero();
        }

        ITradingStorage.Counter memory counter = s.userCounters[_trade.user][ITradingStorage.CounterType.TRADE];

        _trade.index = counter.currentIndex;
        _trade.isOpen = true;
        _trade.tp = _limitTpDistance(_trade.openPrice, _trade.leverage, _trade.tp, _trade.long);
        _trade.sl = _limitSlDistance(_trade.openPrice, _trade.leverage, _trade.sl, _trade.long);

        _tradeInfo.createdBlock = uint32(ChainUtils.getBlockNumber());
        _tradeInfo.tpLastUpdatedBlock = _tradeInfo.createdBlock;
        _tradeInfo.slLastUpdatedBlock = _tradeInfo.createdBlock;
        _tradeInfo.lastOiUpdateTs = 0; // ensure isPartial = false for addPriceImpactOpenInterest

        counter.currentIndex++;
        counter.openCount++;

        s.trades[_trade.user][_trade.index] = _trade;
        s.tradeInfos[_trade.user][_trade.index] = _tradeInfo;
        s.userCounters[_trade.user][ITradingStorage.CounterType.TRADE] = counter;

        if (!s.traderStored[_trade.user]) {
            s.traders.push(_trade.user);
            s.traderStored[_trade.user] = true;
        }

        if (_trade.tradeType == ITradingStorage.TradeType.TRADE) TradingCommonUtils.addTradeOiCollateral(_trade);

        emit ITradingStorageUtils.TradeStored(_trade, _tradeInfo);

        return _trade;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradeCollateralAmount(ITradingStorage.Id memory _tradeId, uint120 _collateralAmount) external {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];
        ITradingStorage.TradeInfo storage i = s.tradeInfos[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType != ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();
        if (_collateralAmount == 0) revert ITradingStorageUtils.TradePositionSizeZero();

        TradingCommonUtils.handleOiDelta(t, TradingCommonUtils.getPositionSizeCollateral(_collateralAmount, t.leverage));

        t.collateralAmount = _collateralAmount;
        i.createdBlock = uint32(ChainUtils.getBlockNumber());

        emit ITradingStorageUtils.TradeCollateralUpdated(_tradeId, _collateralAmount);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradePosition(
        ITradingStorage.Id memory _tradeId,
        uint120 _collateralAmount,
        uint24 _leverage,
        uint64 _openPrice
    ) external {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];
        ITradingStorage.TradeInfo storage i = s.tradeInfos[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType != ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();
        if (_collateralAmount * _leverage == 0) revert ITradingStorageUtils.TradePositionSizeZero();
        if (_openPrice == 0) revert ITradingStorageUtils.TradeOpenPriceZero();

        TradingCommonUtils.handleOiDelta(t, TradingCommonUtils.getPositionSizeCollateral(_collateralAmount, _leverage));

        t.collateralAmount = _collateralAmount;
        t.leverage = _leverage;
        t.openPrice = _openPrice;
        t.tp = _limitTpDistance(t.openPrice, t.leverage, t.tp, t.long);
        t.sl = _limitSlDistance(t.openPrice, t.leverage, t.sl, t.long);

        uint32 blockNumber = uint32(ChainUtils.getBlockNumber());
        i.createdBlock = blockNumber;
        i.tpLastUpdatedBlock = blockNumber;
        i.slLastUpdatedBlock = blockNumber;

        emit ITradingStorageUtils.TradePositionUpdated(_tradeId, _collateralAmount, t.leverage, t.openPrice, t.tp, t.sl);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateOpenOrderDetails(
        ITradingStorage.Id memory _tradeId,
        uint64 _openPrice,
        uint64 _tp,
        uint64 _sl,
        uint16 _maxSlippageP
    ) external {
        ITradingStorage.TradingStorage storage s = _getStorage();

        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];
        ITradingStorage.TradeInfo memory i = s.tradeInfos[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType == ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();
        if (_openPrice == 0) revert ITradingStorageUtils.TradeOpenPriceZero();
        if (_tp > 0 && (t.long ? _tp <= _openPrice : _tp >= _openPrice)) revert ITradingStorageUtils.TradeTpInvalid();
        if (_sl > 0 && (t.long ? _sl >= _openPrice : _sl <= _openPrice)) revert ITradingStorageUtils.TradeSlInvalid();
        if (_maxSlippageP == 0) revert ITradingStorageUtils.MaxSlippageZero();

        _tp = _limitTpDistance(_openPrice, t.leverage, _tp, t.long);
        _sl = _limitSlDistance(_openPrice, t.leverage, _sl, t.long);

        t.openPrice = _openPrice;
        t.tp = _tp;
        t.sl = _sl;

        i.maxSlippageP = _maxSlippageP;
        i.createdBlock = uint32(ChainUtils.getBlockNumber());
        i.tpLastUpdatedBlock = i.createdBlock;
        i.slLastUpdatedBlock = i.createdBlock;

        s.tradeInfos[_tradeId.user][_tradeId.index] = i;

        emit ITradingStorageUtils.OpenOrderDetailsUpdated(_tradeId, _openPrice, _tp, _sl, _maxSlippageP);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradeTp(ITradingStorage.Id memory _tradeId, uint64 _newTp) external {
        ITradingStorage.TradingStorage storage s = _getStorage();

        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];
        ITradingStorage.TradeInfo storage i = s.tradeInfos[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType != ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();

        _newTp = _limitTpDistance(t.openPrice, t.leverage, _newTp, t.long);

        t.tp = _newTp;
        i.tpLastUpdatedBlock = uint32(ChainUtils.getBlockNumber());

        emit ITradingStorageUtils.TradeTpUpdated(_tradeId, _newTp);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function updateTradeSl(ITradingStorage.Id memory _tradeId, uint64 _newSl) external {
        ITradingStorage.TradingStorage storage s = _getStorage();

        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];
        ITradingStorage.TradeInfo storage i = s.tradeInfos[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();
        if (t.tradeType != ITradingStorage.TradeType.TRADE) revert IGeneralErrors.WrongTradeType();

        _newSl = _limitSlDistance(t.openPrice, t.leverage, _newSl, t.long);

        t.sl = _newSl;
        i.slLastUpdatedBlock = uint32(ChainUtils.getBlockNumber());

        emit ITradingStorageUtils.TradeSlUpdated(_tradeId, _newSl);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function closeTrade(ITradingStorage.Id memory _tradeId) external {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Trade storage t = s.trades[_tradeId.user][_tradeId.index];

        if (!t.isOpen) revert IGeneralErrors.DoesntExist();

        t.isOpen = false;
        s.userCounters[_tradeId.user][ITradingStorage.CounterType.TRADE].openCount--;

        if (t.tradeType == ITradingStorage.TradeType.TRADE) TradingCommonUtils.removeTradeOiCollateral(t);

        emit ITradingStorageUtils.TradeClosed(_tradeId);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function storePendingOrder(ITradingStorage.PendingOrder memory _pendingOrder)
        external
        returns (ITradingStorage.PendingOrder memory)
    {
        if (_pendingOrder.user == address(0)) revert IGeneralErrors.ZeroAddress();

        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Trade storage t = s.trades[_pendingOrder.trade.user][_pendingOrder.trade.index];

        if (_pendingOrder.orderType == ITradingStorage.PendingOrderType.MARKET_OPEN) {
            _validateTrade(_pendingOrder.trade);

            if (_pendingOrder.maxSlippageP == 0) revert ITradingStorageUtils.MaxSlippageZero();
        } else {
            if (!t.isOpen) revert IGeneralErrors.DoesntExist();

            if (
                _pendingOrder.orderType == ITradingStorage.PendingOrderType.LIMIT_OPEN
                    ? t.tradeType != ITradingStorage.TradeType.LIMIT
                    : _pendingOrder.orderType == ITradingStorage.PendingOrderType.STOP_OPEN
                        ? t.tradeType != ITradingStorage.TradeType.STOP
                        : t.tradeType != ITradingStorage.TradeType.TRADE
            ) revert IGeneralErrors.WrongTradeType();

            if (_pendingOrder.orderType == ITradingStorage.PendingOrderType.SL_CLOSE && t.sl == 0) {
                revert ITradingInteractionsUtils.NoSl();
            }

            if (_pendingOrder.orderType == ITradingStorage.PendingOrderType.TP_CLOSE && t.tp == 0) {
                revert ITradingInteractionsUtils.NoTp();
            }
        }

        uint256 blockNumber = ChainUtils.getBlockNumber();
        ITradingStorage.Counter memory counter =
            s.userCounters[_pendingOrder.user][ITradingStorage.CounterType.PENDING_ORDER];

        _pendingOrder.index = counter.currentIndex;
        _pendingOrder.isOpen = true;
        _pendingOrder.createdBlock = uint32(blockNumber);

        counter.currentIndex++;
        counter.openCount++;

        s.pendingOrders[_pendingOrder.user][_pendingOrder.index] = _pendingOrder;
        s.userCounters[_pendingOrder.user][ITradingStorage.CounterType.PENDING_ORDER] = counter;

        if (_pendingOrder.orderType != ITradingStorage.PendingOrderType.MARKET_OPEN) {
            s.tradePendingOrderBlock[_pendingOrder.trade.user][_pendingOrder.trade.index][_pendingOrder.orderType] =
                blockNumber;
        }

        if (!s.traderStored[_pendingOrder.user]) {
            s.traders.push(_pendingOrder.user);
            s.traderStored[_pendingOrder.user] = true;
        }

        emit ITradingStorageUtils.PendingOrderStored(_pendingOrder);

        return _pendingOrder;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function closePendingOrder(ITradingStorage.Id memory _orderId) external {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.PendingOrder storage pendingOrder = s.pendingOrders[_orderId.user][_orderId.index];

        if (!pendingOrder.isOpen) revert IGeneralErrors.DoesntExist();

        pendingOrder.isOpen = false;
        s.userCounters[_orderId.user][ITradingStorage.CounterType.PENDING_ORDER].openCount--;

        if (pendingOrder.orderType != ITradingStorage.PendingOrderType.MARKET_OPEN) {
            delete s.tradePendingOrderBlock[pendingOrder.trade.user][pendingOrder.trade.index][pendingOrder.orderType];
        }

        emit ITradingStorageUtils.PendingOrderClosed(_orderId);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCollateral(uint8 _index) external view returns (ITradingStorage.Collateral memory) {
        return _getStorage().collaterals[_index];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function isCollateralActive(uint8 _index) public view returns (bool) {
        return _getStorage().collaterals[_index].isActive;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function isCollateralListed(uint8 _index) external view returns (bool) {
        return _getStorage().collaterals[_index].precision > 0;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCollateralsCount() external view returns (uint8) {
        return _getStorage().lastCollateralIndex;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCollaterals() external view returns (ITradingStorage.Collateral[] memory) {
        ITradingStorage.TradingStorage storage s = _getStorage();
        ITradingStorage.Collateral[] memory collaterals = new ITradingStorage.Collateral[](s.lastCollateralIndex);

        for (uint8 i = 1; i <= s.lastCollateralIndex; ++i) {
            collaterals[i - 1] = s.collaterals[i];
        }

        return collaterals;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCollateralIndex(address _collateral) external view returns (uint8) {
        return _getStorage().collateralIndex[_collateral];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradingActivated() external view returns (ITradingStorage.TradingActivated) {
        return _getStorage().tradingActivated;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTraderStored(address _trader) external view returns (bool) {
        return _getStorage().traderStored[_trader];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTrade(address _trader, uint32 _index) external view returns (ITradingStorage.Trade memory) {
        return _getStorage().trades[_trader][_index];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradeInfo(address _trader, uint32 _index) external view returns (ITradingStorage.TradeInfo memory) {
        return _getStorage().tradeInfos[_trader][_index];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getPendingOrder(ITradingStorage.Id memory _orderId)
        external
        view
        returns (ITradingStorage.PendingOrder memory)
    {
        return _getStorage().pendingOrders[_orderId.user][_orderId.index];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradePendingOrderBlock(ITradingStorage.Id memory _tradeId, ITradingStorage.PendingOrderType _orderType)
        external
        view
        returns (uint256)
    {
        return _getStorage().tradePendingOrderBlock[_tradeId.user][_tradeId.index][_orderType];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCounters(address _trader, ITradingStorage.CounterType _type)
        external
        view
        returns (ITradingStorage.Counter memory)
    {
        return _getStorage().userCounters[_trader][_type];
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getGToken(uint8 _collateralIndex) external view returns (address) {
        return _getStorage().gTokens[_collateralIndex];
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_TRADING_STORAGE_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage() internal pure returns (ITradingStorage.TradingStorage storage s) {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * @dev Returns current address as multi-collateral diamond interface to call other facets functions.
     */
    function _getMultiCollatDiamond() internal view returns (IGNSMultiCollatDiamond) {
        return IGNSMultiCollatDiamond(address(this));
    }

    /**
     * @dev Limits take profit price distance for long/short based on '_openPrice', '_tp, '_leverage' and sets an automatic TP if '_tp' is zero.
     * @param _openPrice trade open price (1e10 precision)
     * @param _leverage trade leverage (1e3 precision)
     * @param _tp trade take profit price (1e10 precision)
     * @param _long trade direction
     */
    function _limitTpDistance(uint64 _openPrice, uint24 _leverage, uint64 _tp, bool _long)
        public
        pure
        returns (uint64)
    {
        if (
            _tp == 0
                || TradingCommonUtils.getPnlPercent(_openPrice, _tp, _long, _leverage)
                    == int256(ConstantsUtils.MAX_PNL_P) * int256(ConstantsUtils.P_10)
        ) {
            uint256 openPrice = uint256(_openPrice);
            uint256 tpDiff = (openPrice * ConstantsUtils.MAX_PNL_P * 1e3) / _leverage / 100;
            uint256 newTp = _long ? openPrice + tpDiff : (tpDiff <= openPrice ? openPrice - tpDiff : 0);
            uint64 maxTp = type(uint64).max;
            return newTp > maxTp ? maxTp : uint64(newTp);
        }

        return _tp;
    }

    /**
     * @dev Limits stop loss price distance for long/short based on '_openPrice', '_sl, '_leverage'.
     * @param _openPrice trade open price (1e10 precision)
     * @param _leverage trade leverage (1e3 precision)
     * @param _sl trade stop loss price (1e10 precision)
     * @param _long trade direction
     */
    function _limitSlDistance(uint64 _openPrice, uint24 _leverage, uint64 _sl, bool _long)
        public
        pure
        returns (uint64)
    {
        if (
            _sl > 0
                && TradingCommonUtils.getPnlPercent(_openPrice, _sl, _long, _leverage)
                    < int256(ConstantsUtils.MAX_SL_P) * int256(ConstantsUtils.P_10) * -1
        ) {
            uint256 openPrice = uint256(_openPrice);
            uint256 slDiff = (openPrice * ConstantsUtils.MAX_SL_P * 1e3) / _leverage / 100;
            uint256 newSl = _long ? openPrice - slDiff : openPrice + slDiff;

            // Here an overflow (for shorts) is actually impossible because _sl is uint64
            // And the new stop loss is always closer (= lower for shorts) than the _sl input

            return uint64(newSl);
        }

        return _sl;
    }

    /**
     * @dev Validation for trade struct (used by storeTrade and storePendingOrder for market open orders)
     * @param _trade trade struct to validate
     */
    function _validateTrade(ITradingStorage.Trade memory _trade) internal view {
        if (_trade.user == address(0)) revert IGeneralErrors.ZeroAddress();

        if (!_getMultiCollatDiamond().isPairIndexListed(_trade.pairIndex)) {
            revert ITradingStorageUtils.TradePairNotListed();
        }

        if (TradingCommonUtils.getPositionSizeCollateral(_trade.collateralAmount, _trade.leverage) == 0) {
            revert ITradingStorageUtils.TradePositionSizeZero();
        }

        if (!isCollateralActive(_trade.collateralIndex)) revert IGeneralErrors.InvalidCollateralIndex();

        if (_trade.openPrice == 0) revert ITradingStorageUtils.TradeOpenPriceZero();

        if (_trade.tp != 0 && (_trade.long ? _trade.tp <= _trade.openPrice : _trade.tp >= _trade.openPrice)) {
            revert ITradingStorageUtils.TradeTpInvalid();
        }

        if (_trade.sl != 0 && (_trade.long ? _trade.sl >= _trade.openPrice : _trade.sl <= _trade.openPrice)) {
            revert ITradingStorageUtils.TradeSlInvalid();
        }
    }
}
