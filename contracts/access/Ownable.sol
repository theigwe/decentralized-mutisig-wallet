// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.8.0;

import "../interfaces/IOwnable.sol";

abstract contract Ownable is IOwnable {
  
  address __owner;

  modifier isOwner() {
    require(__owner == msg.sender, "Is not contract owner.");
    _;
  }

  constructor () {
    __owner = msg.sender;
  }

  function owner() public view override returns(address) {
    return __owner;
  }

  function transferOwnership(address _owner) public override isOwner returns(bool transfered) {
    require(__owner != _owner, "Same owner not allowed.");
    __owner = _owner;
    transfered = true;
    emit OwnershipTransferred(msg.sender, _owner);
  }

  function renounceOwnership() public override isOwner returns(bool renounced) {
    __owner = address(0);
    renounced = true;
    emit OwnershipRenounced(msg.sender);
  }
}