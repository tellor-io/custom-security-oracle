// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITellorOracle {
    function getBlockNumberByTimestamp(bytes32 _queryId, uint256 _timestamp) external view returns (uint256);
    function getReporterByTimestamp(bytes32 _queryId, uint256 _timestamp) external view returns (address);
    function getIndexForDataBefore(bytes32 _queryId, uint256 _timestamp) external view returns (bool, uint256);
    function getTimestampbyQueryIdandIndex(bytes32 _queryId, uint256 _index) external view returns (uint256);
    function retrieveData(bytes32 _queryId, uint256 _timestamp) external view returns (bytes memory);
}