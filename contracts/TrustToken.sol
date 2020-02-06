pragma solidity ^0.5.13;

import "./ClaimableContract.sol";
import "./ValTokenWithHook.sol";


contract TrustToken is ValTokenWithHook, ClaimableContract {
    function decimals() public pure returns (uint8) {
        return 8;
    }
    function rounding() public pure returns (uint8) {
        return 8;
    }
    function name() public pure returns (string memory) {
        return "TrustToken";
    }
    function symbol() public pure returns (string memory) {
        return "TRUST";
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}
