//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title JilaiAirdrop
 * @dev Airdrop contract for distributing JilaiToken to multiple addresses.
 */
contract JilaiAirdrop is Initializable, OwnableUpgradeable, UUPSUpgradeable {
   IERC20 public token;

   event Airdrop(
        address indexed caller,
        address[] recipients,
        uint256[] amounts
    );

    /**
     * @notice Disables initializers to prevent contract from being initialized again.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Initializes the contract, setting the deployer as the owner.
     */
    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

     /**
     * @notice Sets the token contract address to be used for the airdrop.
     * @dev Restricted to the contract owner.
     * @param _token Address of the JilaiToken contract.
     */
    function setToken(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
    }

    /**
     * @notice Distributes tokens to multiple addresses.
     * @dev Restricted to the contract owner. Requires sufficient token balance and allowance.
     * @param recipients Array of addresses to receive tokens.
     * @param amounts Array of token amounts to send to each recipient.
     */
    function airdrop(
        address[] calldata recipients, 
        uint256[] calldata amounts
        ) external onlyOwner {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        require(address(token) != address(0), "Token not set");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            require(amounts[i] > 0, "Amount must be greater than 0");
            require(token.transferFrom(msg.sender, recipients[i], amounts[i]), "Transfer failed");
        }
        emit Airdrop(msg.sender, recipients, amounts);
    }
}