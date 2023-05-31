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
        bytes value; // disputed value
        address initiator; // address which initiated dispute
        address disputedReporter; // reporter who submitted the disputed value
        uint256 slashedAmount; // amount of tokens slashed from reporter
        uint256 fee; // fee paid to initiate dispute
    }

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
        // Ensure value actually exists
        require(
            tellorOracle.getBlockNumberByTimestamp(_queryId, _timestamp) != 0,
            "no value exists at given timestamp"
        );
        // todo: generate dispute ID
        // get vote info from governance contract
        // ensure can't begin dispute if already in dispute
        // todo: collect dispute fee from msg.sender
        oracle.slashReporter(address(0), address(0)); // todo: replace with proper reporter and recipient addresses
        tellorGovernance.beginDispute(_queryId, _timestamp);
    }

    function executeVote(uint256 _disputeId) public {
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
            // If vote is in dispute and fails, iterate through each vote round and transfer the dispute fee to disputed reporter
            token.transfer(_thisDispute.disputedReporter, _thisDispute.fee + _thisDispute.slashedAmount);
        }
        emit VoteExecuted(_disputeId, _result);
    }
}