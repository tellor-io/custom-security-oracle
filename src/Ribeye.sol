// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./interfaces/IERC20.sol";
import "./interfaces/ITellorOracle.sol";


contract Ribeye { // more stake
    address public owner;
    ITellorOracle public tellor;
    address public governance;
    IERC20 public token;
    uint256 public minimumStakeAmount;
    uint256 public stakeAmount;
    uint256 public stakeAmountDollarTarget;
    bytes32 public stakingTokenPriceQueryId;

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
    event NewStakeAmount(uint256 _newStakeAmount);


    constructor(
        address _tellor,
        address _token,
        uint256 _stakeAmountDollarTarget, // set to zero to disable and use minimumStakeAmount
        uint256 _stakingTokenPrice,
        uint256 _minimumStakeAmount,
        bytes32 _stakingTokenPriceQueryId
    ) {
        require(_token != address(0), "must set token address");
        require(_stakingTokenPrice > 0, "must set staking token price");
        require(_stakingTokenPriceQueryId != bytes32(0), "must set staking token price queryId");
        tellor = ITellorOracle(_tellor);
        token = IERC20(_token);
        owner = msg.sender;
        stakeAmountDollarTarget = _stakeAmountDollarTarget;
        minimumStakeAmount = _minimumStakeAmount;
        uint256 _potentialStakeAmount = (_stakeAmountDollarTarget * 1e18) / _stakingTokenPrice;
        if(_potentialStakeAmount < _minimumStakeAmount) {
            stakeAmount = _minimumStakeAmount;
        } else {
            stakeAmount = _potentialStakeAmount;
        }
        stakingTokenPriceQueryId = _stakingTokenPriceQueryId;
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

    function getDataBefore(bytes32 _queryId, uint256 _timestamp) public view returns (
            bool _ifRetrieve,
            bytes memory _value,
            uint256 _timestampRetrieved
        ) {
        // get data from tellor reported by someone both staked on tellor oracle and staked on this contract
        // check if Tellor oracle has value reported before given timestamp
        (bool _found, uint256 _index) = tellor.getIndexForDataBefore(
        _queryId,
        _timestamp
        );
        if (!_found) return (false, bytes(""), 0);
    
        // check if Tellor oracle has a value reported by someone who's also staked on this contract
        // iterate backwards from index for data before to find a value that was reported by someone who's also staked on this contract
        while (_index >= 0) {
            _timestampRetrieved = tellor.getTimestampbyQueryIdandIndex(
                _queryId,
                _index
            );
            address _reporter = tellor.getReporterByTimestamp(_queryId, _timestampRetrieved);
            if (stakerDetails[_reporter].staked) {
                // if the reporter is staked on this contract, return the value
                return (
                    true,
                    tellor.retrieveData(_queryId, _index),
                    _timestampRetrieved
                );
            }
            _index--;
        }
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
            _staker.stakedBalance -= stakeAmount - _lockedBalance;
            _staker.lockedBalance = 0;
        } else {
            // if sum(locked balance + staked balance) is less than stakeAmount,
            // slash sum
            _slashAmount = _stakedBalance + _lockedBalance;
            _staker.stakedBalance = 0;
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
        _staker.stakedBalance += _amount;
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

    /**
     * @dev Updates the stake amount after retrieving the latest
     * 12+-hour-old staking token price from the oracle
     */
    function updateStakeAmount() external {
        // get staking token price
        (bool _valFound, bytes memory _val, ) = tellor.getDataBefore(
            stakingTokenPriceQueryId,
            block.timestamp - 12 hours
        );
        if (_valFound) {
            uint256 _stakingTokenPrice = abi.decode(_val, (uint256));
            require(
                _stakingTokenPrice >= 0.01 ether && _stakingTokenPrice < 1000000 ether,
                "invalid staking token price"
            );

            uint256 _adjustedStakeAmount = (stakeAmountDollarTarget * 1e18) / _stakingTokenPrice;
            if(_adjustedStakeAmount < minimumStakeAmount) {
                stakeAmount = minimumStakeAmount;
            } else {
                stakeAmount = _adjustedStakeAmount;
            }
            emit NewStakeAmount(stakeAmount);
        }
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