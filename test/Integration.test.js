const Airswap = artifacts.require('Swap')
const AirswapERC20TransferHandler = artifacts.require('AirswapERC20TransferHandler')
const TransferHandlerRegistry = artifacts.require('TransferHandlerRegistry')
const Registry = artifacts.require('RegistryMock')
const StakedToken = artifacts.require('MockStakedToken')
const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy')
const TrustToken = artifacts.require('MockTrustToken')
const TrueUSDMock = artifacts.require('TrueUSDMock')
const TrueUSD = artifacts.require('TrueUSD')
const StakingOpportunityFactory = artifacts.require('StakingOpportunityFactory')
const StakedTokenProxyImplementation = artifacts.require('StakedTokenProxyImplementation')
const StakedTokenProxyMigrationMock = artifacts.require('StakedTokenProxyMigrationMock')
const Liquidator = artifacts.require('LiquidatorMock')
const Vesting = artifacts.require('VestingMock')
const Types = artifacts.require('Types')
const UniswapFactory = artifacts.require('uniswap_factory')
const UniswapExchange = artifacts.require('uniswap_exchange')

const bytes32 = require('../true-currencies/test/helpers/bytes32.js')
const assertRevert = require('../true-currencies/test/helpers/assertRevert.js')['default']
const writeAttributeFor = require('../true-currencies/registry/test/helpers/writeAttributeFor.js')
const IS_DEPOSIT_ADDRESS = bytes32('isDepositAddress')
const IS_REGISTERED_CONTRACT = bytes32('isRegisteredContract')
const BLACKLISTED = '0x6973426c61636b6c697374656400000000000000000000000000000000000000'
const PASSED_KYCAML = bytes32('hasPassedKYC/AML')
const AIRSWAP_VALIDATOR = bytes32('AirswapValidatorDomain')
const APPROVED_BENEFICIARY = bytes32('approvedBeneficiary')
const BN = web3.utils.toBN
const ONE_ETHER = BN(1e18)
const ONE_HUNDRED_ETHER = BN(100).mul(ONE_ETHER)
const ONE_BITCOIN = BN(1e8)
const ONE_HUNDRED_BITCOIN = BN(100).mul(ONE_BITCOIN)
const DEFAULT_RATIO = BN(2000);
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const { addressBytes32, uint256Bytes32 } = require('./lib/abi.js')
const { signAction } = require('./lib/multisigLiquidator.js')


