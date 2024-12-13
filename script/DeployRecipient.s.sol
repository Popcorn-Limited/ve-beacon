// // SPDX-License-Identifier: AGPL-3.0
// pragma solidity ^0.8.13;
import {VeRecipientLZ} from "../src/VeRecipient.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployVeRecipientLZ is Script {
    function run() public returns (VeRecipientLZ recipient) {
        uint32 beaconChainEndPointId = 40232; // beacon chain EndPoint ID

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // recipient chain LZ contract address
        address lzEndpoint = address(0);

        // beacon address on beacon chain
        address beacon = address(0);
        
        // deploy recipient - sets msg.sender as owner
        recipient = new VeRecipientLZ(lzEndpoint, beacon, msg.sender);
        
        // set peer with beacon chain
        recipient.setPeer(beaconChainEndPointId, addressToBytes32(beacon));  

        vm.stopBroadcast();
    }
 
    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
