pragma solidity ^0.5.13;

import { ERC20ProxyStorage } from "./ERC20ProxyStorage.sol";

/**
 * @title ClaimableContract
 * @dev The ClaimableContract contract is a copy of Claimable Contract by OpenZeppelin.. 
 and provides basic authorization control functions. Inherits storage layout of 
 ERC20ProxyStorage.
 */
contract ClaimableERC20 is ERC20ProxyStorage {

    function owner() public view returns (address) {
        return owner_;
    }

    function pendingOwner() public view returns (address) {
        return pendingOwner_;
    }

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
    * @dev sets the original `owner` of the contract to the sender
    * at construction. Must then be reinitialized 
    */
    constructor() public {
        owner_ = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyOwner() {
        require(msg.sender == owner_, "only owner");
        _;
    }

    /**
    * @dev Modifier throws if called by any account other than the pendingOwner.
    */
    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner_ , "only pending owner");
        _;
    }

    /**
    * @dev Allows the current owner to set the pendingOwner address.
    * @param newOwner The address to transfer ownership to.
    */
    function transferOwnership(address newOwner) public onlyOwner {
        pendingOwner_ = newOwner;
    }

    /**
    * @dev Allows the pendingOwner address to finalize the transfer.
    */
    function claimOwnership() public onlyPendingOwner {
        emit OwnershipTransferred(owner_, pendingOwner_);
        owner_ = pendingOwner_;
        pendingOwner_ = address(0);
    }
}