pragma solidity ^0.5.13;

import { ERC20 } from "./ERC20/StandardERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/**
 * @title TrustToken
 * @dev The TrustToken contract is a claimable contract where the
 * owner can only mint or transfer ownership. TrustTokens use 8 decimals
 * in order to prevent rewards from getting stuck in the remainder on division.
 * Tolerates dilution to slash stake and accept rewards.
 */
contract TrustToken is ERC20 {
    using SafeMath for uint256;
    /**
     * @dev initialize trusttoken and give ownership to sender
     * This is necessary to set ownership for proxy
     */
    function initialize() public {
        require(!initalized, "already initalized");
        owner_ = msg.sender;
    }

    /**
     * @dev mint TRU
     * Can never mint more than MAX_SUPPLY = 1.45 billion
     */
    function mint(address _to, uint256 _amount) external onlyOwner {
        if (_totalSupply.add(_amount) <= MAX_SUPPLY) {
            _mint(_to, _amount);
        }
        else {
            revert("Max supply exceeded");
        }
    }

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
}
