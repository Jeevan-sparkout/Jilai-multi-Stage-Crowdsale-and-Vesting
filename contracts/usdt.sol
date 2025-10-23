//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract USDToken is Initializable, ERC20Upgradeable, OwnableUpgradeable , UUPSUpgradeable{

    ///@custom:oz-upgrades-unsafe-allow constructor
    constructor(){
        _disableInitializers();
    }
    function initialize (uint256 initialSupply) public initializer {
        __ERC20_init("USDToken", "USDT");
        __Ownable_init();
        __UUPSUpgradeable_init();
        _mint(msg.sender, initialSupply);
    }
    function burn(uint256 amount) public {
        _burn (msg.sender, amount);
    }
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
