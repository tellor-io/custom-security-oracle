// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;


contract CustomGovernance {
    address public extraSecurityOracle;
    address public tellorGovernance;

    constructor(
        address _extraSecurityOracle,
        address _tellorGovernance
    ) {
        extraSecurityOracle = _extraSecurityOracle;
        tellorGovernance = _tellorGovernance;
    }

    function beginDispute() public {
        // lock tokens in extra security oracle (call extraSecurityOracle.slashReporter())
        // call tellorGovernance.beginDispute()
    }

    function executeVote() public {
        // get vote result from tellorGovernance
        // give tokens to winning party
    }
}