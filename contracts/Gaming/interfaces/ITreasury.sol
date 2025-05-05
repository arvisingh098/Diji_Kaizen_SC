// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface ITreasury{
     function isRoleAdmin(address account) external view returns (bool);
}