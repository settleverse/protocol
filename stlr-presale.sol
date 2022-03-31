// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/Address.sol";
import "./access/Ownable.sol";
import "./security/ReentrancyGuard.sol";
import "./token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/ISTLRSettingsV1.sol";
import "./interfaces/ISTLRDaoV1.sol";

contract SettleversePresale is Ownable, ReentrancyGuard {
    ISTLRSettingsV1 public immutable settings;
    IERC20Metadata public immutable usdc;
    
    uint public start;
    uint public duration;
    uint public end;
    PresaleStatus public status;
    uint public max;
    uint public cap;
    uint public raised;
    uint public count;
    bool public openForPublic;

    enum PresaleStatus {
        NotLive,
        Live,
        Concluded
    }

    struct Account {
        uint deposited;
        uint count;
        bool claimed;
    }

    mapping(address => Account) public accounts;
    mapping(address => uint[]) public settlements;
    mapping(address => bool) private _whitelisted;
    uint[] public costs;

    constructor (
        address _settings,
        uint _start,
        uint _duration,
        uint _max,
        uint _cap
    ) {
        settings = ISTLRSettingsV1(_settings);
        usdc = IERC20Metadata(settings.USDC());
        start = _start;
        duration = _duration;
        end = start + duration;
        max = _max * 10 ** usdc.decimals();
        cap = _cap * 10 ** usdc.decimals();
        costs = [50, 125, 350, 1000, 4500];
    }

    /** VIEW FUNCTIONS */

    function isWhitelisted(
        address account
    ) 
        public 
        view 
        returns (bool) 
    {
        return _whitelisted[account];
    }

    /** INTERNAL FUNCTIONS */

    function _whitelist(
        address account, 
        bool _status
    ) 
        internal 
    {
        _whitelisted[account] = _status;
    }

    /** EXTERNAL FUNCTIONS */

    function enter(
        uint[] memory types
    ) 
        external 
        nonReentrant 
    {
        require(status != PresaleStatus.Concluded, "CONCLUDED");
        require(block.timestamp >= start &&
            block.timestamp < end, "NOT LIVE");

        if (status != PresaleStatus.Live) {
            status = PresaleStatus.Live;
            emit PresaleOpened();
        }

        if (!openForPublic) {
            require(isWhitelisted(msg.sender), "NOT WHITELISTED");
        }
        
        uint cost;
        for (uint256 index = 0; index < types.length; index++) {
            cost += costs[types[index]] * 10 ** usdc.decimals();
        }

        require(raised + cost <= cap, "OVER CAP");
        require(accounts[msg.sender].deposited + cost <= max, "OVER MAX");
        require(usdc.balanceOf(msg.sender) >= cost, "BALANCE");

        accounts[msg.sender].deposited += cost;
        raised += cost;
        for (uint256 index = 0; index < types.length; index++) {
            settlements[msg.sender].push(types[index]);
        }
        accounts[msg.sender].count += types.length;
        count += types.length;

        usdc.transferFrom(msg.sender, address(this), cost);
        emit Entered(msg.sender, cost, types.length);
    }

    function claim(
    ) 
        external 
        nonReentrant 
    {
        require(status == PresaleStatus.Concluded, "NOT CONCLUDED");
        require(accounts[msg.sender].deposited > 0, "NOT INVESTED");
        require(!accounts[msg.sender].claimed, "CLAIMED");

        uint[] memory counts = new uint[](5);
        for (uint256 index = 0; index < settlements[msg.sender].length; index++) {
            counts[settlements[msg.sender][index]]++;
        }

        accounts[msg.sender].claimed = true;
        uint total;
        for (uint256 index = 0; index < counts.length; index++) {
            if (counts[index] == 0) continue;
            total += counts[index];
            ISettleverseDao(settings.dao()).mint(msg.sender, index, counts[index]);
        }
        emit Claimed(msg.sender, total);
    }

    /** RESTRICTED FUNCTIONS */

    function close(
    ) 
        external 
        onlyOwner 
    {
        require(settings.dao() != address(0), "DAO");
        require(settings.treasury() != address(0), "TREASURY");
        status = PresaleStatus.Concluded;
        uint balance = usdc.balanceOf(address(this));
        usdc.transfer(settings.treasury(), balance);
        emit PresaleClosed();
    }

    function allowPublic(
    ) 
        external 
        onlyOwner 
    {
        openForPublic = true;
    }

    function withdraw(
    ) 
        external 
        onlyOwner 
    {
        require(status == PresaleStatus.Concluded, "NOT CONCLUDED");

        uint balance = address(this).balance;
        if (balance > 0) {
            Address.sendValue(payable(settings.treasury()), balance);
            emit Withdrawn(balance);
        }
    }

    function withdraw(
        address token
    ) 
        external 
    {
        require(status == PresaleStatus.Concluded, "NOT CONCLUDED");

        uint balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).transfer(settings.treasury(), balance);
            emit Withdrawn(token, balance);
        }
    }

    function setWhitelist(
        address account, 
        bool _status
    ) 
        external 
        onlyOwner 
    {
        _whitelist(account, _status);
    }

    function setWhitelistBatch(
        address[] memory _accounts
    ) 
        external 
        onlyOwner 
    {
        require(status != PresaleStatus.Concluded, "CONCLUDED");
        for (uint256 index = 0; index < _accounts.length; index++) {
            _whitelist(_accounts[index], true);
        }
    }

    function setPresaleTime(
        uint _start, 
        uint _duration
    ) 
        external 
        onlyOwner 
    {
        require(status == PresaleStatus.NotLive, "LIVE");
        start = _start;
        duration = _duration;
        end = start + duration;
        emit PresaleTimeSet(start, duration, end);
    }

    function setPresaleLimits(
        uint _max, 
        uint _cap
    ) 
        external 
        onlyOwner 
    {
        require(status == PresaleStatus.NotLive, "LIVE");
        max = _max * 10 ** usdc.decimals();
        cap = _cap * 10 ** usdc.decimals();
    }

    event Entered(address account, uint cost, uint count);
    event Claimed(address account, uint count);
    event PresaleOpened();
    event PresaleClosed();
    event Withdrawn(uint amount);
    event Withdrawn(address token, uint amount);
    event PresaleTimeSet(uint start, uint duration, uint end);
    event PresaleLimitSet(uint max, uint cap);
}