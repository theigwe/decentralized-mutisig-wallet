// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.8.0;

interface IOwnable {
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event OwnershipRenounced(address indexed renouncedOwner);

  function owner() external view returns (address);

  function transferOwnership(address newOwner) external returns(bool transfered);

  function renounceOwnership() external returns(bool renounced);
}