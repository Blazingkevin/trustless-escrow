// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Escrow.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        Escrow escrow = new Escrow(owner);

        vm.stopBroadcast();

        console.log("========================================");
        console.log("Escrow Contract Deployed!");
        console.log("========================================");
        console.log("Contract Address:", address(escrow));
        console.log("Owner Address:", owner);
        console.log("========================================");
    }
}
