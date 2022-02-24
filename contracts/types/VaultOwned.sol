//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';

contract VaultOwned is Ownable {
  
  address internal _vault;

  event VaultTransferred(address indexed newVault);

  function setVault( address vault_ ) external onlyOwner() {
    require(vault_ != address(0), "IA0");
    _vault = vault_;
    emit VaultTransferred( _vault );
  }

  function vault() public view returns (address) {
    return _vault;
  }

  modifier onlyVault() {
    require( _vault == msg.sender, "VaultOwned: caller is not the Vault" );
    _;
  }

}
