pragma solidity ^0.5.13;

interface TradeExecutor {
    function info() external view returns (uint256 compatibilityID, uint256 inputToken, uint256 inputAmount, uint256 outputAmount);
    function execute() external returns (uint256 inputConsumed, uint256 outputAmount);
}

contract Liquidator {
    mapping (address => uint256) attributes;
    /**
        We STATICCALL into orders to invoke them
        orders execute and return some amount or zero
        Invariant: only one offer per compatibilityID
        Invariant: orders are sorted by greatest output amount
    */
    TradeExecutor[] offers;

    uint256 constant LIQUIDATOR_CAN_RECEIVE     = 0xff00000000000000000000000000000000000000000000000000000000000000;
    uint256 constant LIQUIDATOR_CAN_RECEIVE_INV = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    function reclaim(uint256 _debt, address _destination) external {
        require(attributes[_destination] & LIQUIDATOR_CAN_RECEIVE != 0);
        for (uint256 i = offers.length; i --> 0;) {
            (bool success, bytes memory output) = address(offers[i]).delegatecall(abi.encode(bytes4(0x61461954))); // execute()
            if (!success) {
                continue;
            }
            (uint256 inputConsumed, uint256 outputConsumed) = abi.decode(output, (uint256, uint256));
        }
    }

    function registerAirswap(uint256 expiry, address counterparty, address inputToken, uint256 inputAmount, uint256 outputAmount, bytes32 r, bytes32 s, bytes32 v) external {
        // TODO
    }

    function registerUniswap(address _intermediary) external {
        // TODO
    }
}
