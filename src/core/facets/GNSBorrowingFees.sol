// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../abstract/GNSAddressStore.sol";

import "../../interfaces/libraries/IBorrowingFeesUtils.sol";

import "../../libraries/BorrowingFeesUtils.sol";

/**
 * @dev Facet #9: Borrowing Fees and open interests
 */
contract GNSBorrowingFees is GNSAddressStore, IBorrowingFeesUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Management Setters

    /// @inheritdoc IBorrowingFeesUtils
    function setBorrowingPairParams(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        BorrowingPairParams calldata _value
    ) external onlyRole(Role.MANAGER) {
        BorrowingFeesUtils.setBorrowingPairParams(_collateralIndex, _pairIndex, _value);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function setBorrowingPairParamsArray(
        uint8 _collateralIndex,
        uint16[] calldata _indices,
        BorrowingPairParams[] calldata _values
    ) external onlyRole(Role.MANAGER) {
        BorrowingFeesUtils.setBorrowingPairParamsArray(_collateralIndex, _indices, _values);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function setBorrowingGroupParams(
        uint8 _collateralIndex,
        uint16 _groupIndex,
        BorrowingGroupParams calldata _value
    ) external onlyRole(Role.MANAGER) {
        BorrowingFeesUtils.setBorrowingGroupParams(_collateralIndex, _groupIndex, _value);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function setBorrowingGroupParamsArray(
        uint8 _collateralIndex,
        uint16[] calldata _indices,
        BorrowingGroupParams[] calldata _values
    ) external onlyRole(Role.MANAGER) {
        BorrowingFeesUtils.setBorrowingGroupParamsArray(_collateralIndex, _indices, _values);
    }

    // Interactions

    /// @inheritdoc IBorrowingFeesUtils
    function handleTradeBorrowingCallback(
        uint8 _collateralIndex,
        address _trader,
        uint16 _pairIndex,
        uint32 _index,
        uint256 _positionSizeCollateral,
        bool _open,
        bool _long
    ) external virtual onlySelf {
        BorrowingFeesUtils.handleTradeBorrowingCallback(
            _collateralIndex,
            _trader,
            _pairIndex,
            _index,
            _positionSizeCollateral,
            _open,
            _long
        );
    }

    /// @inheritdoc IBorrowingFeesUtils
    function resetTradeBorrowingFees(
        uint8 _collateralIndex,
        address _trader,
        uint16 _pairIndex,
        uint32 _index,
        bool _long
    ) external virtual onlySelf {
        BorrowingFeesUtils.resetTradeBorrowingFees(_collateralIndex, _trader, _pairIndex, _index, _long);
    }

    // Getters

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingPairPendingAccFees(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        uint256 _currentBlock
    ) public view returns (uint64 accFeeLong, uint64 accFeeShort, uint64 pairAccFeeDelta) {
        return BorrowingFeesUtils.getBorrowingPairPendingAccFees(_collateralIndex, _pairIndex, _currentBlock);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingGroupPendingAccFees(
        uint8 _collateralIndex,
        uint16 _groupIndex,
        uint256 _currentBlock
    ) public view returns (uint64 accFeeLong, uint64 accFeeShort, uint64 groupAccFeeDelta) {
        return BorrowingFeesUtils.getBorrowingGroupPendingAccFees(_collateralIndex, _groupIndex, _currentBlock);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getTradeBorrowingFee(BorrowingFeeInput memory _input) public view returns (uint256 feeAmountCollateral) {
        return BorrowingFeesUtils.getTradeBorrowingFee(_input);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getTradeLiquidationPrice(LiqPriceInput calldata _input) external view returns (uint256) {
        return BorrowingFeesUtils.getTradeLiquidationPrice(_input);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getPairOisCollateral(
        uint8 _collateralIndex,
        uint16 _pairIndex
    ) public view returns (uint256 longOi, uint256 shortOi) {
        return BorrowingFeesUtils.getPairOisCollateral(_collateralIndex, _pairIndex);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingPairGroupIndex(
        uint8 _collateralIndex,
        uint16 _pairIndex
    ) public view returns (uint16 groupIndex) {
        return BorrowingFeesUtils.getBorrowingPairGroupIndex(_collateralIndex, _pairIndex);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getPairOiCollateral(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        bool _long
    ) external view returns (uint256) {
        return BorrowingFeesUtils.getPairOiCollateral(_collateralIndex, _pairIndex, _long);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function withinMaxBorrowingGroupOi(
        uint8 _collateralIndex,
        uint16 _pairIndex,
        bool _long,
        uint256 _positionSizeCollateral
    ) external view returns (bool) {
        return
            BorrowingFeesUtils.withinMaxBorrowingGroupOi(_collateralIndex, _pairIndex, _long, _positionSizeCollateral);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingGroup(
        uint8 _collateralIndex,
        uint16 _groupIndex
    ) external view returns (BorrowingData memory) {
        return BorrowingFeesUtils.getBorrowingGroup(_collateralIndex, _groupIndex);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingGroupOi(
        uint8 _collateralIndex,
        uint16 _groupIndex
    ) external view returns (OpenInterest memory) {
        return BorrowingFeesUtils.getBorrowingGroupOi(_collateralIndex, _groupIndex);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingPair(uint8 _collateralIndex, uint16 _pairIndex) external view returns (BorrowingData memory) {
        return BorrowingFeesUtils.getBorrowingPair(_collateralIndex, _pairIndex);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingPairOi(uint8 _collateralIndex, uint16 _pairIndex) external view returns (OpenInterest memory) {
        return BorrowingFeesUtils.getBorrowingPairOi(_collateralIndex, _pairIndex);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingPairGroups(
        uint8 _collateralIndex,
        uint16 _pairIndex
    ) external view returns (BorrowingPairGroup[] memory) {
        return BorrowingFeesUtils.getBorrowingPairGroups(_collateralIndex, _pairIndex);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getAllBorrowingPairs(
        uint8 _collateralIndex
    ) external view returns (BorrowingData[] memory, OpenInterest[] memory, BorrowingPairGroup[][] memory) {
        return BorrowingFeesUtils.getAllBorrowingPairs(_collateralIndex);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingGroups(
        uint8 _collateralIndex,
        uint16[] calldata _indices
    ) external view returns (BorrowingData[] memory, OpenInterest[] memory) {
        return BorrowingFeesUtils.getBorrowingGroups(_collateralIndex, _indices);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getBorrowingInitialAccFees(
        uint8 _collateralIndex,
        address _trader,
        uint32 _index
    ) external view returns (BorrowingInitialAccFees memory) {
        return BorrowingFeesUtils.getBorrowingInitialAccFees(_collateralIndex, _trader, _index);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getPairMaxOi(uint8 _collateralIndex, uint16 _pairIndex) external view returns (uint256) {
        return BorrowingFeesUtils.getPairMaxOi(_collateralIndex, _pairIndex);
    }

    /// @inheritdoc IBorrowingFeesUtils
    function getPairMaxOiCollateral(uint8 _collateralIndex, uint16 _pairIndex) external view returns (uint256) {
        return BorrowingFeesUtils.getPairMaxOiCollateral(_collateralIndex, _pairIndex);
    }
}
