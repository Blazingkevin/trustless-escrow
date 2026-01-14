// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../test/Base.t.sol";
import "../../src/Escrow.sol";

contract EscrowTest is BaseTest {
    Escrow public escrow;

    function setUp() public override {
        super.setUp();

        escrow = new Escrow(deployer);

        vm.deal(client, 100 ether);
        vm.deal(freelancer, 10 ether);
        vm.deal(attacker, 10 ether);
    }

    function test_createEscrow_WithETH_Success() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        assertEq(escrowId, 0, "First escrow should have ID 0");

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);

        assertEq(data.client, client, "Client should match");
        assertEq(data.freelancer, freelancer, "Freelancer should match");
        assertEq(data.arbitrator, address(0), "No arbitrator");
        assertEq(data.token, address(0), "Should be ETH escrow");

        uint256 expectedNet = amount - (amount * 100 / 10000);
        assertEq(data.totalAmount, expectedNet, "Amount should be net of fees");
        assertEq(data.releasedAmount, 0, "Nothing released yet");
        assertEq(data.deadline, deadline, "Deadline should match");
        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Funded), "Should be Funded");
        assertEq(data.hasArbitrator, false, "No arbitrator assigned");
    }

    function test_createEscrow_ZeroAddressFreelancer_Reverts() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.expectRevert(IEscrow.ZeroAddress.selector);

        vm.prank(client);
        escrow.createEscrow{value: amount}(address(0), address(0), address(0), amount, deadline);
    }

    function test_createEscrow_ZeroAmount_Reverts() public {
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.expectRevert(IEscrow.InvalidAmount.selector);
        vm.prank(client);
        escrow.createEscrow{value: 0}(freelancer, address(0), address(0), 0, deadline);
    }

    function test_createEscrow_PastDeadline_Reverts() public {
        uint256 amount = 1 ether;

        vm.warp(block.timestamp + 1 weeks);
        uint256 pastDeadline = block.timestamp - 1 days;

        vm.expectRevert(abi.encodeWithSelector(IEscrow.DeadlinePassed.selector, pastDeadline, block.timestamp));

        vm.prank(client);
        escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, pastDeadline);
    }

    function test_createEscrow_MismatchedValue_Reverts() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.expectRevert(IEscrow.InvalidAmount.selector);
        vm.prank(client);
        escrow.createEscrow{value: 0.5 ether}(freelancer, address(0), address(0), amount, deadline);
    }

    function test_releaseToFreelancer_Success() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        uint256 freelancerBalanceBefore = freelancer.balance;

        vm.prank(client);
        escrow.releaseToFreelancer(escrowId);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Resolved), "Should be Resolved");
        assertEq(data.releasedAmount, data.totalAmount, "All funds should be released");

        uint256 freelancerBalanceAfter = freelancer.balance;
        assertEq(
            freelancerBalanceAfter - freelancerBalanceBefore, data.totalAmount, "Freelancer should receive net amount"
        );
    }

    function test_releaseToFreelancer_OnlyClient_Reverts() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        vm.expectRevert(abi.encodeWithSelector(IEscrow.NotAuthorized.selector, freelancer, client));
        vm.prank(freelancer);
        escrow.releaseToFreelancer(escrowId);
    }

    function test_releaseToFreelancer_Attacker_Reverts() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        vm.expectRevert(abi.encodeWithSelector(IEscrow.NotAuthorized.selector, attacker, client));
        vm.prank(attacker);
        escrow.releaseToFreelancer(escrowId);
    }

    function test_refundToClient_ByFreelancer_Success() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        uint256 clientBalanceBefore = client.balance;

        vm.prank(freelancer);
        escrow.refundToClient(escrowId);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Refunded), "Should be Refunded");

        uint256 clientBalanceAfter = client.balance;
        assertEq(clientBalanceAfter - clientBalanceBefore, data.totalAmount, "Client should receive refund");
    }

    function test_refundToClient_ByClientBeforeDeadline_Reverts() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        vm.expectRevert(abi.encodeWithSelector(IEscrow.DeadlineNotPassed.selector, deadline, block.timestamp));
        vm.prank(client);
        escrow.refundToClient(escrowId);
    }

    function test_refundToClient_ByClientAfterDeadline_Success() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        vm.warp(deadline + 1);

        uint256 clientBalanceBefore = client.balance;

        vm.prank(client);
        escrow.refundToClient(escrowId);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Refunded), "Should be Refunded");

        uint256 clientBalanceAfter = client.balance;
        assertEq(clientBalanceAfter - clientBalanceBefore, data.totalAmount, "Client should receive refund");
    }

    function test_refundToClient_Attacker_Reverts() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        vm.expectRevert(abi.encodeWithSelector(IEscrow.NotAuthorized.selector, attacker, client));
        vm.prank(attacker);
        escrow.refundToClient(escrowId);
    }

    function test_releaseToFreelancer_AlreadyReleased_Reverts() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        vm.prank(client);
        escrow.releaseToFreelancer(escrowId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InvalidState.selector, IEscrow.EscrowState.Resolved, IEscrow.EscrowState.Funded
            )
        );
        vm.prank(client);
        escrow.releaseToFreelancer(escrowId);
    }

    function test_refundToClient_AlreadyRefunded_Reverts() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        vm.prank(freelancer);
        escrow.refundToClient(escrowId);

        // Act & Assert: Try to refund again
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InvalidState.selector, IEscrow.EscrowState.Refunded, IEscrow.EscrowState.Funded
            )
        );
        vm.prank(freelancer);
        escrow.refundToClient(escrowId);
    }

    function test_refundToClient_AfterRelease_Reverts() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + ONE_WEEK;

        vm.prank(client);
        uint256 escrowId = escrow.createEscrow{value: amount}(freelancer, address(0), address(0), amount, deadline);

        vm.prank(client);
        escrow.releaseToFreelancer(escrowId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InvalidState.selector, IEscrow.EscrowState.Resolved, IEscrow.EscrowState.Funded
            )
        );
        vm.prank(freelancer);
        escrow.refundToClient(escrowId);
    }

    function test_getEscrow_Nonexistent_Reverts() public {
        vm.expectRevert(IEscrow.InvalidAmount.selector);
        escrow.getEscrow(999);
    }
}
