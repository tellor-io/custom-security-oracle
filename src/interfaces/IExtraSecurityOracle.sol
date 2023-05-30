// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IExtraSecurityOracle {
    function slashReporter(address _reporter, address _recipient) external returns (uint256 _slashAmount);
}