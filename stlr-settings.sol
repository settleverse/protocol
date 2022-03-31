// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/Address.sol";
import "./security/Pausable.sol";
import "./token/ERC20/IERC20.sol";

import "./interfaces/ISTLRHelperV1.sol";

contract STLRSettingsV1 is Pausable {
    
    /** GLOBAL PARAMETERS */

    address public immutable STLR;
    address public immutable USDC;
    address public dao;
    address public treasury;
    address public manager;
    address public helper;
    address public presale;
    uint public claimFee = 500; // 5.0 % claim fee

    /** TOKEN PARAMETERS */

    uint public transferLimit;
    uint public walletMax;
    bool public feeOnTransfer = true;
    uint public constant SELL_FEE = 750; // 7.5 % sell fee

    /** DAO PARAMETERS */

    uint public interestRate = 10000;
    uint public claimCooldown = 6 hours;
    uint public baseRewardFee = 1 ether; // 1 FTM
    uint public maxRewardFee = 25 ether; // 25 FTM
    uint public rotDeduction = 2500; // 25 %
    uint public maxRotCount = 2; // max. 50 % deduction

    uint public constant MAX_SETTLEMENTS = 100;
    uint public constant REWARD_FREQUENCY = 1 minutes; // less than or equal to 1 day
    uint public constant BASE_DENOMINATOR = 10000;

    /** FARMING PARAMETERS */

    uint public farmingWithdrawDelay = 1 weeks; // 1 week after deposit
    uint public farmingClaimCooldown = 1 days; // claim cooldown

    uint public constant LOCKED_PERCENT = 15;

    /** PRIVATE VARIABLES */

    mapping(address => bool) private _operators;
    mapping(address => bool) private _exemptFromFees;
    mapping(address => bool) private _marketPairs;

    constructor(
        address _stlr,
        address _usdc,
        address _treasury
    ) {
        STLR = _stlr;
        USDC = _usdc;
        treasury = _treasury;

        setExemptFromFee(owner(), true);
        setExemptFromFee(treasury, true);
        transferLimit = IERC20(STLR).totalSupply() * 5 / 1000; // 0.5% of total supply
        walletMax = IERC20(STLR).totalSupply() * 15 / 1000; // 1.5% of total supply
    }

    /** VIEW FUNCTIONS */

    function isOperator(
        address operator
    ) 
        external 
        view 
        returns (bool)
    {
        return _operators[operator];
    }

    function isExemptFromFee(
        address account
    )
        external
        view
        returns (bool)
    {
        return _exemptFromFees[account];
    }

    function isMarketPair(
        address pair
    )
        external
        view
        returns (bool)
    {
        return _marketPairs[pair];
    }

    /** RESTRICTED FUNCTIONS */

    function setDao(
        address _dao
    )
        external
        onlyOwner
    {
        require(_dao != address(0), 'Dao can not be null address');
        dao = _dao;
        setExemptFromFee(dao, true);
        emit DaoUpdated(dao);
    }

    function setTreasury(
        address _treasury
    ) 
        external 
        onlyOwner 
    {
        require(_treasury != address(0), 'Treasury can not be null address');
        treasury = _treasury;
        setExemptFromFee(treasury, true);
        emit TreasuryUpdated(treasury);
    }

    function setManager(
        address _manager
    )
        external
        onlyOwner
    {
        require(_manager != address(0), 'Manager can not be null address');
        manager = _manager;
        setExemptFromFee(manager, true);
        emit ManagerUpdated(manager);
    }

    function setHelper(
        address _helper
    )
        external
        onlyOwner
    {
        require(_helper != address(0), 'Helper can not be null address');
        helper = _helper;
        setExemptFromFee(helper, true);
        setMarketPair(ISTLRHelperV1(helper).pair(), true);
        emit HelperUpdated(helper);
    }

    function setPresale(
        address _presale
    )
        external
        onlyOwner
    {
        require(_presale != address(0), 'Presale can not be null address');
        presale = _presale;
        setOperator(presale, true);
        emit PresaleUpdated(presale);
    }

    function setInterestRate(
        uint _rate
    ) 
        external 
        onlyOwner
    {
        require(_rate != uint(0), 'Interest rate can not be null');
        interestRate = _rate;
        emit InterestRateUpdated(interestRate);
    }

    function setClaimFee(
        uint _fee
    )
        external 
        onlyOwner 
    {
        require(_fee <= 1000, 'Claim fee not within bounds');
        claimFee = _fee;
        emit ClaimFeeUpdated(claimFee);
    }

    function setClaimCooldown(
        uint _cooldown
    ) 
        external 
        onlyOwner 
    {
        require(_cooldown <= 24 hours, 'Cooldown not within bounds');
        claimCooldown = _cooldown;
        emit ClaimCooldownUpdated(claimCooldown);
    }

    function setRewardFees(
        uint _baseRewardFee, 
        uint _maxRewardFee
    ) 
        external 
        onlyOwner 
    {
        baseRewardFee = _baseRewardFee;
        maxRewardFee = _maxRewardFee;
        emit RewardFeesUpdated(baseRewardFee, maxRewardFee);
    }

    function setRotParameters(
        uint _rotDeduction, 
        uint _maxRotCount
    ) 
        external 
        onlyOwner 
    {
        rotDeduction = _rotDeduction;
        maxRotCount = _maxRotCount;
        emit RotParametersUpdated(rotDeduction, maxRotCount);
    }

    function setFarmingParameters(
        uint _withdrawDelay,
        uint _claimCooldown
    )
        external
        onlyOwner
    {
        require(_withdrawDelay <= 30 days, 'Withdraw delay not within bounds');
        require(_claimCooldown <= 24 hours, 'Cooldown not within bounds');
        farmingWithdrawDelay = _withdrawDelay;
        farmingClaimCooldown = _claimCooldown;
        emit FarmingParametersUpdated(farmingWithdrawDelay, farmingClaimCooldown);
    }

    function setOperator(
        address operator, 
        bool status
    ) 
        public 
        onlyOwner 
    {
        _operators[operator] = status;
        if (status) {
            setExemptFromFee(operator, true);
        } else {
            setExemptFromFee(operator, false);
        }
        emit OperatorUpdated(operator, status);
    }

    /** TOKEN FUNCTIONS */

    function setTransferLimit(
        uint _prcnt
    ) 
        external 
        onlyOwner 
    {
        require(_prcnt > 0, 'Transfer limit can not be zero');
        transferLimit = IERC20(STLR).totalSupply() * _prcnt / 1000;
        emit TransferLimitUpdated(transferLimit);
    }

    function setWalletLimit(
        uint _prcnt
    ) 
        external 
        onlyOwner 
    {
        walletMax = IERC20(STLR).totalSupply() * _prcnt / 1000;
        emit WalletLimitUpdated(walletMax);
    }

    function setExemptFromFee(
        address account, 
        bool status
    ) 
        public 
        onlyOwner 
    {
        _exemptFromFees[account] = status;
        emit ExemptFromFeeUpdated(account, status);
    }

    function setMarketPair(
        address pair, 
        bool status
    ) 
        public 
        onlyOwner 
    {
        _marketPairs[pair] = status;
        emit MarketPairUpdated(pair, status);
    }

    function setFeeOnTransfer(
        bool status
    ) 
        external 
        onlyOwner 
    {
        feeOnTransfer = status;
        emit FeeOnTransferUpdated(status);
    }

    /** RECOVERY FUNCTIONS */

    function recover(
        address token
    )
        external
        onlyOwner
    {
        uint balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(treasury, balance);
        emit Recovered(token, balance);
    }

    function recover(
    ) 
        external 
        onlyOwner 
    {
        uint balance = address(this).balance;
        Address.sendValue(payable(treasury), balance);
        emit Recovered(balance);
    }

    /** EVENTS */

    event DaoUpdated(address dao);
    event TreasuryUpdated(address treasury);
    event ManagerUpdated(address manager);
    event HelperUpdated(address helper);
    event PresaleUpdated(address presale);
    event InterestRateUpdated(uint rate);
    event ClaimFeeUpdated(uint fee);
    event ClaimCooldownUpdated(uint cooldown);
    event RewardFeesUpdated(uint baseFee, uint maxFee);
    event RotParametersUpdated(uint deduction, uint maxCount);
    event FarmingParametersUpdated(uint delay, uint cooldown);
    event OperatorUpdated(address operator, bool status);
    event TransferLimitUpdated(uint limit);
    event WalletLimitUpdated(uint limit);
    event ExemptFromFeeUpdated(address account, bool status);
    event MarketPairUpdated(address pair, bool status);
    event FeeOnTransferUpdated(bool status);
    event Recovered(address token, uint amount);
    event Recovered(uint amount);
}