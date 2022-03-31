// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./access/Ownable.sol";
import "./token/ERC20/ERC20.sol";

import "./interfaces/ISTLRSettingsV1.sol";

contract Settleverse is ERC20, Ownable {
    ISTLRSettingsV1 public settings;

    constructor(
    ) 
        ERC20('Settleverse', 'STLR') 
    {
        uint supply = 1975000 * 10 ** 18;
        _mint(owner(), supply);
    }

    /** VIEWS */

    function dao(
    ) 
        external 
        view 
        returns (address) 
    {
        return settings.dao();
    }

    function treasury(
    ) 
        external 
        view 
        returns (address) 
    {
        return settings.treasury();
    }

    /** ERC20 FUNCTIONS */

    function transferFrom(
        address sender, 
        address recipient, 
        uint256 amount
    ) 
        public 
        override (ERC20) 
        returns (bool) 
    {
        if (!settings.isExemptFromFee(sender) && !settings.isExemptFromFee(recipient)) {
            require(amount <= settings.transferLimit(), 'This transfer exceeds the allowed transfer limit!');

            uint fee;
            if (settings.isMarketPair(recipient)) {
                fee = amount * settings.SELL_FEE() / 10000;
                amount = amount - fee;
                super.transferFrom(sender, settings.treasury(), fee);
            } else {
                if (settings.feeOnTransfer() && !settings.isMarketPair(sender)) {
                    fee = amount * settings.SELL_FEE() / 10000;
                    amount = amount - fee;
                }

                require(balanceOf(recipient) + amount <= settings.walletMax(), 'This transfer exceeds the allowed wallet limit!');
                if (fee > 0) super.transferFrom(sender, settings.treasury(), fee);
            }
        }
        
        return super.transferFrom(sender, recipient, amount);
    }

    function transfer(
        address recipient, 
        uint256 amount
    ) 
        public 
        override (ERC20) 
        returns (bool) 
    {
        if (!settings.isExemptFromFee(msg.sender) && !settings.isExemptFromFee(recipient)) {
            require(amount <= settings.transferLimit(), 'This transfer exceeds the allowed transfer limit!');

            uint fee;
            if (settings.isMarketPair(recipient)) {
                fee = amount * settings.SELL_FEE() / 10000;
                amount = amount - fee;
                super.transfer(settings.treasury(), fee);
            } else {
                if (settings.feeOnTransfer() && !settings.isMarketPair(msg.sender)) {
                    fee = amount * settings.SELL_FEE() / 10000;
                    amount = amount - fee;
                }

                require(balanceOf(recipient) + amount <= settings.walletMax(), 'This transfer exceeds the allowed wallet limit!');
                if (fee > 0) super.transfer(settings.treasury(), fee);
            }
        }

        return super.transfer(recipient, amount);
    }

    function burn(
        uint256 _amount
    ) 
        public 
    {
        _burn(msg.sender, _amount);
    }

    /** RESTRICTED FUNCTIONS */

    function setSettings(
        address _settings
    ) 
        external 
        onlyOwner 
    {
        require(_settings != address(0), 'Settings is null address');
        settings = ISTLRSettingsV1(_settings);
    }
}