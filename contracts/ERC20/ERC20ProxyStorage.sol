pragma solidity ^0.5.13;

/**
 * All storage must be declared here
 * New storage must be appended to the end
 * Never remove items from this list
 */
contract ERC20ProxyStorage {
    uint256 constant MAX_SUPPLY = 145000000000000000;
    bool initalized = false;

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;
    uint256 _totalSupply;

    address owner_;
    address pendingOwner_;
}
