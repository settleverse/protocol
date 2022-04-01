// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/Address.sol";
import "./access/Ownable.sol";
import "./token/ERC20/ERC20.sol";

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/ISTLRSettingsV1.sol";

contract STLRPurchaseHelperV1 is Ownable {
    ISTLRSettingsV1 public settings;
    IERC20Metadata public immutable stlr;
    IERC20Metadata public immutable usdc;

    IUniswapV2Factory public immutable factory;
    IUniswapV2Router02 public immutable router;
    IUniswapV2Pair public immutable pair;

    bool public isZapEnabled = true;

    constructor(
        address _settings,
        address _router
    ) {
        settings = ISTLRSettingsV1(_settings);
        
        stlr = IERC20Metadata(settings.STLR());
        usdc = IERC20Metadata(settings.USDC());

        // BSC TESTNET ROUTER: 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
        // FANTOM TESTNET ROUTER: 0xa6AD18C2aC47803E193F75c3677b14BF19B94883
        router = IUniswapV2Router02(_router);
        factory = IUniswapV2Factory(router.factory());
        if (factory.getPair(address(stlr), address(usdc)) == address(0)) {
            factory.createPair(address(stlr), address(usdc));
        }
        pair = IUniswapV2Pair(factory.getPair(address(stlr), address(usdc)));
    }

    function zapLiquidity(
        uint256 _usdcAmount
    ) 
        external 
        returns (uint256) 
    {

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(stlr);

        usdc.transferFrom(msg.sender, address(this), _usdcAmount);
        usdc.approve(address(router), _usdcAmount);
        router.swapExactTokensForTokens(
            _usdcAmount / 2, 
            0, 
            path,
            address(this),
            block.timestamp + 120
        );

        uint _stlr = stlr.balanceOf(address(this));
        uint _usdc = usdc.balanceOf(address(this));
        stlr.approve(address(router), _stlr);
        usdc.approve(address(router), _usdc);
        
        (, , uint liquidity) = router.addLiquidity(
            address(stlr),
            address(usdc),
            _stlr,
            _usdc,
            0,
            0,
            msg.sender,
            block.timestamp + 120
        );

        return liquidity;
    }

    function unzapLiquidity(
        uint256 _amount
    ) 
        public 
        returns (uint256, uint256) 
    {
        return router.removeLiquidity(
            address(stlr),
            address(usdc),
            _amount,
            0,
            0,
            msg.sender,
            block.timestamp + 120
        );
    }

    function getTotalSupply(
    ) 
        public 
        view 
        returns (uint256) 
    {
        return stlr.totalSupply() / 10**stlr.decimals();
    }

    function getFDV(
    ) 
        public 
        view 
        returns (uint256) 
    {
        return getUSDCForOneStlr() * getTotalSupply();
    }

    function calculateLiquidityRatio(
    ) 
        external 
        view 
        returns (uint256) 
    {
        uint256 usdcReserves = getUSDCReserve();
        uint256 fdv = getFDV();
        return usdcReserves * 1e4 / fdv;
    }

    function getUSDCReserve(
    ) 
        public 
        view 
        returns (uint256) 
    {
        (uint token0Reserve, uint token1Reserve,) = pair.getReserves();
        if (pair.token0() == address(usdc)) {
            return token0Reserve;
        }
        return token1Reserve;
    }

    function getUSDCForOneLP(
    ) 
        external 
        view 
        returns (uint256) 
    {
        uint256 lpSupply = pair.totalSupply();
        uint256 totalReserveInUSDC = getUSDCReserve() * 2;
        return totalReserveInUSDC * 10 ** pair.decimals() / lpSupply;
    }

    function getLPFromUSDC(
        uint256 _amount
    ) 
        external 
        view 
        returns (uint256) 
    {
        uint256 lpSupply = pair.totalSupply();
        uint256 totalReserveInUSDC = getUSDCReserve() * 2;
        return _amount * lpSupply / totalReserveInUSDC;
    }

    function getStlrforUSDC(
    ) 
        external 
        view 
        returns (uint256) 
    {
        address[] memory path = new address[](2);
        path[0] = address(stlr);
        path[1] = address(usdc);
        uint256[] memory amountsOut = router.getAmountsIn(10 ** usdc.decimals(), path);
        return amountsOut[0];
    }

    function getUSDCForStlr(
        uint256 _amount
    ) 
        public 
        view 
        returns (uint256) 
    {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(stlr);
        uint256[] memory amountsOut = router.getAmountsIn(_amount, path);
        return amountsOut[0];
    }

    function getUSDCForOneStlr(
    ) 
        public 
        view 
        returns (uint256) 
    {
        return getUSDCForStlr(10 ** stlr.decimals());
    }

    /** OWNER FUNCTIONS */

    function setSettings(
        address _settings
    ) 
        external 
        onlyOwner 
    {
        require(_settings != address(0), 'Settings is null address');
        settings = ISTLRSettingsV1(_settings);
    }
    
    function setZapEnabled(
        bool status
    ) 
        external 
        onlyOwner 
    {
        isZapEnabled = status;
        emit ZapEnabledSet(status);
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

    function recover(
    ) 
        external 
        onlyOwner 
    {
        uint balance = address(this).balance;
        Address.sendValue(payable(owner()), balance);
        emit Recovered(balance);
    }

    /** EVENTS */

    event ZapEnabledSet(bool status);
    event Recovered(address token, uint amount);
    event Recovered(uint amount);
}