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
        // uint256 rewardDebt; // used for staking reward calculation
        // uint256 reporterLastTimestamp; // timestamp of reporter's last reported value
        // uint256 reportsSubmitted; // total number of reports submitted by reporter
        // uint256 startVoteCount; // total number of governance votes when stake deposited
        // uint256 startVoteTally; // staker vote tally when stake deposited
        bool staked; // used to keep track of total stakers
        // mapping(bytes32 => uint256) reportsSubmittedByQueryId; // mapping of queryId to number of reports submitted by reporter
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
            // toWithdraw -= stakeAmount;
        } else if (_lockedBalance + _stakedBalance >= stakeAmount) {
            // if locked balance + staked balance is at least stakeAmount,
            // slash from locked balance and slash remainder from staked balance
            _slashAmount = stakeAmount;
            // _updateStakeAndPayRewards(
            //     _reporter,
            //     _stakedBalance - (stakeAmount - _lockedBalance)
            // );
            // toWithdraw -= _lockedBalance;
            _staker.lockedBalance = 0;
        } else {
            // if sum(locked balance + staked balance) is less than stakeAmount,
            // slash sum
            _slashAmount = _stakedBalance + _lockedBalance;
            // toWithdraw -= _lockedBalance;
            // _updateStakeAndPayRewards(_reporter, 0);
            _staker.lockedBalance = 0;
        }
        require(token.transfer(_recipient, _slashAmount));
        emit ReporterSlashed(_reporter, _recipient, _slashAmount);
    }

    /**
     * @dev Allows a reporter to submit stake
     * @param _amount amount of tokens to stake
     */
    function depositStake(uint256 _amount) external {
        require(governance != address(0), "governance address not set");
        StakeInfo storage _staker = stakerDetails[msg.sender];
        uint256 _stakedBalance = _staker.stakedBalance;
        uint256 _lockedBalance = _staker.lockedBalance;
        if (_lockedBalance > 0) {
            if (_lockedBalance >= _amount) {
                // if staker's locked balance covers full _amount, use that
                _staker.lockedBalance -= _amount;
                // toWithdraw -= _amount;
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
                // toWithdraw -= _staker.lockedBalance;
                _staker.lockedBalance = 0;
            }
        } else {
            if (_stakedBalance == 0) {
                // if staked balance and locked balance equal 0, save current vote tally.
                // voting participation used for calculating rewards
                // (bool _success, bytes memory _returnData) = governance.call(
                //     abi.encodeWithSignature("getVoteCount()")
                // );
                // if (_success) {
                //     _staker.startVoteCount = uint256(abi.decode(_returnData, (uint256)));
                // }
                // (_success,_returnData) = governance.call(
                //     abi.encodeWithSignature("getVoteTallyByAddress(address)",msg.sender)
                // );
                // if(_success){
                //     _staker.startVoteTally =  abi.decode(_returnData,(uint256));
                // }
            }
            require(token.transferFrom(msg.sender, address(this), _amount));
        }
        // _updateStakeAndPayRewards(msg.sender, _stakedBalance + _amount);
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
        // _updateStakeAndPayRewards(msg.sender, _staker.stakedBalance - _amount);
        _staker.startDate = block.timestamp;
        _staker.lockedBalance += _amount;
        // toWithdraw += _amount;
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
        // toWithdraw -= _staker.lockedBalance;
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