pragma solidity ^0.5.13;

import "../../true-currencies/contracts/mocks/TrueUSDMock.sol";
import "../../true-currencies/registry/contracts/mocks/RegistryMock.sol";
import "../../true-currencies/contracts/Proxy/OwnedUpgradeabilityProxy.sol";

contract TrustTokenDependencies is OwnedUpgradeabilityProxy, TrueUSDMock, RegistryMock {}
