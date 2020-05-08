pragma solidity ^0.5.13;

import "./Unlock.sol";

contract TrustTokenVault is Vault {
    TrustToken trustToken;

    constructor(TrustToken _trustToken) public {
        trustToken = _trustToken;
    }

    function token() internal view returns (TrustToken) {
        return trustToken;
    }
}

contract UnlockTrustTokens is Unlock {
    TrustTokenVault trustTokenVault;

    constructor(TrustTokenVault _trustTokenVault) public {
        trustTokenVault = _trustTokenVault;
    }

    function vault() internal view returns (Vault) {
        return trustTokenVault;
    }
}
