// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./token/ERC20/ERC20.sol";

contract SettleverseUSDC is ERC20 {
    constructor() ERC20('MockUSDC', 'sUSDC') {
        _mint(msg.sender, 2500000 * 10 ** 6);
    }

    /** ERC20 FUNCTIONS */

    function decimals() public pure override (ERC20) returns (uint8) {
        return 6;
    }
}