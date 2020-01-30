pragma solidity ^0.5.13;

import "../Vesting.sol";

contract VestingMock is Vesting {
    TrustToken mockTrustToken;
    constructor(TrustToken trustToken) public {
        mockTrustToken = trustToken;
    }
    function token() internal view returns (TrustToken) {
        return mockTrustToken;
    }
}
