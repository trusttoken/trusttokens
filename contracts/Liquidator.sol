pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;


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

    function registerAirswap(Order calldata _order) external {
        // TODO require _order.signature.validator is valid
        require(_order.expiry > now + 1 hours);
        require(_order.sender.wallet == address(this));
        require(_order.signer.kind == ERC20_KIND);
        require(_order.signer.token == outputToken());
        require(_order.sender.kind == ERC20_KIND);
        // require(_order.sender.token == stakeToken())
        uint256 compatibilityID = uint256(_order.nonce) ^ (uint256(_order.signer.wallet) << 96);
        /*
            Create an order contract with the bytecode to call the validator with the supplied args
            During execution this liquidator will delegatecall into the order contract
            The order contract copies its code to memory to mload the calldata and then executes call
            The order contract returns the data from the validator
            Though the return data is expected to be empty, we will still report whether the contract reverted, by reverting if it reverts
            We do not need to worry about other contexts executing this contract because we check that the liquidator is the counterparty and the liquidator will authorize no spenders
            Deploy (10 bytes)
        PC  Opcodes                                       Assembly         Stack
        00  610312                                        PUSH2 0312       786
        03  80                                            DUP1             786 786
        04  600A                                          PUSH1 0A         786 786 10
        06  3D                                            RETURNDATASIZE   786 786 10 0
        07  39                                            CODECOPY         786
        08  3D                                            RETURNDATASIZE   786 0
        09  F3                                            RETURN
            Order Contract (786 bytes)
        PC  Opcodes                                       Assembly         Stack                                         Notes
        00  38                                            CODESIZE         cs
        01  3D                                            RETURNDATASIZE   cs 0
        02  3D                                            RETURNDATASIZE   cs 0 0
        03  39                                            CODECOPY
        04  3D                                            RETURNDATASIZE   0                                             (outSize)
        05  3D                                            RETURNDATASIZE   0 0                                           (outStart)
        06  6102E4                                        PUSH2 2E4        0 0 740                                       (inSize)
        09  602F                                          PUSH1 2F         0 0 740 2F                                    (inStart)
        0b  3D                                            RETURNDATASIZE   0 0 740 2F 0                                  wei
        0c  73xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx    PUSH20 validator 0 0 740 2F 0 validator                        address
        21  5A                                            GAS              0 0 740 2F 0 validator gas
        22  F1                                            CALL             revert
        23  602A                                          PUSH1 2A         revert goto
        25  57                                            JUMPI
        26  3D                                            RETURNDATASIZE   rds
        27  6000                                          PUSH1 0          rds 0
        29  F3                                            RETURN
        2a  5B                                            JUMPDEST
        2b  3D                                            RETURNDATASIZE   rds
        2c  6000                                          PUSH1 0          rds 0
        2e  FD                                            REVERT
        2f  <>                                            <Order Calldata>                                               size of Order calldata is 740 bytes
        */
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
