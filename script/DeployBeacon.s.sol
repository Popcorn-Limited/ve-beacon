// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {VeBeaconLZ} from "../src/VeBeacon.sol";
import {VeRecipientLZ} from "../src/VeRecipient.sol";
import {IVotingMinimal} from "../src/interfaces/IVotingEscrow.sol";

// deploy beacon
contract DeployVeBeaconLZ is Script {
    function run() public returns (VeBeaconLZ beacon) {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        IVotingMinimal veToken = IVotingMinimal(address(0)); // veTOKEN

        // beacon chain LZ Endpoint
        address lzEndpoint = address(address(0));

        // deploy - sets msg.sender as owner
        beacon = new VeBeaconLZ(veToken, lzEndpoint, msg.sender);

        vm.stopBroadcast();
    }
}

// broadcast balance
contract TransmitBalanceBeacon is Script {
    function run() public {
        vm.startBroadcast();
        VeBeaconLZ beacon = VeBeaconLZ(address(0));
        address user = address(0);
        uint32 recipientEndpointID = 40231; // arb sepolia

        (uint256 v, ) = beacon.quote(recipientEndpointID, 0, user);

        // broadcast balance
        beacon.broadcastVeBalance{value: v}(user, recipientEndpointID, 0);

        vm.stopBroadcast();
    }
}

// register new peer - add new chain
contract SetupRecipientPeer is Script {
    function run() public {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        uint32 recipientEndpointId = 40231; // arbitrum sepolia eID

        VeBeaconLZ beacon = VeBeaconLZ(address(0));

        // veRecipient address on recipient chain
        address veRecipient = address(0);

        // set recipient peer on beacon chain
        beacon.setPeer(recipientEndpointId, addressToBytes32(veRecipient));

        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
