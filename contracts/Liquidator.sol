pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./ValSafeMath.sol";
import "../true-currencies/registry/contracts/Registry.sol";
import "wjm-airswap-swap/contracts/Swap.sol";

interface TradeExecutor {
}

interface UniswapV1 {
    function tokenToExchangeSwapInput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, UniswapV1 exchangeAddress) external returns (uint256 tokensBought);
    function tokenToExchangeTransferInput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, address recipient, UniswapV1 exchangeAddress) external returns (uint256 tokensBought);
    function tokenToExchangeSwapOutput(uint256 tokensBought, uint256 maxTokensSold, uint256 maxEthSold, uint256 deadline, UniswapV1 exchangeAddress) external returns (uint256 tokensSold);
    function tokenToExchangeTransferOutput(uint256 tokensBought, uint256 maxTokensSold, uint256 maxEthSold, uint256 deadline, address recipient, UniswapV1 exchangeAddress) external returns (uint256 tokensSold);
}
interface UniswapV1Factory {
    function getExchange(IERC20 token) external returns (UniswapV1);
}


contract Liquidator {
    using ValSafeMath for uint256;

    address public owner;
    address public pendingOwner;
    mapping (address => uint256) attributes;
    mapping (address => bytes32) domainSeparators;
    /**
        We DELEGATECALL into orders to invoke them
        Invariant: orders are sorted by greatest price
    */
    // sorted singly-linked list
    mapping (/* TradeExecutor */ address => TradeExecutor) public next;

    bytes32 constant APPROVED_BENEFICIARY = "approvedBeneficiary";
    uint256 constant LIQUIDATOR_CAN_RECEIVE     = 0xff00000000000000000000000000000000000000000000000000000000000000;
    uint256 constant LIQUIDATOR_CAN_RECEIVE_INV = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    bytes32 constant AIRSWAP_VALIDATOR = "AirswapValidatorDomain";
    uint256 constant MAX_UINT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant MAX_UINT128 = 0xffffffffffffffffffffffffffffffff;
    bytes1 constant AIRSWAP_AVAILABLE = bytes1(0x0);
    bytes2 EIP191_HEADER = 0x1901;
    function outputToken() internal view returns (IERC20);
    function stakeToken() internal view returns (IERC20);
    function outputUniswapV1() internal view returns (UniswapV1);
    function stakeUniswapV1() internal view returns (UniswapV1);
    function registry() internal view returns (Registry);
    function pool() internal view returns (address);

    constructor() public {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    function initialize() internal {
        outputToken().approve(address(outputUniswapV1()), MAX_UINT);
        stakeToken().approve(address(stakeUniswapV1()), MAX_UINT);
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event LimitOrder(TradeExecutor indexed order);
    event Fill(TradeExecutor indexed order);
    event Cancel(TradeExecutor indexed order);
    event Liquidated(uint256 indexed stakeAmount, uint256 indexed debtAmount);
    event LiquidationError(TradeExecutor indexed order, bytes error);

    modifier onlyRegistry {
        require(msg.sender == address(registry()), "only registry");
        _;
    }
    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner, "only pending owner");
        _;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        pendingOwner = newOwner;
    }

    function claimOwnership() public onlyPendingOwner {
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function syncAttributeValue(address _account, bytes32 _attribute, uint256 _value) external onlyRegistry {
        if (_attribute == AIRSWAP_VALIDATOR) {
            if (_value > 0) {
                stakeToken().approve(_account, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
                domainSeparators[_account] = bytes32(_value);
            } else {
                stakeToken().approve(_account, 0);
                domainSeparators[_account] = bytes32(0);
            }
        } else if (_attribute == APPROVED_BENEFICIARY) {
            if (_value > 0) {
                attributes[_account] |= LIQUIDATOR_CAN_RECEIVE;
            } else {
                attributes[_account] &= LIQUIDATOR_CAN_RECEIVE_INV;
            }
        }
    }

    struct UniswapState {
        UniswapV1 uniswap;
        uint256 etherBalance;
        uint256 tokenBalance;
    }

    // See ./uniswap/uniswap_exchange.vy
    function outputForUniswapV1Input(uint256 stakeInputAmount, UniswapState memory outputUniswapV1State, UniswapState memory stakeUniswapV1State) internal pure returns (uint256 outputAmount) {
        uint256 inputAmountWithFee = 997 * stakeInputAmount;
        inputAmountWithFee = 997 * (inputAmountWithFee * stakeUniswapV1State.etherBalance) / (stakeUniswapV1State.tokenBalance * 1000 + inputAmountWithFee);
        outputAmount = (inputAmountWithFee * outputUniswapV1State.tokenBalance) / (outputUniswapV1State.etherBalance * 1000 + inputAmountWithFee);
    }

    // See ./uniswap/uniswap_exchange.vy
    function inputForUniswapV1Output(uint256 outputAmount, UniswapState memory outputUniswapV1State, UniswapState memory stakeUniswapV1State) internal pure returns (uint256 inputAmount) {
        if (outputAmount >= outputUniswapV1State.tokenBalance) {
            return MAX_UINT128;
        }
        uint256 ethNeeded = (outputUniswapV1State.etherBalance * outputAmount * 1000) / (997 * (outputUniswapV1State.tokenBalance - outputAmount)) + 1;
        if (ethNeeded >= stakeUniswapV1State.etherBalance) {
            return MAX_UINT128;
        }
        inputAmount = (stakeUniswapV1State.tokenBalance * ethNeeded * 1000) / (997 * (stakeUniswapV1State.etherBalance - ethNeeded)) + 1;
    }

    function head() public view returns (TradeExecutor) {
        return next[address(0)];
    }

    function reclaimStake(address _destination, uint256 _stake) external onlyOwner {
        require(attributes[_destination] & LIQUIDATOR_CAN_RECEIVE != 0, "unregistered recipient");
        stakeToken().transferFrom(pool(), _destination, _stake);
    }

    /**
     * Put stake in pool without being credited for it
    */
    function returnStake(address _from, uint256 balance) external {
        stakeToken().transferFrom(_from, pool(), balance);
    }

    function reclaim(address _destination, int256 _debt) external onlyOwner {
        require(_debt > 0, "Must reclaim positive amount");
        require(_debt < int256(MAX_UINT128), "reclaim amount too large");
        require(attributes[_destination] & LIQUIDATOR_CAN_RECEIVE != 0, "unregistered recipient");
        address stakePool = pool();
        uint256 remainingStake = stakeToken().balanceOf(stakePool);
        // withdraw to liquidator
        require(stakeToken().transferFrom(stakePool, address(this), remainingStake), "unapproved");

        UniswapState memory outputUniswapV1State;
        UniswapState memory stakeUniswapV1State;
        outputUniswapV1State.uniswap = outputUniswapV1();
        outputUniswapV1State.etherBalance = address(outputUniswapV1State.uniswap).balance;
        outputUniswapV1State.tokenBalance = outputToken().balanceOf(address(outputUniswapV1State.uniswap));
        stakeUniswapV1State.uniswap = stakeUniswapV1();
        stakeUniswapV1State.etherBalance = address(stakeUniswapV1State.uniswap).balance;
        stakeUniswapV1State.tokenBalance = stakeToken().balanceOf(address(stakeUniswapV1State.uniswap));
        int256 remainingDebt = _debt;
        TradeExecutor curr = head();
        while (curr != TradeExecutor(0) && gasleft() > 160000) {
            FlatOrder memory order = airswapOrderInfo(curr);
            if (order.senderAmount <= remainingStake) {
                if (inputForUniswapV1Output(uint256(remainingDebt), outputUniswapV1State, stakeUniswapV1State) * order.signerAmount < order.senderAmount * uint256(remainingDebt)) {
                    // remaining orders are not as good as uniswap
                    break;
                }
                (bool success, bytes memory returnValue) = address(curr).delegatecall("");
                if (success) {
                    emit Fill(curr);
                    remainingDebt -= int256(order.signerAmount);
                    remainingStake -= order.senderAmount; // underflow not possible because airswap transfer succeeded
                    emit Liquidated(order.senderAmount, order.signerAmount);
                    if (remainingDebt <= 0) {
                        break;
                    }
                } else {
                    emit Cancel(curr);
                    emit LiquidationError(curr, returnValue);
                }
            } else {
                emit Cancel(curr);
            }
            address prev = address(curr);
            curr = next[prev];
            next[prev] = TradeExecutor(0);
        }
        next[address(0)] = curr;
        if (remainingDebt > 0) {
            if (remainingStake > 0) {
                if (outputForUniswapV1Input(remainingStake, outputUniswapV1State, stakeUniswapV1State) < uint256(remainingDebt)) {
                    // liquidate all stake :(
                    uint256 outputAmount = stakeUniswapV1State.uniswap.tokenToExchangeSwapInput(remainingStake, 1, 1, block.timestamp, outputUniswapV1State.uniswap);
                    emit Liquidated(remainingStake, outputAmount);
                    remainingDebt -= int256(outputAmount);
                    remainingStake = 0;
                    outputToken().transfer(_destination, uint256(_debt - remainingDebt));
                } else {
                    // finish liquidation via uniswap
                    uint256 stakeSold = stakeUniswapV1State.uniswap.tokenToExchangeSwapOutput(uint256(remainingDebt), remainingStake, MAX_UINT, block.timestamp, outputUniswapV1State.uniswap);
                    emit Liquidated(stakeSold, uint256(remainingDebt));
                    remainingDebt = 0;
                    remainingStake -= stakeSold;
                    outputToken().transfer(_destination, uint256(_debt));
                }
            }
        } else {
            if (remainingDebt < 0) {
                // pay out stake liquidation value
                outputToken().transfer(stakePool, uint256(-remainingDebt));
            }
            outputToken().transfer(_destination, uint256(_debt));
        }
        if (remainingStake > 0) {
            // return remainder stake to pool
            stakeToken().transfer(stakePool, remainingStake);
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
    uint256 constant SWAP_GAS_COST = 150000;

    struct FlatOrder {
        uint256 nonce;                // Unique per order and should be sequential
        uint256 expiry;               // Expiry in seconds since 1 January 1970
        bytes4 signerKind;                  // Interface ID of the token
        address signerWallet;               // Wallet address of the party
        IERC20 signerToken;                 // Contract address of the token
        uint256 signerAmount;               // Amount for ERC-20 or ERC-1155
        uint256 signerId;                   // ID for ERC-721 or ERC-1155
        bytes4 senderKind;                  // Interface ID of the token
        address senderWallet;               // Wallet address of the party
        IERC20 senderToken;                 // Contract address of the token
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

    bytes32 constant ORDER_TYPEHASH = 0x1b7987701aec5d914b7e2663640474d587fdf71bf8cf50a672b29ff7ddc7b557;
    bytes32 constant PARTY_TYPEHASH = 0xf7dd27dc10c7dbaecb34f7bf8396d9ce2f7972a5556959ec094912041b15e285;
    //bytes32 constant DOMAIN_TYPEHASH = 0x91ab3d17e3a50a9d89e63fd30b92be7f5336b03b287bb946787a83a9d62a2766;
    bytes32 constant ZERO_PARTY_HASH = 0xb3df6f92b1402b8652ec14dde0ab8816789b2da8a6b0962109a31f4c72c625d2;

    function hashERC20Party(Party memory _party) internal pure returns (bytes32) {
        return keccak256(abi.encode(PARTY_TYPEHASH, ERC20_KIND, _party.wallet, _party.token, _party.amount, _party.id));
    }

    function validAirswapSignatory(Swap validator, address signer, address signatory) internal view returns (bool) {
        if (signatory == signer) {
            return true;
        }
        return validator.signerAuthorizations(signer, signatory);
    }

    function validAirswapSignature(Order memory _order) internal view returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(EIP191_HEADER, domainSeparators[_order.signature.validator], keccak256(abi.encode(ORDER_TYPEHASH, _order.nonce, _order.expiry, hashERC20Party(_order.signer), hashERC20Party(_order.sender), ZERO_PARTY_HASH))));
        if (_order.signature.version == 0x45) {
            return ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)), _order.signature.v, _order.signature.r, _order.signature.s) == _order.signature.signatory;
        } else if (_order.signature.version == 0x01) {
            return ecrecover(hash, _order.signature.v, _order.signature.r, _order.signature.s) == _order.signature.signatory;
        } else {
            return false;
        }
    }

    function registerAirswap(Order calldata _order) external returns (TradeExecutor orderContract) {
        require(domainSeparators[_order.signature.validator] != bytes32(0), "unregistered validator");
        require(_order.expiry > now + 1 hours, "expiry too soon");
        require(_order.sender.kind == ERC20_KIND, "send erc20");
        require(_order.sender.wallet == address(this), "counterparty must be liquidator");
        require(_order.sender.amount < MAX_UINT128, "ask too large");
        require(_order.sender.token == stakeToken(), "must buy stake");
        require(_order.signer.kind == ERC20_KIND, "sign erc20");
        require(_order.signer.token == outputToken(), "incorrect token offerred");
        require(_order.signer.amount < MAX_UINT128, "bid too large");
        require(_order.affiliate.amount == 0, "affiliate amount must be zero");
        require(_order.affiliate.wallet == address(0), "affiliate wallet must be zero");
        require(_order.affiliate.kind == ERC20_KIND, "affiliate erc20");
        require(outputToken().balanceOf(_order.signer.wallet) >= _order.signer.amount, "insufficient signer balance");
        require(outputToken().allowance(_order.signer.wallet, _order.signature.validator) >= _order.signer.amount, "insufficient signer allowance");
        uint256 poolBalance = stakeToken().balanceOf(pool()); 
        require(poolBalance >= _order.sender.amount, "insufficient pool balance");
        // verify senderAmount / poolBalance > swapGasCost / blockGasLimit
        require(_order.sender.amount.mul(block.gaslimit, "senderAmount overflow") > poolBalance.mul(SWAP_GAS_COST, "poolBalance overflow"), "order too small");
        Swap validator = Swap(_order.signature.validator);
        require(validator.signerMinimumNonce(_order.signer.wallet) <= _order.nonce, "signer minimum nonce is higher");
        require(validator.signerNonceStatus(_order.signer.wallet, _order.nonce) == AIRSWAP_AVAILABLE, "signer nonce unavailable");
        require(validAirswapSignature(_order), "signature invalid");
        require(validAirswapSignatory(Swap(_order.signature.validator), _order.signer.wallet, _order.signature.signatory), "signatory invalid");
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
        address prev = address(0);
        TradeExecutor curr = next[address(0)];
        while (curr != TradeExecutor(0)) {
            FlatOrder memory currInfo = airswapOrderInfo(curr);
            // no need to check overflow because multiplying unsigned values under 16 bytes results in an unsigned value under 32 bytes
            if (currInfo.signerAmount * _order.sender.amount < currInfo.senderAmount * _order.signer.amount) {
                next[address(orderContract)] = curr;
                break;
            }
            poolBalance -= currInfo.senderAmount;
            prev = address(curr);
            curr = next[prev];
        }
        require(poolBalance >= _order.sender.amount, "insufficent remaining pool balance");
        next[prev] = orderContract;
        emit LimitOrder(orderContract);
        return orderContract;
    }

    /**
        If the order cannot be executed at this moment, it is prunable
        No need to check things immutably true that were checked during registration
    */
    function prunableOrder(FlatOrder memory _order) internal view returns (bool) {
        if (_order.expiry < now) {
            return true;
        }
        // can assume rewardToken == outputToken()
        IERC20 rewardToken = _order.signerToken;
        if (rewardToken.balanceOf(_order.signerWallet) < _order.signerAmount) {
            return true;
        }
        if (rewardToken.allowance(_order.signerWallet, _order.validator) < _order.signerAmount) {
            return true;
        }
        if (Swap(_order.validator).signerNonceStatus(_order.signerWallet, _order.nonce) != AIRSWAP_AVAILABLE) {
            return true;
        }
        if (Swap(_order.validator).signerMinimumNonce(_order.signerWallet) > _order.nonce) {
            return true;
        }
        if (!validAirswapSignatory(Swap(_order.validator), _order.signerWallet, _order.signatory)) {
            return true;
        }
        return false;
    }

    /**
        Remove all orders that would fail
        Remove all orders worse than what is available in uniswap
    */
    function prune() external {
        address prevValid = address(0);
        TradeExecutor curr = next[address(0)];
        while (curr != TradeExecutor(0) && gasleft() > 30000) {
            FlatOrder memory currInfo = airswapOrderInfo(curr);
            if (prunableOrder(currInfo)) {
                emit Cancel(curr);
                address prev = address(curr);
                curr = next[prev];
                next[prev] = TradeExecutor(0);
            } else {
                if (next[prevValid] != curr) {
                    next[prevValid] = curr;
                }
                prevValid = address(curr);
                curr = next[prevValid];
            }
        }
        next[prevValid] = curr;
    }
}
