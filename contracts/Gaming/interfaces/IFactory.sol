// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IFactory{
     function acceptedToken() external view returns (address[] memory);
     function treasuryContract() external view returns(address);
     function itemNFTContract() external view returns(address);
     function soulStakingContract() external view returns(address);
     function bakaBearNFTContract() external view returns(address);
     function minimumCorruptionBribe() external view returns(uint256);
     function minimumVotingDirectionBribe() external view returns(uint256);


}