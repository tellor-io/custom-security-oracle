// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITellorGovernance {
    enum VoteResult {
        FAILED,
        PASSED,
        INVALID
    } // status of a potential vote
    
    function beginDispute(bytes32 _queryId, uint256 _timestamp) external;
    function getVoteInfo() external view returns (bytes32, uint256[17] memory, bool, VoteResult, address);
}