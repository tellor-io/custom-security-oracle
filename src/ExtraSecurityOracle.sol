// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./interfaces/IERC20.sol";


contract ExtraSecurityOracle {
    address public owner;
    address public tellor;
    address public governance;
    IERC20 public token;
    uint256 public minimumStakeAmount;
    uint256 public stakeAmount;
    uint256 public reportingLock;
    // todo: add & implement min usd stake amount (stakeAmountDollarTarget). User can set to zero to disable.

    mapping(address => StakeInfo) private stakerDetails; // mapping from a persons address to their staking info

    struct StakeInfo {
        uint256 startDate; // stake or withdrawal request start date
        uint256 stakedBalance; // staked token balance
        uint256 lockedBalance; // amount locked for withdrawal
        bool staked; // used to keep track of total stakers
    }

    event NewStaker(address indexed _staker, uint256 indexed _amount);
    event StakeWithdrawRequested(address _staker, uint256 _amount);
    event StakeWithdrawn(address _staker);
    event ReporterSlashed(
        address indexed _reporter,
        address _recipient,
        uint256 _slashAmount
    );


    constructor(
        address _tellor,
        address _token,
        uint256 _minimumStakeAmount,
        uint256 _reportingLock
    ) {
        tellor = _tellor;
        token = IERC20(_token);
        minimumStakeAmount = _minimumStakeAmount;
        stakeAmount = _minimumStakeAmount; // todo: need to be determined using fixed dollar amount, or just use minimumStakeAmount?
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
        // todo: get data from tellor reported by someone both staked on tellor oracle and staked on this contract
        // todo: call tellor.getDataBefore()
        // todo: then do binary search to find a value that was reported by someone who's also staked on this contract
    }

    /**
     * @dev Slashes a reporter and transfers their stake amount to the given recipient
     * Note: this function is only callable by the governance address.
     * @param _reporter is the address of the reporter being slashed
     * @param _recipient is the address receiving the reporter's stake
     * @return _slashAmount uint256 amount of token slashed and sent to recipient address
     */
    function slashReporter(address _reporter, address _recipient)
        external
        returns (uint256 _slashAmount)
    {
        require(msg.sender == governance, "only governance can slash reporter");
        StakeInfo storage _staker = stakerDetails[_reporter];
        uint256 _stakedBalance = _staker.stakedBalance;
        uint256 _lockedBalance = _staker.lockedBalance;
        require(_stakedBalance + _lockedBalance > 0, "zero staker balance");

        if (_lockedBalance >= stakeAmount) {
            // if locked balance is at least stakeAmount, slash from locked balance
            _slashAmount = stakeAmount;
            _staker.lockedBalance -= stakeAmount;
        } else if (_lockedBalance + _stakedBalance >= stakeAmount) {
            // if locked balance + staked balance is at least stakeAmount,
            // slash from locked balance and slash remainder from staked balance
            _slashAmount = stakeAmount;
            _staker.lockedBalance = 0;
        } else {
            // if sum(locked balance + staked balance) is less than stakeAmount,
            // slash sum
            _slashAmount = _stakedBalance + _lockedBalance;
            _staker.lockedBalance = 0;
        }
        require(token.transfer(_recipient, _slashAmount));
        emit ReporterSlashed(_reporter, _recipient, _slashAmount);
        return _slashAmount;
    }

    /**
     * @dev Allows a reporter to submit stake
     * @param _amount amount of tokens to stake
     */
    function depositStake(uint256 _amount) external {
        require(governance != address(0), "governance address not set");
        StakeInfo storage _staker = stakerDetails[msg.sender];
        uint256 _lockedBalance = _staker.lockedBalance;
        if (_lockedBalance > 0) {
            if (_lockedBalance >= _amount) {
                // if staker's locked balance covers full _amount, use that
                _staker.lockedBalance -= _amount;
            } else {
                // otherwise, stake the whole locked balance and transfer the
                // remaining amount from the staker's address
                require(
                    token.transferFrom(
                        msg.sender,
                        address(this),
                        _amount - _lockedBalance
                    )
                );
                _staker.lockedBalance = 0;
            }
        } else {
            require(token.transferFrom(msg.sender, address(this), _amount));
        }
        _staker.stakedBalance = _amount;
        _staker.startDate = block.timestamp; // This resets the staker start date to now
        emit NewStaker(msg.sender, _amount);
    }

    /**
     * @dev Allows a reporter to request to withdraw their stake
     * @param _amount amount of staked tokens requesting to withdraw
     */
    function requestStakingWithdraw(uint256 _amount) external {
        StakeInfo storage _staker = stakerDetails[msg.sender];
        require(
            _staker.stakedBalance >= _amount,
            "insufficient staked balance"
        );
        _staker.startDate = block.timestamp;
        _staker.stakedBalance -= _amount;
        _staker.lockedBalance += _amount;
        emit StakeWithdrawRequested(msg.sender, _amount);
    }

    /**
     * @dev Withdraws a reporter's stake after the lock period expires
     */
    function withdrawStake() external {
        StakeInfo storage _staker = stakerDetails[msg.sender];
        // Ensure reporter is locked and that enough time has passed
        require(
            block.timestamp - _staker.startDate >= 7 days,
            "7 days didn't pass"
        );
        require(
            _staker.lockedBalance > 0,
            "reporter not locked for withdrawal"
        );
        require(token.transfer(msg.sender, _staker.lockedBalance));
        _staker.lockedBalance = 0;
        emit StakeWithdrawn(msg.sender);
    }

    /// GETTERS ///
    function getTokenAddress() external view returns (address) {
        return address(token);
    }

    function getTellorAddress() external view returns (address) {
        return address(tellor);
    }

    function getStakeAmount() external view returns (uint256) {
        return stakeAmount;
    }
}