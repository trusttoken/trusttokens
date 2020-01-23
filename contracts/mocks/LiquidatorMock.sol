pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;


import "../Liquidator.sol";

contract LiquidatorMock is Liquidator {
    //UniswapFactory mockUniswapFactory;
    address mockPool;
    Registry mockRegistry;
    IERC20 mockOutputToken;
    IERC20 mockStakeToken;
    UniswapV1 mockOutputUniswap;
    UniswapV1 mockStakeUniswap;
    constructor(address _pool, Registry _registry, /*UniswapFactory _uniswapFactory,*/ IERC20 _outputToken, IERC20 _stakeToken, UniswapV1 _outputUniswap, UniswapV1 _stakeUniswap) public {
        mockPool = _pool;
        mockRegistry = _registry;
        //mockUniswapFactory = _uniswapFactory;
        mockOutputToken = _outputToken;
        mockStakeToken = _stakeToken;
        mockOutputUniswap = _outputUniswap;
        mockStakeUniswap = _stakeUniswap;
    }
    /*
    function uniswapFactory() internal view returns (UniswapFactory uniswapFactory_) {
        uniswapFactory_ = mockUniswapFactory;
    }
    */
    function pool() internal view returns (address pool_) {
        pool_ = mockPool;
    }
    function outputToken() internal view returns (IERC20 outputToken_) {
        outputToken_ = mockOutputToken;
    }
    function stakeToken() internal view returns (IERC20 stakeToken_) {
        stakeToken_ = mockStakeToken;
    }
    function registry() internal view returns (Registry registry_) {
        registry_ = mockRegistry;
    }
    function outputUniswapV1() internal view returns (UniswapV1 outputUniswapV1_) {
        outputUniswapV1_ = mockOutputUniswap;
    }
    function stakeUniswapV1() internal view returns (UniswapV1 stakeUniswapV1_) {
        stakeUniswapV1_ = mockStakeUniswap;
    }
}
