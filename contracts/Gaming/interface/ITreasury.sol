// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ITreasury{
     function isRoleAdmin(address account) external view returns (bool);
}