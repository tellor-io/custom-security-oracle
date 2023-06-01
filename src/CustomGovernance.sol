// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./interfaces/IExtraSecurityOracle.sol";
import "./interfaces/ITellorGovernance.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ITellorOracle.sol";


contract CustomGovernance {
    IExtraSecurityOracle public oracle;
    IERC20 public token; // token used for dispute fees, same as reporter staking token
    ITellorGovernance public tellorGovernance;
    ITellorOracle public tellorOracle;

    mapping(uint256 => Dispute) private disputeInfo; // mapping of dispute IDs to the details of the dispute

    // Structs
    struct Dispute {
        bytes32 queryId; // query ID of disputed value
        uint256 timestamp; // timestamp of disputed value
        address initiator; // address which initiated dispute
        address disputedReporter; // reporter who submitted the disputed value
        uint256 slashedAmount; // amount of tokens slashed from reporter
        uint256 fee; // fee paid to initiate dispute
    }

    // Events
    event NewDispute(
        uint256 _disputeId,
        bytes32 _queryId,
        uint256 _timestamp,
        address _reporter
    );
    event VoteExecuted(uint256 _disputeId, ITellorGovernance.VoteResult _result);


    constructor(
        address _oracle,
        address _tellorGovernance
    ) {
        oracle = IExtraSecurityOracle(_oracle);
        token = IERC20(oracle.getTokenAddress());
        tellorGovernance = ITellorGovernance(_tellorGovernance);
        tellorOracle = ITellorOracle(oracle.getTellorAddress());
    }

    function beginDispute(bytes32 _queryId, uint256 _timestamp) public {
        require(
            tellorOracle.getBlockNumberByTimestamp(_queryId, _timestamp) != 0,
            "no value exists at given timestamp"
        );
        bytes32 _hash = keccak256(abi.encodePacked(_queryId, _timestamp));
        require(
            tellorGovernance.getVoteRounds(_hash).length == 0,
            "vote already in progress"
        ); // Should revert if there's already a voting round open for the disputed value

        // Save dispute info
        uint256 _disputeId = tellorGovernance.getVoteCount() + 1;
        Dispute storage _thisDispute = disputeInfo[_disputeId];
        _thisDispute.queryId = _queryId;
        _thisDispute.timestamp = _timestamp;
        _thisDispute.initiator = msg.sender;
        _thisDispute.disputedReporter = tellorOracle.getReporterByTimestamp(
            _queryId,
            _timestamp
        );

        uint256 _disputeFee = getDisputeFee();
        require(
            token.transferFrom(msg.sender, address(this), _disputeFee),
            "Fee must be paid"
        );
        uint256 _slashedAmount = oracle.slashReporter(
            _thisDispute.disputedReporter,
            address(this)
        );
        tellorGovernance.beginDispute(_queryId, _timestamp); // todo: don't call this if already dispute open on tellor side

        _thisDispute.slashedAmount = _slashedAmount;
        _thisDispute.fee = _disputeFee;

        emit NewDispute(
            _disputeId,
            _queryId,
            _timestamp,
            _thisDispute.disputedReporter
        );
    }

    function executeVote(uint256 _disputeId) public { // tddo: make sure this is getting the final dispute id of the last voting round, and that can fetch the original slash/fee 
        (,,bool _executed, ITellorGovernance.VoteResult _result,) = tellorGovernance.getVoteInfo(_disputeId);
        require(_executed, "Vote not executed");

        Dispute storage _thisDispute = disputeInfo[_disputeId];
        if (_result == ITellorGovernance.VoteResult.PASSED) {
            // Return fee to dispute initiator
            token.transfer(_thisDispute.initiator, _thisDispute.fee);
            // Give reporter's slashed stake to dispute initiator
            token.transfer(
                _thisDispute.initiator,
                _thisDispute.slashedAmount
            );
        } else if (_result == ITellorGovernance.VoteResult.INVALID) {
            // Return fee to initiator
            token.transfer(_thisDispute.initiator, _thisDispute.fee);
            // Return slashed tokens to disputed reporter
            token.transfer(
                _thisDispute.disputedReporter,
                _thisDispute.slashedAmount
            );
        } else if (_result == ITellorGovernance.VoteResult.FAILED) {
            // If vote is in dispute and fails, return slashed tokens to reporter and give dispute fee to reporter
            token.transfer(_thisDispute.disputedReporter, _thisDispute.fee + _thisDispute.slashedAmount);
        }
        emit VoteExecuted(_disputeId, _result);
    }

    /**
     * @dev Get the latest dispute fee
     */
    function getDisputeFee() public view returns (uint256) {
        return (oracle.getStakeAmount() / 10);
    }
}