pragma solidity 0.5.13;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

/**
 * @title Liquidator Interface
 * @dev Liquidate stake token for reward token
 */
contract ILiquidator {

    /** @dev Get output token (token to get from liquidation exchange). */
    function outputToken() internal view returns (IERC20);

    /** @dev Get stake token (token to be liquidated). */
    function stakeToken() internal view returns (IERC20);

    /** @dev Address of staking pool. */
    function pool() internal view returns (address);

    /**
     * @dev Transfer stake without liquidation
     */
    function reclaimStake(address _destination, uint256 _stake) external;

    /**
     * @dev Award stake tokens to stakers
     * Transfer to the pool without creating a staking position
     * Allows us to reward as staking or reward token
     */
    function returnStake(address _from, uint256 balance) external;

    /**
     * @dev Sells stake for underlying asset and pays to destination.
     */
    function reclaim(address _destination, int256 _debt) external;
}
