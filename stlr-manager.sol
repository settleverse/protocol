// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/Address.sol";
import "./security/Pausable.sol";
import "./security/ReentrancyGuard.sol";
import "./token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/ISTLRSettingsV1.sol";
import "./interfaces/ISTLRDaoV1.sol";

contract STLRManagerV1 is Ownable, ReentrancyGuard {
    ISettleverseDao public stlrDao;
    IERC20Metadata public immutable stlr;
    IERC20Metadata public immutable usdc;

    constructor(
        address _stlrDao
    ) {
        stlrDao = ISettleverseDao(_stlrDao);
        stlr = IERC20Metadata(ISTLRSettingsV1(stlrDao.settings()).STLR());
        usdc = IERC20Metadata(ISTLRSettingsV1(stlrDao.settings()).USDC());
    }

    /** INTERNAL FUNCTIONS */

    function _claim(
        address account,
        bool _compound
    )
        internal
        returns (uint rewards)
    {
        rewards = stlrDao.claim(account, _compound);
    }

    /** EXTERNAL FUNCTIONS */

    function declare(
        uint _faction
    ) 
        external 
        nonReentrant
    {
        stlrDao.declare(msg.sender, _faction);
    }

    function settle(
        uint settlementType, 
        uint count
    ) 
        external 
        nonReentrant 
    {
        require(count > 0, 'Count must be more than zero');
        require(settlementType >= 0 && settlementType < stlrDao.settCount(), 'Invalid settlement type');

        (, , uint stlrAmount, uint usdcAmount) = stlrDao.settlementTypes(settlementType);
        uint _stlr = count * stlrAmount * 10 ** stlr.decimals();
        uint _usdc = count * usdcAmount * 10 ** usdc.decimals();

        stlrDao.settle(msg.sender, settlementType, count);

        stlr.transferFrom(msg.sender, address(stlrDao), _stlr);
        usdc.transferFrom(msg.sender, stlrDao.treasury(), _usdc);
    }

    function claim(
    ) 
        external
        payable
        nonReentrant
        payFee(msg.sender)
    {
        _claim(msg.sender, false);
    }

    function compound(
        uint settlementType,
        uint count
    ) 
        external
        payable
        nonReentrant
        payFee(msg.sender)
    {
        require(count > 0, 'Count must be more than zero');
        require(settlementType >= 0 && settlementType < stlrDao.settCount(), 'Invalid settlement type');
        
        uint rewards = _claim(msg.sender, true);
        (, , uint stlrAmount, uint usdcAmount) = stlrDao.settlementTypes(settlementType);
        uint _stlr = count * stlrAmount * 10 ** stlr.decimals();
        uint _usdc = count * usdcAmount * 10 ** usdc.decimals();
        uint diff;
        uint fee;
        uint refund;
        if (rewards < _stlr) {
            diff = _stlr - rewards;
            require(stlr.balanceOf(msg.sender) >= diff, 'You do not have enough STLR to compound');
        } else {
            uint rest = rewards - _stlr;
            if (rest > 0) {
                fee = rest * ISTLRSettingsV1(stlrDao.settings()).claimFee() / 10000;
                refund = rest - fee;
            }
        }

        stlrDao.compound(msg.sender, settlementType, count, fee, refund);

        if (diff > 0) {
            stlr.transferFrom(msg.sender, address(stlrDao), diff);
        }
        usdc.transferFrom(msg.sender, stlrDao.treasury(), _usdc);
    }

    /** RESTRICTED FUNCTIONS */

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

    function recover(
        address token
    )
        external
        onlyOwner
    {
        uint balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(owner(), balance);
        emit Recovered(token, balance);
    }

    function recover() 
        external 
        onlyOwner 
    {
        uint balance = address(this).balance;
        Address.sendValue(payable(owner()), balance);
        emit Recovered(balance);
    }

    /** MODIFIERS */

    modifier payFee(
        address account
    ) {
        (, , , , uint count, , ) = stlrDao.accounts(account);
        uint fee = count * ISTLRSettingsV1(stlrDao.settings()).baseRewardFee();
        if (fee > ISTLRSettingsV1(stlrDao.settings()).maxRewardFee()) fee = ISTLRSettingsV1(stlrDao.settings()).maxRewardFee();
        require(msg.value == fee, 'REWARD_FEE');
        Address.sendValue(payable(stlrDao.treasury()), address(this).balance);

        _;
    }

    /** EVENTS */

    event DaoUpdated(address dao);
    event Recovered(address token, uint amount);
    event Recovered(uint amount);
}