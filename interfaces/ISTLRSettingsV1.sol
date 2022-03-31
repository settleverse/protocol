// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISTLRSettingsV1 {
    function STLR() external view returns (address);
    function USDC() external view returns (address);

    function dao() external view returns (address);
    function manager() external view returns (address);
    function treasury() external view returns (address);
    function helper() external view returns (address);
    function presale() external view returns (address);
    function paused() external view returns (bool);

    function isOperator(address) external view returns (bool);
    function isExemptFromFee(address) external view returns (bool);
    function isMarketPair(address) external view returns (bool);

    function baseRewardFee() external view returns (uint);
    function maxRewardFee() external view returns (uint);
    function claimFee() external view returns (uint);
    function claimCooldown() external view returns (uint);
    function interestRate() external view returns (uint);
    function maxRotCount() external view returns (uint);
    function rotDeduction() external view returns (uint);
    function farmingClaimCooldown() external view returns (uint);
    function farmingWithdrawDelay() external view returns (uint);

    function transferLimit() external view returns (uint);
    function walletMax() external view returns (uint);
    function feeOnTransfer() external view returns (bool);

    function REWARD_FREQUENCY() external view returns (uint);
    function BASE_DENOMINATOR() external view returns (uint);
    function MAX_SETTLEMENTS() external view returns (uint);
    function LOCKED_PERCENT() external view returns (uint);
    function SELL_FEE() external view returns (uint);
}