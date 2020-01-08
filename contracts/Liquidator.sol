pragma solidity ^0.5.13;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

interface TradeExecutor {
    function info() external view returns (uint256 compatibilityID, uint256 inputToken, uint256 inputAmount, uint256 outputAmount);
    function execute(uint256 maxInput) external returns (uint256 inputToken, uint256 inputConsumed, uint256 outputAmount);
}
interface Uniswap {
    function tokenToTokenSwap(uint256 inputAmount, uint256 maxOutputAmount) external returns (uint256 outputAmount);
}
interface UniswapFactory {
    function getExchange(IERC20 input, IERC20 output) external returns (Uniswap);
}

contract Liquidator {
    mapping (address => uint256) attributes;
    /**
        We STATICCALL into orders to invoke them
        orders execute and return some amount or zero
        Invariant: only one offer per compatibilityID
        Invariant: orders are sorted by greatest output amount
    */
    TradeExecutor[][] offers;
    IERC20[] tokens;
    address[] stakedAssets;

    uint256 constant LIQUIDATOR_CAN_RECEIVE     = 0xff00000000000000000000000000000000000000000000000000000000000000;
    uint256 constant LIQUIDATOR_CAN_RECEIVE_INV = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    function uniswapFactory() internal view returns (UniswapFactory);
    function outputToken() internal view returns (IERC20);

    function reclaim(uint256 _debt, address _destination) external {
        require(attributes[_destination] & LIQUIDATOR_CAN_RECEIVE != 0);
        for (uint256 i = offers.length; i --> 0;) {
            // XXX
            (bool success, bytes memory output) = address(offers[i][0]).delegatecall(abi.encodeWithSelector(bytes4(0x61461954))); // execute()
            if (!success) {
                continue;
            }
            (uint256 inputToken, uint256 inputConsumed, uint256 outputConsumed) = abi.decode(output, (uint256, uint256, uint256));
        }
    }

    function registerAirswap(uint256 _expiry, address _counterparty, uint256 _nonce, address _inputToken, uint256 _inputAmount, uint256 _outputAmount, bytes32 _r, bytes32 _s, bytes32 _v) external {
        uint256 compatibilityID = uint256(_nonce) ^ (uint256(_counterparty) << 96);
        // TODO
    }

    function registerIntermediaryUniswap(IERC20 _inputToken, IERC20 _intermediaryToken) external {
        Uniswap uniswap = uniswapFactory().getExchange(_inputToken, _intermediaryToken);
        _inputToken.approve(address(uniswap), 0xff00000000000000000000000000000000000000000000000000000000000000);
        uint256 compatibilityID = uint256(address(_intermediaryToken)) ^ (uint256(address(_inputToken)) << 96);
        // TODO
    }

    struct TokenState {
        IERC20 token;
        address stakedAsset;
        uint256 remainingInput;
        Uniswap directUniswap;
        uint256 uniswapOutputLiquidity;
        uint256 uniswapInputLiquidity;
        uint256 cumulativeOutput;
    }
    /**
        Remove all orders that would fail
        Remove all orders worse than what is available in uniswap
    */
    function prune() external {
        uint256 offersLength = offers.length;
        uint256 tokensLength = tokens.length;
        TokenState[] memory tokenState = new TokenState[](tokensLength);
 
        for (uint256 i = tokensLength; i --> 0;) {
            tokenState[i].token = tokens[i];
            tokenState[i].stakedAsset = stakedAssets[i];
            tokenState[i].remainingInput = tokenState[i].token.balanceOf(stakedAssets[i]);
            tokenState[i].directUniswap = uniswapFactory().getExchange(tokenState[i].token, outputToken());
            tokenState[i].uniswapInputLiquidity = tokenState[i].token.balanceOf(address(tokenState[i].directUniswap));
            tokenState[i].uniswapOutputLiquidity = outputToken().balanceOf(address(tokenState[i].directUniswap));
            //(uint256 inputToken, uint256 inputConsumed, uint256 outputConsumed) = offers[i].info();
        }
    }
}
