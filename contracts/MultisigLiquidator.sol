pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;

import "./Liquidator.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

/**
 * Multisig that requires all signatures up-front
 * This is superior to separate transactions because there is no public pre-transaction signal
 * This can keep pending liquidations secret
 * The contract enforces that the owners remain distinct and requires 2 of 3 for all transactions
 * Signatures can be done with or without the Ethereum Signed Message prefix
 * Signature data format is packed:
 *** bytes20 MultisigLiquidator Address
 *** bytes32 nonce
 *** bytes action calldata
 * Action calldata is ABI-encoded and called to the relevant target if validated
 */
contract MultisigLiquidator {
    using ECDSA for bytes32;

    uint256 public nonce; // replay protection
    address[3] public owners;

    constructor(address[3] memory _owners) public {
        require(_owners[0] != _owners[1], "first two owners match");
        require(_owners[1] != _owners[2], "last two owners match");
        require(_owners[0] != _owners[2], "first and last owners match");
        owners[0] = _owners[0];
        owners[1] = _owners[1];
        owners[2] = _owners[2];
    }

    function liquidator() internal view returns (Liquidator);
    event Data(bytes32 indexed hash,bytes data);

    modifier msValidated(bytes memory action, bytes[2] memory signatures) {
        address[3] memory firstSignatureCandidates;
        firstSignatureCandidates[0] = owners[0];
        firstSignatureCandidates[1] = owners[1];
        firstSignatureCandidates[2] = owners[2];
        bytes memory data = abi.encodePacked(address(this), nonce++, action);
        bytes32 hash = keccak256(data);
        emit Data(hash, data);
        address recoveredNoPrefix = hash.recover(signatures[0]);
        address recoveredWithPrefix = hash.toEthSignedMessageHash().recover(signatures[0]);
        address[3] memory secondSignatureCandidates;
        uint8 unmatchingSignatureCount = 0; 
        for (uint256 i = 3; i --> 0;) {
            address candidate = firstSignatureCandidates[i];
            if (candidate != recoveredNoPrefix && candidate != recoveredWithPrefix) {
                secondSignatureCandidates[unmatchingSignatureCount++] = candidate;
            }
        }
        require(unmatchingSignatureCount == 2, "invalid first signature");

        recoveredNoPrefix = hash.recover(signatures[1]);
        recoveredWithPrefix = hash.toEthSignedMessageHash().recover(signatures[1]);
        unmatchingSignatureCount = 0;
        for (uint256 i = 2; i --> 0;) {
            address candidate = secondSignatureCandidates[i];
            if (candidate != recoveredNoPrefix && candidate != recoveredWithPrefix) {
                unmatchingSignatureCount++;
            }
        }
        require(unmatchingSignatureCount == 1, "invalid second signature");
        _;
    }

    modifier onlySelf {
        require(msg.sender == address(this), "unauthorized");
        _;
    }

    function updateOwner(address oldOwner, address newOwner) onlySelf external {
        require(newOwner != address(0x0), "empty newOwner");
        for (uint8 i = 3; i --> 0;) {
            address priorOwner = owners[i];
            if (oldOwner == priorOwner) {
                owners[i] = newOwner;
            } else {
                require(newOwner != priorOwner, "newOwner is already an owner");
            }
        }
    }

    function liquidatorCall(bytes memory action, bytes[2] memory signatures) msValidated(action, signatures) internal returns (bytes memory) {
        (bool success, bytes memory result) = address(liquidator()).call(action);
        require(success, string(result));
        return result;
    }

    function multisigCall(bytes memory action, bytes[2] memory signatures) msValidated(action, signatures) internal returns (bytes memory) {
        (bool success, bytes memory result) = address(this).call(action);
        require(success, string(result));
        return result;
    }

    function reclaim(int256 _debt, address _destination, bytes[2] memory signatures) public returns (bytes memory) {
        return liquidatorCall(abi.encodeWithSignature("reclaim(int256,address)", _debt, _destination), signatures);
    }

    function msUpdateOwner(address oldOwner, address newOwner, bytes[2] memory signatures) public returns (bytes memory) {
        return multisigCall(abi.encodeWithSignature("updateOwner(address,address)", oldOwner, newOwner), signatures);
    }

    function msTransferProxyOwnership(address newOwner, bytes[2] memory signatures) public returns (bytes memory) {
        return multisigCall(abi.encodeWithSignature("transferProxyOwnership(address)", newOwner), signatures);
    }

    function msClaimProxyOwnership(bytes[2] memory signatures) public returns (bytes memory) {
        return multisigCall(abi.encodeWithSignature("claimProxyOwnership()"), signatures);
    }

    function msUpgradeTo(address implementation, bytes[2] memory signatures) public returns (bytes memory) {
        return multisigCall(abi.encodeWithSignature("upgradeTo(address)", implementation), signatures);
    }
}
