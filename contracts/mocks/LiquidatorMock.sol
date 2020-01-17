pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;


import "../Liquidator.sol";

contract LiquidatorMock is Liquidator {
    //UniswapFactory mockUniswapFactory;
    Registry mockRegistry;
    IERC20 mockOutputToken;
    IERC20 mockStakeToken;
    constructor(Registry _registry, /*UniswapFactory _uniswapFactory,*/ IERC20 _outputToken, IERC20 _stakeToken) public {
        mockRegistry = _registry;
        //mockUniswapFactory = _uniswapFactory;
        mockOutputToken = _outputToken;
        mockStakeToken = _stakeToken;
    }
    /*
    function uniswapFactory() internal view returns (UniswapFactory uniswapFactory_) {
        uniswapFactory_ = mockUniswapFactory;
    }
    */
    function outputToken() internal view returns (IERC20 outputToken_) {
        outputToken_ = mockOutputToken;
    }
    function stakeToken() internal view returns (IERC20 stakeToken_) {
        stakeToken_ = mockStakeToken;
    }
    function registry() internal view returns (Registry registry_) {
        registry_ = mockRegistry;
    }
}
