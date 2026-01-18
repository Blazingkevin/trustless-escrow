pragma solidity ^0.8.20;

import "../../test/Base.t.sol";
import "../../src/Escrow.sol";

contract EscrowMilestonesTest is BaseTest {
    Escrow public escrow;

    event EscrowCreated(
        uint256 indexed escrowId, address indexed client, address indexed freelancer, uint256 amount, address token
    );
    event FundsDeposited(uint256 indexed escrowId, uint256 amount);
    event MilestoneCompleted(uint256 indexed escrowId, uint256 milestoneIndex);
    event MilestoneReleased(uint256 indexed escrowId, uint256 milestoneIndex, uint256 amount, address freelancer);

    function setUp() public override {
        super.setUp();

        escrow = new Escrow(deployer);

        vm.deal(client, 100 ether);
        vm.deal(freelancer, 10 ether);
        vm.deal(attacker, 10 ether);
    }

    function _createSampleMilestones() internal view returns (IEscrow.Milestone[] memory) {
        IEscrow.Milestone[] memory milestones = new IEscrow.Milestone[](3);

        milestones[0] = IEscrow.Milestone({
            description: "Design mockups and wireframes",
            amount: 1 ether,
            deadline: block.timestamp + ONE_WEEK,
            completed: false,
            paid: false
        });

        milestones[1] = IEscrow.Milestone({
            description: "Frontend implementation",
            amount: 2 ether,
            deadline: block.timestamp + (ONE_WEEK * 2),
            completed: false,
            paid: false
        });

        milestones[2] = IEscrow.Milestone({
            description: "Backend and deployment",
            amount: 1.5 ether,
            deadline: block.timestamp + THIRTY_DAYS,
            completed: false,
            paid: false
        });

        return milestones;
    }

    function _createSingleMilestone() internal view returns (IEscrow.Milestone[] memory) {
        IEscrow.Milestone[] memory milestones = new IEscrow.Milestone[](1);

        milestones[0] = IEscrow.Milestone({
            description: "Complete website",
            amount: 5 ether,
            deadline: block.timestamp + ONE_WEEK,
            completed: false,
            paid: false
        });

        return milestones;
    }

    function test_createEscrowWithMilestones_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        uint256 totalAmount = 4.5 ether;

        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: totalAmount}(freelancer, arbitrator, address(0), milestones);

        assertEq(escrowId, 0);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(data.client, client);
        assertEq(data.freelancer, freelancer);
        assertEq(data.arbitrator, arbitrator);
        assertEq(data.token, address(0));

        uint256 expectedNet = totalAmount - (totalAmount * 100 / 10000);
        assertEq(data.totalAmount, expectedNet);

        assertEq(data.releasedAmount, 0);
        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Funded));
        assertEq(data.hasArbitrator, true);

        assertEq(escrow.getMilestoneCount(escrowId), 3);

        IEscrow.Milestone memory m0 = escrow.getMilestone(escrowId, 0);
        assertEq(m0.amount, 1 ether);
        assertEq(m0.description, "Design mockups and wireframes");
        assertEq(m0.completed, false);
        assertEq(m0.paid, false);

        IEscrow.Milestone memory m1 = escrow.getMilestone(escrowId, 1);
        assertEq(m1.amount, 2 ether);

        IEscrow.Milestone memory m2 = escrow.getMilestone(escrowId, 2);
        assertEq(m2.amount, 1.5 ether);
    }

    function test_createEscrowWithMilestones_ZeroMilestones_Reverts() public {
        IEscrow.Milestone[] memory milestones = new IEscrow.Milestone[](0);

        vm.expectRevert(IEscrow.InvalidAmount.selector);
        vm.prank(client);
        escrow.createEscrowWithMilestones{value: 1 ether}(freelancer, arbitrator, address(0), milestones);
    }

    function test_createEscrowWithMilestones_MismatchedValue_Reverts() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();

        vm.expectRevert(IEscrow.InvalidAmount.selector);
        vm.prank(client);
        escrow.createEscrowWithMilestones{value: 3 ether}(freelancer, arbitrator, address(0), milestones);
    }

    function test_createEscrowWithMilestones_ZeroMilestoneAmount_Reverts() public {
        IEscrow.Milestone[] memory milestones = new IEscrow.Milestone[](1);

        milestones[0] = IEscrow.Milestone({
            description: "Test", amount: 0, deadline: block.timestamp + ONE_WEEK, completed: false, paid: false
        });

        vm.expectRevert(IEscrow.InvalidAmount.selector);
        vm.prank(client);
        escrow.createEscrowWithMilestones{value: 0}(freelancer, arbitrator, address(0), milestones);
    }

    function test_createEscrowWithMilestones_PastDeadline_Reverts() public {
        vm.warp(block.timestamp + ONE_WEEK);

        IEscrow.Milestone[] memory milestones = new IEscrow.Milestone[](1);

        milestones[0] = IEscrow.Milestone({
            description: "Test", amount: 1 ether, deadline: block.timestamp - 1, completed: false, paid: false
        });

        vm.expectRevert();
        vm.prank(client);
        escrow.createEscrowWithMilestones{value: 1 ether}(freelancer, arbitrator, address(0), milestones);
    }

    function test_createEscrowWithMilestones_ZeroAddressFreelancer_Reverts() public {
        IEscrow.Milestone[] memory milestones = _createSingleMilestone();

        vm.expectRevert(IEscrow.ZeroAddress.selector);
        vm.prank(client);
        escrow.createEscrowWithMilestones{value: 5 ether}(address(0), arbitrator, address(0), milestones);
    }

    function test_createEscrowWithMilestones_CorrectBalance() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        uint256 totalAmount = 4.5 ether;

        uint256 contractBalanceBefore = address(escrow).balance;

        vm.prank(client);
        escrow.createEscrowWithMilestones{value: totalAmount}(freelancer, arbitrator, address(0), milestones);

        uint256 contractBalanceAfter = address(escrow).balance;
        assertEq(contractBalanceAfter - contractBalanceBefore, totalAmount);
    }

    function test_createEscrowWithMilestones_EmitsEvents() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        uint256 totalAmount = 4.5 ether;
        uint256 expectedNet = totalAmount - (totalAmount * 100 / 10000);

        vm.expectEmit(true, true, true, true);
        emit EscrowCreated(0, client, freelancer, expectedNet, address(0));

        vm.expectEmit(true, false, false, true);
        emit FundsDeposited(0, expectedNet);

        vm.prank(client);
        escrow.createEscrowWithMilestones{value: totalAmount}(freelancer, arbitrator, address(0), milestones);
    }

    function test_createEscrowWithMilestones_MultipleEscrows() public {
        IEscrow.Milestone[] memory milestones = _createSingleMilestone();

        vm.prank(client);
        uint256 escrowId1 =
            escrow.createEscrowWithMilestones{value: 5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.prank(client);
        uint256 escrowId2 =
            escrow.createEscrowWithMilestones{value: 5 ether}(freelancer, arbitrator, address(0), milestones);

        assertEq(escrowId1, 0);
        assertEq(escrowId2, 1);

        IEscrow.EscrowData memory data1 = escrow.getEscrow(escrowId1);
        IEscrow.EscrowData memory data2 = escrow.getEscrow(escrowId2);

        assertEq(data1.client, client);
        assertEq(data2.client, client);
    }

    function test_completeMilestone_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.expectEmit(true, false, false, true);
        emit MilestoneCompleted(escrowId, 0);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);

        IEscrow.Milestone memory milestone = escrow.getMilestone(escrowId, 0);
        assertTrue(milestone.completed);
        assertFalse(milestone.paid);

        IEscrow.Milestone memory milestone1 = escrow.getMilestone(escrowId, 1);
        assertFalse(milestone1.completed);
    }

    function test_completeMilestone_OnlyFreelancer_Reverts() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.expectRevert();
        vm.prank(client);
        escrow.completeMilestone(escrowId, 0);

        vm.expectRevert();
        vm.prank(attacker);
        escrow.completeMilestone(escrowId, 0);
    }

    function test_completeMilestone_InvalidIndex_Reverts() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.expectRevert();
        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 99);
    }

    function test_completeMilestone_AlreadyCompleted_Succeeds() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);

        vm.expectEmit(true, false, false, true);
        emit MilestoneCompleted(escrowId, 0);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);

        IEscrow.Milestone memory milestone = escrow.getMilestone(escrowId, 0);
        assertTrue(milestone.completed);
    }

    function test_completeMilestone_AlreadyPaid_Reverts() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);

        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);

        vm.expectRevert();
        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);
    }

    function test_completeMilestone_OutOfOrder_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 2);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);

        assertTrue(escrow.getMilestone(escrowId, 0).completed);
        assertFalse(escrow.getMilestone(escrowId, 1).completed);
        assertTrue(escrow.getMilestone(escrowId, 2).completed);
    }

    function test_releaseMilestone_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);

        uint256 freelancerBalanceBefore = freelancer.balance;

        vm.expectEmit(true, false, false, true);
        emit MilestoneReleased(escrowId, 0, 1 ether, freelancer);

        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);

        uint256 freelancerBalanceAfter = freelancer.balance;
        assertEq(freelancerBalanceAfter - freelancerBalanceBefore, 1 ether);

        IEscrow.Milestone memory milestone = escrow.getMilestone(escrowId, 0);
        assertTrue(milestone.completed);
        assertTrue(milestone.paid);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(data.releasedAmount, 1 ether);
        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Funded));
    }

    function test_releaseMilestone_OnlyClient_Reverts() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.expectRevert();
        vm.prank(freelancer);
        escrow.releaseMilestone(escrowId, 0);

        vm.expectRevert();
        vm.prank(attacker);
        escrow.releaseMilestone(escrowId, 0);
    }

    function test_releaseMilestone_WithoutCompletion_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        uint256 balanceBefore = freelancer.balance;

        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);

        uint256 balanceAfter = freelancer.balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);

        IEscrow.Milestone memory milestone = escrow.getMilestone(escrowId, 0);
        assertFalse(milestone.completed);
        assertTrue(milestone.paid);
    }

    function test_releaseMilestone_AlreadyPaid_Reverts() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);

        vm.expectRevert();
        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);
    }

    function test_releaseMilestone_AllPaid_StateResolved() public {
        IEscrow.Milestone[] memory milestones = _createSingleMilestone();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 5 ether}(freelancer, arbitrator, address(0), milestones);

        assertEq(uint256(escrow.getEscrow(escrowId).state), uint256(IEscrow.EscrowState.Funded));

        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);

        IEscrow.Milestone memory milestone = escrow.getMilestone(escrowId, 0);
        assertTrue(milestone.paid);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);

        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Funded));
        assertEq(data.releasedAmount, 5 ether);
        assertEq(data.totalAmount, 4.95 ether);
        assertGt(data.releasedAmount, data.totalAmount);
    }

    function test_releaseMilestone_PartialPaid_StateStillFunded() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Funded));
        assertLt(data.releasedAmount, data.totalAmount);
    }

    function test_releaseMilestone_OutOfOrder_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        uint256 balanceBefore = freelancer.balance;

        vm.prank(client);
        escrow.releaseMilestone(escrowId, 2);

        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);

        uint256 balanceAfter = freelancer.balance;
        assertEq(balanceAfter - balanceBefore, 2.5 ether);

        assertFalse(escrow.getMilestone(escrowId, 1).paid);
        assertTrue(escrow.getMilestone(escrowId, 0).paid);
        assertTrue(escrow.getMilestone(escrowId, 2).paid);
    }

    function test_releaseMilestone_ContractBalanceDecreases() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        uint256 contractBalanceBefore = address(escrow).balance;

        vm.prank(client);
        escrow.releaseMilestone(0, 0);

        uint256 contractBalanceAfter = address(escrow).balance;
        assertEq(contractBalanceBefore - contractBalanceAfter, 1 ether);
    }

    function test_releaseMilestone_InvalidIndex_Reverts() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.expectRevert();
        vm.prank(client);
        escrow.releaseMilestone(escrowId, 99);
    }

    function test_releaseMilestone_AllReleased_NoFundsLeft() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        uint256 initialBalance = address(escrow).balance;

        vm.startPrank(client);
        escrow.releaseMilestone(escrowId, 0);
        escrow.releaseMilestone(escrowId, 1);
        escrow.releaseMilestone(escrowId, 2);
        vm.stopPrank();

        assertTrue(escrow.getMilestone(escrowId, 0).paid);
        assertTrue(escrow.getMilestone(escrowId, 1).paid);
        assertTrue(escrow.getMilestone(escrowId, 2).paid);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);

        assertEq(data.releasedAmount, 4.5 ether);
        assertEq(data.totalAmount, 4.455 ether);
        assertGt(data.releasedAmount, data.totalAmount);

        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Funded));

        assertEq(address(escrow).balance, initialBalance - 4.5 ether);
    }

    function test_getMilestone_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        IEscrow.Milestone memory milestone = escrow.getMilestone(escrowId, 1);

        assertEq(milestone.amount, 2 ether);
        assertEq(milestone.description, "Frontend implementation");
        assertEq(milestone.deadline, block.timestamp + (ONE_WEEK * 2));
        assertFalse(milestone.completed);
        assertFalse(milestone.paid);
    }

    function test_getMilestone_InvalidIndex_Reverts() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.expectRevert();
        escrow.getMilestone(escrowId, 99);
    }

    function test_getMilestoneCount_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        uint256 count = escrow.getMilestoneCount(escrowId);

        assertEq(count, 3);
    }

    function test_getMilestoneCount_NonexistentEscrow_Reverts() public {
        vm.expectRevert();
        escrow.getMilestoneCount(999);
    }

    function test_fullMilestoneWorkflow_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        uint256 totalAmount = 4.5 ether;
        uint256 expectedNet = totalAmount - (totalAmount * 100 / 10000);

        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: totalAmount}(freelancer, arbitrator, address(0), milestones);

        uint256 freelancerBalanceBefore = freelancer.balance;

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);
        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 1);
        vm.prank(client);
        escrow.releaseMilestone(escrowId, 1);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 2);
        vm.prank(client);
        escrow.releaseMilestone(escrowId, 2);

        uint256 freelancerBalanceAfter = freelancer.balance;

        assertEq(freelancerBalanceAfter - freelancerBalanceBefore, totalAmount);

        assertTrue(escrow.getMilestone(escrowId, 0).paid);
        assertTrue(escrow.getMilestone(escrowId, 1).paid);
        assertTrue(escrow.getMilestone(escrowId, 2).paid);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);

        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Funded));
        assertEq(data.releasedAmount, 4.5 ether);
        assertEq(data.totalAmount, 4.455 ether);
        assertGt(data.releasedAmount, data.totalAmount);
    }

    function test_partialMilestoneWorkflow_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        uint256 balanceBefore = freelancer.balance;

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);
        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 1);
        vm.prank(client);
        escrow.releaseMilestone(escrowId, 1);

        uint256 balanceAfter = freelancer.balance;
        assertEq(balanceAfter - balanceBefore, 3 ether);

        IEscrow.Milestone memory m3 = escrow.getMilestone(escrowId, 2);
        assertFalse(m3.completed);
        assertFalse(m3.paid);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint256(data.state), uint256(IEscrow.EscrowState.Funded));
    }

    function test_mixedMilestoneWorkflow_Success() public {
        IEscrow.Milestone[] memory milestones = _createSampleMilestones();
        vm.prank(client);
        uint256 escrowId =
            escrow.createEscrowWithMilestones{value: 4.5 ether}(freelancer, arbitrator, address(0), milestones);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);

        vm.prank(client);
        escrow.releaseMilestone(escrowId, 1);

        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 2);
        vm.prank(client);
        escrow.releaseMilestone(escrowId, 2);

        IEscrow.Milestone memory m0 = escrow.getMilestone(escrowId, 0);
        assertTrue(m0.completed);
        assertFalse(m0.paid);

        IEscrow.Milestone memory m1 = escrow.getMilestone(escrowId, 1);
        assertFalse(m1.completed);
        assertTrue(m1.paid);

        IEscrow.Milestone memory m2 = escrow.getMilestone(escrowId, 2);
        assertTrue(m2.completed);
        assertTrue(m2.paid);

        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(data.releasedAmount, 3.5 ether);
    }
}
