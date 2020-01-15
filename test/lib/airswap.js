const ERC20_INTERFACE_ID = '0x36372b07'
const BYTES12_ZERO = '000000000000000000000000'
const ORDER_TYPEHASH = web3.utils.sha3('Order(uint256 nonce,uint256 expiry,Party signer,Party sender,Party affiliate)Party(bytes4 kind,address wallet,address token,uint256 amount,uint256 id)')
const PARTY_TYPEHASH = web3.utils.sha3('Party(bytes4 kind,address wallet,address token,uint256 amount,uint256 id)')
const EIP712_DOMAIN_TYPEHASH = web3.utils.sha3('EIP712Domain(string name,string version,address verifyingContract)')
const DOMAIN_NAME = 'SWAP'
const DOMAIN_VERSION = '2'
const SIG191_VERSION = '0x01'
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

function uint256Bytes32(uint256) {
    let bytes = uint256.toString(16)
    if (bytes.length < 64) {
        bytes = '0'.repeat(64 - bytes.length) + bytes
    }
    return bytes
}

function addressBytes32(address) {
    return BYTES12_ZERO + address.slice(2)
}

function hashParty(party) {
    return web3.utils.sha3(PARTY_TYPEHASH
        + ERC20_INTERFACE_ID.slice(2) + '0'.repeat(56)
        + addressBytes32(party['wallet'])
        + addressBytes32(party['token'])
        + uint256Bytes32(party['amount'])
        + uint256Bytes32(0)
    )
}

function hashOrder(order) {
    return web3.utils.sha3(ORDER_TYPEHASH
        + uint256Bytes32(order.nonce)
        + uint256Bytes32(order.expiry)
        + hashParty(order.signer)
        + hashParty(order.sender)
        + hashParty(order.affiliate)
    )
}

function hashDomain(verifyingContract) {
    domain = (EIP712_DOMAIN_TYPEHASH +
        web3.utils.sha3(DOMAIN_NAME).slice(2) +
        web3.utils.sha3(DOMAIN_VERSION).slice(2) +
        addressBytes32(verifyingContract)
    )
    return web3.utils.sha3(domain)
}

function canonicalParty(party) {
    return (
        ERC20_INTERFACE_ID.slice(2) + '0'.repeat(56) +
        addressBytes32(party.wallet) +
        addressBytes32(party.token) + 
        uint256Bytes32(party.amount) +
        uint256Bytes32(0)
    )
}


class Order {
    constructor(nonce, expiry, verifyingContractAddress, makerAddress, makerTokenAmount, makerTokenAddress, takerAddress, takerTokenAmount, takerTokenAddress) {
        this.verifyingContract = verifyingContractAddress
        this.nonce = nonce
        this.expiry = expiry
        this.signer = {
            wallet: makerAddress,
            amount: makerTokenAmount,
            token: makerTokenAddress,
        }
        this.sender = {
            wallet: takerAddress,
            amount: takerTokenAmount,
            token: takerTokenAddress,
        }
        this.affiliate = {
            wallet: ZERO_ADDRESS,
            amount: 0,
            token: ZERO_ADDRESS,
        }
    }
    get signingData() {
        return ('0x1901' +
            hashDomain(this.verifyingContract).slice(2) +
            hashOrder(this).slice(2)
        )
    }
    get signingHash() {
        return web3.utils.sha3(this.signingData        )
    }
    async sign() {
        const sig = await web3.eth.sign(this.signingData, this.signer.wallet)
        this.r = sig.slice(2, 66)
        this.s = sig.slice(66, 130)
        this.v = parseInt(sig.slice(130))
        if (this.v < 27) {
            this.v += 27
        }
        return sig
    }
    get abiV2Bytes() {
        return (
            uint256Bytes32(this.nonce) +
            uint256Bytes32(this.expiry) +
            canonicalParty(this.signer) + 
            canonicalParty(this.sender) +
            canonicalParty(this.affiliate) +
            addressBytes32(this.signer.wallet) +
            addressBytes32(this.verifyingContract) +
            uint256Bytes32(SIG191_VERSION) +
            uint256Bytes32(this.v) +
            this.r +
            this.s
        )
    }
    get web3Tuple() {
        return [
            this.nonce,
            this.expiry,
            [
                ERC20_INTERFACE_ID,
                this.signer.wallet,
                this.signer.token,
                this.signer.amount,
                0
            ],
            [
                ERC20_INTERFACE_ID,
                this.sender.wallet,
                this.sender.token,
                this.sender.amount,
                0
            ],
            [
                ERC20_INTERFACE_ID,
                ZERO_ADDRESS,
                ZERO_ADDRESS,
                0,
                0
            ],
            [
                this.signer.wallet,
                this.verifyingContract,
                SIG191_VERSION,
                this.v,
                '0x'+this.r,
                '0x'+this.s
            ]
        ]
    }
}

module.exports = {
    Order,
}
