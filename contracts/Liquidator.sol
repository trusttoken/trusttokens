pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "../true-currencies/registry/contracts/Registry.sol";

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
        We DELEGATECALL into orders to invoke them
        orders execute and return some amount or zero
        Invariant: only one offer per compatibilityID
        Invariant: orders are sorted by greatest output amount
    */
    // sorted singly-linked list
    TradeExecutor public head;
    mapping (/* TradeExecutor */ address => TradeExecutor) public next;

    bytes32 constant APPROVED_BENEFICIARY = "approvedBeneficiary";
    uint256 constant LIQUIDATOR_CAN_RECEIVE     = 0xff00000000000000000000000000000000000000000000000000000000000000;
    uint256 constant LIQUIDATOR_CAN_RECEIVE_INV = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    bytes32 constant IS_AIRSWAP_VALIDATOR = "isAirswapValidator";
    uint256 constant AIRSWAP_VALIDATOR     = 0x00ff000000000000000000000000000000000000000000000000000000000000;
    uint256 constant AIRSWAP_VALIDATOR_INV = 0xff00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    //function uniswapFactory() internal view returns (UniswapFactory);
    function outputToken() internal view returns (IERC20);
    function stakeToken() internal view returns (IERC20);
    function registry() internal view returns (Registry);
    event Liquidated(uint256 stakeAmount, uint256 debtAmount);

    modifier onlyRegistry {
        require(msg.sender == address(registry()), "only registry");
        _;
    }

    function syncAttributeValue(address _account, bytes32 _attribute, uint256 _value) external onlyRegistry {
        if (_attribute == IS_AIRSWAP_VALIDATOR) {
            if (_value > 0) {
                stakeToken().approve(_account, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
                attributes[_account] |= AIRSWAP_VALIDATOR;
            } else {
                stakeToken().approve(_account, 0);
                attributes[_account] &= AIRSWAP_VALIDATOR_INV;
            }
        } else if (_attribute == APPROVED_BENEFICIARY) {
            if (_value > 0) {
                attributes[_account] |= LIQUIDATOR_CAN_RECEIVE;
            } else {
                attributes[_account] &= LIQUIDATOR_CAN_RECEIVE_INV;
            }
        }
    }

    function reclaim(uint256 _debt, address _destination) external {
        // TODO auth
        require(attributes[_destination] & LIQUIDATOR_CAN_RECEIVE != 0, "unregistered recipient");
        // TODO withdraw to liquidator
        TradeExecutor curr = head;
        uint256 total = 0;
        while (curr != TradeExecutor(0)) {
            FlatOrder memory order = airswapOrderInfo(curr);
            // TODO check uniswaps
            if (total + order.signerAmount > _debt) {
                continue;
            }
            (bool success, bytes memory returnValue) = address(curr).delegatecall("");
            if (success) {
                total += order.signerAmount;
                emit Liquidated(order.senderAmount, order.signerAmount);
            }
            curr = next[address(curr)];
        }
        outputToken().transfer(_destination, total);
        // TODO return remainder to pool
    }

    /**
     * Airswap v2
     * See 0x3E0c31C3D4067Ed5d7d294F08B79B6003B7bf9c8
    **/
    struct Order {
        uint256 nonce;                // Unique per order and should be sequential
        uint256 expiry;               // Expiry in seconds since 1 January 1970
        Party signer;                 // Party to the trade that sets terms
        Party sender;                 // Party to the trade that accepts terms
        Party affiliate;              // Party compensated for facilitating (optional)
        Signature signature;          // Signature of the order
    }
    struct Party {
        bytes4 kind;                  // Interface ID of the token
        address wallet;               // Wallet address of the party
        IERC20 token;                // Contract address of the token
        uint256 amount;               // Amount for ERC-20 or ERC-1155
        uint256 id;                   // ID for ERC-721 or ERC-1155
    }
    struct Signature {
        address signatory;            // Address of the wallet used to sign
        address validator;            // Address of the intended swap contract
        bytes1 version;               // EIP-191 signature version
        uint8 v;                      // `v` value of an ECDSA signature
        bytes32 r;                    // `r` value of an ECDSA signature
        bytes32 s;                    // `s` value of an ECDSA signature
    }
    bytes4 constant ERC20_KIND = 0x36372b07;

    struct FlatOrder {
        uint256 nonce;                // Unique per order and should be sequential
        uint256 expiry;               // Expiry in seconds since 1 January 1970
        bytes4 signerKind;                  // Interface ID of the token
        address signerWallet;               // Wallet address of the party
        address signerToken;                // Contract address of the token
        uint256 signerAmount;               // Amount for ERC-20 or ERC-1155
        uint256 signerId;                   // ID for ERC-721 or ERC-1155
        bytes4 senderKind;                  // Interface ID of the token
        address senderWallet;               // Wallet address of the party
        address senderToken;                // Contract address of the token
        uint256 senderAmount;               // Amount for ERC-20 or ERC-1155
        uint256 senderId;                   // ID for ERC-721 or ERC-1155
        bytes4 affiliateKind;                  // Interface ID of the token
        address affiliateWallet;               // Wallet address of the party
        address affiliateToken;                // Contract address of the token
        uint256 affiliateAmount;               // Amount for ERC-20 or ERC-1155
        uint256 affiliateId;                   // ID for ERC-721 or ERC-1155
        address signatory;            // Address of the wallet used to sign
        address validator;            // Address of the intended swap contract
        bytes1 version;               // EIP-191 signature version
        uint8 v;                      // `v` value of an ECDSA signature
        bytes32 r;                    // `r` value of an ECDSA signature
        bytes32 s;                    // `s` value of an ECDSA signature
    }
    function airswapOrderInfo(TradeExecutor _airswapOrderContract) public view returns (FlatOrder memory order) {
        assembly {
            extcodecopy(_airswapOrderContract, order, 51, 736)
        }
    }

    function registerAirswap(Order calldata _order) external returns (TradeExecutor orderContract) {
        // TODO require _order.signature.validator is valid
        require(attributes[_order.signature.validator] & AIRSWAP_VALIDATOR != 0, "unregistered validator");
        require(_order.expiry > now + 1 hours);
        require(_order.sender.kind == ERC20_KIND);
        require(_order.sender.wallet == address(this));
        require(_order.sender.amount < 0xffffffffffffffffffffffffffffffff);
        require(_order.sender.token == stakeToken());
        require(_order.signer.kind == ERC20_KIND);
        require(_order.signer.token == outputToken());
        require(_order.signer.amount < 0xffffffffffffffffffffffffffffffff);
        uint256 compatibilityID = uint256(_order.nonce) ^ (uint256(_order.signer.wallet) << 96);
        address validator = _order.signature.validator;
        /*
            Create an order contract with the bytecode to call the validator with the supplied args
            During execution this liquidator will delegatecall into the order contract
            The order contract copies its code to memory to load the calldata and then executes call
            The order contract returns the data from the validator
            Though the return data is expected to be empty, we will still report whether the contract reverted, by reverting if it reverts
            We do not need to worry about other contexts executing this contract because we check that the liquidator is the counterparty and the liquidator will authorize no spenders
            Deploy (10 bytes)
        PC  Opcodes                                       Assembly         Stack
        00  610313                                        PUSH2 0313       787
        03  80                                            DUP1             787 787
        04  600A                                          PUSH1 0A         787 787 10
        06  3D                                            RETURNDATASIZE   787 787 10 0
        07  39                                            CODECOPY         787
        08  3D                                            RETURNDATASIZE   787 0
        09  F3                                            RETURN
            Order Contract (787 bytes)
        PC  Opcodes                                       Assembly         Stack                                         Notes
        00  38                                            CODESIZE         cs
        01  3D                                            RETURNDATASIZE   cs 0
        02  3D                                            RETURNDATASIZE   cs 0 0
        03  39                                            CODECOPY
        04  38                                            CODESIZE   0                                             (outSize)
        05  3D                                            RETURNDATASIZE   0 0                                           (outStart)
        06  6102E4                                        PUSH2 2E4        0 0 740                                       (inSize)
        09  602F                                          PUSH1 2F         0 0 740 2F                                    (inStart)
        0b  3D                                            RETURNDATASIZE   0 0 740 2F 0                                  wei
        0c  73xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx    PUSH20 validator 0 0 740 2F 0 validator                        address   (maybe use mload?)
        21  5A                                            GAS              0 0 740 2F 0 validator gas
        22  F1                                            CALL             success
        23  602A                                          PUSH1 2A         success goto
        25  57                                            JUMPI
        26  3D                                            RETURNDATASIZE   rds
        27  6000                                          PUSH1 0          rds 0
        29  FD                                            REVERT
        2a  5B                                            JUMPDEST
        2b  3D                                            RETURNDATASIZE   rds
        2c  6000                                          PUSH1 0          rds 0
        2e  F3                                            RETURN
        2f  67641C2F<>                                    <Order Calldata>                                               size of Order calldata is 740 bytes
        */
        assembly {
            let start := mload(0x40)
            mstore(start,             0x00000000000000000000000000000000000000000061031380600A3D393DF338)
            mstore(add(start, 32), or(0x3D3D39383D6102E4602F3D730000000000000000000000000000000000000000, validator))
            mstore(add(start, 64),    0x5AF1602A573D6000FD5B3D6000F367641C2F0000000000000000000000000000)
            calldatacopy(add(start, 82), 4, 736)
            orderContract := create(0, add(start, 21), 797)
        }
        TradeExecutor prev = TradeExecutor(0);
        TradeExecutor curr = head;
        while (curr != TradeExecutor(0)) {
            FlatOrder memory currInfo = airswapOrderInfo(curr);
            // no need to check overflow because multiplying unsigned values under 16 bytes results in an unsigned value under 32 bytes
            if (currInfo.signerAmount * _order.sender.amount > currInfo.senderAmount * _order.signer.amount) {
                next[address(orderContract)] = curr;
                if (prev == TradeExecutor(0)) {
                    head = orderContract;
                } else {
                    next[address(prev)] = orderContract;
                }
                return orderContract;
            }
            prev = curr;
            curr = next[address(curr)];
        }
        if (prev == TradeExecutor(0)) {
            head = orderContract;
        } else {
            next[address(prev)] = orderContract;
        }
        return orderContract;
    }

    function registerIntermediaryUniswap(IERC20 _inputToken, IERC20 _intermediaryToken) external {
        /*
        Uniswap uniswap = uniswapFactory().getExchange(_inputToken, _intermediaryToken);
        _inputToken.approve(address(uniswap), 0xff00000000000000000000000000000000000000000000000000000000000000);
        uint256 compatibilityID = uint256(address(_intermediaryToken)) ^ (uint256(address(_inputToken)) << 96);
        // TODO
        */
    }

    /**
        Remove all orders that would fail
        Remove all orders worse than what is available in uniswap
    */
    function prune() external {
        // TODO
    }
}
