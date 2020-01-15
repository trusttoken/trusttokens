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
        this.liquidator = await Liquidator.new(this.rewardToken.address, {from: owner})
    })
    describe('Airswap', function() {
        let nonce = 0
        let expiry = parseInt(Date.now() / 1000) + 12000
        it('registers a swap', async function() {
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED.mul(BN(2)), this.stakeToken.address)
            nonce += 1
            await order.sign()
            await this.liquidator.registerAirswap(order.web3Tuple)
        })
    })
})
