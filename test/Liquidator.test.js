const Liquidator = artifacts.require('LiquidatorMock')
const BN = web3.utils.toBN
const ONE_HUNDRED = BN(100).mul(BN(1e18))
const assertRevert = require('../true-currencies/test/helpers/assertRevert.js')['default']
const MockTrustToken = artifacts.require('MockTrustToken')
const TrueUSD = artifacts.require('TrueUSD')
const Airswap = artifacts.require('Swap')
const AirswapERC20TransferHandler = artifacts.require('AirswapERC20TransferHandler')
const TransferHandlerRegistry = artifacts.require('TransferHandlerRegistry')
const Registry = artifacts.require('RegistryMock')
const { Order } = require('./lib/airswap.js')
const Types = artifacts.require('Types')
const ERC20_KIND = '0x36372b07'
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const ZERO_BYTES32 = '0x0000000000000000000000000000000000000000000000000000000000000000'

contract('Liquidator', function(accounts) {
    const [_, owner, issuer, oneHundred, account1, account2, kycAccount, fakeUniswap, fakePool] = accounts
    beforeEach(async function() {
        this.registry = await Registry.new({ from: owner });
        this.rewardToken = await TrueUSD.new({ from: issuer });
        this.stakeToken = await MockTrustToken.new(this.registry.address, { from: issuer });
        await this.rewardToken.setRegistry(this.registry.address, {from: issuer})
        await this.rewardToken.mint(fakeUniswap, ONE_HUNDRED, {from:issuer});
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        await this.stakeToken.mint(fakeUniswap, ONE_HUNDRED, {from:issuer});
        await this.stakeToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        //await this.registry.subscribe(PASSED_KYCAML, this.stakeToken.address, {from: owner})
        //await this.registry.setAttributeValue(oneHundred, PASSED_KYCAML, 1, {from: owner})
        //await this.registry.setAttributeValue(kycAccount, PASSED_KYCAML, 1, {from: owner})
        this.transferHandler = await AirswapERC20TransferHandler.new({from: owner})
        this.transferHandlerRegistry = await TransferHandlerRegistry.new({from: owner})
        this.transferHandlerRegistry.addTransferHandler(ERC20_KIND, this.transferHandler.address,{from:owner})
        this.types = await Types.new()
        await Airswap.link('Types', this.types.address)
        this.airswap = await Airswap.new(this.transferHandlerRegistry.address, {from: owner})
        this.liquidator = await Liquidator.new(this.rewardToken.address, this.stakeToken.address, {from: owner})
    })
    describe('Airswap', function() {
        let nonce = 0
        let expiry = parseInt(Date.now() / 1000) + 12000
        it('registers a swap', async function() {
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED.mul(BN(2)), this.stakeToken.address)
            await order.sign()
            await this.liquidator.registerAirswap(order.web3Tuple)
            const trade = await this.liquidator.head.call()
            const next = await this.liquidator.next.call(trade)
            const orderInfo = await this.liquidator.airswapOrderInfo(trade, { gas: 3000000 })
            assert(next == ZERO_ADDRESS)
            assert(orderInfo.nonce == nonce)
            assert(orderInfo.expiry == expiry)
            assert(orderInfo.signerKind == ERC20_KIND)
            assert(orderInfo.signerWallet == oneHundred)
            assert(orderInfo.signerToken == this.rewardToken.address)
            assert(orderInfo.signerAmount == ONE_HUNDRED)
            assert(orderInfo.signerId == 0)
            assert(orderInfo.senderKind == ERC20_KIND)
            assert(orderInfo.senderWallet == this.liquidator.address)
            assert(orderInfo.senderToken == this.stakeToken.address)
            assert(orderInfo.senderAmount == ONE_HUNDRED.mul(BN(2)))
            assert(orderInfo.senderId == 0)
            assert(orderInfo.affiliateKind == ERC20_KIND)
            assert(orderInfo.affiliateWallet == ZERO_ADDRESS)
            assert(orderInfo.affiliateToken == ZERO_ADDRESS)
            assert(orderInfo.affiliateAmount == 0)
            assert(orderInfo.affiliateId == 0)
            assert(orderInfo.validator == this.airswap.address)
            assert(orderInfo.signatory == oneHundred)
            assert(orderInfo.version == '0x01')
            assert(['27', '28'].includes(orderInfo.v))
            assert(orderInfo.r.length == 66)
            assert(orderInfo.r != ZERO_BYTES32)
            assert(orderInfo.s.length == 66)
            assert(orderInfo.s != ZERO_BYTES32)
            nonce += 1
        })
    })
})
