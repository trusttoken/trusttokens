pragma solidity ^0.5.13;

pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./ValSafeMath.sol";
import "@trusttoken/registry/contracts/Registry.sol";
import "wjm-airswap-swap/contracts/Swap.sol";

/**
 * @dev Program that executes a trade
 * TradeExecutor is a contract that executes a trade
 * It's much cheaper to deploy and run a contract than to
 * execute in the liquidator
 * TradeExecutor is called via delegatecall
 */
interface TradeExecutor {
}

/**
 * @dev Uniswap
 * This is nessesary since Uniswap is written in vyper.
 */
interface UniswapV1 {
    function tokenToExchangeSwapInput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, UniswapV1 exchangeAddress) external returns (uint256 tokensBought);
    function tokenToExchangeTransferInput(uint256 tokensSold, uint256 minTokensBought, uint256 minEthBought, uint256 deadline, address recipient, UniswapV1 exchangeAddress) external returns (uint256 tokensBought);
    function tokenToExchangeSwapOutput(uint256 tokensBought, uint256 maxTokensSold, uint256 maxEthSold, uint256 deadline, UniswapV1 exchangeAddress) external returns (uint256 tokensSold);
    function tokenToExchangeTransferOutput(uint256 tokensBought, uint256 maxTokensSold, uint256 maxEthSold, uint256 deadline, address recipient, UniswapV1 exchangeAddress) external returns (uint256 tokensSold);
}

/**
 * @dev Uniswap Factory
 * This is nessesary since Uniswap is written in vyper.
 */
interface UniswapV1Factory {
    function getExchange(IERC20 token) external returns (UniswapV1);
}


/**
 * @title Abstract Liquidator
 * @dev Liquidate staked tokenns on uniswap.
 * Airswap uses domainSeparators to validate transactions and prevent replay protection
 * When signing an airswap order we require specification of which validator we are using.
 * This is because there are multiple instances of AirswapV2.
 * StakingOpportunityFactory does not create a Liquidator, rather this must be created
 * Outside of the factory.
 * prune() removes all orders that would fail from
 */
