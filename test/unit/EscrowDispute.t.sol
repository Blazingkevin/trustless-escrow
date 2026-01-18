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

contract EscrowDisputesTest is Test {
    Escrow public escrow;
    MockToken public token;
    
    address public owner = address(this);
    address public client = address(0x1);
    address public freelancer = address(0x2);
    address public arbitrator = address(0x3);
    address public attacker = address(0x4);
    
    uint256 constant ESCROW_AMOUNT = 10_000 * 10**18;
    uint256 constant DEADLINE_OFFSET = 30 days;
    uint256 constant PLATFORM_FEE_BPS = 100;
    uint256 constant ARBITRATION_FEE_BPS = 200;
    
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
        uint256 platformFee = (_gross * PLATFORM_FEE_BPS) / 10000;
        return _gross - platformFee;
    }
    
    function _createEscrowWithArbitrator() internal returns (uint256) {
        vm.startPrank(client);
        token.approve(address(escrow), ESCROW_AMOUNT);
        
        uint256 deadline = block.timestamp + DEADLINE_OFFSET;
        uint256 escrowId = escrow.createEscrow(
            freelancer,
            arbitrator,
            address(token),
            ESCROW_AMOUNT,
            deadline
        );
        
        vm.stopPrank();
        return escrowId;
    }
    
    function _createEscrowWithoutArbitrator() internal returns (uint256) {
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
    
    function test_raiseDispute_ByClient_Success() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        string memory reason = "Work not delivered as specified";
        
        vm.expectEmit(true, true, false, true);
        emit DisputeRaised(escrowId, client, reason);
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, reason);
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Disputed));
        assertEq(data.disputeReason, reason);
        assertEq(data.disputeRaiser, client);
        assertEq(data.disputeRaisedAt, block.timestamp);
    }
    
    event DisputeRaised(uint256 indexed escrowId, address indexed raiser, string reason);
    event DisputeResolved(uint256 indexed escrowId, address indexed winner, uint256 amount);
    
    function test_raiseDispute_ByFreelancer_Success() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        string memory reason = "Client not responding to deliverables";
        
        vm.expectEmit(true, true, false, true);
        emit DisputeRaised(escrowId, freelancer, reason);
        
        vm.prank(freelancer);
        escrow.raiseDispute(escrowId, reason);
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Disputed));
        assertEq(data.disputeRaiser, freelancer);
    }
    
    function test_raiseDispute_WithoutArbitrator_Reverts() public {
        uint256 escrowId = _createEscrowWithoutArbitrator();
        
        vm.expectRevert(IEscrow.CannotDisputeWithoutArbitrator.selector);
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Some reason");
    }
    
    function test_raiseDispute_ByAttacker_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.OnlyPartiesCanRaiseDispute.selector,
                attacker
            )
        );
        vm.prank(attacker);
        escrow.raiseDispute(escrowId, "Malicious dispute");
    }
    
    function test_raiseDispute_EmptyReason_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.expectRevert(IEscrow.EmptyDisputeReason.selector);
        vm.prank(client);
        escrow.raiseDispute(escrowId, "");
    }
    
    function test_raiseDispute_AlreadyDisputed_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "First reason");
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InvalidState.selector,
                IEscrow.EscrowState.Disputed,
                IEscrow.EscrowState.Funded
            )
        );
        vm.prank(freelancer);
        escrow.raiseDispute(escrowId, "Second reason");
    }
    
    function test_raiseDispute_AfterResolved_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
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
        escrow.raiseDispute(escrowId, "Late dispute");
    }
    
    function test_raiseDispute_BlocksMilestoneRelease() public {
        vm.startPrank(client);
        token.approve(address(escrow), ESCROW_AMOUNT);
        
        IEscrow.Milestone[] memory milestones = new IEscrow.Milestone[](2);
        milestones[0] = IEscrow.Milestone({
            description: "Milestone 1",
            amount: ESCROW_AMOUNT / 2,
            deadline: block.timestamp + 15 days,
            completed: false,
            paid: false
        });
        milestones[1] = IEscrow.Milestone({
            description: "Milestone 2",
            amount: ESCROW_AMOUNT / 2,
            deadline: block.timestamp + 30 days,
            completed: false,
            paid: false
        });
        
        uint256 escrowId = escrow.createEscrowWithMilestones(
            freelancer,
            arbitrator,
            address(token),
            milestones
        );
        vm.stopPrank();
        
        vm.prank(freelancer);
        escrow.completeMilestone(escrowId, 0);
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Quality issues");
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InvalidState.selector,
                IEscrow.EscrowState.Disputed,
                IEscrow.EscrowState.Funded
            )
        );
        vm.prank(client);
        escrow.releaseMilestone(escrowId, 0);
    }
    
    function test_resolveDispute_FullAmountToFreelancer_Success() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Work incomplete");
        
        uint256 netInEscrow = _netAmount(ESCROW_AMOUNT);
        uint256 remainingFunds = netInEscrow;
        uint256 arbitrationFee = (remainingFunds * ARBITRATION_FEE_BPS) / 10000;
        uint256 availableAfterFee = remainingFunds - arbitrationFee;
        
        uint256 freelancerBalBefore = token.balanceOf(freelancer);
        uint256 arbitratorBalBefore = token.balanceOf(arbitrator);
        uint256 clientBalBefore = token.balanceOf(client);
        
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            availableAfterFee,
            "Work was delivered as specified. Client's objections are subjective."
        );
        
        assertEq(
            token.balanceOf(freelancer),
            freelancerBalBefore + availableAfterFee,
            "Freelancer should receive full amount minus fees"
        );
        assertEq(
            token.balanceOf(arbitrator),
            arbitratorBalBefore + arbitrationFee,
            "Arbitrator should receive 2% fee of net escrow"
        );
        assertEq(
            token.balanceOf(client),
            clientBalBefore,
            "Client should receive nothing"
        );
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Resolved));
    }
    
    function test_resolveDispute_FullAmountToClient_Success() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Work is completely wrong");
        
        uint256 netInEscrow = _netAmount(ESCROW_AMOUNT);
        uint256 remainingFunds = netInEscrow;
        uint256 arbitrationFee = (remainingFunds * ARBITRATION_FEE_BPS) / 10000;
        uint256 availableAfterFee = remainingFunds - arbitrationFee;
        
        uint256 clientBalBefore = token.balanceOf(client);
        uint256 arbitratorBalBefore = token.balanceOf(arbitrator);
        uint256 freelancerBalBefore = token.balanceOf(freelancer);
        
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            client,
            availableAfterFee,
            "Work does not match specifications. Full refund warranted."
        );
        
        assertEq(
            token.balanceOf(client),
            clientBalBefore + availableAfterFee,
            "Client should be refunded full amount minus fees"
        );
        assertEq(
            token.balanceOf(arbitrator),
            arbitratorBalBefore + arbitrationFee,
            "Arbitrator should get 2% of net escrow"
        );
        assertEq(
            token.balanceOf(freelancer),
            freelancerBalBefore,
            "Freelancer should receive nothing"
        );
    }
    
    function test_resolveDispute_PartialAmount_Success() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(freelancer);
        escrow.raiseDispute(escrowId, "Client not responding");
        
        uint256 netInEscrow = _netAmount(ESCROW_AMOUNT);
        uint256 remainingFunds = netInEscrow;
        uint256 arbitrationFee = (remainingFunds * ARBITRATION_FEE_BPS) / 10000;
        uint256 availableAfterFee = remainingFunds - arbitrationFee;
        
        uint256 freelancerAmount = (availableAfterFee * 60) / 100;
        uint256 clientAmount = availableAfterFee - freelancerAmount;
        
        uint256 freelancerBalBefore = token.balanceOf(freelancer);
        uint256 clientBalBefore = token.balanceOf(client);
        uint256 arbitratorBalBefore = token.balanceOf(arbitrator);
        
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            freelancerAmount,
            "Work is 60% complete. Fair split: 60% to freelancer, 40% refund to client."
        );
        
        assertEq(
            token.balanceOf(freelancer),
            freelancerBalBefore + freelancerAmount,
            "Freelancer should get 60%"
        );
        assertEq(
            token.balanceOf(client),
            clientBalBefore + clientAmount,
            "Client should get 40% refund"
        );
        assertEq(
            token.balanceOf(arbitrator),
            arbitratorBalBefore + arbitrationFee,
            "Arbitrator should get 2% fee of net escrow"
        );
        
        assertEq(
            freelancerAmount + clientAmount + arbitrationFee,
            netInEscrow,
            "All funds should be distributed"
        );
    }
    
    function test_resolveDispute_OnlyArbitrator_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Dispute");
        
        uint256 amount = ESCROW_AMOUNT / 2;
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.NotAuthorized.selector,
                client,
                arbitrator
            )
        );
        vm.prank(client);
        escrow.resolveDispute(escrowId, freelancer, amount, "Client favors freelancer");
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.NotAuthorized.selector,
                freelancer,
                arbitrator
            )
        );
        vm.prank(freelancer);
        escrow.resolveDispute(escrowId, freelancer, amount, "Freelancer favors themselves");
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.NotAuthorized.selector,
                attacker,
                arbitrator
            )
        );
        vm.prank(attacker);
        escrow.resolveDispute(escrowId, attacker, amount, "Attacker steals");
    }
    
    function test_resolveDispute_NoActiveDispute_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.expectRevert(IEscrow.NoActiveDispute.selector);
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            ESCROW_AMOUNT,
            "Trying to resolve without dispute"
        );
    }
    
    function test_resolveDispute_ExcessiveAmount_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Dispute");
        
        uint256 netInEscrow = _netAmount(ESCROW_AMOUNT);
        uint256 remainingFunds = netInEscrow;
        uint256 arbitrationFee = (remainingFunds * ARBITRATION_FEE_BPS) / 10000;
        uint256 availableAfterFee = remainingFunds - arbitrationFee;
        uint256 excessiveAmount = availableAfterFee + 1;
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InsufficientFundsForResolution.selector,
                excessiveAmount,
                availableAfterFee
            )
        );
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            excessiveAmount,
            "Trying to award too much"
        );
    }
    
    function test_resolveDispute_ZeroAmount_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Dispute");
        
        vm.expectRevert(IEscrow.ZeroResolutionAmount.selector);
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            0,
            "Winner gets nothing?"
        );
    }
    
    function test_resolveDispute_ArbitratorAsWinner_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Dispute");
        
        uint256 amount = ESCROW_AMOUNT / 2;
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.OnlyPartiesCanRaiseDispute.selector,
                arbitrator
            )
        );
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            arbitrator,
            amount,
            "I'm awarding funds to myself"
        );
    }
    
    function test_resolveDispute_EmptyReasoning_Reverts() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Dispute");
        
        vm.expectRevert(IEscrow.EmptyDisputeReason.selector);
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            ESCROW_AMOUNT / 2,
            ""
        );
    }
    
    function test_resolveDispute_EmitsEvent() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Dispute");
        
        uint256 amount = ESCROW_AMOUNT / 2;
        
        vm.expectEmit(true, true, false, true);
        emit DisputeResolved(escrowId, freelancer, amount);
        
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            amount,
            "50/50 split is fair"
        );
    }
    
    function test_disputeAfterPartialMilestoneRelease_Success() public {
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
            arbitrator,
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
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Milestone 3 not satisfactory");
        
        IEscrow.EscrowData memory escrowData = escrow.getEscrow(escrowId);
        uint256 actualRemainingFunds = escrowData.totalAmount - escrowData.releasedAmount;
        
        uint256 arbitrationFee = (actualRemainingFunds * ARBITRATION_FEE_BPS) / 10000;
        uint256 availableAfterFee = actualRemainingFunds - arbitrationFee;
        
        uint256 freelancerBalBefore = token.balanceOf(freelancer);
        uint256 clientBalBefore = token.balanceOf(client);
        
        uint256 freelancerAmount = (availableAfterFee * 70) / 100;
        
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            freelancerAmount,
            "Milestone 3 is 70% complete. Fair split."
        );
        
        uint256 totalDistributed = token.balanceOf(freelancer) - freelancerBalBefore
            + token.balanceOf(client) - clientBalBefore
            + arbitrationFee;
        
        assertEq(totalDistributed, actualRemainingFunds, "Should distribute only remaining funds");
    }
    
    function test_cannotRaiseDisputeAfterResolution() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "First dispute");
        
        uint256 amount = ESCROW_AMOUNT / 2;
        vm.prank(arbitrator);
        escrow.resolveDispute(escrowId, freelancer, amount, "Resolved");
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrow.InvalidState.selector,
                IEscrow.EscrowState.Resolved,
                IEscrow.EscrowState.Funded
            )
        );
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Second dispute");
    }
    
    function test_fullDisputeWorkflow_Success() public {
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(freelancer);
        escrow.raiseDispute(escrowId, "Client not responding to completion requests");
        
        IEscrow.EscrowData memory data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Disputed));
        
        uint256 netInEscrow = _netAmount(ESCROW_AMOUNT);
        uint256 remainingFunds = netInEscrow;
        uint256 arbitrationFee = (remainingFunds * ARBITRATION_FEE_BPS) / 10000;
        uint256 availableAfterFee = remainingFunds - arbitrationFee;
        uint256 freelancerAmount = (availableAfterFee * 90) / 100;
        
        uint256 freelancerBalBefore = token.balanceOf(freelancer);
        uint256 clientBalBefore = token.balanceOf(client);
        uint256 arbitratorBalBefore = token.balanceOf(arbitrator);
        
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            freelancerAmount,
            "Work completed as specified. Client non-responsive. 90% to freelancer, 10% to client for delayed feedback."
        );
        
        data = escrow.getEscrow(escrowId);
        assertEq(uint(data.state), uint(IEscrow.EscrowState.Resolved));
        
        assertEq(
            token.balanceOf(freelancer) - freelancerBalBefore,
            freelancerAmount,
            "Freelancer should get 90%"
        );
        assertEq(
            token.balanceOf(arbitrator) - arbitratorBalBefore,
            arbitrationFee,
            "Arbitrator should get 2%"
        );
        assertGt(
            token.balanceOf(client),
            clientBalBefore,
            "Client should get some refund"
        );
        
        uint256 totalDistributed = 
            (token.balanceOf(freelancer) - freelancerBalBefore) +
            (token.balanceOf(client) - clientBalBefore) +
            (token.balanceOf(arbitrator) - arbitratorBalBefore);
        
        assertEq(totalDistributed, netInEscrow, "All net escrow funds should be distributed");
    }
    
    function testFuzz_resolveDispute_MathAlwaysAddsUp(uint256 winnerPercentage) public {
        winnerPercentage = bound(winnerPercentage, 1, 100);
        
        uint256 escrowId = _createEscrowWithArbitrator();
        
        vm.prank(client);
        escrow.raiseDispute(escrowId, "Fuzz test dispute");
        
        uint256 netInEscrow = _netAmount(ESCROW_AMOUNT);
        uint256 arbitrationFee = (netInEscrow * ARBITRATION_FEE_BPS) / 10000;
        uint256 availableAfterFee = netInEscrow - arbitrationFee;
        uint256 winnerAmount = (availableAfterFee * winnerPercentage) / 100;
        
        uint256 freelancerBalBefore = token.balanceOf(freelancer);
        uint256 clientBalBefore = token.balanceOf(client);
        uint256 arbitratorBalBefore = token.balanceOf(arbitrator);
        
        vm.prank(arbitrator);
        escrow.resolveDispute(
            escrowId,
            freelancer,
            winnerAmount,
            "Fuzz test resolution"
        );
        
        uint256 totalDistributed = 
            (token.balanceOf(freelancer) - freelancerBalBefore) +
            (token.balanceOf(client) - clientBalBefore) +
            (token.balanceOf(arbitrator) - arbitratorBalBefore);
        
        assertEq(totalDistributed, netInEscrow, "Fuzz: All net escrow funds should always be distributed");
    }
}
