// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../interfaces/IGNSMultiCollatDiamond.sol";

import "./StorageUtils.sol";
import "./ConstantsUtils.sol";
import "./TradingCommonUtils.sol";
import "./TradingStorageUtils.sol";

/**
 * @dev GNSPriceImpact facet internal library
 *
 * This is a library to help manage a price impact decay algorithm .
 *
 * When a trade is placed, OI is added to the window corresponding to time of open.
 * When a trade is removed, OI is removed from the window corresponding to time of open.
 *
 * When calculating price impact, only the most recent X windows are taken into account.
 *
 */
library PriceImpactUtils {
    uint48 private constant MAX_WINDOWS_COUNT = 5;
    uint48 private constant MAX_WINDOWS_DURATION = 30 days;
    uint48 private constant MIN_WINDOWS_DURATION = 10 minutes;

    /**
     * @dev Validates new windowsDuration value
     */
    modifier validWindowsDuration(uint48 _windowsDuration) {
        if (_windowsDuration < MIN_WINDOWS_DURATION || _windowsDuration > MAX_WINDOWS_DURATION)
            revert IPriceImpactUtils.WrongWindowsDuration();
        _;
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function initializePriceImpact(
        uint48 _windowsDuration,
        uint48 _windowsCount
    ) internal validWindowsDuration(_windowsDuration) {
        if (_windowsCount > MAX_WINDOWS_COUNT) revert IGeneralErrors.AboveMax();

        _getStorage().oiWindowsSettings = IPriceImpact.OiWindowsSettings({
            startTs: uint48(block.timestamp),
            windowsDuration: _windowsDuration,
            windowsCount: _windowsCount
        });

        emit IPriceImpactUtils.OiWindowsSettingsInitialized(_windowsDuration, _windowsCount);
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setPriceImpactWindowsCount(uint48 _newWindowsCount) internal {
        IPriceImpact.OiWindowsSettings storage settings = _getStorage().oiWindowsSettings;

        if (_newWindowsCount > MAX_WINDOWS_COUNT) revert IGeneralErrors.AboveMax();

        settings.windowsCount = _newWindowsCount;

        emit IPriceImpactUtils.PriceImpactWindowsCountUpdated(_newWindowsCount);
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setPriceImpactWindowsDuration(
        uint48 _newWindowsDuration,
        uint256 _pairsCount
    ) internal validWindowsDuration(_newWindowsDuration) {
        IPriceImpact.PriceImpactStorage storage priceImpactStorage = _getStorage();
        IPriceImpact.OiWindowsSettings storage settings = priceImpactStorage.oiWindowsSettings;

        if (settings.windowsCount > 0) {
            _transferPriceImpactOiForPairs(
                _pairsCount,
                priceImpactStorage.windows[settings.windowsDuration],
                priceImpactStorage.windows[_newWindowsDuration],
                settings,
                _newWindowsDuration
            );
        }

        settings.windowsDuration = _newWindowsDuration;

        emit IPriceImpactUtils.PriceImpactWindowsDurationUpdated(_newWindowsDuration);
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setPairDepths(
        uint256[] calldata _indices,
        uint128[] calldata _depthsAboveUsd,
        uint128[] calldata _depthsBelowUsd
    ) internal {
        if (_indices.length != _depthsAboveUsd.length || _depthsAboveUsd.length != _depthsBelowUsd.length)
            revert IGeneralErrors.WrongLength();

        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _indices.length; ++i) {
            s.pairDepths[_indices[i]] = IPriceImpact.PairDepth({
                onePercentDepthAboveUsd: _depthsAboveUsd[i],
                onePercentDepthBelowUsd: _depthsBelowUsd[i]
            });

            emit IPriceImpactUtils.OnePercentDepthUpdated(_indices[i], _depthsAboveUsd[i], _depthsBelowUsd[i]);
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function addPriceImpactOpenInterest(address _trader, uint32 _index, uint256 _oiDeltaCollateral) internal {
        // 1. Prepare variables
        IPriceImpact.OiWindowsSettings storage settings = _getStorage().oiWindowsSettings;
        ITradingStorage.Trade memory trade = _getMultiCollatDiamond().getTrade(_trader, _index);
        ITradingStorage.TradeInfo storage tradeInfo = TradingStorageUtils._getStorage().tradeInfos[_trader][_index];
        IPriceImpact.TradePriceImpactInfo storage tradePriceImpactInfo = _getStorage().tradePriceImpactInfos[_trader][
            _index
        ];

        uint256 currentWindowId = _getCurrentWindowId(settings);
        uint256 currentCollateralPriceUsd = _getMultiCollatDiamond().getCollateralPriceUsd(trade.collateralIndex);
        uint128 oiDeltaUsd = uint128(
            TradingCommonUtils.convertCollateralToUsd(
                _oiDeltaCollateral,
                _getMultiCollatDiamond().getCollateral(trade.collateralIndex).precisionDelta,
                currentCollateralPriceUsd
            )
        );

        // 2. Handle logic for partials when last OI delta is still in an active window
        bool isPartial = tradeInfo.lastOiUpdateTs > 0;
        if (
            isPartial &&
            _getWindowId(tradeInfo.lastOiUpdateTs, settings) >=
            _getEarliestActiveWindowId(currentWindowId, settings.windowsCount)
        ) {
            // 2.1 Fetch last OI delta for trade
            uint128 lastWindowOiUsd = getTradeLastWindowOiUsd(_trader, _index);

            // 2.2 Remove it from existing window
            removePriceImpactOpenInterest(_trader, _index, lastWindowOiUsd);

            // 2.3 Add it to current window, scaling it to the current collateral/usd price
            oiDeltaUsd += uint128((currentCollateralPriceUsd * lastWindowOiUsd) / tradeInfo.collateralPriceUsd);
        }

        // 3. Add OI to current window
        IPriceImpact.PairOi storage currentWindow = _getStorage().windows[settings.windowsDuration][trade.pairIndex][
            currentWindowId
        ];
        if (trade.long) {
            currentWindow.oiLongUsd += oiDeltaUsd;
        } else {
            currentWindow.oiShortUsd += oiDeltaUsd;
        }

        // 4. Update trade info
        tradeInfo.lastOiUpdateTs = uint48(block.timestamp);
        tradeInfo.collateralPriceUsd = uint48(currentCollateralPriceUsd);
        tradePriceImpactInfo.lastWindowOiUsd = oiDeltaUsd;

        emit IPriceImpactUtils.PriceImpactOpenInterestAdded(
            IPriceImpact.OiWindowUpdate(
                _trader,
                _index,
                settings.windowsDuration,
                trade.pairIndex,
                currentWindowId,
                trade.long,
                oiDeltaUsd
            ),
            isPartial
        );
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function removePriceImpactOpenInterest(address _trader, uint32 _index, uint256 _oiDeltaCollateral) internal {
        // 1. Prepare vars
        ITradingStorage.Trade memory trade = _getMultiCollatDiamond().getTrade(_trader, _index);
        ITradingStorage.TradeInfo memory tradeInfo = _getMultiCollatDiamond().getTradeInfo(_trader, _index);
        IPriceImpact.OiWindowsSettings storage settings = _getStorage().oiWindowsSettings;
        IPriceImpact.TradePriceImpactInfo storage tradePriceImpactInfo = _getStorage().tradePriceImpactInfos[_trader][
            _index
        ];

        // If trade OI wasn't stored in any window we return early
        if (_oiDeltaCollateral == 0 || tradeInfo.lastOiUpdateTs == 0) {
            return;
        }

        uint256 currentWindowId = _getCurrentWindowId(settings);
        uint256 addWindowId = _getWindowId(tradeInfo.lastOiUpdateTs, settings);
        bool notOutdated = _isWindowPotentiallyActive(addWindowId, currentWindowId);

        uint128 oiDeltaUsd = uint128(
            TradingCommonUtils.convertCollateralToUsd(
                _oiDeltaCollateral,
                _getMultiCollatDiamond().getCollateral(trade.collateralIndex).precisionDelta,
                tradeInfo.collateralPriceUsd
            )
        );

        // 2. Remove OI if window where OI was added isn't outdated
        if (notOutdated) {
            IPriceImpact.PairOi storage window = _getStorage().windows[settings.windowsDuration][trade.pairIndex][
                addWindowId
            ];

            // 2.1 Prevent removing trade OI that was already expired by capping delta at active OI
            uint128 lastWindowOiUsd = getTradeLastWindowOiUsd(_trader, _index);
            oiDeltaUsd = oiDeltaUsd > lastWindowOiUsd ? lastWindowOiUsd : oiDeltaUsd;

            // 2.2 Remove delta from last OI delta for trade so it's up to date
            tradePriceImpactInfo.lastWindowOiUsd = lastWindowOiUsd - oiDeltaUsd;

            // 2.3 Remove OI from trade last oi updated window
            if (trade.long) {
                window.oiLongUsd = oiDeltaUsd < window.oiLongUsd ? window.oiLongUsd - oiDeltaUsd : 0;
            } else {
                window.oiShortUsd = oiDeltaUsd < window.oiShortUsd ? window.oiShortUsd - oiDeltaUsd : 0;
            }
        }

        emit IPriceImpactUtils.PriceImpactOpenInterestRemoved(
            IPriceImpact.OiWindowUpdate(
                _trader,
                _index,
                settings.windowsDuration,
                trade.pairIndex,
                addWindowId,
                trade.long,
                oiDeltaUsd
            ),
            notOutdated
        );
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getTradeLastWindowOiUsd(address _trader, uint32 _index) internal view returns (uint128) {
        uint128 lastWindowOiUsd = _getStorage().tradePriceImpactInfos[_trader][_index].lastWindowOiUsd;
        ITradingStorage.Trade memory trade = _getMultiCollatDiamond().getTrade(_trader, _index);
        return
            lastWindowOiUsd > 0
                ? lastWindowOiUsd
                : uint128( // if lastWindowOiUsd = 0 for trade, it was opened before partials => pos size USD using tradeInfo.collateralPriceUsd
                    TradingCommonUtils.convertCollateralToUsd(
                        TradingCommonUtils.getPositionSizeCollateral(trade.collateralAmount, trade.leverage),
                        _getMultiCollatDiamond().getCollateral(trade.collateralIndex).precisionDelta,
                        _getMultiCollatDiamond().getTradeInfo(_trader, _index).collateralPriceUsd
                    )
                );
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getPriceImpactOi(uint256 _pairIndex, bool _long) internal view returns (uint256 activeOi) {
        IPriceImpact.PriceImpactStorage storage priceImpactStorage = _getStorage();
        IPriceImpact.OiWindowsSettings storage settings = priceImpactStorage.oiWindowsSettings;

        // Return 0 if windowsCount is 0 (no price impact OI)
        if (settings.windowsCount == 0) {
            return 0;
        }

        uint256 currentWindowId = _getCurrentWindowId(settings);
        uint256 earliestWindowId = _getEarliestActiveWindowId(currentWindowId, settings.windowsCount);

        for (uint256 i = earliestWindowId; i <= currentWindowId; ++i) {
            IPriceImpact.PairOi memory _pairOi = priceImpactStorage.windows[settings.windowsDuration][_pairIndex][i];
            activeOi += _long ? _pairOi.oiLongUsd : _pairOi.oiShortUsd;
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getTradePriceImpact(
        uint256 _openPrice, // 1e10
        uint256 _pairIndex,
        bool _long,
        uint256 _tradeOpenInterestUsd // 1e18 USD
    )
        internal
        view
        returns (
            uint256 priceImpactP, // 1e10 (%)
            uint256 priceAfterImpact // 1e10
        )
    {
        IPriceImpact.PairDepth storage pDepth = _getStorage().pairDepths[_pairIndex];
        uint256 depth = _long ? pDepth.onePercentDepthAboveUsd : pDepth.onePercentDepthBelowUsd;

        (priceImpactP, priceAfterImpact) = _getTradePriceImpact(
            _openPrice,
            _long,
            depth > 0 ? getPriceImpactOi(_pairIndex, _long) : 0, // saves gas if depth is 0
            _tradeOpenInterestUsd,
            depth
        );
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getPairDepth(uint256 _pairIndex) internal view returns (IPriceImpact.PairDepth memory) {
        return _getStorage().pairDepths[_pairIndex];
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getOiWindowsSettings() internal view returns (IPriceImpact.OiWindowsSettings memory) {
        return _getStorage().oiWindowsSettings;
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getOiWindow(
        uint48 _windowsDuration,
        uint256 _pairIndex,
        uint256 _windowId
    ) internal view returns (IPriceImpact.PairOi memory) {
        return
            _getStorage().windows[_windowsDuration > 0 ? _windowsDuration : getOiWindowsSettings().windowsDuration][
                _pairIndex
            ][_windowId];
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getOiWindows(
        uint48 _windowsDuration,
        uint256 _pairIndex,
        uint256[] calldata _windowIds
    ) internal view returns (IPriceImpact.PairOi[] memory) {
        IPriceImpact.PairOi[] memory _pairOis = new IPriceImpact.PairOi[](_windowIds.length);

        for (uint256 i; i < _windowIds.length; ++i) {
            _pairOis[i] = getOiWindow(_windowsDuration, _pairIndex, _windowIds[i]);
        }

        return _pairOis;
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getPairDepths(uint256[] calldata _indices) internal view returns (IPriceImpact.PairDepth[] memory) {
        IPriceImpact.PairDepth[] memory depths = new IPriceImpact.PairDepth[](_indices.length);

        for (uint256 i = 0; i < _indices.length; ++i) {
            depths[i] = getPairDepth(_indices[i]);
        }

        return depths;
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getTradePriceImpactInfo(
        address _trader,
        uint32 _index
    ) internal view returns (IPriceImpact.TradePriceImpactInfo memory) {
        return _getStorage().tradePriceImpactInfos[_trader][_index];
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_PRICE_IMPACT_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage() internal pure returns (IPriceImpact.PriceImpactStorage storage s) {
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
     * @dev Transfers total long / short OI from last '_settings.windowsCount' windows of `_prevPairOiWindows`
     * to current window of `_newPairOiWindows` for `_pairsCount` pairs.
     *
     * Emits a {PriceImpactOiTransferredPairs} event.
     *
     * @param _pairsCount number of pairs
     * @param _prevPairOiWindows previous pair OI windows (previous windowsDuration mapping)
     * @param _newPairOiWindows new pair OI windows (new windowsDuration mapping)
     * @param _settings current OI windows settings
     * @param _newWindowsDuration new windows duration
     */
    function _transferPriceImpactOiForPairs(
        uint256 _pairsCount,
        mapping(uint256 => mapping(uint256 => IPriceImpact.PairOi)) storage _prevPairOiWindows, // pairIndex => windowId => PairOi
        mapping(uint256 => mapping(uint256 => IPriceImpact.PairOi)) storage _newPairOiWindows, // pairIndex => windowId => PairOi
        IPriceImpact.OiWindowsSettings memory _settings,
        uint48 _newWindowsDuration
    ) internal {
        uint256 prevCurrentWindowId = _getCurrentWindowId(_settings);
        uint256 prevEarliestWindowId = _getEarliestActiveWindowId(prevCurrentWindowId, _settings.windowsCount);

        uint256 newCurrentWindowId = _getCurrentWindowId(
            IPriceImpact.OiWindowsSettings(_settings.startTs, _newWindowsDuration, _settings.windowsCount)
        );

        for (uint256 pairIndex; pairIndex < _pairsCount; ++pairIndex) {
            _transferPriceImpactOiForPair(
                pairIndex,
                prevCurrentWindowId,
                prevEarliestWindowId,
                _prevPairOiWindows[pairIndex],
                _newPairOiWindows[pairIndex][newCurrentWindowId]
            );
        }

        emit IPriceImpactUtils.PriceImpactOiTransferredPairs(
            _pairsCount,
            prevCurrentWindowId,
            prevEarliestWindowId,
            newCurrentWindowId
        );
    }

    /**
     * @dev Transfers total long / short OI from `prevEarliestWindowId` to `prevCurrentWindowId` windows of
     * `_prevPairOiWindows` to `_newPairOiWindow` window.
     *
     * Emits a {PriceImpactOiTransferredPair} event.
     *
     * @param _pairIndex index of the pair
     * @param _prevCurrentWindowId previous current window ID
     * @param _prevEarliestWindowId previous earliest active window ID
     * @param _prevPairOiWindows previous pair OI windows (previous windowsDuration mapping)
     * @param _newPairOiWindow new pair OI window (new windowsDuration mapping)
     */
    function _transferPriceImpactOiForPair(
        uint256 _pairIndex,
        uint256 _prevCurrentWindowId,
        uint256 _prevEarliestWindowId,
        mapping(uint256 => IPriceImpact.PairOi) storage _prevPairOiWindows,
        IPriceImpact.PairOi storage _newPairOiWindow
    ) internal {
        IPriceImpact.PairOi memory totalPairOi;

        // Aggregate sum of total long / short OI for past windows
        for (uint256 id = _prevEarliestWindowId; id <= _prevCurrentWindowId; ++id) {
            IPriceImpact.PairOi memory pairOi = _prevPairOiWindows[id];

            totalPairOi.oiLongUsd += pairOi.oiLongUsd;
            totalPairOi.oiShortUsd += pairOi.oiShortUsd;

            // Clean up previous map once added to the sum
            delete _prevPairOiWindows[id];
        }

        bool longOiTransfer = totalPairOi.oiLongUsd > 0;
        bool shortOiTransfer = totalPairOi.oiShortUsd > 0;

        if (longOiTransfer) {
            _newPairOiWindow.oiLongUsd += totalPairOi.oiLongUsd;
        }

        if (shortOiTransfer) {
            _newPairOiWindow.oiShortUsd += totalPairOi.oiShortUsd;
        }

        // Only emit IPriceImpactUtils.even if there was an actual OI transfer
        if (longOiTransfer || shortOiTransfer) {
            emit IPriceImpactUtils.PriceImpactOiTransferredPair(_pairIndex, totalPairOi);
        }
    }

    /**
     * @dev Returns window id at `_timestamp` given `_settings`.
     * @param _timestamp timestamp
     * @param _settings OI windows settings
     */
    function _getWindowId(
        uint48 _timestamp,
        IPriceImpact.OiWindowsSettings memory _settings
    ) internal pure returns (uint256) {
        return (_timestamp - _settings.startTs) / _settings.windowsDuration;
    }

    /**
     * @dev Returns window id at current timestamp given `_settings`.
     * @param _settings OI windows settings
     */
    function _getCurrentWindowId(IPriceImpact.OiWindowsSettings memory _settings) internal view returns (uint256) {
        return _getWindowId(uint48(block.timestamp), _settings);
    }

    /**
     * @dev Returns earliest active window id given `_currentWindowId` and `_windowsCount`.
     * @param _currentWindowId current window id
     * @param _windowsCount active windows count
     */
    function _getEarliestActiveWindowId(
        uint256 _currentWindowId,
        uint48 _windowsCount
    ) internal pure returns (uint256) {
        uint256 windowNegativeDelta = _windowsCount - 1; // -1 because we include current window
        return _currentWindowId > windowNegativeDelta ? _currentWindowId - windowNegativeDelta : 0;
    }

    /**
     * @dev Returns whether '_windowId' can be potentially active id given `_currentWindowId`
     * @param _windowId window id
     * @param _currentWindowId current window id
     */
    function _isWindowPotentiallyActive(uint256 _windowId, uint256 _currentWindowId) internal pure returns (bool) {
        return _currentWindowId - _windowId < MAX_WINDOWS_COUNT;
    }

    /**
     * @dev Returns trade price impact % and opening price after impact.
     * @param _openPrice trade open price (1e10 precision)
     * @param _long true for long, false for short
     * @param _startOpenInterestUsd existing open interest of pair on trade side in USD (1e18 precision)
     * @param _tradeOpenInterestUsd open interest of trade in USD (1e18 precision)
     * @param _onePercentDepthUsd one percent depth of pair in USD on trade side
     */
    function _getTradePriceImpact(
        uint256 _openPrice, // 1e10
        bool _long,
        uint256 _startOpenInterestUsd, // 1e18 USD
        uint256 _tradeOpenInterestUsd, // 1e18 USD
        uint256 _onePercentDepthUsd // USD
    )
        internal
        pure
        returns (
            uint256 priceImpactP, // 1e10 (%)
            uint256 priceAfterImpact // 1e10
        )
    {
        if (_onePercentDepthUsd == 0) {
            return (0, _openPrice);
        }

        priceImpactP =
            ((_startOpenInterestUsd + _tradeOpenInterestUsd / 2) * ConstantsUtils.P_10) /
            _onePercentDepthUsd /
            1e18;

        uint256 priceImpact = (priceImpactP * _openPrice) / ConstantsUtils.P_10 / 100;
        priceAfterImpact = _long ? _openPrice + priceImpact : _openPrice - priceImpact;
    }
}
