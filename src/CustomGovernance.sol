// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./interfaces/IRibeye.sol";
import "./interfaces/ITellorGovernance.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ITellorOracle.sol";


contract CustomGovernance {
    IRibeye public oracle;
    IERC20 public token; // token used for dispute fees, same as reporter staking token
    ITellorGovernance public tellorGovernance;
    ITellorOracle public tellorOracle;

    mapping(bytes32 => Dispute) private disputeInfo; // mapping of unique identifier to the details of the dispute

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
        bytes32 _hash,
        bytes32 _queryId,
        uint256 _timestamp,
        address _reporter
    );
    event VoteExecuted(bytes32 _hash, ITellorGovernance.VoteResult _result);


    constructor(
        address _oracle,
        address _tellorGovernance
    ) {
        oracle = IRibeye(_oracle);
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

        // Save dispute info
        Dispute storage _thisDispute = disputeInfo[_hash];
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
        if (tellorGovernance.getVoteRounds(_hash).length == 0) {
            tellorGovernance.beginDispute(_queryId, _timestamp);
        }

        _thisDispute.slashedAmount = _slashedAmount;
        _thisDispute.fee = _disputeFee;

        emit NewDispute(
            _hash,
            _queryId,
            _timestamp,
            _thisDispute.disputedReporter
        );
    }

    function executeVote(bytes32 _queryId, uint256 _timestamp) public {
        bytes32 _hash = keccak256(abi.encodePacked(_queryId, _timestamp));
        uint256 _disputeIdLastRound = tellorGovernance.getVoteRounds(_hash)[tellorGovernance.getVoteRounds(_hash).length - 1];
        (,,bool _executed, ITellorGovernance.VoteResult _result,) = tellorGovernance.getVoteInfo(_disputeIdLastRound);
        require(_executed, "Vote not executed");

        Dispute storage _thisDispute = disputeInfo[_hash];
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
        emit VoteExecuted(_hash, _result);
    }

    /**
     * @dev Get the latest dispute fee
     */
    function getDisputeFee() public view returns (uint256) {
        return (oracle.getStakeAmount() / 10);
    }
}