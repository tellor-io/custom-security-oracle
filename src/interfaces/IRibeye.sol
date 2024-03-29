// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRibeye {
    function slashReporter(address _reporter, address _recipient) external returns (uint256 _slashAmount);
    function getTokenAddress() external view returns (address);
    function getTellorAddress() external view returns (address);
    function getStakeAmount() external view returns (uint256);
}