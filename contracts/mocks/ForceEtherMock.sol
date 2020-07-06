// SPDX-License-Identifier: MIT
pragma solidity 0.6.10;

contract ForceEther {
    constructor() public payable { }

    function destroyAndSend(address payable _recipient) public {
        selfdestruct(_recipient);
    }
}