contract ALiquidator {
    using ValSafeMath for uint256;

    // owner, attributes, and domain separators
    address public owner;
    address public pendingOwner;
    mapping (address => uint256) attributes;

    // domain separators is a paramater of airswap synced as an attribute
    // when you register an airswap validator you need to register domain separators
    // 32 bytes in data that you sign which corresponds to contract signed for
    // used for replay protection, examples of this in test files
    // mappings updated in syncAttributeValue
    // signedTypedData standard
    mapping (address => bytes32) domainSeparators;

    // Orders are contracts that execute airswaps
    // We DELEGATECALL into orders to invoke them
    // Orders are stored in this mapping as a sorted singly linkedlist
    // Invariant: orders are sorted by greatest price
    // Linked list head and tail are mapped to zero
    // It's much much cheaper to deploy a contract to execute the trade
    mapping (/* TradeExecutor */ address => TradeExecutor) public next;

    // constants
    bytes32 constant APPROVED_BENEFICIARY = "approvedBeneficiary";
    uint256 constant LIQUIDATOR_CAN_RECEIVE     = 0xff00000000000000000000000000000000000000000000000000000000000000;
    uint256 constant LIQUIDATOR_CAN_RECEIVE_INV = 0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    // part of signature so that signing for airswap doesn't sign for all airswap instances
    bytes32 constant AIRSWAP_VALIDATOR = "AirswapValidatorDomain";
    uint256 constant MAX_UINT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant MAX_UINT128 = 0xffffffffffffffffffffffffffffffff;
    bytes1 constant AIRSWAP_AVAILABLE = bytes1(0x0);
    bytes2 EIP191_HEADER = 0x1901;

    // internal variables implemented as storage by Liquidator
    // these variables must be known at construction time
    // kLiquidator is the actual implementation of ALiquidator

    /** @dev Get output token (token to get from liqudiation exchange). */
    function outputToken() internal view returns (IERC20);
    /** @dev Get stake token (token to be liquidated). */
    function stakeToken() internal view returns (IERC20);
    /** @dev Output token on uniswap. */
    function outputUniswapV1() internal view returns (UniswapV1);
    /** @dev Stake token on uniswap. */
    function stakeUniswapV1() internal view returns (UniswapV1);
    /** @dev Contract registry. */
    function registry() internal view returns (Registry);
    /** @dev Address of staking pool. */
    function pool() internal view returns (address);

    /**
     * @dev implementation constructor needs to call initialize
     * Here we approve transfers to uniswap for the staking and output token
     */
    function initialize() internal {
        outputToken().approve(address(outputUniswapV1()), MAX_UINT);
        stakeToken().approve(address(stakeUniswapV1()), MAX_UINT);
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event LimitOrder(TradeExecutor indexed order);
    event Fill(TradeExecutor indexed order);
    event Cancel(TradeExecutor indexed order);
    event Liquidated(uint256 indexed stakeAmount, uint256 indexed debtAmount);

    // used to track why a liquidation failed
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

    /**
     * @dev Two flags are supported by this function:
     * AIRSWAP_VALIDATOR and APPROVED_BENEFICIARY
     * Can sync by saying this contract is the registry or sync from registry directly.
     * Registry decides what is a valid airswap.
     */
    function syncAttributeValue(address _account, bytes32 _attribute, uint256 _value) external onlyRegistry {
        if (_attribute == AIRSWAP_VALIDATOR) {
            if (_value > 0) {
                // register domain separator and approve validator to spend
                stakeToken().approve(_account, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
                domainSeparators[_account] = bytes32(_value);
            } else {
                stakeToken().approve(_account, 0);
                domainSeparators[_account] = bytes32(0);
            }
        } else if (_attribute == APPROVED_BENEFICIARY) {
            // approved beneficiary flag defines whether someone can recieve
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

    /**
     * @dev Calculate how much output we get for a stake input amount
     * Much cheaper to do this logic ourselves locally than an external call
     * Allows us to do this multiple times in one transaction
     * See ./uniswap/uniswap_exchange.vy
     */
    function outputForUniswapV1Input(uint256 stakeInputAmount, UniswapState memory outputUniswapV1State, UniswapState memory stakeUniswapV1State) internal pure returns (uint256 outputAmount) {
        uint256 inputAmountWithFee = 997 * stakeInputAmount;
        inputAmountWithFee = 997 * (inputAmountWithFee * stakeUniswapV1State.etherBalance) / (stakeUniswapV1State.tokenBalance * 1000 + inputAmountWithFee);
        outputAmount = (inputAmountWithFee * outputUniswapV1State.tokenBalance) / (outputUniswapV1State.etherBalance * 1000 + inputAmountWithFee);
    }

    /**
     * @dev Calcualte how much input we need to get a desired output
     * Is able to let us know if there is slippage in uniswap exchange rate
     * and continue with Airswap
     * See./uniswap/uniswap_exchange.vy
     */
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

    /**
     * @dev Transfer stake without liquidation
     * requires LIQUIDATOR_CAN_RECEIVE flag (recipient must be registered)
     */
    function reclaimStake(address _destination, uint256 _stake) external onlyOwner {
        require(attributes[_destination] & LIQUIDATOR_CAN_RECEIVE != 0, "unregistered recipient");
        stakeToken().transferFrom(pool(), _destination, _stake);
    }

    /**
     * @dev Award stake tokens to stakers.
     * Transfer to the pool without creating a staking position.
     * Allows us to reward as staking or reward token.
     */
    function returnStake(address _from, uint256 balance) external {
        stakeToken().transferFrom(_from, pool(), balance);
    }

    /**
     * @dev Sells stake for underlying asset and pays to destination.
     * Use airswap trades as long as they're better than uniswap.
     * Contract won't slip Uniswap this way.
     * If we reclaim more than we actually owe we award to stakers.
     * Not possible to convert back into TrustTokens here.
     */
    function reclaim(address _destination, int256 _debt) external onlyOwner {
        require(_debt > 0, "Must reclaim positive amount");
        require(_debt < int256(MAX_UINT128), "reclaim amount too large");
        require(attributes[_destination] & LIQUIDATOR_CAN_RECEIVE != 0, "unregistered recipient");

        // get balance of stake pool
        address stakePool = pool();
        uint256 remainingStake = stakeToken().balanceOf(stakePool);

        // withdraw to liquidator
        require(stakeToken().transferFrom(stakePool, address(this), remainingStake), "unapproved");

        // load uniswap state for output and staked token
        UniswapState memory outputUniswapV1State;
        UniswapState memory stakeUniswapV1State;
        outputUniswapV1State.uniswap = outputUniswapV1();
        outputUniswapV1State.etherBalance = address(outputUniswapV1State.uniswap).balance;
        outputUniswapV1State.tokenBalance = outputToken().balanceOf(address(outputUniswapV1State.uniswap));
        stakeUniswapV1State.uniswap = stakeUniswapV1();
        stakeUniswapV1State.etherBalance = address(stakeUniswapV1State.uniswap).balance;
        stakeUniswapV1State.tokenBalance = stakeToken().balanceOf(address(stakeUniswapV1State.uniswap));

        // calculate remaining debt
        int256 remainingDebt = _debt;

        // set order linkedlist to head
        TradeExecutor curr = head();

        // walk through iterator while we still have orders and gas
        while (curr != TradeExecutor(0) && gasleft() > SWAP_GAS_COST) {
            // load order using airswapOrderInfo which copies end of order contract into memory
            // now we have the order in memory. This is very cheap (<1000 gas)
            // ~23x more efficient than using storage
            FlatOrder memory order = airswapOrderInfo(curr);

            // if order tries to buy more stake than we have we cancel order
            // othwerwise continue to walk through orders
            if (order.senderAmount <= remainingStake) {

                // check price using cross product
                // checks if we get a better deal in uniswap
                if (inputForUniswapV1Output(uint256(remainingDebt), outputUniswapV1State, stakeUniswapV1State) * order.signerAmount < order.senderAmount * uint256(remainingDebt)) {
                    // remaining orders are not as good as uniswap
                    break;
                }

                // use delegatecall to process order from our address
                // we are the only people who can execute this order
                (bool success, bytes memory returnValue) = address(curr).delegatecall("");

                // on success, emit fill event and update state
                // otherwise cancel and emit liqudiation error
                // an order either cancels or fills
                if (success) {
                    emit Fill(curr);

                    // calculate remaining debt
                    remainingDebt -= int256(order.signerAmount);
                    remainingStake -= order.senderAmount; // underflow not possible because airswap transfer succeeded

                    // emit liquidation and break if no more debt
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

            // advance through linkedlist by setting head to next item
            address prev = address(curr);
            curr = next[prev];
            next[prev] = TradeExecutor(0);
        }
        next[address(0)] = curr;

        // if we have remaining debt and stake, we use Uniswap
        // we can use uniswap by specifying desired output or input
        // we
        if (remainingDebt > 0) {
            if (remainingStake > 0) {
                if (outputForUniswapV1Input(remainingStake, outputUniswapV1State, stakeUniswapV1State) < uint256(remainingDebt)) {
                    // liquidate all remaining stake :(
                    uint256 outputAmount = stakeUniswapV1State.uniswap.tokenToExchangeSwapInput(remainingStake, 1, 1, block.timestamp, outputUniswapV1State.uniswap);
                    emit Liquidated(remainingStake, outputAmount);

                    // update remaining stake and debt
                    remainingDebt -= int256(outputAmount);
                    remainingStake = 0;

                    // send output token to destination
                    outputToken().transfer(_destination, uint256(_debt - remainingDebt));
                } else {
                    // finish liquidation via uniswap
                    uint256 stakeSold = stakeUniswapV1State.uniswap.tokenToExchangeSwapOutput(uint256(remainingDebt), remainingStake, MAX_UINT, block.timestamp, outputUniswapV1State.uniswap);
                    emit Liquidated(stakeSold, uint256(remainingDebt));
                    remainingDebt = 0;
                    remainingStake -= stakeSold;
                    //
                    outputToken().transfer(_destination, uint256(_debt));
                }
            }
        } else {
            // if we end up with a tiny amount of delta, transfer to the pool
            if (remainingDebt < 0) {
                outputToken().transfer(stakePool, uint256(-remainingDebt));
            }

            // transfer output token to destination
            outputToken().transfer(_destination, uint256(_debt));
        }

        // if there is remaining stake, return remainder to pool
        if (remainingStake > 0) {
            stakeToken().transfer(stakePool, remainingStake);
        }
    }

    /**
     * Airswap v2 logic
     * See 0x3E0c31C3D4067Ed5d7d294F08B79B6003B7bf9c8
     * Important to prune orders which have expired
     * or where someone has withdrawn their capital
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

    // if there is a hard fork, must update these gas costs
    bytes4 constant ERC20_KIND = 0x36372b07;
    uint256 constant SWAP_GAS_COST = 150000;
    uint256 constant PRUNE_GAS_COST = 30000;

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

    /**
     * @dev Copies airswap info into memory and returns it
     * Uses extcodecopy
     * Needs to return a FlatOrder instead of an Order to save space in memory
     */
    function airswapOrderInfo(TradeExecutor _airswapOrderContract) public view returns (FlatOrder memory order) {
        assembly {
            extcodecopy(_airswapOrderContract, order, 51, 736)
        }
    }

    bytes32 constant ORDER_TYPEHASH = 0x1b7987701aec5d914b7e2663640474d587fdf71bf8cf50a672b29ff7ddc7b557;
    bytes32 constant PARTY_TYPEHASH = 0xf7dd27dc10c7dbaecb34f7bf8396d9ce2f7972a5556959ec094912041b15e285;
    //bytes32 constant DOMAIN_TYPEHASH = 0x91ab3d17e3a50a9d89e63fd30b92be7f5336b03b287bb946787a83a9d62a2766;
    bytes32 constant ZERO_PARTY_HASH = 0xb3df6f92b1402b8652ec14dde0ab8816789b2da8a6b0962109a31f4c72c625d2;

    /**
     * @dev Calculate signature for airswap
     */
    function hashERC20Party(Party memory _party) internal pure returns (bytes32) {
        return keccak256(abi.encode(PARTY_TYPEHASH, ERC20_KIND, _party.wallet, _party.token, _party.amount, _party.id));
    }

    /**
     * @dev Return true if valid airswap signatory
     * Can sign on someone else's behalf if authorized
     */
    function validAirswapSignatory(Swap validator, address signer, address signatory) internal view returns (bool) {
        if (signatory == signer) {
            return true;
        }
        return validator.signerAuthorizations(signer, signatory);
    }

    /**
     * @dev Return true if valid airswap signature
     */
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

    /**
     * @dev Register Valid Airswap
     * Ensures a bunch of logic to regsiter a valid airswap order
     * Prevent really large orders that would cause overflow
     * Ensures correct exchange of token types
     * Ensures no affiliate in airswap order
     * Checks signer has the balance they are offering to exchange
     * Checks order registrant has approval
     *
     * Downsides:
     * Can register orders that fail, but this will be pruned very cheaply
     * Can register order and transfer in the same transaction
     */
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
        // check nonce data
        require(validator.signerMinimumNonce(_order.signer.wallet) <= _order.nonce, "signer minimum nonce is higher");
        require(validator.signerNonceStatus(_order.signer.wallet, _order.nonce) == AIRSWAP_AVAILABLE, "signer nonce unavailable");
        // validate signature and signatory
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

        // above codes refer to the assembly below
        assembly {
            let start := mload(0x40)
            mstore(start,             0x00000000000000000000000000000000000000000061031380600A3D393DF338)
            mstore(add(start, 32), or(0x3D3D39383D6102E4602F3D730000000000000000000000000000000000000000, validator))
            mstore(add(start, 64),    0x5AF1602A573D6000FD5B3D6000F367641C2F0000000000000000000000000000)
            calldatacopy(add(start, 82), 4, 736)
            orderContract := create(0, add(start, 21), 797)
        }

        // walk through list and insert order
        // if we run out of gas we revert
        // e.g. if someone's order isn't good enough to be
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
     * @dev return True if an order is prunable
     * If the order cannot be executed at this moment, it is prunable
     * No need to check things immutably true that were checked during registration
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
        // check allowance, nonce status, and minimum nonce correspond to cancellation
        if (rewardToken.allowance(_order.signerWallet, _order.validator) < _order.signerAmount) {
            return true;
        }
        if (Swap(_order.validator).signerNonceStatus(_order.signerWallet, _order.nonce) != AIRSWAP_AVAILABLE) {
            return true;
        }
        if (Swap(_order.validator).signerMinimumNonce(_order.signerWallet) > _order.nonce) {
            return true;
        }
        // check signatory has not been revoked
        if (!validAirswapSignatory(Swap(_order.validator), _order.signerWallet, _order.signatory)) {
            return true;
        }
        return false;
    }

    /**
     * @dev Remove all orders that would fail
     * Remove all orders worse than what is available in uniswap
     * Much cheaper to prune than to run an order that would fail
     */
    function prune() external {
        address prevValid = address(0);
        TradeExecutor curr = next[address(0)];

        // walk through list and prune
        while (curr != TradeExecutor(0) && gasleft() > PRUNE_GAS_COST) {
            // get order from memory
            FlatOrder memory currInfo = airswapOrderInfo(curr);

            // if order is prunable, remove from linkedlist
            // otherwise continue to walk through list
            // gas refud from pruning makes it very cheap
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
