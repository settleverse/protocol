// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISettleverseDao {
    function treasury() external view returns (address);
    function settings() external view returns (address);
    function settlementTypes(uint) external view returns (bool, uint, uint, uint);
    function accounts(address) external view returns (bool, uint, uint, uint, uint, uint, uint);

    function declare(address, uint) external;
    function settle(address, uint, uint) external;
    function claim(address, bool) external returns (uint);
    function compound(address, uint, uint, uint, uint) external;
    function mint(address, uint, uint) external;
}