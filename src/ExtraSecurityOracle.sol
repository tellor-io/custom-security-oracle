// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;


contract ExtraSecurityOracle {
    address public owner;
    address public tellor;
    address public governance;
    address public token;
    uint256 public minimumStakeAmount;
    uint256 public reportingLock;


    constructor(
        address _tellor,
        address _token,
        uint256 _minimumStakeAmount,
        uint256 _reportingLock
    ) {
        tellor = _tellor;
        token = _token;
        minimumStakeAmount = _minimumStakeAmount;
        reportingLock = _reportingLock;
        owner = msg.sender;
    }

    /**
     * @dev Allows the owner to initialize the governance address
     * @param _governanceAddress address of custom governance contract (CustomGovernance.sol)
     */
    function init(address _governanceAddress) external {
        require(msg.sender == owner, "only owner can set governance address");
        require(governance == address(0), "governance address already set");
        require(
            _governanceAddress != address(0),
            "governance address can't be zero address"
        );
        governance = _governanceAddress;
    }

    function getDataBefore() public {
        // get data from tellor reported by someone both staked on tellor oracle and staked on this contract
    }

    function slashReporter() public {
        // only called by custom governance contract
    }

    function depositStake() public {}

    function requestStakingWithdraw() public {}

    function withdrawStake() public {}

}