// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../abstract/GNSAddressStore.sol";

import "../../interfaces/libraries/IPriceImpactUtils.sol";

import "../../libraries/PriceImpactUtils.sol";
import "../../libraries/PairsStorageUtils.sol";

/**
 * @dev Facet #4: Price impact OI windows
 */
contract GNSPriceImpact is GNSAddressStore, IPriceImpactUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IPriceImpactUtils
    function initializePriceImpact(uint48 _windowsDuration, uint48 _windowsCount) external  {
        PriceImpactUtils.initializePriceImpact(_windowsDuration, _windowsCount);
    }

    // Management Setters

    /// @inheritdoc IPriceImpactUtils
    function setPriceImpactWindowsCount(uint48 _newWindowsCount) external onlyRole(Role.GOV) {
        PriceImpactUtils.setPriceImpactWindowsCount(_newWindowsCount);
    }

    /// @inheritdoc IPriceImpactUtils
    function setPriceImpactWindowsDuration(uint48 _newWindowsDuration) external onlyRole(Role.GOV) {
        PriceImpactUtils.setPriceImpactWindowsDuration(_newWindowsDuration, PairsStorageUtils.pairsCount());
    }

    /// @inheritdoc IPriceImpactUtils
    function setPairDepths(
        uint256[] calldata _indices,
        uint128[] calldata _depthsAboveUsd,
        uint128[] calldata _depthsBelowUsd
    ) external onlyRole(Role.MANAGER) {
        PriceImpactUtils.setPairDepths(_indices, _depthsAboveUsd, _depthsBelowUsd);
    }

    // Interactions

    /// @inheritdoc IPriceImpactUtils
    function addPriceImpactOpenInterest(address _trader, uint32 _index, uint256 _oiDeltaCollateral)
        external
        virtual
        onlySelf
    {
        PriceImpactUtils.addPriceImpactOpenInterest(_trader, _index, _oiDeltaCollateral);
    }

    /// @inheritdoc IPriceImpactUtils
    function removePriceImpactOpenInterest(address _trader, uint32 _index, uint256 _oiDeltaCollateral)
        external
        virtual
        onlySelf
    {
        PriceImpactUtils.removePriceImpactOpenInterest(_trader, _index, _oiDeltaCollateral);
    }

    // Getters

    /// @inheritdoc IPriceImpactUtils
    function getTradeLastWindowOiUsd(address _trader, uint32 _index) external view returns (uint128) {
        return PriceImpactUtils.getTradeLastWindowOiUsd(_trader, _index);
    }

    /// @inheritdoc IPriceImpactUtils
    function getPriceImpactOi(uint256 _pairIndex, bool _long) external view returns (uint256 activeOi) {
        return PriceImpactUtils.getPriceImpactOi(_pairIndex, _long);
    }

    /// @inheritdoc IPriceImpactUtils
    function getTradePriceImpact(uint256 _openPrice, uint256 _pairIndex, bool _long, uint256 _tradeOpenInterestUsd)
        external
        view
        returns (uint256 priceImpactP, uint256 priceAfterImpact)
    {
        (priceImpactP, priceAfterImpact) =
            PriceImpactUtils.getTradePriceImpact(_openPrice, _pairIndex, _long, _tradeOpenInterestUsd);
    }

    /// @inheritdoc IPriceImpactUtils
    function getPairDepth(uint256 _pairIndex) external view returns (PairDepth memory) {
        return PriceImpactUtils.getPairDepth(_pairIndex);
    }

    /// @inheritdoc IPriceImpactUtils
    function getOiWindowsSettings() external view returns (OiWindowsSettings memory) {
        return PriceImpactUtils.getOiWindowsSettings();
    }

    /// @inheritdoc IPriceImpactUtils
    function getOiWindow(uint48 _windowsDuration, uint256 _pairIndex, uint256 _windowId)
        external
        view
        returns (PairOi memory)
    {
        return PriceImpactUtils.getOiWindow(_windowsDuration, _pairIndex, _windowId);
    }

    /// @inheritdoc IPriceImpactUtils
    function getOiWindows(uint48 _windowsDuration, uint256 _pairIndex, uint256[] calldata _windowIds)
        external
        view
        returns (PairOi[] memory)
    {
        return PriceImpactUtils.getOiWindows(_windowsDuration, _pairIndex, _windowIds);
    }

    /// @inheritdoc IPriceImpactUtils
    function getPairDepths(uint256[] calldata _indices) external view returns (PairDepth[] memory) {
        return PriceImpactUtils.getPairDepths(_indices);
    }

    /// @inheritdoc IPriceImpactUtils
    function getTradePriceImpactInfo(address _trader, uint32 _index)
        external
        view
        returns (IPriceImpact.TradePriceImpactInfo memory)
    {
        return PriceImpactUtils.getTradePriceImpactInfo(_trader, _index);
    }
}
