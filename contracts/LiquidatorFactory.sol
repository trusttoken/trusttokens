pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;

import "./ALiquidator.sol";
import "./ProxiableLiquidator.sol";

contract LiquidatorFactory is Ownable {
  address implementation;

  constructor(address _implementation) public {
    implementation = _implementation;
  }

  function createLiquidator(
      Registry _registry,
      IERC20 _outputToken,
      IERC20 _stakeToken,
      UniswapV1 _outputUniswap,
      UniswapV1 _stakeUniswap
  ) external returns (ALiquidator) {
    OwnedUpgradeabilityProxy proxy = new OwnedUpgradeabilityProxy();
    proxy.upgradeTo(implementation);
    ProxiableLiquidator liquidator = ProxiableLiquidator(address(proxy));
    liquidator.configure(
      _registry,
      _outputToken,
      _stakeToken,
      _outputUniswap,
      _stakeUniswap
    );
    return liquidator;
  }

  function setImplementation(address _implementation) external onlyOwner {
    implementation = _implementation;
  }
}
