// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEscrow {
    enum EscrowState {
        Created,
        Funded,
        InProgress,
        Disputed,
        Resolved,
        Refunded
    }

    /**
     * @param description what work must be completed
     * @param amount amount that will be paid when work is done (in wei)
     * @param deadline the deadline of the task
     * @param completed whether the work has been completed and freelancer has asked for fund release
     * @param paid whether fund has been released by the client
     */
    struct Milestone {
        string description;
        uint256 amount;
        uint256 deadline;
        bool completed;
        bool paid;
    }

    /**
     * @param client Address that created escrow and deposited funds
     * @param freelancer Address that will receive payment
     * @param arbitrator Address that can resolve dispute (optional, only necessary when there is dispute)
     * @param token Token address
     * @param totalAmount Total escrow amount
     * @param releasedAmount How much has been paid out
     * @param deadline Final deadline for all work
     * @param state Current escrow state
     * @param milestones Array of payment milestones
     * @param hasArbitrator whether an arbitrator was designated
     */
    struct EscrowData {
        address client;
        address freelancer;
        address arbitrator;
        address token;
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 deadline;
        EscrowState state;
        Milestone[] milestones;
        bool hasArbitrator;
        string disputeReason;
        address disputeRaiser;
        uint256 disputeRaisedAt;
    }

    // emitted when escrow is created
    event EscrowCreated(
        uint256 indexed escrowId, address indexed client, address indexed freelancer, uint256 amount, address token
    );

    // emitted when funds are deposited into escrow
    event FundDeposited(uint256 indexed escrowId, uint256 amount);

    // emitted when milestone is completed and released
    event MilestoneReleased(uint256 indexed escrowId, uint256 milestoneIndex, uint256 amount, address freelancer);

    // Emitted when freelancer completes a milestone
    event MilestoneCompleted(uint256 indexed escrowId, uint256 milestoneIndex);

    // Emitted when funds are released to freelancer
    event FundsReleased(uint256 indexed escrowId, uint256 amount, address freelancer);

    // emitted when dispute is raised
    event DisputeRaised(uint256 indexed escrowId, address indexed raiser, string reason);

    // emitted when dispute is resolved
    event DisputeResolved(uint256 indexed escrowId, address indexed winner, uint256 amount);

    // emitted when funds is refunded
    event FundsRefunded(uint256 indexed escrowId, uint256 amount, address client);

    // emitted when deadline is extended
    event DeadlineExtended(uint256 indexed escrowId, uint256 newDeadline);

    // emitted when funds are deposited into escrow
    event FundsDeposited(uint256 indexed escrowId, uint256 amount);

    // thrown when caller is not authorized for operation
    error NotAuthorized(address caller, address required);

    // thrown when escrow is in invalid state to perform the operation
    error InvalidState(EscrowState currentState, EscrowState requiredState);

    // Thrown when deadline has passed
    error DeadlinePassed(uint256 deadline, uint256 currentTime);

    // thrown when deadline hasn't passed
    error DeadlineNotPassed(uint256 deadline, uint256 currentTime);

    // thrown when amount is inavlid
    error InvalidAmount();

    // thrown when milestone index is out of bound
    error InvalidMilestoneIndex(uint256 index, uint256 maxIndex);

    // thwrown when milestone has already been paid
    error MilestoneAlreadyPaid(uint256 milestoneIndex);

    // thrown when transfer failed
    error TransferFailed();

    // thrown when action is attempted by an arbitrator that is not assigned
    error NoArbitratorAssigned();

    // when attempting to use zero address
    error ZeroAddress();

    // Thrown when a dispute has already been raised
    error DisputeAlreadyActive();

    // thrown when trying to raise dispute without an arbitrator
    error CannotDisputeWithoutArbitrator();

    // Thrown when non-party tries to raise dispute
    error OnlyPartiesCanRaiseDispute(address caller);

    // Thrown when trying to perform action on non-disputed escrow
    error NoActiveDispute();

    // Thrown when dispute reason is empty
    error EmptyDisputeReason();

    // Thrown when resolution amount exceeds available funds
    error InsufficientFundsForResolution(uint256 requested, uint256 available);

    // Thrown when resolution amount is zero
    error ZeroResolutionAmount();

    // create a simple escrow without milestone (I will improve on this)
    function createEscrow(address _freelancer, address _arbitrator, address _token, uint256 _amount, uint256 _deadline)
        external
        payable
        returns (uint256 escrowId);

    // release funds from escrow to freelancer
    function releaseToFreelancer(uint256 _escrowId) external;

    // refund to client
    function refundToClient(uint256 _escrowId) external;

    // resolve dispute(for arbitrators only)
    function resolveDispute(uint256 escrowId, address winner, uint256 amount, string calldata _reasoning) external;

    // get escrow data
    function getEscrow(uint256 _escrowId) external view returns (EscrowData memory data);

    // Create escrow with milestones
    function createEscrowWithMilestones(
        address _freelancer,
        address _arbitrator,
        address _token,
        Milestone[] calldata _milestones
    ) external payable returns (uint256 escrowId);

    // Freelancer marks milestone as completed
    function completeMilestone(uint256 _escrowId, uint256 _milestoneIndex) external;

    // Client releases payment for a completed milestone
    function releaseMilestone(uint256 _escrowId, uint256 _milestoneIndex) external;

    // Get details of a specific milestone
    function getMilestone(uint256 _escrowId, uint256 _milestoneIndex) external view returns (Milestone memory milestone);

    // Get total number of milestones for an escrow
    function getMilestoneCount(uint256 _escrowId) external view returns (uint256 count);

    // Raise a dispute
    function raiseDispute(uint256 _escrowId, string calldata _reason) external;
}