contract('Deployment', function(accounts) {
    const [_, deployer, owner, fakeController, oneHundred, account1, account2, kycAccount, auditor, manager, approvedBeneficiary] = accounts
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
            this.tusdMockImplementation = await TrueUSDMock.new(ZERO_ADDRESS, 0, {from:deployer})
            this.tusdImplementation = await TrueUSD.new({from:deployer})
            await this.tusdProxy.upgradeTo(this.tusdMockImplementation.address, {from:deployer})
            this.tusdMock = await TrueUSDMock.at(this.tusdProxy.address)
            this.tusd = await TrueUSD.at(this.tusdProxy.address)
            await this.tusdMock.initialize({from:deployer})
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
            await this.tusd.transferOwnership(fakeController, {from:deployer})
            await this.tusd.claimOwnership({from:fakeController})
            await this.registry.transferOwnership(owner, {from:deployer})
            await this.registry.claimOwnership({from:owner})
            // mint 100
            await this.tusd.mint(oneHundred, ONE_HUNDRED_ETHER, {from:fakeController})
        })
        it('has expected owners', async function() {
            assert.equal(await this.registryProxy.proxyOwner.call(), owner)
            assert.equal(await this.tusdProxy.proxyOwner.call(), owner)
            assert.equal(await this.registry.owner.call(), owner)
            assert.equal(await this.tusd.owner.call(), fakeController)
        })
        it('TUSD registry is registry', async function() {
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
                this.trust = await TrustToken.new(this.registry.address, {from:deployer})
            })
            it('TrustToken owner is deployer', async function() {
                //assert.equal(await this.trust.registry.call(), this.registry.address)
                assert.equal(await this.trust.owner.call(), deployer)
            })
            describe('Vesting', function() {
                beforeEach(async function() {
                    this.vesting = await Vesting.new(this.trust.address, {from:deployer})
                    await this.trust.transferOwnership(this.vesting.address, {from:deployer})
                    await this.vesting.transferOwnership(owner, {from:deployer})
                    await this.vesting.claimTokenOwnership({from:deployer})
                    await this.vesting.claimOwnership({from:owner})
                    // mint 100
                    const now = parseInt(Date.now() / 1000)
                    await this.vesting.scheduleMint(oneHundred, ONE_HUNDRED_BITCOIN, now, {from:owner})
                    await this.vesting.claim(0, {from:oneHundred})
                    await this.vesting.scheduleMint(account1, ONE_HUNDRED_BITCOIN, now, {from:owner})
                    await this.vesting.claim(1, {from:account1})
                    await this.vesting.scheduleMint(account2, ONE_HUNDRED_BITCOIN, now, {from:owner})
                    await this.vesting.claim(2, {from:account2})
                })
                it('TrustToken is owned by Vesting contract which is owned by owner', async function() {
                    assert.equal(await this.trust.owner.call(), this.vesting.address)
                    assert.equal(await this.vesting.owner.call(), owner)
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
                        await this.trustUniswap.addLiquidity(ONE_HUNDRED_ETHER, ONE_HUNDRED_BITCOIN, expiry, {from:oneHundred, value:1e17})
                    })
                    it('provided Uniswap liquidity', async function() {
                        assert(ONE_HUNDRED_BITCOIN.eq(await this.trust.balanceOf.call(this.trustUniswap.address)))
                        assert(ONE_HUNDRED_ETHER.eq(await this.tusd.balanceOf.call(this.tusdUniswap.address)))
                    })
                    describe('Liquidator', function() {
                        beforeEach(async function() {
                            this.liquidator = await Liquidator.new({from:deployer})
                            await this.registry.subscribe(AIRSWAP_VALIDATOR, this.liquidator.address, {from:owner})
                            await this.registry.subscribe(APPROVED_BENEFICIARY, this.liquidator.address, {from:owner})
                            await this.registry.setAttributeValue(approvedBeneficiary, APPROVED_BENEFICIARY, 1, {from:owner})
                        })
                        describe('Multisig Liquidator', function() {
                            beforeEach(async function() {
                                this.multisigLiquidator = await MultisigLiquidator.new([owner, auditor, manager], this.liquidator.address)
                                this.liquidator.transferOwnership(this.multisigLiquidator.address, {from:deployer})
                                const action = web3.utils.sha3('claimOwnership()').slice(0, 10)
                                const sig1 = await signAction(manager, this.multisigLiquidator.address, 0, action)
                                const sig2 = await signAction(owner, this.multisigLiquidator.address, 0, action)
                                await this.multisigLiquidator.claimOwnership([sig1, sig2])
                            })
                            describe('Airswap', function() {
                                beforeEach(async function() {
                                    this.types = await Types.new()
                                    await Airswap.link('Types', this.types.address)
                                    this.transferHandler = await AirswapERC20TransferHandler.new({from: deployer})
                                    this.transferHandlerRegistry = await TransferHandlerRegistry.new({from: deployer})
                                    this.transferHandlerRegistry.addTransferHandler(ERC20_KIND, this.transferHandler.address,{from:deployer})
                                    this.airswap = await Airswap.new(this.transferHandlerRegistry.new({from:deployer}))
                                    await this.registry.setAttributeValue(this.airswap.address, AIRSWAP_VALIDATOR, 1, {from:owner})
                                })
                                describe('Factory', function() {
                                    beforeEach(async function() {
                                        this.factory = await StakingOpportunityFactory.new(this.registry.address, {from:deployer})
                                    })
                                    describe('Staking', function() {
                                        beforeEach(async function() {
                                            this.stakedTrust = await StakedToken.at((await this.factory.createProxyStakingOpportunity(this.trust.address, this.tusd.address, this.liquidator.address))[0].args.opportunity)
                                        })
                                    })
                                })
                            })
                        })
                    })
                })
            })
        })
    })
})