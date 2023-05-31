// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITellorOracle {
    function getBlockNumberByTimestamp(bytes32 _queryId, uint256 _timestamp) external view returns (uint256);
    function getReporterByTimestamp(bytes32 _queryId, uint256 _timestamp) external view returns (address);
}