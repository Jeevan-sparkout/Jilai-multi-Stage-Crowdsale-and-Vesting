//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

    /**
     * @title JilaiToken
     * @dev ERC20 token with upgradeability and ownable functionality using OpenZeppelin libraries.
    */
contract JilaiToken is Initializable, ERC20Upgradeable, OwnableUpgradeable , UUPSUpgradeable{
    /**
     * @notice Disables initializers to prevent contract from being initialized again.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(){
        _disableInitializers();
    }

    /**
     * @notice Initializes the token with a given initial supply.
     * @dev Mints `initialSupply` tokens to the deployer's address.
     * @param initialSupply The amount of tokens to mint initially.
     */
    function initialize (uint256 initialSupply) public initializer {
        __ERC20_init("JILAI", "JIL.AI");
        __Ownable_init();
        __UUPSUpgradeable_init();
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Burns a specified amount of tokens from the caller's balance.
     * @dev Reduces the total supply by `amount`.
     * @param amount The number of tokens to burn.
     */
    function burn(uint256 amount) public {
        _burn (msg.sender, amount);
    }
    
    /**
     * @notice Authorizes an upgrade to a new contract implementation.
     * @dev Restricted to only the contract owner.
     * @param newImplementation Address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}