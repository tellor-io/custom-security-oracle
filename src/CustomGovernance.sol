// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./interfaces/IExtraSecurityOracle.sol";
import "./interfaces/ITellorGovernance.sol";


contract CustomGovernance {
    IExtraSecurityOracle public extraSecurityOracle;
    ITellorGovernance public tellorGovernance;


    constructor(
        address _extraSecurityOracle,
        address _tellorGovernance
    ) {
        extraSecurityOracle = IExtraSecurityOracle(_extraSecurityOracle);
        tellorGovernance = ITellorGovernance(_tellorGovernance);
    }

    function beginDispute(bytes32 _queryId, uint256 _timestamp) public {
        // todo: ensure can't begin dispute if already in dispute ? if vote round > 1 ?
        // todo: collect dispute fee from msg.sender
        extraSecurityOracle.slashReporter(address(0), address(0)); // todo: replace with proper reporter and recipient addresses
        tellorGovernance.beginDispute(_queryId, _timestamp);
    }

    function executeVote() public {
        (,,bool _executed, ITellorGovernance.VoteResult _result,) = tellorGovernance.getVoteInfo();
        require(_executed, "Vote not executed");
        // todo: give tokens to proper parties
    }
}