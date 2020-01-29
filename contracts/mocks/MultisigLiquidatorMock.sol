pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;

import "../MultisigLiquidator.sol";


contract MultisigLiquidatorMock is MultisigLiquidator {

    Liquidator mockLiquidator;

    constructor(address[3] memory _owners, Liquidator _liquidator) MultisigLiquidator(_owners) public {
        mockLiquidator = _liquidator;
    }

    function liquidator() internal view returns (Liquidator) {
        return mockLiquidator;
    }
}
