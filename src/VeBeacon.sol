// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IVotingMinimal as IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import "./base/Structs.sol";
import "solmate/utils/SafeTransferLib.sol";

/// @title VeBeacon
/// @author Vaultcraft
/// @notice Broadcasts veToken balances to other chains via Layer Zero
contract VeBeaconLZ is OApp {
    using OptionsBuilder for bytes;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error VeBeacon__UserNotInitialized();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event BroadcastVeBalance(address indexed user, uint256 indexed endpointID);

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant SLOPE_CHANGES_LENGTH = 8;
    uint256 internal constant DATA_LENGTH =
        4 + 8 * 32 + 32 + SLOPE_CHANGES_LENGTH * 64; // 4b selector + 8 * 32b args + 32b array length + SLOPE_CHANGES_LENGTH * 64b array content

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------
    IVotingEscrow public immutable votingEscrow;

    constructor(
        IVotingEscrow votingEscrow_,
        address layerZeroEndpoint_,
        address owner_
    ) OApp(layerZeroEndpoint_, owner_) {
        votingEscrow = votingEscrow_;
    }

    /// @notice Broadcasts a user's vetoken balance to another chain. Should use quote()
    /// to compute the msg.value required when calling this function.
    /// @param user the user address
    /// @param endpointID the target chain's LZ endpoint Id
    /// @param gasLimit the gas limit of the call to the recipient
    function broadcastVeBalance(
        address user,
        uint32 endpointID,
        uint256 gasLimit
    ) external payable {
        _broadcastVeBalance(user, endpointID, gasLimit);
        _refundEthBalanceIfWorthIt();
    }

    /// @notice Broadcasts a user's vetoken balance to a list of other chains. Should use quote()
    /// to compute the msg.value required when calling this function (currently only applicable to Arbitrum).
    /// @param user the user address
    /// @param endpointIDList the LZ endpoint ID of the target chains
    /// @param gasLimit the gas limit of each call to the recipient
    function broadcastVeBalanceMultiple(
        address user,
        uint32[] calldata endpointIDList,
        uint256 gasLimit
    ) external payable {
        uint256 len = endpointIDList.length;
        for (uint256 i; i < len; ) {
            _broadcastVeBalance(user, endpointIDList[i], gasLimit);

            unchecked {
                ++i;
            }
        }
        _refundEthBalanceIfWorthIt();
    }

    /// @dev Quotes the gas needed to pay for the full layer zero transaction.
    /// @param dstEid Destination chain's LZ endpoint ID
    /// @param gasLimit gasLimit for the execution tx
    /// @param user to get balance of
    /// @return nativeFee Estimated gas fee in native gas.
    /// @return lzTokenFee Estimated gas fee in ZRO token.
    function quote(
        uint32 dstEid,
        uint128 gasLimit,
        address user
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        // encode ve-balance payload
        bytes memory _payload = _getVeBalancePayload(user);

        // create LZ options
        bytes memory options = _createOptions(uint128(gasLimit));

        // call LZ quote
        MessagingFee memory fee = _quote(dstEid, _payload, options, false);

        return (fee.nativeFee, fee.lzTokenFee);
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _broadcastVeBalance(
        address user,
        uint32 endpointID,
        uint256 gasLimit
    ) internal virtual {
        // encode ve-balance payload
        bytes memory payload = _getVeBalancePayload(user);

        // create LZ options
        bytes memory options = _createOptions(uint128(gasLimit));

        // send data to recipient on target chain using LayerZero
        _lzSend(
            endpointID,
            payload,
            options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );

        emit BroadcastVeBalance(user, endpointID);
    }

    function _getVeBalancePayload(
        address user
    ) internal view returns (bytes memory payload) {
        // get user voting escrow data
        uint256 epoch = votingEscrow.user_point_epoch(user);
        if (epoch == 0) revert VeBeacon__UserNotInitialized();
        (int128 userBias, int128 userSlope, uint256 userTs, ) = votingEscrow
            .user_point_history(user, epoch);

        // get global data
        epoch = votingEscrow.epoch();
        (
            int128 globalBias,
            int128 globalSlope,
            uint256 globalTs,

        ) = votingEscrow.point_history(epoch);

        // fetch slope changes in the range [currentEpochStartTimestamp + 1 weeks, currentEpochStartTimestamp + (SLOPE_CHANGES_LENGTH + 1) * 1 weeks]
        uint256 currentEpochStartTimestamp = (block.timestamp / (1 weeks)) *
            (1 weeks);
        SlopeChange[] memory slopeChanges = new SlopeChange[](
            SLOPE_CHANGES_LENGTH
        );
        for (uint256 i; i < SLOPE_CHANGES_LENGTH; ) {
            currentEpochStartTimestamp += 1 weeks;
            slopeChanges[i] = SlopeChange({
                ts: currentEpochStartTimestamp,
                change: votingEscrow.slope_changes(currentEpochStartTimestamp)
            });
            unchecked {
                ++i;
            }
        }

        payload = abi.encode(
            user,
            userBias,
            userSlope,
            userTs,
            globalBias,
            globalSlope,
            globalTs,
            slopeChanges
        );
    }

    function _refundEthBalanceIfWorthIt() internal {
        if (address(this).balance == 0) return; // early return if beacon has no balance
        if (address(this).balance < block.basefee * 21000) return; // early return if refunding ETH costs more than the refunded amount
        SafeTransferLib.safeTransferETH(msg.sender, address(this).balance);
    }

    function _createOptions(
        uint128 gasLimit
    ) internal pure returns (bytes memory) {
        // creates options for gas and msg.value on receiver side
        return
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(
                gasLimit > 0 ? gasLimit : 1e6,
                0
            );
    }

    // the veBeacon is never a receiver
    function _lzReceive(
        Origin calldata origin, // struct containing info about the message sender
        bytes32 guid, // global packet identifier
        bytes calldata payload, // encoded message payload being received
        address executor, // the Executor address.
        bytes calldata extraData // arbitrary data appended by the Executor
    ) internal override {}
}