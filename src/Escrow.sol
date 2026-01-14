// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IEscrow.sol";

contract Escrow is IEscrow, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;
    
    uint256 _nextEscrowId;
    mapping(uint256 => EscrowData) private _escrows;

    uint256 public platformFeePercent = 100; // using basis point i.e 1%
    uint256 public constant MAX_PLATFORM_FEE = 1000; // 10% max
    mapping(address => uint256) public platformFees;

    //helpful modifiers
    modifier onlyClient(uint256 _escrowId) {
        if (msg.sender != _escrows[_escrowId].client) {
            revert NotAuthorized(msg.sender, _escrows[_escrowId].client);
        }
        _;
    }

    modifier onlyFreelancer(uint256 _escrowId) {
        if (msg.sender != _escrows[_escrowId].freelancer) {
            revert NotAuthorized(msg.sender, _escrows[_escrowId].freelancer);
        }
        _;
    }

    modifier onlyArbitrator(uint256 _escrowId) {
        if (!_escrows[_escrowId].hasArbitrator) {
            revert NoArbitratorAssigned();
        }
        if (msg.sender != _escrows[_escrowId].arbitrator) {
            revert NotAuthorized(msg.sender, _escrows[_escrowId].arbitrator);
        }
        _;
    }

    modifier inState(uint256 _escrowId, EscrowState _requiredState) {
        EscrowState currentState = _escrows[_escrowId].state;
        if (currentState != _requiredState) {
            revert InvalidState(currentState, _requiredState);
        }
        _;
    }

    modifier escrowExists(uint256 _escrowId) {
        if (_escrowId >= _nextEscrowId) {
            revert InvalidAmount();
        }
        _;
    }

    constructor(address _owner) Ownable(_owner) {
        _nextEscrowId = 0;
    }

    function createEscrow(address _freelancer, address _arbitrator, address _token, uint256 _amount, uint256 _deadline)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 escrowId)
    {
        if (_freelancer == address(0)) revert ZeroAddress();
        if (_amount == 0) revert InvalidAmount();
        if (_deadline <= block.timestamp) {
            revert DeadlinePassed(_deadline, block.timestamp);
        }

        escrowId = _nextEscrowId++;

        if (_token == address(0)) {
            if (msg.value != _amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert InvalidAmount();
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }

        uint256 fee = (_amount * platformFeePercent) / 10000;
        uint256 netAmount = _amount - fee;
        platformFees[_token] += fee;

        EscrowData storage escrow = _escrows[escrowId];
        escrow.client = msg.sender;
        escrow.freelancer = _freelancer;
        escrow.arbitrator = _arbitrator;
        escrow.token = _token;
        escrow.totalAmount = netAmount;
        escrow.releasedAmount = 0;
        escrow.deadline = _deadline;
        escrow.state = EscrowState.Funded;
        escrow.hasArbitrator = _arbitrator != address(0);

        emit EscrowCreated(escrowId, msg.sender, _freelancer, netAmount, _token);
        emit FundsDeposited(escrowId, netAmount);

        return escrowId;
    }

    function refundToClient(uint256 _escrowId)
        external
        whenNotPaused
        nonReentrant
        escrowExists(_escrowId)
        inState(_escrowId, EscrowState.Funded)
    {
        EscrowData storage escrow = _escrows[_escrowId];

        bool isFreelancer = msg.sender == escrow.freelancer;
        bool isClient = msg.sender == escrow.client;
        bool deadlinePassed = block.timestamp > escrow.deadline;

        // Freelancer can always refund, client only after deadline
        if (!isFreelancer && !(isClient && deadlinePassed)) {
            if (!isClient && !isFreelancer) {
                revert NotAuthorized(msg.sender, escrow.client);
            } else {
                revert DeadlineNotPassed(escrow.deadline, block.timestamp);
            }
        }

        uint256 amountToRefund = escrow.totalAmount - escrow.releasedAmount;
        if (amountToRefund == 0) revert InvalidAmount();

        escrow.releasedAmount = escrow.totalAmount;
        escrow.state = EscrowState.Refunded;

        _transfer(escrow.token, escrow.client, amountToRefund);

        emit FundsRefunded(_escrowId, amountToRefund, escrow.client);
    }

    function releaseToFreelancer(uint256 _escrowId)
        external
        whenNotPaused
        nonReentrant
        escrowExists(_escrowId)
        onlyClient(_escrowId)
        inState(_escrowId, EscrowState.Funded)
    {
        EscrowData storage escrow = _escrows[_escrowId];

        uint256 amountToRelease = escrow.totalAmount - escrow.releasedAmount;

        if (amountToRelease == 0) revert InvalidAmount();

        escrow.releasedAmount = escrow.totalAmount;
        escrow.state = EscrowState.Resolved;

        _transfer(escrow.token, escrow.freelancer, amountToRelease);

        emit FundsReleased(_escrowId, amountToRelease, escrow.freelancer);
    }

    function resolveDispute(uint256 _escrowId, address _winner, uint256 _amount, string calldata _reasoning) external {
        // I will implement later when I think through it properly
        revert("Not implemented yet");
    }

    function getEscrow(uint256 _escrowId) external view escrowExists(_escrowId) returns (EscrowData memory) {
        return _escrows[_escrowId];
    }

    function _transfer(address _token, address _to, uint256 _amount) internal {
        if (_token == address(0)) {
            (bool success,) = _to.call{value: _amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }
}
