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
    uint256 constant MAX_UINT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /**
    * @dev the constructor sets the original owner of the contract to the sender account.
    */
    constructor() public {
        _setUpgradeabilityOwner(msg.sender);
        expiration = MAX_UINT;
    }

    /**
     *
    */
    function setExpiration(uint256 _newTimestamp) external onlyProxyOwner {
        expiration = _newTimestamp;
    }

    /**
    * @dev Allows the proxy owner to upgrade the current version of the proxy.
    * @param implementation representing the address of the new implementation to be set.
    */
    function upgradeTo(address implementation) public onlyProxyOwner {
        if (block.timestamp < expiration) {
            super.upgradeTo(implementation);
        }
        else {
            revert("Proxy has passed upgrade expiration time");
        }
    }  
  }
