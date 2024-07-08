// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../interfaces/IGNSMultiCollatDiamond.sol";

import "./StorageUtils.sol";
import "./ChainUtils.sol";
import "./ConstantsUtils.sol";
import "./TradingCommonUtils.sol";

/**
 *
 * @dev GNSBorrowingFees facet internal library
 */
library BorrowingFeesUtils {
    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function setBorrowingPairParams(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        IBorrowingFees.BorrowingPairParams calldata _value
    ) internal validCollateralIndex(_collateralIndex) {
        _setBorrowingPairParams(_collateralIndex, _pairIndex, _value);
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function setBorrowingPairParamsArray(
        uint8 _collateralIndex,
        uint16[] calldata _indices,
        IBorrowingFees.BorrowingPairParams[] calldata _values
    ) internal validCollateralIndex(_collateralIndex) {
        uint256 len = _indices.length;
        if (len != _values.length) {
            revert IGeneralErrors.WrongLength();
        }

        for (uint256 i; i < len; ++i) {
            _setBorrowingPairParams(_collateralIndex, _indices[i], _values[i]);
        }
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function setBorrowingGroupParams(
        uint8 _collateralIndex,
        uint16 _groupIndex,
        IBorrowingFees.BorrowingGroupParams calldata _value
    ) internal validCollateralIndex(_collateralIndex) {
        _setBorrowingGroupParams(_collateralIndex, _groupIndex, _value);
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function setBorrowingGroupParamsArray(
        uint8 _collateralIndex,
        uint16[] calldata _indices,
        IBorrowingFees.BorrowingGroupParams[] calldata _values
    ) internal validCollateralIndex(_collateralIndex) {
        uint256 len = _indices.length;
        if (len != _values.length) {
            revert IGeneralErrors.WrongLength();
        }

        for (uint256 i; i < len; ++i) {
            _setBorrowingGroupParams(_collateralIndex, _indices[i], _values[i]);
        }
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function handleTradeBorrowingCallback(
        uint8 _collateralIndex,
        address _trader,
        uint16 _pairIndex,
        uint32 _index,
        uint256 _positionSizeCollateral,
        bool _open,
        bool _long
    ) internal validCollateralIndex(_collateralIndex) {
        // 1. Store pair and group pending acc fees until now
        uint256 blockNumber = ChainUtils.getBlockNumber();
        uint16 groupIndex = getBorrowingPairGroupIndex(_collateralIndex, _pairIndex);
        _setPairPendingAccFees(_collateralIndex, _pairIndex, blockNumber);
        _setGroupPendingAccFees(_collateralIndex, groupIndex, blockNumber);

        // 2. Update pair and group OIs
        _updatePairOi(_collateralIndex, _pairIndex, _long, _open, _positionSizeCollateral);
        _updateGroupOi(_collateralIndex, groupIndex, _long, _open, _positionSizeCollateral);

        // 3. If open, initialize trade initial acc fees
        if (_open) resetTradeBorrowingFees(_collateralIndex, _trader, _pairIndex, _index, _long);

        emit IBorrowingFeesUtils.TradeBorrowingCallbackHandled(
            _collateralIndex, _trader, _pairIndex, _index, _open, _long, _positionSizeCollateral
        );
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function resetTradeBorrowingFees(
        uint8 _collateralIndex,
        address _trader,
        uint16 _pairIndex,
        uint32 _index,
        bool _long
    ) internal validCollateralIndex(_collateralIndex) {
        uint256 currentBlock = ChainUtils.getBlockNumber();

        (uint64 pairAccFeeLong, uint64 pairAccFeeShort,) =
            getBorrowingPairPendingAccFees(_collateralIndex, _pairIndex, currentBlock);
        (uint64 groupAccFeeLong, uint64 groupAccFeeShort,) = getBorrowingGroupPendingAccFees(
            _collateralIndex, getBorrowingPairGroupIndex(_collateralIndex, _pairIndex), currentBlock
        );

        IBorrowingFees.BorrowingInitialAccFees memory initialFees = IBorrowingFees.BorrowingInitialAccFees(
            _long ? pairAccFeeLong : pairAccFeeShort,
            _long ? groupAccFeeLong : groupAccFeeShort,
            ChainUtils.getUint48BlockNumber(currentBlock),
            0 // placeholder
        );

        _getStorage().initialAccFees[_collateralIndex][_trader][_index] = initialFees;

        emit IBorrowingFeesUtils.BorrowingInitialAccFeesStored(
            _collateralIndex, _trader, _pairIndex, _index, _long, initialFees.accPairFee, initialFees.accGroupFee
        );
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingPairPendingAccFees(uint8 _collateralIndex, uint16 _pairIndex, uint256 _currentBlock)
        internal
        view
        returns (uint64 accFeeLong, uint64 accFeeShort, uint64 pairAccFeeDelta)
    {
        IBorrowingFees.BorrowingFeesStorage storage s = _getStorage();
        IBorrowingFees.BorrowingData memory pair = s.pairs[_collateralIndex][_pairIndex];

        (uint256 pairOiLong, uint256 pairOiShort) = getPairOisCollateral(_collateralIndex, _pairIndex);

        (accFeeLong, accFeeShort, pairAccFeeDelta) = _getBorrowingPendingAccFees(
            IBorrowingFees.PendingBorrowingAccFeesInput(
                pair.accFeeLong,
                pair.accFeeShort,
                pairOiLong,
                pairOiShort,
                pair.feePerBlock,
                _currentBlock,
                pair.accLastUpdatedBlock,
                s.pairOis[_collateralIndex][_pairIndex].max,
                pair.feeExponent,
                _getMultiCollatDiamond().getCollateral(_collateralIndex).precision
            )
        );
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingGroupPendingAccFees(uint8 _collateralIndex, uint16 _groupIndex, uint256 _currentBlock)
        internal
        view
        returns (uint64 accFeeLong, uint64 accFeeShort, uint64 groupAccFeeDelta)
    {
        IBorrowingFees.BorrowingFeesStorage storage s = _getStorage();

        IBorrowingFees.BorrowingData memory group = s.groups[_collateralIndex][_groupIndex];
        IBorrowingFees.OpenInterest memory groupOi = s.groupOis[_collateralIndex][_groupIndex];

        uint128 collateralPrecision = _getMultiCollatDiamond().getCollateral(_collateralIndex).precision;

        (accFeeLong, accFeeShort, groupAccFeeDelta) = _getBorrowingPendingAccFees(
            IBorrowingFees.PendingBorrowingAccFeesInput(
                group.accFeeLong,
                group.accFeeShort,
                (uint256(groupOi.long) * collateralPrecision) / ConstantsUtils.P_10,
                (uint256(groupOi.short) * collateralPrecision) / ConstantsUtils.P_10,
                group.feePerBlock,
                _currentBlock,
                group.accLastUpdatedBlock,
                groupOi.max,
                group.feeExponent,
                collateralPrecision
            )
        );
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getTradeBorrowingFee(IBorrowingFees.BorrowingFeeInput memory _input)
        internal
        view
        returns (uint256 feeAmountCollateral)
    {
        IBorrowingFees.BorrowingInitialAccFees memory initialFees =
            _getStorage().initialAccFees[_input.collateralIndex][_input.trader][_input.index];
        IBorrowingFees.BorrowingPairGroup[] memory pairGroups =
            _getStorage().pairGroups[_input.collateralIndex][_input.pairIndex];

        IBorrowingFees.BorrowingPairGroup memory firstPairGroup;
        if (pairGroups.length > 0) {
            firstPairGroup = pairGroups[0];
        }

        uint256 borrowingFeeP; // 1e10 %

        // If pair has had no group after trade was opened, initialize with pair borrowing fee
        if (pairGroups.length == 0 || firstPairGroup.block > initialFees.block) {
            borrowingFeeP = (
                (
                    pairGroups.length == 0
                        ? _getBorrowingPairPendingAccFee(
                            _input.collateralIndex, _input.pairIndex, ChainUtils.getBlockNumber(), _input.long
                        )
                        : (_input.long ? firstPairGroup.pairAccFeeLong : firstPairGroup.pairAccFeeShort)
                ) - initialFees.accPairFee
            );
        }

        // Sum of max(pair fee, group fee) for all groups the pair was in while trade was open
        for (uint256 i = pairGroups.length; i > 0; --i) {
            (uint64 deltaGroup, uint64 deltaPair, bool beforeTradeOpen) = _getBorrowingPairGroupAccFeesDeltas(
                _input.collateralIndex,
                i - 1,
                pairGroups,
                initialFees,
                _input.pairIndex,
                _input.long,
                ChainUtils.getBlockNumber()
            );

            borrowingFeeP += (deltaGroup > deltaPair ? deltaGroup : deltaPair);

            // Exit loop at first group before trade was open
            if (beforeTradeOpen) break;
        }

        feeAmountCollateral = (_input.collateral * _input.leverage * borrowingFeeP) / 1e3 / ConstantsUtils.P_10 / 100; // collateral precision
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getTradeLiquidationPrice(IBorrowingFees.LiqPriceInput calldata _input) internal view returns (uint256) {
        uint256 closingFeesCollateral = (
            TradingCommonUtils.getPositionSizeCollateralBasis(
                _input.collateralIndex, _input.pairIndex, (_input.collateral * _input.leverage) / 1e3
            )
                * (
                    _getMultiCollatDiamond().pairCloseFeeP(_input.pairIndex)
                        + _getMultiCollatDiamond().pairTriggerOrderFeeP(_input.pairIndex)
                )
        ) / ConstantsUtils.P_10 / 100;

        uint256 borrowingFeesCollateral = _input.useBorrowingFees
            ? getTradeBorrowingFee(
                IBorrowingFees.BorrowingFeeInput(
                    _input.collateralIndex,
                    _input.trader,
                    _input.pairIndex,
                    _input.index,
                    _input.long,
                    _input.collateral,
                    _input.leverage
                )
            )
            : 0;

        return _getTradeLiquidationPrice(
            _input.openPrice,
            _input.long,
            _input.collateral,
            _input.leverage,
            borrowingFeesCollateral + closingFeesCollateral,
            _getMultiCollatDiamond().getCollateral(_input.collateralIndex).precisionDelta
        );
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getPairOisCollateral(uint8 _collateralIndex, uint16 _pairIndex)
        internal
        view
        returns (uint256 longOiCollateral, uint256 shortOiCollateral)
    {
        IBorrowingFees.OpenInterest storage pairOi = _getStorage().pairOis[_collateralIndex][_pairIndex];
        ITradingStorageUtils.Collateral memory collateralConfig =
            _getMultiCollatDiamond().getCollateral(_collateralIndex);
        return (
            (pairOi.long * collateralConfig.precision) / ConstantsUtils.P_10,
            (pairOi.short * collateralConfig.precision) / ConstantsUtils.P_10
        );
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingPairGroupIndex(uint8 _collateralIndex, uint16 _pairIndex)
        internal
        view
        returns (uint16 groupIndex)
    {
        IBorrowingFees.BorrowingPairGroup[] memory pairGroups = _getStorage().pairGroups[_collateralIndex][_pairIndex];
        return pairGroups.length == 0 ? 0 : pairGroups[pairGroups.length - 1].groupIndex;
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getPairOiCollateral(uint8 _collateralIndex, uint16 _pairIndex, bool _long)
        internal
        view
        returns (uint256)
    {
        (uint256 longOiCollateral, uint256 shortOiCollateral) = getPairOisCollateral(_collateralIndex, _pairIndex);
        return _long ? longOiCollateral : shortOiCollateral;
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function withinMaxBorrowingGroupOi(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        bool _long,
        uint256 _positionSizeCollateral
    ) internal view returns (bool) {
        IBorrowingFees.OpenInterest memory groupOi =
            _getStorage().groupOis[_collateralIndex][getBorrowingPairGroupIndex(_collateralIndex, _pairIndex)];

        return (groupOi.max == 0)
            || (
                (_long ? groupOi.long : groupOi.short)
                    + (_positionSizeCollateral * ConstantsUtils.P_10)
                        / _getMultiCollatDiamond().getCollateral(_collateralIndex).precision <= groupOi.max
            );
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingGroup(uint8 _collateralIndex, uint16 _groupIndex)
        internal
        view
        returns (IBorrowingFees.BorrowingData memory)
    {
        return _getStorage().groups[_collateralIndex][_groupIndex];
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingGroupOi(uint8 _collateralIndex, uint16 _groupIndex)
        internal
        view
        returns (IBorrowingFees.OpenInterest memory)
    {
        return _getStorage().groupOis[_collateralIndex][_groupIndex];
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingPair(uint8 _collateralIndex, uint16 _pairIndex)
        internal
        view
        returns (IBorrowingFees.BorrowingData memory)
    {
        return _getStorage().pairs[_collateralIndex][_pairIndex];
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingPairOi(uint8 _collateralIndex, uint16 _pairIndex)
        internal
        view
        returns (IBorrowingFees.OpenInterest memory)
    {
        return _getStorage().pairOis[_collateralIndex][_pairIndex];
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingPairGroups(uint8 _collateralIndex, uint16 _pairIndex)
        internal
        view
        returns (IBorrowingFees.BorrowingPairGroup[] memory)
    {
        return _getStorage().pairGroups[_collateralIndex][_pairIndex];
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getAllBorrowingPairs(uint8 _collateralIndex)
        internal
        view
        returns (
            IBorrowingFees.BorrowingData[] memory,
            IBorrowingFees.OpenInterest[] memory,
            IBorrowingFees.BorrowingPairGroup[][] memory
        )
    {
        IBorrowingFees.BorrowingFeesStorage storage s = _getStorage();

        uint16 len = uint16(_getMultiCollatDiamond().pairsCount());
        IBorrowingFees.BorrowingData[] memory pairs = new IBorrowingFees.BorrowingData[](len);
        IBorrowingFees.OpenInterest[] memory pairOi = new IBorrowingFees.OpenInterest[](len);
        IBorrowingFees.BorrowingPairGroup[][] memory pairGroups = new IBorrowingFees.BorrowingPairGroup[][](len);

        for (uint16 i; i < len; ++i) {
            pairs[i] = s.pairs[_collateralIndex][i];
            pairOi[i] = s.pairOis[_collateralIndex][i];
            pairGroups[i] = s.pairGroups[_collateralIndex][i];
        }

        return (pairs, pairOi, pairGroups);
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingGroups(uint8 _collateralIndex, uint16[] calldata _indices)
        internal
        view
        returns (IBorrowingFees.BorrowingData[] memory, IBorrowingFees.OpenInterest[] memory)
    {
        IBorrowingFees.BorrowingFeesStorage storage s = _getStorage();

        uint256 len = _indices.length;
        IBorrowingFees.BorrowingData[] memory groups = new IBorrowingFees.BorrowingData[](len);
        IBorrowingFees.OpenInterest[] memory groupOis = new IBorrowingFees.OpenInterest[](len);

        for (uint256 i; i < len; ++i) {
            groups[i] = s.groups[_collateralIndex][_indices[i]];
            groupOis[i] = s.groupOis[_collateralIndex][_indices[i]];
        }

        return (groups, groupOis);
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getBorrowingInitialAccFees(uint8 _collateralIndex, address _trader, uint32 _index)
        internal
        view
        returns (IBorrowingFees.BorrowingInitialAccFees memory)
    {
        return _getStorage().initialAccFees[_collateralIndex][_trader][_index];
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getPairMaxOi(uint8 _collateralIndex, uint16 _pairIndex) internal view returns (uint256) {
        return _getStorage().pairOis[_collateralIndex][_pairIndex].max;
    }

    /**
     * @dev Check IBorrowingFeesUtils interface for documentation
     */
    function getPairMaxOiCollateral(uint8 _collateralIndex, uint16 _pairIndex) internal view returns (uint256) {
        return (
            uint256(_getMultiCollatDiamond().getCollateral(_collateralIndex).precision)
                * _getStorage().pairOis[_collateralIndex][_pairIndex].max
        ) / ConstantsUtils.P_10;
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_BORROWING_FEES_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage() internal pure returns (IBorrowingFees.BorrowingFeesStorage storage s) {
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
     * @dev Reverts if collateral index is not valid
     */
    modifier validCollateralIndex(uint8 _collateralIndex) {
        if (!_getMultiCollatDiamond().isCollateralListed(_collateralIndex)) {
            revert IGeneralErrors.InvalidCollateralIndex();
        }
        _;
    }

    /**
     * @dev Returns pending acc borrowing fee for a pair on one side only
     * @param _collateralIndex index of the collateral
     * @param _pairIndex index of the pair
     * @param _currentBlock current block number
     * @param _long true if long side
     * @return accFee new pair acc borrowing fee
     */
    function _getBorrowingPairPendingAccFee(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        uint256 _currentBlock,
        bool _long
    ) internal view returns (uint64 accFee) {
        (uint64 accFeeLong, uint64 accFeeShort,) =
            getBorrowingPairPendingAccFees(_collateralIndex, _pairIndex, _currentBlock);
        return _long ? accFeeLong : accFeeShort;
    }

    /**
     * @dev Returns pending acc borrowing fee for a borrowing group on one side only
     * @param _collateralIndex index of the collateral
     * @param _groupIndex index of the borrowing group
     * @param _currentBlock current block number
     * @param _long true if long side
     * @return accFee new group acc borrowing fee
     */
    function _getBorrowingGroupPendingAccFee(
        uint8 _collateralIndex,
        uint16 _groupIndex,
        uint256 _currentBlock,
        bool _long
    ) internal view returns (uint64 accFee) {
        (uint64 accFeeLong, uint64 accFeeShort,) =
            getBorrowingGroupPendingAccFees(_collateralIndex, _groupIndex, _currentBlock);
        return _long ? accFeeLong : accFeeShort;
    }

    /**
     * @dev Pure function that returns the new acc borrowing fees and delta between two blocks (for pairs and groups)
     * @param _input input data (last acc fees, OIs, fee per block, current block, etc.)
     * @return newAccFeeLong new acc borrowing fee on long side
     * @return newAccFeeShort new acc borrowing fee on short side
     * @return delta delta with current acc borrowing fee (for side that changed)
     */
    function _getBorrowingPendingAccFees(IBorrowingFees.PendingBorrowingAccFeesInput memory _input)
        internal
        pure
        returns (uint64 newAccFeeLong, uint64 newAccFeeShort, uint64 delta)
    {
        if (_input.currentBlock < _input.accLastUpdatedBlock) {
            revert IGeneralErrors.BlockOrder();
        }

        bool moreShorts = _input.oiLong < _input.oiShort;
        uint256 netOi = moreShorts ? _input.oiShort - _input.oiLong : _input.oiLong - _input.oiShort;

        uint256 _delta = _input.maxOi > 0 && _input.feeExponent > 0
            ? (
                (_input.currentBlock - _input.accLastUpdatedBlock) * _input.feePerBlock
                    * ((netOi * 1e10) / _input.maxOi) ** _input.feeExponent
            ) / (uint256(_input.collateralPrecision) ** _input.feeExponent)
            : 0; // 1e10 (%)

        if (_delta > type(uint64).max) {
            revert IGeneralErrors.Overflow();
        }
        delta = uint64(_delta);

        newAccFeeLong = moreShorts ? _input.accFeeLong : _input.accFeeLong + delta;
        newAccFeeShort = moreShorts ? _input.accFeeShort + delta : _input.accFeeShort;
    }

    /**
     * @dev Pure function that returns the liquidation price for a trade (1e10 precision)
     * @param _openPrice trade open price (1e10 precision)
     * @param _long true if long, false if short
     * @param _collateral trade collateral (collateral precision)
     * @param _leverage trade leverage (1e3 precision)
     * @param _feesCollateral closing fees + borrowing fees amount (collateral precision)
     * @param _collateralPrecisionDelta collateral precision delta (10^18/10^decimals)
     */
    function _getTradeLiquidationPrice(
        uint256 _openPrice,
        bool _long,
        uint256 _collateral,
        uint256 _leverage,
        uint256 _feesCollateral,
        uint128 _collateralPrecisionDelta
    ) internal pure returns (uint256) {
        uint256 precisionDeltaUint = uint256(_collateralPrecisionDelta);

        int256 openPriceInt = int256(_openPrice);
        int256 collateralLiqNegativePnlInt =
            int256((_collateral * ConstantsUtils.LIQ_THRESHOLD_P * precisionDeltaUint * 1e3) / 100); // 1e18 * 1e3
        int256 feesInt = int256(_feesCollateral * precisionDeltaUint * 1e3); // 1e18 * 1e3

        // 1e10
        int256 liqPriceDistance = (openPriceInt * (collateralLiqNegativePnlInt - feesInt)) // 1e10 * 1e18 * 1e3
            / int256(_collateral) / int256(_leverage) / int256(precisionDeltaUint); // 1e10

        int256 liqPrice = _long ? openPriceInt - liqPriceDistance : openPriceInt + liqPriceDistance; // 1e10

        return liqPrice > 0 ? uint256(liqPrice) : 0; // 1e10
    }

    /**
     * @dev Function to set borrowing pair params
     * @param _collateralIndex index of the collateral
     * @param _pairIndex index of the pair
     * @param _value new pair params
     */
    function _setBorrowingPairParams(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        IBorrowingFees.BorrowingPairParams calldata _value
    ) internal {
        if (_value.feeExponent < 1 || _value.feeExponent > 3) {
            revert IBorrowingFeesUtils.BorrowingWrongExponent();
        }

        IBorrowingFees.BorrowingFeesStorage storage s = _getStorage();
        IBorrowingFees.BorrowingData storage p = s.pairs[_collateralIndex][_pairIndex];

        uint16 prevGroupIndex = getBorrowingPairGroupIndex(_collateralIndex, _pairIndex);
        uint256 currentBlock = ChainUtils.getBlockNumber();

        _setPairPendingAccFees(_collateralIndex, _pairIndex, currentBlock);

        if (_value.groupIndex != prevGroupIndex) {
            _setGroupPendingAccFees(_collateralIndex, prevGroupIndex, currentBlock);
            _setGroupPendingAccFees(_collateralIndex, _value.groupIndex, currentBlock);

            (uint256 oiLong, uint256 oiShort) = getPairOisCollateral(_collateralIndex, _pairIndex);

            // Only remove OI from old group if old group is not 0
            _updateGroupOi(_collateralIndex, prevGroupIndex, true, false, oiLong);
            _updateGroupOi(_collateralIndex, prevGroupIndex, false, false, oiShort);

            // Add OI to new group if it's not group 0 (even if old group is 0)
            // So when we assign a pair to a group, it takes into account its OI
            // And group 0 OI will always be 0 but it doesn't matter since it's not used
            _updateGroupOi(_collateralIndex, _value.groupIndex, true, true, oiLong);
            _updateGroupOi(_collateralIndex, _value.groupIndex, false, true, oiShort);

            IBorrowingFees.BorrowingData memory newGroup = s.groups[_collateralIndex][_value.groupIndex];
            IBorrowingFees.BorrowingData memory prevGroup = s.groups[_collateralIndex][prevGroupIndex];

            s.pairGroups[_collateralIndex][_pairIndex].push(
                IBorrowingFees.BorrowingPairGroup(
                    _value.groupIndex,
                    ChainUtils.getUint48BlockNumber(currentBlock),
                    newGroup.accFeeLong,
                    newGroup.accFeeShort,
                    prevGroup.accFeeLong,
                    prevGroup.accFeeShort,
                    p.accFeeLong,
                    p.accFeeShort,
                    0 // placeholder
                )
            );

            emit IBorrowingFeesUtils.BorrowingPairGroupUpdated(
                _collateralIndex, _pairIndex, prevGroupIndex, _value.groupIndex
            );
        }

        p.feePerBlock = _value.feePerBlock;
        p.feeExponent = _value.feeExponent;
        s.pairOis[_collateralIndex][_pairIndex].max = _value.maxOi;

        emit IBorrowingFeesUtils.BorrowingPairParamsUpdated(
            _collateralIndex, _pairIndex, _value.groupIndex, _value.feePerBlock, _value.feeExponent, _value.maxOi
        );
    }

    /**
     * @dev Function to set borrowing group params
     * @param _collateralIndex index of the collateral
     * @param _groupIndex index of the borrowing group
     * @param _value new group params
     */
    function _setBorrowingGroupParams(
        uint8 _collateralIndex,
        uint16 _groupIndex,
        IBorrowingFees.BorrowingGroupParams calldata _value
    ) internal {
        if (_groupIndex == 0) {
            revert IBorrowingFeesUtils.BorrowingZeroGroup();
        }
        if (_value.feeExponent < 1 || _value.feeExponent > 3) {
            revert IBorrowingFeesUtils.BorrowingWrongExponent();
        }

        _setGroupPendingAccFees(_collateralIndex, _groupIndex, ChainUtils.getBlockNumber());

        IBorrowingFees.BorrowingFeesStorage storage s = _getStorage();
        IBorrowingFees.BorrowingData storage group = s.groups[_collateralIndex][_groupIndex];

        group.feePerBlock = _value.feePerBlock;
        group.feeExponent = _value.feeExponent;
        s.groupOis[_collateralIndex][_groupIndex].max = _value.maxOi;

        emit IBorrowingFeesUtils.BorrowingGroupUpdated(
            _collateralIndex, _groupIndex, _value.feePerBlock, _value.maxOi, _value.feeExponent
        );
    }

    /**
     * @dev Function to update a borrowing pair/group open interest
     * @param _oiStorage open interest storage reference
     * @param _long true if long, false if short
     * @param _increase true if increase, false if decrease
     * @param _amountCollateral amount of collateral to increase/decrease (collateral precision)
     * @param _collateralPrecision collateral precision (10^decimals)
     * @return newOiLong new long open interest (1e10)
     * @return newOiShort new short open interest (1e10)
     * @return delta difference between new and current open interest (1e10)
     */
    function _updateOi(
        IBorrowingFees.OpenInterest storage _oiStorage,
        bool _long,
        bool _increase,
        uint256 _amountCollateral,
        uint128 _collateralPrecision
    ) internal returns (uint72 newOiLong, uint72 newOiShort, uint72 delta) {
        _amountCollateral = (_amountCollateral * ConstantsUtils.P_10) / _collateralPrecision; // 1e10

        if (_amountCollateral > type(uint72).max) {
            revert IGeneralErrors.Overflow();
        }

        delta = uint72(_amountCollateral);

        IBorrowingFees.OpenInterest memory oi = _oiStorage;

        if (_long) {
            oi.long = _increase ? oi.long + delta : delta > oi.long ? 0 : oi.long - delta;
            _oiStorage.long = oi.long;
        } else {
            oi.short = _increase ? oi.short + delta : delta > oi.short ? 0 : oi.short - delta;
            _oiStorage.short = oi.short;
        }

        return (oi.long, oi.short, delta);
    }

    /**
     * @dev Function to update a borrowing group's open interest
     * @param _collateralIndex index of the collateral
     * @param _pairIndex index of the borrowing group
     * @param _long true if long, false if short
     * @param _increase true if increase, false if decrease
     * @param _amountCollateral amount of collateral to increase/decrease (collateral precision)
     */
    function _updatePairOi(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        bool _long,
        bool _increase,
        uint256 _amountCollateral
    ) internal {
        (uint72 newOiLong, uint72 newOiShort, uint72 delta) = _updateOi(
            _getStorage().pairOis[_collateralIndex][_pairIndex],
            _long,
            _increase,
            _amountCollateral,
            _getMultiCollatDiamond().getCollateral(_collateralIndex).precision
        );

        emit IBorrowingFeesUtils.BorrowingPairOiUpdated(
            _collateralIndex, _pairIndex, _long, _increase, delta, newOiLong, newOiShort
        );
    }

    /**
     * @dev Function to update a borrowing group's open interest
     * @param _collateralIndex index of the collateral
     * @param _groupIndex index of the borrowing group
     * @param _long true if long, false if short
     * @param _increase true if increase, false if decrease
     * @param _amountCollateral amount of collateral to increase/decrease (collateral precision)
     */
    function _updateGroupOi(
        uint8 _collateralIndex,
        uint16 _groupIndex,
        bool _long,
        bool _increase,
        uint256 _amountCollateral
    ) internal {
        if (_groupIndex > 0) {
            (uint72 newOiLong, uint72 newOiShort, uint72 delta) = _updateOi(
                _getStorage().groupOis[_collateralIndex][_groupIndex],
                _long,
                _increase,
                _amountCollateral,
                _getMultiCollatDiamond().getCollateral(_collateralIndex).precision
            );

            emit IBorrowingFeesUtils.BorrowingGroupOiUpdated(
                _collateralIndex, _groupIndex, _long, _increase, delta, newOiLong, newOiShort
            );
        }
    }

    /**
     * @dev Calculates the borrowing group and pair acc fees deltas for a trade between pair group at index _i and next one
     * @param _collateralIndex index of the collateral
     * @param _i index of the borrowing pair group
     * @param _pairGroups all pair's historical borrowing groups
     * @param _initialFees trade initial borrowing fees
     * @param _pairIndex index of the pair
     * @param _long true if long, false if short
     * @param _currentBlock current block number
     * @return deltaGroup difference between new and current group acc borrowing fee
     * @return deltaPair difference between new and current pair acc borrowing fee
     * @return beforeTradeOpen true if pair group was set before trade was opened
     */
    function _getBorrowingPairGroupAccFeesDeltas(
        uint8 _collateralIndex,
        uint256 _i,
        IBorrowingFees.BorrowingPairGroup[] memory _pairGroups,
        IBorrowingFees.BorrowingInitialAccFees memory _initialFees,
        uint16 _pairIndex,
        bool _long,
        uint256 _currentBlock
    ) internal view returns (uint64 deltaGroup, uint64 deltaPair, bool beforeTradeOpen) {
        IBorrowingFees.BorrowingPairGroup memory group = _pairGroups[_i];

        beforeTradeOpen = group.block < _initialFees.block;

        if (_i == _pairGroups.length - 1) {
            // Last active group
            deltaGroup = _getBorrowingGroupPendingAccFee(_collateralIndex, group.groupIndex, _currentBlock, _long);
            deltaPair = _getBorrowingPairPendingAccFee(_collateralIndex, _pairIndex, _currentBlock, _long);
        } else {
            // Previous groups
            IBorrowingFees.BorrowingPairGroup memory nextGroup = _pairGroups[_i + 1];

            // If it's not the first group to be before the trade was opened then fee is 0
            if (beforeTradeOpen && nextGroup.block <= _initialFees.block) {
                return (0, 0, beforeTradeOpen);
            }

            deltaGroup = _long ? nextGroup.prevGroupAccFeeLong : nextGroup.prevGroupAccFeeShort;
            deltaPair = _long ? nextGroup.pairAccFeeLong : nextGroup.pairAccFeeShort;
        }

        if (beforeTradeOpen) {
            deltaGroup -= _initialFees.accGroupFee;
            deltaPair -= _initialFees.accPairFee;
        } else {
            deltaGroup -= (_long ? group.initialAccFeeLong : group.initialAccFeeShort);
            deltaPair -= (_long ? group.pairAccFeeLong : group.pairAccFeeShort);
        }
    }

    /**
     *
     * @param _collateralIndex index of the collateral
     * @param _pairIndex index of the pair
     * @param _currentBlock current block number
     * @return accFeeLong new pair acc borrowing fee on long side (1e10 precision)
     * @return accFeeShort new pair acc borrowing fee on short side (1e10 precision)
     */
    function _setPairPendingAccFees(uint8 _collateralIndex, uint16 _pairIndex, uint256 _currentBlock)
        internal
        returns (uint64 accFeeLong, uint64 accFeeShort)
    {
        (accFeeLong, accFeeShort,) = getBorrowingPairPendingAccFees(_collateralIndex, _pairIndex, _currentBlock);

        IBorrowingFees.BorrowingData storage pair = _getStorage().pairs[_collateralIndex][_pairIndex];

        (pair.accFeeLong, pair.accFeeShort) = (accFeeLong, accFeeShort);
        pair.accLastUpdatedBlock = ChainUtils.getUint48BlockNumber(_currentBlock);

        emit IBorrowingFeesUtils.BorrowingPairAccFeesUpdated(
            _collateralIndex, _pairIndex, _currentBlock, pair.accFeeLong, pair.accFeeShort
        );
    }

    /**
     *
     * @param _collateralIndex index of the collateral
     * @param _groupIndex index of the borrowing group
     * @param _currentBlock current block number
     * @return accFeeLong new group acc borrowing fee on long side (1e10 precision)
     * @return accFeeShort new group acc borrowing fee on short side (1e10 precision)
     */
    function _setGroupPendingAccFees(uint8 _collateralIndex, uint16 _groupIndex, uint256 _currentBlock)
        internal
        returns (uint64 accFeeLong, uint64 accFeeShort)
    {
        (accFeeLong, accFeeShort,) = getBorrowingGroupPendingAccFees(_collateralIndex, _groupIndex, _currentBlock);

        IBorrowingFees.BorrowingData storage group = _getStorage().groups[_collateralIndex][_groupIndex];

        (group.accFeeLong, group.accFeeShort) = (accFeeLong, accFeeShort);
        group.accLastUpdatedBlock = ChainUtils.getUint48BlockNumber(_currentBlock);

        emit IBorrowingFeesUtils.BorrowingGroupAccFeesUpdated(
            _collateralIndex, _groupIndex, _currentBlock, group.accFeeLong, group.accFeeShort
        );
    }
}
