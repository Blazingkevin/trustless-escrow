pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/Escrow.sol";
import "../../src/interfaces/IEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract EscrowTimeLockTest is Test {
    Escrow public escrow;
    MockToken public token;
    
    address public owner = address(this);
    address public client = address(0x1);
    address public freelancer = address(0x2);
    address public arbitrator = address(0x3);
    address public attacker = address(0x4);
    
    uint256 constant ESCROW_AMOUNT = 10_000 * 10**18;
    uint256 constant DEADLINE_OFFSET = 30 days;
    uint256 constant GRACE_PERIOD = 7 days;
    
    event FundsReleased(uint256 indexed escrowId, uint256 amount, address freelancer);
    event DeadlineExtended(uint256 indexed escrowId, uint256 newDeadline);
    
    function setUp() public {
        escrow = new Escrow(owner);
        token = new MockToken();
        
        token.mint(client, ESCROW_AMOUNT * 10);
        
        vm.label(client, "Client");
        vm.label(freelancer, "Freelancer");
        vm.label(arbitrator, "Arbitrator");
        vm.label(attacker, "Attacker");
    }
    
    function _netAmount(uint256 _gross) internal pure returns (uint256) {
        uint256 platformFee = (_gross * 100) / 10000;
        return _gross - platformFee;
    }
    
    function _createEscrow() internal returns (uint256) {
        vm.startPrank(client);
        token.approve(address(escrow), ESCROW_AMOUNT);
        
        uint256 deadline = block.timestamp + DEADLINE_OFFSET;
        uint256 escrowId = escrow.createEscrow(
            freelancer,
            address(0),
            address(token),
            ESCROW_AMOUNT,
            deadline
        );
        
        vm.stopPrank();
        return escrowId;
    }
    
    function test_claimAfterDeadline_BeforeDeadline_Reverts() public {
        uint256 escrowId = _createEscrow();
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.GracePeriodNotEnded.selector,
                block.timestamp + DEADLINE_OFFSET + GRACE_PERIOD,
                block.timestamp
            )
        );
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
    }
    
    function test_claimAfterDeadline_DuringGracePeriod_Reverts() public {
        uint256 escrowId = _createEscrow();
        
        uint256 deadline = block.timestamp + DEADLINE_OFFSET;
        vm.warp(deadline + 1 days);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.GracePeriodNotEnded.selector,
                deadline + GRACE_PERIOD,
                deadline + 1 days
            )
        );
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
    }
    
    function test_claimAfterDeadline_AfterGracePeriod_Success() public {
        uint256 escrowId = _createEscrow();
        
        uint256 deadline = block.timestamp + DEADLINE_OFFSET;
        vm.warp(deadline + GRACE_PERIOD + 1);
        
        uint256 freelancerBalBefore = token.balanceOf(freelancer);
        uint256 expectedAmount = _netAmount(ESCROW_AMOUNT);
        
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
        
        assertEq(
            token.balanceOf(freelancer),
            freelancerBalBefore + expectedAmount,
            "Freelancer should receive all funds"
        );
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Resolved));
        assertEq(data.releasedAmount, data.totalAmount, "All funds should be released");
    }
    
    function test_claimAfterDeadline_OnlyFreelancer_Reverts() public {
        uint256 escrowId = _createEscrow();
        
        vm.warp(block.timestamp + DEADLINE_OFFSET + GRACE_PERIOD + 1);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.NotAuthorized.selector,
                client,
                freelancer
            )
        );
        vm.prank(client);
        escrow.claimAfterDeadline(escrowId);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.NotAuthorized.selector,
                attacker,
                freelancer
            )
        );
        vm.prank(attacker);
        escrow.claimAfterDeadline(escrowId);
    }
    
    function test_claimAfterDeadline_AlreadyResolved_Reverts() public {
        uint256 escrowId = _createEscrow();
        
        // Client releases funds normally first
        vm.prank(client);
        escrow.releaseToFreelancer(escrowId);
        
        // Now try to claim after deadline (should fail - already resolved)
        vm.warp(block.timestamp + DEADLINE_OFFSET + GRACE_PERIOD + 1);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InvalidState.selector,
                IEscrow.EscrowState.Resolved,
                IEscrow.EscrowState.Funded
            )
        );
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
    }
    
    function test_claimAfterDeadline_EmitsEvent() public {
        uint256 escrowId = _createEscrow();
        
        vm.warp(block.timestamp + DEADLINE_OFFSET + GRACE_PERIOD + 1);
        
        uint256 expectedAmount = _netAmount(ESCROW_AMOUNT);
        
        vm.expectEmit(true, true, false, true);
        emit FundsReleased(escrowId, expectedAmount, freelancer);
        
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
    }
    
    function test_claimAfterDeadline_ExactlyAtGraceEnd_Success() public {
        uint256 escrowId = _createEscrow();
        
        uint256 deadline = block.timestamp + DEADLINE_OFFSET;
        vm.warp(deadline + GRACE_PERIOD + 1);
        
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Resolved));
    }
    
    function test_claimAfterDeadline_YearsLater_Success() public {
        uint256 escrowId = _createEscrow();
        
        vm.warp(block.timestamp + 365 days * 5);
        
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Resolved));
    }
    
    
    function test_extendDeadline_ByClient_Success() public {
        uint256 escrowId = _createEscrow();
        
        uint256 oldDeadline = block.timestamp + DEADLINE_OFFSET;
        uint256 newDeadline = oldDeadline + 15 days;
        
        vm.expectEmit(true, false, false, true);
        emit DeadlineExtended(escrowId, newDeadline);
        
        vm.prank(client);
        escrow.extendDeadline(escrowId, newDeadline);
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(data.deadline, newDeadline, "Deadline should be updated");
    }
    
    function test_extendDeadline_OnlyClient_Reverts() public {
        uint256 escrowId = _createEscrow();
        uint256 newDeadline = block.timestamp + DEADLINE_OFFSET + 15 days;
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.NotAuthorized.selector,
                freelancer,
                client
            )
        );
        vm.prank(freelancer);
        escrow.extendDeadline(escrowId, newDeadline);
    }
    
    function test_extendDeadline_ShorterDeadline_Reverts() public {
        uint256 escrowId = _createEscrow();
        uint256 oldDeadline = block.timestamp + DEADLINE_OFFSET;
        uint256 earlierDeadline = oldDeadline - 5 days;
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InvalidDeadlineExtension.selector,
                oldDeadline,
                earlierDeadline
            )
        );
        vm.prank(client);
        escrow.extendDeadline(escrowId, earlierDeadline);
    }
    
    function test_extendDeadline_ToPast_Reverts() public {
        uint256 escrowId = _createEscrow();
        
        vm.warp(block.timestamp + 50 days);
        
        uint256 pastDeadline = block.timestamp - 1 days;
        
        vm.expectRevert();
        vm.prank(client);
        escrow.extendDeadline(escrowId, pastDeadline);
    }
    
    function test_extendDeadline_MultipleTimes_Success() public {
        uint256 escrowId = _createEscrow();
        
        uint256 deadline1 = block.timestamp + DEADLINE_OFFSET;
        uint256 deadline2 = deadline1 + 10 days;
        uint256 deadline3 = deadline2 + 5 days;
        
        vm.prank(client);
        escrow.extendDeadline(escrowId, deadline2);
        
        vm.prank(client);
        escrow.extendDeadline(escrowId, deadline3);
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(data.deadline, deadline3, "Should have latest deadline");
    }
    
    function test_extendDeadline_ResetsGracePeriod_Success() public {
        uint256 escrowId = _createEscrow();
        
        uint256 oldDeadline = block.timestamp + DEADLINE_OFFSET;
        uint256 newDeadline = oldDeadline + 20 days;
        
        vm.prank(client);
        escrow.extendDeadline(escrowId, newDeadline);
        
        vm.warp(oldDeadline + GRACE_PERIOD + 1);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.GracePeriodNotEnded.selector,
                newDeadline + GRACE_PERIOD,
                oldDeadline + GRACE_PERIOD + 1
            )
        );
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
        
        vm.warp(newDeadline + GRACE_PERIOD + 1);
        
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Resolved));
    }
    
    function test_claimAfterDeadline_WithMilestones_Success() public {
        // Create escrow with milestones
        vm.startPrank(client);
        token.approve(address(escrow), ESCROW_AMOUNT);
        
        uint256 netInEscrow = _netAmount(ESCROW_AMOUNT);
        uint256 milestoneAmount = netInEscrow / 3;
        
        IEscrow.Milestone[] memory milestones = new IEscrow.Milestone[](3);
        for (uint i = 0; i < 3; i++) {
            milestones[i] = IEscrow.Milestone({
                description: string(abi.encodePacked("Milestone ", vm.toString(i + 1))),
                amount: milestoneAmount,
                deadline: block.timestamp + (15 days * (i + 1)),
                completed: false,
                paid: false
            });
        }
        
        uint256 escrowId = escrow.createEscrowWithMilestones(
            freelancer,
            address(0), // No arbitrator
            address(token),
            milestones
        );
        vm.stopPrank();
        
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
        
        uint256 finalDeadline = block.timestamp + (15 days * 3);
        vm.warp(finalDeadline + GRACE_PERIOD + 1);
        
        uint256 freelancerBalBefore = token.balanceOf(freelancer);
        
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
        
        uint256 received = token.balanceOf(freelancer) - freelancerBalBefore;
        assertGt(received, 0, "Should receive remaining funds");
    }
    
    function test_extendDeadline_AfterResolved_Reverts() public {
        uint256 escrowId = _createEscrow();
        
        vm.prank(client);
        escrow.releaseToFreelancer(escrowId);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InvalidState.selector,
                IEscrow.EscrowState.Resolved,
                IEscrow.EscrowState.Funded
            )
        );
        vm.prank(client);
        escrow.extendDeadline(escrowId, block.timestamp + 100 days);
    }
    
    function test_fullTimeLockWorkflow_Success() public {
        // 1. Create escrow
        uint256 escrowId = _createEscrow();
        uint256 originalDeadline = block.timestamp + DEADLINE_OFFSET;
        
        uint256 extendedDeadline = originalDeadline + 15 days;
        vm.prank(client);
        escrow.extendDeadline(escrowId, extendedDeadline);
        
        vm.warp(extendedDeadline + GRACE_PERIOD + 1);
        
        uint256 freelancerBalBefore = token.balanceOf(freelancer);
        
        vm.prank(freelancer);
        escrow.claimAfterDeadline(escrowId);
        
        assertEq(
            token.balanceOf(freelancer),
            freelancerBalBefore + _netAmount(ESCROW_AMOUNT),
            "Freelancer should receive all funds"
        );
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Resolved));
        assertEq(data.deadline, extendedDeadline, "Should have extended deadline");
    }
}

