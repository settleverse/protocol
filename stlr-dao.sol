// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/Address.sol";
import "./access/Ownable.sol";
import "./token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/ISTLRSettingsV1.sol";

contract SettleverseDaoV1 is Ownable {
    uint public counter;
    ISTLRSettingsV1 public settings;
    IERC20Metadata public immutable stlr;
    IERC20Metadata public immutable usdc;

    struct SettlementType {
        bool active;
        uint multiplier;
        uint stlr;
        uint usdc;
    }

    struct Settlement {
        bool active;
        uint settlementType;
        address account;
        uint boost;
        uint paidOut;
        uint lastClaimed;
        uint skin;
        uint createdAt;
        uint id;
    }

    struct Account {
        bool exists;
        uint faction;
        uint score;
        uint boost;
        uint count;
        uint paidOut;
        uint claimedAt;
    }

    mapping(address => Account) public accounts;
    mapping(uint => SettlementType) public settlementTypes;
    mapping(uint => Settlement) public settlements;
    mapping(address => uint[]) public userSettlements;

    mapping(uint => bool) private factions;
    mapping(uint => address[]) public factionUsers;

    uint public settCount;

    constructor(
        address _settings
    ) {
        settings = ISTLRSettingsV1(_settings);
        stlr = IERC20Metadata(settings.STLR());
        usdc = IERC20Metadata(settings.USDC());

        settlementTypes[0] = SettlementType(true, 35, 50, 50); // Hamlet
        settlementTypes[1] = SettlementType(true, 100, 125, 125); // Village
        settlementTypes[2] = SettlementType(true, 325, 350, 350); // Town
        settlementTypes[3] = SettlementType(true, 1200, 1000, 1000); // City
        settlementTypes[4] = SettlementType(true, 7500, 4500, 4500); // Metropolis
        settCount = 5;

        factions[0] = true; // Humans
        factions[1] = true; // Dwarves
        factions[2] = true; // Elves
    }

    /** VIEW FUNCTIONS */

    function treasury(
    ) 
        external 
        view 
        returns (address) 
    {
        return settings.treasury();
    }

    function getTotalSettlements(
    ) 
        external 
        view 
        returns (uint) 
    {
        return counter;
    }

    function getFactionCount(
        uint _faction
    ) 
        external 
        view 
        returns (uint) 
    {
        return factionUsers[_faction].length;
    }

    function getSettlements(
        address _account
    ) 
        public 
        view 
        returns (Settlement[] memory, uint) 
    {
        uint count = accounts[_account].count;
        Settlement[] memory _settlements = new Settlement[](count);
        for (uint256 index = 0; index < count; index++) {
            Settlement memory sett = settlements[userSettlements[_account][index]];
            _settlements[index] = sett;
        }

        return (_settlements, count);
    }

    function rewardsOfId(
        uint id
    ) 
        public 
        view 
        returns (uint) 
    {
        uint frequency = settings.REWARD_FREQUENCY();
        uint denominator = settings.BASE_DENOMINATOR();
        uint interval = uint(block.timestamp / frequency);
        Settlement memory sett = settlements[id];
        if (!sett.active) return 0;
        SettlementType memory settlementType = settlementTypes[sett.settlementType];
        if (!settlementType.active) return 0;
        uint period = interval - sett.lastClaimed;
        if (period == 0) return 0;
        uint rate = ((settlementType.multiplier * 10 ** 18 / (86400 * denominator / frequency)) * settings.interestRate() * (denominator + sett.boost)) / (denominator * 100);
        uint rewards = period * rate;
        if (sett.paidOut > settlementType.stlr) {
            uint rot = uint(sett.paidOut / settlementType.stlr);
            if (rot > settings.maxRotCount()) rot = settings.maxRotCount();
            rewards = rewards * (denominator - (rot * settings.rotDeduction())) / denominator;
        }

        uint boost = accounts[sett.account].boost;
        if (boost > 0) {
            rewards = rewards * (denominator + boost) / denominator;
        }

        return rewards;
    }

    function earned(
        address _account
    ) 
        external 
        view 
        returns (uint rewards) 
    {
        (Settlement[] memory _settlements, uint count) = getSettlements(_account);

        for (uint256 index = 0; index < count; index++) {
            uint id = _settlements[index].id;
            rewards += rewardsOfId(id);
        }
    }

    /** INTERNAL FUNCTIONS */

    function _remove(
        address _account, 
        uint id
    ) 
        internal 
    {
        uint index;
        for (uint i = 0; i < userSettlements[_account].length; i++) {
            if (settlements[userSettlements[_account][i]].id == id) {
                index = i;
                break;
            }
        }

        userSettlements[_account][index] = userSettlements[_account][userSettlements[_account].length - 1];
        userSettlements[_account].pop();
    }

    function _create(
        address _account, 
        uint _settlementType, 
        uint count
    ) 
        internal 
        whenNotPaused 
    {
        require(_settlementType >= 0 && _settlementType < settCount, 'Invalid settlement type');
        require(settlementTypes[_settlementType].active, 'Settlement type is inactive');
        require(accounts[_account].exists, 'Account does not exist yet');
        require(userSettlements[_account].length + count <= settings.MAX_SETTLEMENTS(), 'Max settlements per account reached');

        Account memory account = accounts[_account];
        SettlementType memory settlementType = settlementTypes[_settlementType];

        uint day = uint(block.timestamp / settings.REWARD_FREQUENCY());

        for (uint index = 0; index < count; index++) {
            uint current = counter + index;
            settlements[current] = Settlement(true, _settlementType, _account, 0, 0, day, 0, block.timestamp, current);
            account.score += settlementType.multiplier;
            userSettlements[_account].push(current);
        }

        counter += count;
        account.count += count;
        if (account.claimedAt == 0) account.claimedAt = block.timestamp;
        accounts[_account] = account;
        emit Settle(_account, _settlementType, count);
    }

    function _claim(
        address _account, 
        bool _compound
    ) 
        internal 
        returns (uint256 rewards) 
    {
        require(_account != address(0), 'Null address is not allowed');
        require(accounts[_account].exists, 'Account does not exist yet');
        require(block.timestamp - accounts[_account].claimedAt > settings.claimCooldown(), 'Claim still on cooldown');
    
        Account memory account = accounts[_account];
        (Settlement[] memory _settlements, uint count) = getSettlements(_account);

        uint interval = uint(block.timestamp / settings.REWARD_FREQUENCY());
        for (uint256 index = 0; index < count; index++) {
            Settlement memory sett = _settlements[index];
            uint reward = rewardsOfId(sett.id);
            rewards += reward;

            sett.paidOut += reward;
            sett.lastClaimed = interval;
            settlements[sett.id] = sett;
        }

        if (rewards > 0) {
            if (!_compound) {
                uint fee = rewards * settings.claimFee() / 10000;
                rewards = rewards - fee;
                stlr.transfer(settings.treasury(), fee);
                stlr.transfer(_account, rewards);
            }

            account.paidOut += rewards;
            account.claimedAt = block.timestamp;

            accounts[_account] = account;
        }
    }

    /** EXTERNAL FUNCTIONS */

    function declare(
        address account,
        uint _faction
    ) 
        external 
        onlyManager
    {
        require(factions[_faction], 'Faction does not exist');
        require(!accounts[account].exists, 'Account already exists');
        accounts[account] = Account(true, _faction, 0, 0, 0, 0, 0);
        factionUsers[_faction].push(account);
    }

    function settle(
        address account,
        uint _settlementType, 
        uint count
    ) 
        external 
        onlyManager
    {
        _create(account, _settlementType, count);
    }

    function claim(
        address account,
        bool _compound
    ) 
        external 
        onlyManager
        returns (uint rewards)
    {
        rewards = _claim(account, _compound);
    }

    function compound(
        address account,
        uint _settlementType,
        uint count,
        uint fee,
        uint refund
    )
        external
        onlyManager
    {
        _create(account, _settlementType, count);
        if (fee > 0) stlr.transfer(settings.treasury(), fee);
        if (refund > 0) stlr.transfer(account, refund);
    }

    /** RESTRICTED FUNCTIONS */

    function setSettlementSkin(
        address _account,
        uint id,
        uint skin
    )
        external
        onlyOperator(msg.sender)
    {
        require(accounts[_account].exists, 'Account does not exist');
        require(settlements[id].account == _account, 'Accounts do not match');
        Settlement memory settlement = settlements[id];
        settlement.skin = skin;
        settlements[id] = settlement;
    }

    function setSettlementBoost(
        address _account, 
        uint id, 
        uint boost
    ) 
        external 
        onlyOperator(msg.sender) 
    {
        require(id < counter, 'Invalid id');
        require(settlements[id].account == _account, 'Accounts do not match');
        Settlement memory settlement = settlements[id];
        settlement.boost = boost;
        settlements[id] = settlement;
    }

    function setAccountBoost(
        address _account, 
        uint boost
    ) 
        external 
        onlyOperator(msg.sender) 
    {
        require(accounts[_account].exists, 'Account does not exist');
        Account memory account = accounts[_account];
        account.boost = boost;
        accounts[_account] = account;
    }

    function transferSettlement(
        uint id, 
        address _sender, 
        address _recipient
    ) 
        external 
        onlyOperator(msg.sender) 
    {
        require(accounts[_sender].exists && accounts[_recipient].exists, 'Accounts do not exist');
        require(_sender != _recipient, 'Invalid recipient');
        require(id < counter, 'Invalid id');
        require(settlements[id].account == _sender, 'Accounts do not match');
        Account memory sender = accounts[_sender];
        Account memory recipient = accounts[_recipient];
        Settlement memory settlement = settlements[id];
        uint multiplier = settlementTypes[settlement.settlementType].multiplier;
        settlement.account = _recipient;
        sender.count -= 1;
        sender.score -= multiplier;
        recipient.count += 1;
        recipient.score += multiplier;
        userSettlements[_recipient].push(id);
        _remove(_sender, id);
        settlements[id] = settlement;
        accounts[_sender] = sender;
        accounts[_recipient] = recipient;
        emit Transfer(_sender, _recipient, id);
    }

    function mint(
        address _account, 
        uint _settlementType, 
        uint count
    ) 
        external 
        onlyOperator(msg.sender) 
    {
        _create(_account, _settlementType, count);
    }

    /** OWNER FUNCTIONS */

    function setSettlementType(
        uint index, 
        bool _active, 
        uint _multiplier, 
        uint _stlr, 
        uint _usdc
    ) 
        external 
        onlyOwner 
    {
        require(index >= 0 && index <= settCount, 'Invalid settlement type');
        settlementTypes[index] = SettlementType(_active, _multiplier, _stlr, _usdc);
        if (index == settCount) {
            settCount = index + 1;
        }
    }

    function setSettings(
        address _settings
    ) 
        external 
        onlyOwner 
    {
        require(_settings != address(0), 'Settings is null address');
        settings = ISTLRSettingsV1(_settings);
    }

    function transfer(
        address token, 
        uint amount
    ) 
        external 
        onlyOwner 
    {
        require(settings.treasury() != address(0), 'Treasury is null address');
        IERC20(token).transfer(settings.treasury(), amount);
    }

    /** MODIFIERS */

    modifier whenNotPaused(
    ) {
        require(!settings.paused(), 'Contract is paused');

        _;
    }

    modifier onlyOperator(
        address operator
    ) {
        require(settings.isOperator(operator), 'NOT_OPERATOR');

        _;
    }

    modifier onlyManager(
    ) {
        require(msg.sender == settings.manager(), 'NOT_MANAGER');

        _;
    }

    /** EVENTS */

    event Settle(address account, uint settlementType, uint count);
    event Transfer(address sender, address recipient, uint id);
}