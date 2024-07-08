// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./TradingStorageUtils.sol";

/**
 * @dev External library for array getters to save bytecode size in facet libraries
 */
library ArrayGetters {
    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTraders(uint32 _offset, uint32 _limit) public view returns (address[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();

        if (s.traders.length == 0) return new address[](0);

        uint256 lastIndex = s.traders.length - 1;
        _limit = _limit == 0 || _limit > lastIndex ? uint32(lastIndex) : _limit;

        address[] memory traders = new address[](_limit - _offset + 1);

        uint32 currentIndex;
        for (uint32 i = _offset; i <= _limit; ++i) {
            address trader = s.traders[i];
            if (
                s.userCounters[trader][ITradingStorage.CounterType.TRADE].openCount > 0
                    || s.userCounters[trader][ITradingStorage.CounterType.PENDING_ORDER].openCount > 0
            ) {
                traders[currentIndex++] = trader;
            }
        }

        return traders;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTrades(address _trader) public view returns (ITradingStorage.Trade[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter = s.userCounters[_trader][ITradingStorage.CounterType.TRADE];
        ITradingStorage.Trade[] memory trades = new ITradingStorage.Trade[](traderCounter.openCount);

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            ITradingStorage.Trade memory trade = s.trades[_trader][i];
            if (trade.isOpen) {
                trades[currentIndex++] = trade;
            }
        }

        return trades;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTrades(uint256 _offset, uint256 _limit) external view returns (ITradingStorage.Trade[] memory) {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);

        uint256 currentTradeIndex; // current global trade index
        uint256 currentArrayIndex; // current index in returned trades array

        ITradingStorage.Trade[] memory trades = new ITradingStorage.Trade[](_limit - _offset + 1);

        // Fetch all trades for each trader
        for (uint256 i; i < traders.length; ++i) {
            ITradingStorage.Trade[] memory traderTrades = getTrades(traders[i]);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderTrades.length; ++j) {
                if (currentTradeIndex >= _offset && currentTradeIndex <= _limit) {
                    trades[currentArrayIndex++] = traderTrades[j];
                }
                currentTradeIndex++;
            }
        }

        return trades;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradeInfos(address _trader) public view returns (ITradingStorage.TradeInfo[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter = s.userCounters[_trader][ITradingStorage.CounterType.TRADE];
        ITradingStorage.TradeInfo[] memory tradeInfos = new ITradingStorage.TradeInfo[](traderCounter.openCount);

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            if (s.trades[_trader][i].isOpen) {
                tradeInfos[currentIndex++] = s.tradeInfos[_trader][i];
            }
        }

        return tradeInfos;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTradeInfos(uint256 _offset, uint256 _limit)
        external
        view
        returns (ITradingStorage.TradeInfo[] memory)
    {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);

        uint256 currentTradeIndex; // current global trade index
        uint256 currentArrayIndex; // current index in returned trades array

        ITradingStorage.TradeInfo[] memory tradesInfos = new ITradingStorage.TradeInfo[](_limit - _offset + 1);

        // Fetch all trades for each trader
        for (uint256 i; i < traders.length; ++i) {
            ITradingStorage.TradeInfo[] memory traderTradesInfos = getTradeInfos(traders[i]);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderTradesInfos.length; ++j) {
                if (currentTradeIndex >= _offset && currentTradeIndex <= _limit) {
                    tradesInfos[currentArrayIndex++] = traderTradesInfos[j];
                }
                currentTradeIndex++;
            }
        }

        return tradesInfos;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getPendingOrders(address _trader) public view returns (ITradingStorage.PendingOrder[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter =
            s.userCounters[_trader][ITradingStorage.CounterType.PENDING_ORDER];
        ITradingStorage.PendingOrder[] memory pendingOrders =
            new ITradingStorage.PendingOrder[](traderCounter.openCount);

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            if (s.pendingOrders[_trader][i].isOpen) {
                pendingOrders[currentIndex++] = s.pendingOrders[_trader][i];
            }
        }

        return pendingOrders;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllPendingOrders(uint256 _offset, uint256 _limit)
        external
        view
        returns (ITradingStorage.PendingOrder[] memory)
    {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);

        uint256 currentPendingOrderIndex; // current global pending order index
        uint256 currentArrayIndex; // current index in returned pending orders array

        ITradingStorage.PendingOrder[] memory pendingOrders = new ITradingStorage.PendingOrder[](_limit - _offset + 1);

        // Fetch all trades for each trader
        for (uint256 i; i < traders.length; ++i) {
            ITradingStorage.PendingOrder[] memory traderPendingOrders = getPendingOrders(traders[i]);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderPendingOrders.length; ++j) {
                if (currentPendingOrderIndex >= _offset && currentPendingOrderIndex <= _limit) {
                    pendingOrders[currentArrayIndex++] = traderPendingOrders[j];
                }
                currentPendingOrderIndex++;
            }
        }

        return pendingOrders;
    }
}
