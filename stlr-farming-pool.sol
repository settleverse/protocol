// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/Address.sol";
import "./security/Pausable.sol";
import "./security/ReentrancyGuard.sol";
import "./token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/ISTLRSettingsV1.sol";
import "./interfaces/ISTLRDaoV1.sol";

contract STLRFarmingPoolV1 is ReentrancyGuard, Pausable {
    ISettleverseDao public stlrDao;
    IERC20Metadata public immutable stlr;
    IERC20Metadata public immutable usdc;
    IERC20Metadata public immutable stakingToken;

    uint public periodFinish;
    uint public rewardRate;
    uint public rewardsDuration;
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;

    struct Deposit {
        bool exists;
        uint amount;
        uint timestamp;
    }

    struct Claim {
        uint total;
        uint timestamp;
    }

    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;

    uint private _totalSupply;
    uint private _totalLocked;
    uint private _totalAccounts;
    uint private _totalPaidOut;
    mapping(address => Deposit) private _deposits;
    mapping(address => uint) private _locked;
    mapping(address => Claim) private _claims;

    // CONSTRUCTOR

    constructor (
        address _stlrDao,
        address _stakingToken,
        uint _rewardsDuration
    ) {
        require(_stlrDao != address(0) &&
            _stakingToken != address(0), '!null');

        stlrDao = ISettleverseDao(_stlrDao);
        stlr = IERC20Metadata(ISTLRSettingsV1(stlrDao.settings()).STLR());
        usdc = IERC20Metadata(ISTLRSettingsV1(stlrDao.settings()).USDC());
        stakingToken = IERC20Metadata(_stakingToken);
        rewardsDuration = _rewardsDuration;
    }

    // VIEWS

    function totalSupply(
    ) 
        external 
        view 
        returns (uint) 
    {
        return _totalSupply;
    }

    function totalLocked(
    ) 
        external 
        view 
        returns (uint) 
    {
        return _totalLocked;
    }

    function totalAccounts(
    ) 
        external 
        view 
        returns (uint) 
    {
        return _totalAccounts;
    }

    function totalPaidOut(
    ) 
        external 
        view 
        returns (uint) 
    {
        return _totalPaidOut;
    }

    function balanceOf(
        address account
    ) 
        public 
        view 
        returns (uint) 
    {
        return _deposits[account].amount;
    }

    function lockedOf(
        address account
    ) 
        public 
        view 
        returns (uint) 
    {
        return _locked[account];
    }

    function availableOf(
        address account
    ) 
        public 
        view 
        returns (uint) 
    {
        return balanceOf(account) - lockedOf(account);
    }

    function timestampOf(
        address account
    ) 
        public 
        view 
        returns (uint) 
    {
        return _deposits[account].timestamp;
    }

    function nextClaimAt(
        address account
    ) 
        public 
        view 
        returns (uint) 
    {
        return _claims[account].timestamp + ISTLRSettingsV1(stlrDao.settings()).farmingClaimCooldown();
    }

    function withdrawableAt(
        address account
    ) 
        public 
        view 
        returns (uint) 
    {
        return _deposits[account].timestamp + ISTLRSettingsV1(stlrDao.settings()).farmingWithdrawDelay();
    }

    function claimedOf(
        address account
    ) 
        external 
        view 
        returns (uint) 
    {
        return _claims[account].total;
    }

    function lastTimeRewardApplicable(
    ) 
        public 
        view 
        returns (uint) 
    {
        return min(block.timestamp, periodFinish);
    }

    function rewardPerToken(
    ) 
        public 
        view 
        returns (uint) 
    {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (
                (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / _totalSupply
            );
    }

    function earned(
        address account
    ) 
        public 
        view 
        returns (uint) 
    {
        return
            _deposits[account].amount
                * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + rewards[account];
    }

    function getRewardForDuration(
    ) 
        external 
        view 
        returns (uint) 
    {
        return rewardRate * rewardsDuration;
    }

    function min(
        uint a, 
        uint b
    ) 
        public 
        pure 
        returns (uint) 
    {
        return a < b ? a : b;
    }

    function treasury(
    ) 
        public 
        view 
        returns (address) 
    {
        return stlrDao.treasury();
    }

    // PUBLIC FUNCTIONS

    function stake(
        uint amount
    )
        external
        nonReentrant
        notPaused
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake 0");

        uint balBefore = stakingToken.balanceOf(address(this));
        stakingToken.transferFrom(msg.sender, address(this), amount);
        uint balAfter = stakingToken.balanceOf(address(this));
        uint actualReceived = balAfter - balBefore;
        uint lockedAmount = ISTLRSettingsV1(stlrDao.settings()).LOCKED_PERCENT() * actualReceived / 100;
        stakingToken.transfer(treasury(), lockedAmount);

        _totalSupply = _totalSupply + actualReceived;
        _deposits[msg.sender].amount = _deposits[msg.sender].amount + actualReceived;
        _deposits[msg.sender].timestamp = block.timestamp;
        _locked[msg.sender] = _locked[msg.sender] + lockedAmount;
        _totalLocked = _totalLocked + lockedAmount;
        if (!_deposits[msg.sender].exists) {
            _deposits[msg.sender].exists = true;
            _claims[msg.sender].timestamp = block.timestamp;
            _totalAccounts++;
        }
        
        emit Staked(msg.sender, actualReceived);
    }

    function withdraw(
        uint amount
    )
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        uint available = availableOf(msg.sender);
        require(amount <= available, "Cannot withdraw more than available amount");
        require(_deposits[msg.sender].timestamp + ISTLRSettingsV1(stlrDao.settings()).farmingWithdrawDelay() < block.timestamp, "You can not withdraw yet");

        _totalSupply = _totalSupply - amount;
        _deposits[msg.sender].amount = _deposits[msg.sender].amount - amount;
        stakingToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claim(
    ) 
        external 
        nonReentrant 
        updateReward(msg.sender) 
        claimable(msg.sender)
    {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            _totalPaidOut += reward;
            uint fee = reward * ISTLRSettingsV1(stlrDao.settings()).claimFee() / 10000;
            uint amount = reward - fee;
            stlr.transfer(msg.sender, amount);
            stlr.transfer(treasury(), fee);
            _claims[msg.sender].timestamp = block.timestamp;
            _claims[msg.sender].total += amount;
            emit RewardPaid(msg.sender, reward);
        }
    }

    function settle(
        uint _settlementType, 
        uint count
    )
        external
        nonReentrant
        updateReward(msg.sender)
        claimable(msg.sender)
    {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            uint stlr_;
            uint usdc_;
            (, , stlr_, usdc_) = stlrDao.settlementTypes(_settlementType);
            uint _stlr = count * stlr_ * 10 ** stlr.decimals();
            uint _usdc = count * usdc_ * 10 ** usdc.decimals();
            require(usdc.balanceOf(msg.sender) >= _usdc, 'You do not have enough USDC to create settlements');
            
            uint diff = 0;
            if (reward < _stlr) {
                diff = _stlr - reward;
                require(stlr.balanceOf(msg.sender) >= diff, 'You do not have enough STLR');
                rewards[msg.sender] = 0;
                _totalPaidOut += reward;
                _claims[msg.sender].total += reward;
                stlr.transferFrom(msg.sender, address(stlrDao), diff);
                stlr.transfer(address(stlrDao), reward);
            } else {
                diff = reward - _stlr;
                rewards[msg.sender] = diff;
                _totalPaidOut += _stlr;
                _claims[msg.sender].total += _stlr;
                stlr.transfer(address(stlrDao), _stlr);
            }

            _claims[msg.sender].timestamp = block.timestamp;
            emit RewardPaid(msg.sender, _stlr);

            usdc.transferFrom(msg.sender, treasury(), _usdc);
            stlrDao.mint(msg.sender, _settlementType, count);
        }
    }

    // RESTRICTED FUNCTIONS

    function notifyRewardAmount(
        uint reward
    )
        external
        onlyOwner
        updateReward(address(0))
    {
        uint balBefore = stlr.balanceOf(address(this));
        stlr.transferFrom(msg.sender, address(this), reward);
        uint balAfter = stlr.balanceOf(address(this));
        uint actualReceived = balAfter - balBefore;
        require(actualReceived == reward, "Whitelist the pool to exclude fees");

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint remaining = periodFinish - block.timestamp;
            uint leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = stlr.balanceOf(address(this));
        require(
            rewardRate <= balance / rewardsDuration,
            "Provided reward too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(
        address tokenAddress, 
        uint tokenAmount
    )
        external
        onlyOwner
    {
        // Cannot recover the staking token or the rewards token
        require(
            tokenAddress != address(stakingToken) &&
                tokenAddress != address(stlr),
            "Cannot withdraw the staking or rewards tokens"
        );
        IERC20(tokenAddress).transfer(treasury(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function recover(
    ) 
        external 
        onlyOwner 
    {
        uint balance = address(this).balance;
        Address.sendValue(payable(treasury()), balance);
        emit Recovered(balance);
    }

    function setRewardsDuration(
        uint _rewardsDuration
    ) 
        external 
        onlyOwner 
    {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setDao(
        address _dao
    ) 
        external 
        onlyOwner 
    {
        require(_dao != address(0), "Can not be null address");
        stlrDao = ISettleverseDao(_dao);
        emit DaoUpdated(_dao);
    }

    // *** MODIFIERS ***

    modifier updateReward(
        address account
    ) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }

        _;
    }

    modifier claimable(
        address account
    ) {
        require(
            nextClaimAt(account) < block.timestamp, 
            "You can not claim yet"
        );

        _;
    }

    // *** EVENTS ***

    event RewardAdded(uint reward);
    event Staked(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
    event RewardPaid(address indexed user, uint reward);
    event RewardsDurationUpdated(uint newDuration);
    event DaoUpdated(address dao);
    event ClaimFeeUpdated(uint fee);
    event Recovered(address token, uint amount);
    event Recovered(uint amount);
}