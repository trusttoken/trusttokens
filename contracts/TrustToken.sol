pragma solidity ^0.5.13;

import "./ClaimableContract.sol";
import "./ValTokenWithHook.sol";


/**
 * @title TrustToken
 * @dev The TrustToken contract is a claimable contract where the 
 * owner can only mint or transfer ownership. TrustTokens use 8 decimals
 * in order to prevent rewards from getting stuck in the remainder on division.
 * Tolerates dilution to slash stake and accept rewards.
 */
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
        return "TRU";
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}
