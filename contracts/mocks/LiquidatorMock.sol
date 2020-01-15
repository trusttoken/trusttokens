pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;


import "../Liquidator.sol";

contract LiquidatorMock is Liquidator {
    //UniswapFactory mockUniswapFactory;
    IERC20 mockOutputToken;
    constructor(/*UniswapFactory _uniswapFactory,*/ IERC20 _outputToken) public {
        //mockUniswapFactory = _uniswapFactory;
        mockOutputToken = _outputToken;
    }
    /*
    function uniswapFactory() internal view returns (UniswapFactory uniswapFactory_) {
        uniswapFactory_ = mockUniswapFactory;
    }
    */
    function outputToken() internal view returns (IERC20 outputToken_) {
        outputToken_ = mockOutputToken;
    }
}
