pragma solidity ^0.5.13;

import { OwnedUpgradeabilityProxy } from "./OwnedUpgradeabilityProxy.sol";

/**
 * @title TimeOwnedUpgradeabilityProxy
 * @dev This contract combines an upgradeability proxy with 
 * basic authorization control functionalities
 *
 * This contract allows us to specify a time at which the proxy can no longer
 * be upgraded
 */
contract TimeOwnedUpgradeabilityProxy is OwnedUpgradeabilityProxy {

    uint256 expiration;

    /**
    * @dev the constructor sets the original owner of the contract to the sender account.
    */
    constructor() public {
        _setUpgradeabilityOwner(msg.sender);
        // set expiration to ~4 months from now
        expiration = block.timestamp + 124 days;
    }

    /**
     * @dev extends expiration ~4 months
    */
    function extendExpiration() external onlyProxyOwner {
        require (block.timestamp < expiration, "after expration date");
        expiration = expiration + 124 days;
    }

    /**
    * @dev Allows the proxy owner to upgrade the current version of the proxy.
    * @param implementation representing the address of the new implementation to be set.
    */
    function upgradeTo(address implementation) public onlyProxyOwner {
        require (block.timestamp < expiration, "after expration date");
        super.upgradeTo(implementation);
    }
  }