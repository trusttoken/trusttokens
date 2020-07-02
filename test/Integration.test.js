const Registry = artifacts.require('RegistryMock')
const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy')
const TrustToken = artifacts.require('MockTrustToken')
const MockERC20Token = artifacts.require('MockERC20Token')
const Liquidator = artifacts.require('Liquidator')
const UniswapFactory = artifacts.require('uniswap_factory')
const UniswapExchange = artifacts.require('uniswap_exchange')

const bytes32 = require('@trusttoken/registry/test/helpers/bytes32.js')
const assertRevert = require('@trusttoken/registry/test/helpers/assertRevert.js')
const IS_DEPOSIT_ADDRESS = bytes32('isDepositAddress')
const IS_REGISTERED_CONTRACT = bytes32('isRegisteredContract')
const BLACKLISTED = '0x6973426c61636b6c697374656400000000000000000000000000000000000000'
const AIRSWAP_VALIDATOR = bytes32('AirswapValidatorDomain')
const APPROVED_BENEFICIARY = bytes32('approvedBeneficiary')
const BN = web3.utils.toBN
const ONE_ETHER = BN(1e18)
const ONE_HUNDRED_ETHER = BN(100).mul(ONE_ETHER)
const ONE_BITCOIN = BN(1e8)
const ONE_HUNDRED_BITCOIN = BN(100).mul(ONE_BITCOIN)
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'


