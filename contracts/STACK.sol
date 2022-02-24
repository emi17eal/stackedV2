//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol';
import './libraries/LowGasSafeMath.sol';
import './types/VaultOwned.sol';


contract StackToken is ERC20Permit, VaultOwned {

    using LowGasSafeMath for uint256;

    uint public transferTax;  // 5000 = 5%
    address public taxAddress;

    constructor() 
    ERC20('StackToken', 'STACK', 9)
    ERC20Permit('StackToken') {
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if (transferTax == 0) {
            _transfer(msg.sender, recipient, amount);
        }
        else {
            uint tax = (amount * transferTax)/1e5;
            _transfer(msg.sender, taxAddress, tax);
            _transfer(msg.sender, recipient, amount - tax);
        }
        // uint amount_ = transferTax == 0 ? amount : (amount * transferTax)/1e5; 
        return true;   
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        if (transferTax == 0) {
            _transfer(sender, recipient, amount);
        }
        else {
            uint tax = (amount * transferTax)/1e5;
            _transfer(sender, taxAddress, tax);
            _transfer(sender, recipient, amount - tax);
        }
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender] -= amount
        );
        return true;
    }

    // MAKE SURE VAULT ONLY
    function mint(address account_, uint256 amount_) external onlyVault {
        _mint(account_, amount_);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account_, uint256 amount_) external {
        _burnFrom(account_, amount_);
    }

    function _burnFrom(address account_, uint256 amount_) internal {
        uint256 decreasedAllowance_ = 
            allowance(account_, msg.sender).sub(amount_);

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }

    function setTax (uint _tax) external onlyOwner {
        transferTax = _tax;
    }

    function setTaxAddress (address _taxAddress) external onlyOwner {
        taxAddress = _taxAddress;
    }
}