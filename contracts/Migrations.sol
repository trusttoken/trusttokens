pragma solidity ^0.5.13;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

// This is a truffle contract, needed for truffle integration.
contract Migrations is Ownable {
    uint256 public lastCompletedMigration;

    function setCompleted(uint _completed) public onlyOwner {
        lastCompletedMigration = _completed;
    }

    function upgrade(address _newAddress) public onlyOwner {
        Migrations upgraded = Migrations(_newAddress);
        upgraded.setCompleted(lastCompletedMigration);
    }
}