contract('Deployment', function(accounts) {
    const [_, account1, account2, deployer, owner, oneHundred, approvedBeneficiary] = accounts
    describe('TrueUSD and Registry', function() {
        beforeEach(async function() {
            // registry
            this.registryProxy = await OwnedUpgradeabilityProxy.new({from:deployer})
            this.registryImplementation = await Registry.new({from:deployer})
            await this.registryProxy.upgradeTo(this.registryImplementation.address, {from:deployer})
            this.registry = await Registry.at(this.registryProxy.address)
            await this.registry.initialize({from:deployer})
            // trueusd
            this.tusdProxy = await OwnedUpgradeabilityProxy.new({from:deployer})
            this.tusdMockImplementation = await MockERC20Token.new(ZERO_ADDRESS, 0, {from:deployer})
            this.tusdImplementation = await MockERC20Token.new({from:deployer})
            await this.tusdProxy.upgradeTo(this.tusdMockImplementation.address, {from:deployer})
            this.tusd = await MockERC20Token.at(this.tusdProxy.address)
            // await this.tusdMock.initialize({from:deployer})
            await this.tusdProxy.upgradeTo(this.tusdImplementation.address, {from:deployer})
            await this.tusd.setRegistry(this.registry.address, {from:deployer})
            // subscriptions
            await this.registry.subscribe(IS_REGISTERED_CONTRACT, this.tusd.address, {from:deployer})
            await this.registry.subscribe(BLACKLISTED, this.tusd.address, {from:deployer})
            await this.registry.subscribe(IS_DEPOSIT_ADDRESS, this.tusd.address, {from:deployer})
            // transfer proxy ownership
            await this.registryProxy.transferProxyOwnership(owner, {from:deployer})
            await this.registryProxy.claimProxyOwnership({from:owner})
            await this.tusdProxy.transferProxyOwnership(owner, {from:deployer})
            await this.tusdProxy.claimProxyOwnership({from:owner})
            // transfer ownership
            // await this.tusd.transferOwnership(fakeController, {from:deployer})
            // await this.tusd.claimOwnership({from:fakeController})
            await this.registry.transferOwnership(owner, {from:deployer})
            await this.registry.claimOwnership({from:owner})
            // mint 100
            // await this.tusd.mint(oneHundred, ONE_HUNDRED_ETHER, {from:fakeController})
            await this.tusd.mint(oneHundred, ONE_HUNDRED_ETHER, {from:deployer})
        })
        it('has expected owners', async function() {
            assert.equal(await this.registryProxy.proxyOwner.call(), owner)
            assert.equal(await this.tusdProxy.proxyOwner.call(), owner)
            assert.equal(await this.registry.owner.call(), owner)
            // assert.equal(await this.tusd.owner.call(), fakeController)
        })
        it.skip('TUSD registry is registry', async function() {
            assert.equal(await this.tusd.registry.call(), this.registry.address)
        })
        it('minted TUSD', async function() {
            assert(ONE_HUNDRED_ETHER.eq(await this.tusd.balanceOf.call(oneHundred)))
        })
        describe('TrustToken', function() {
            beforeEach(async function() {
                // TrustToken
                /*
                this.trustProxy = await OwnedUpgradeabilityProxy.new({from:deployer})
                this.trustImplementation = await TrustToken.new(this.registry.address, {from:deployer})
                this.trustProxy.upgradeTo(this.trustImplementation.address, {from:deployer})
                this.trust = await TrustToken.at(this.trustProxy.address)
                // transer proxy ownership
                await this.trustProxy.transferProxyOwnership(owner, {from:deployer})
                await this.trustProxy.claimProxyOwnership({from:owner})
                */
                this.trust = await TrustToken.new({from:deployer})
                await this.trust.initialize(this.registry.address, {from:deployer})
                await this.registry.subscribe(IS_REGISTERED_CONTRACT, this.trust.address, {from:owner})
            })

            it('cannot initialize twice', async function () {
                await assertRevert(this.trust.initialize(this.registry.address, {from:deployer}))
            })

            it('TrustToken owner is deployer', async function() {
                //assert.equal(await this.trust.registry.call(), this.registry.address)
                assert.equal(await this.trust.owner.call(), deployer)
            })
            describe('Mint', function() {
                beforeEach(async function() {
                    // mint 100
                    this.trust.mint(oneHundred, ONE_HUNDRED_BITCOIN, {from: deployer});
                    this.trust.mint(account1, ONE_HUNDRED_BITCOIN, {from: deployer});
                    this.trust.mint(account2, ONE_HUNDRED_BITCOIN, {from: deployer});
                })
                it('issued TrustTokens', async function() {
                    assert(ONE_HUNDRED_BITCOIN.eq(await this.trust.balanceOf.call(oneHundred)))
                })
                describe('Uniswap', function() {
                    beforeEach(async function() {
                        this.uniswapFactory = await UniswapFactory.new()
                        this.uniswapTemplate = await UniswapExchange.new()
                        await this.uniswapFactory.initializeFactory(this.uniswapTemplate.address)
                        this.tusdUniswapAddress = (await this.uniswapFactory.createExchange(this.tusd.address)).logs[0].args.exchange
                        this.tusdUniswap = await UniswapExchange.at(this.tusdUniswapAddress)
                        this.trustUniswapAddress = (await this.uniswapFactory.createExchange(this.trust.address)).logs[0].args.exchange
                        this.trustUniswap = await UniswapExchange.at(this.trustUniswapAddress)
                        // add liquidity
                        await this.tusd.approve(this.tusdUniswap.address, ONE_HUNDRED_ETHER, {from:oneHundred})
                        const expiry = parseInt(Date.now() / 1000) + 12000
                        await this.tusdUniswap.addLiquidity(ONE_HUNDRED_ETHER, ONE_HUNDRED_ETHER, expiry, {from:oneHundred, value:1e17})
                        await this.trust.approve(this.trustUniswap.address, ONE_HUNDRED_BITCOIN, {from:oneHundred})
                        await this.trustUniswap.addLiquidity(ONE_HUNDRED_BITCOIN, ONE_HUNDRED_BITCOIN, expiry, {from:oneHundred, value:1e17})
                    })
                    it('provided Uniswap liquidity', async function() {
                        assert(ONE_HUNDRED_BITCOIN.eq(await this.trust.balanceOf.call(this.trustUniswap.address)))
                        assert(ONE_HUNDRED_ETHER.eq(await this.tusd.balanceOf.call(this.tusdUniswap.address)))
                    })
                    describe('Liquidator', function() {
                        beforeEach(async function() {
                            this.liquidator = await Liquidator.new({from:deployer})
                            await this.liquidator.configure(this.registry.address, this.tusd.address, this.trust.address, this.tusdUniswap.address, this.trustUniswap.address, {from:deployer})
                            await this.liquidator.transferOwnership(owner, {from:deployer})
                            await this.liquidator.claimOwnership({from: owner})
                            await this.registry.subscribe(AIRSWAP_VALIDATOR, this.liquidator.address, {from:owner})
                            await this.registry.subscribe(APPROVED_BENEFICIARY, this.liquidator.address, {from:owner})
                            await this.registry.setAttributeValue(approvedBeneficiary, APPROVED_BENEFICIARY, 1, {from:owner})
                        })
                    })
                })
            })
        })
    })
})
