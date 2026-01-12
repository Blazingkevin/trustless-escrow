// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract BaseTest is Test {
    address public deployer; // COntract deployer
    address public client; // Client who creates the escrow
    address public freelancer; // Freelancer who receives payment
    address public arbitrator; // Arbitrator who resolves a dispute
    address public attacker; // Malicious actor for security test
    address public user1; // Generic test user 1
    address public user2; // Generic test user 2

    uint256 public constant ESCROW_AMOUNT = 1 ether;
    uint256 public constant SMALL_AMOUNT = 0.1 ether;
    uint256 public constant LARGE_AMOUUNT = 10 ether;

    uint256 public constant ONE_DAY = 1 days;
    uint256 public constant ONE_WEEK = 7 days;
    uint256 public constant THIRTY_DAYS = 30 days;

    function setUp() public virtual {
        // create labelled deterministic addresses for test actors
        deployer = makeAddr("deployer");
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        arbitrator = makeAddr("arbitrator");
        attacker = makeAddr("attacker");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // fund each of the actor address with ether
        vm.deal(deployer, 100 ether);
        vm.deal(client, 100 ether);
        vm.deal(freelancer, 100 ether);
        vm.deal(arbitrator, 100 ether);
        vm.deal(attacker, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        //label addresses
        vm.label(deployer, "Deployer");
        vm.label(client, "Client");
        vm.label(freelancer, "Freelanceer");
        vm.label(arbitrator, "Arbitrator");
        vm.label(attacker, "Attacker");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
    }

    function createUser(string memory label, uint256 balance) public returns (address addr) {
        addr = makeAddr(label);
        vm.deal(addr, balance);
        vm.label(addr, label);
    }

    function assertBalance(address addr, uint256 expected) public view {
        assertEq(addr.balance, expected, string.concat("Balance mismatch for ", vm.toString(addr)));
    }
}
