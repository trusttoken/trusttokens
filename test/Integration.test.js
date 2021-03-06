const Airswap = artifacts.require('Swap')
const AirswapERC20TransferHandler = artifacts.require('AirswapERC20TransferHandler')
const TransferHandlerRegistry = artifacts.require('TransferHandlerRegistry')
const Registry = artifacts.require('RegistryMock')
const StakedToken = artifacts.require('StakedToken')
const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy')
const TrustToken = artifacts.require('MockTrustToken')
const MockERC20Token = artifacts.require('MockERC20Token')
const StakingOpportunityFactory = artifacts.require('StakingOpportunityFactory')
const StakedTokenProxy = artifacts.require('StakedTokenProxy')
const Liquidator = artifacts.require('Liquidator')
const Types = artifacts.require('Types')
const UniswapFactory = artifacts.require('uniswap_factory')
const UniswapExchange = artifacts.require('uniswap_exchange')

const timeMachine = require('ganache-time-traveler')
const bytes32 = require('@trusttoken/registry/test/helpers/bytes32.js')
const assertRevert = require('@trusttoken/registry/test/helpers/assertRevert.js')
const writeAttributeFor = require('@trusttoken/registry/test/helpers/writeAttributeFor.js')
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
const DEFAULT_RATIO = BN(1000);
const ERC20_KIND = '0x36372b07'
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const { hashDomain, Order } = require('./lib/airswap.js')


contract('Deployment', function(accounts) {
    const [_, account1, account2, deployer, owner, fakeController, oneHundred, kycAccount, kycWriteKey, approvedBeneficiary] = accounts // auditor, manager,
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
                        describe('Multisig Liquidator', function() {
                            beforeEach(async function() {
                                /*
                                this.multisigLiquidator = await MultisigLiquidator.new([owner, auditor, manager], this.liquidator.address)
                                this.liquidator.transferOwnership(this.multisigLiquidator.address, {from:deployer})
                                const action = web3.utils.sha3('claimOwnership()').slice(0, 10)
                                const sig1 = await signAction(manager, this.multisigLiquidator.address, 0, action)
                                const sig2 = await signAction(owner, this.multisigLiquidator.address, 0, action)
                                await this.multisigLiquidator.claimOwnership([sig1, sig2])
                                */
                            })
                            describe('Airswap', function() {
                                beforeEach(async function() {
                                    this.types = await Types.new()
                                    await Airswap.link('Types', this.types.address)
                                    this.transferHandler = await AirswapERC20TransferHandler.new({from: deployer})
                                    this.transferHandlerRegistry = await TransferHandlerRegistry.new({from: deployer})
                                    this.transferHandlerRegistry.addTransferHandler(ERC20_KIND, this.transferHandler.address,{from:deployer})
                                    this.airswap = await Airswap.new(this.transferHandlerRegistry.address, {from:deployer})
                                    await this.registry.setAttributeValue(this.airswap.address, AIRSWAP_VALIDATOR, hashDomain(this.airswap.address), {from:owner})
                                })
                                describe('Factory', function() {
                                    beforeEach(async function() {
                                        this.stakingImplementation = await StakedTokenProxy.new()
                                        this.factory = await StakingOpportunityFactory.new(this.registry.address, this.stakingImplementation.address, {from:deployer})
                                        await this.registry.setAttributeValue(this.factory.address, writeAttributeFor(IS_REGISTERED_CONTRACT), 1, {from:owner})
                                    })
                                    describe('Staking', function() {
                                        beforeEach(async function() {
                                            const stakeCreation = await this.factory.createProxyStakingOpportunity(this.trust.address, this.tusd.address, this.liquidator.address)
                                            this.stakedTrust = await StakedToken.at(stakeCreation.logs[0].args.opportunity)
                                            //const action = web3.utils.sha3('setPool(address)').slice(0, 10) + addressBytes32(this.stakedTrust.address)
                                            //const sig1 = await signAction(manager, this.multisigLiquidator.address, 1, action)
                                            //const sig2 = await signAction(owner, this.multisigLiquidator.address, 1, action)
                                            //await this.multisigLiquidator.setPool(this.stakedTrust.address, [sig1, sig2])
                                            //console.log(this.stakedTrust)
                                            await this.liquidator.setPool(this.stakedTrust.address, {from:owner})
                                            await this.registry.setAttributeValue(kycWriteKey, writeAttributeFor(PASSED_KYCAML), 1, {from:owner})
                                            await this.registry.setAttributeValue(kycAccount, PASSED_KYCAML, 1, {from:kycWriteKey})
                                        })
                                        describe('After Staking', function() {
                                            beforeEach(async function() {
                                                await this.trust.transfer(this.stakedTrust.address, ONE_HUNDRED_BITCOIN, {from:account1})
                                            })
                                            it('staked', async function() {
                                                assert(ONE_HUNDRED_BITCOIN.eq(await this.trust.balanceOf(this.stakedTrust.address)))
                                                assert(ONE_HUNDRED_BITCOIN.mul(DEFAULT_RATIO).eq(await this.stakedTrust.balanceOf(account1)))
                                            })
                                            it('can reclaim stake directly', async function() {
                                                // const action = web3.utils.sha3('reclaimStake(address,uint256)').slice(0, 10) + addressBytes32(approvedBeneficiary) + uint256Bytes32(ONE_HUNDRED_BITCOIN)
                                                // const sig1 = await signAction(manager, this.multisigLiquidator.address, 2, action)
                                                // const sig2 = await signAction(owner, this.multisigLiquidator.address, 2, action)
                                                // await this.multisigLiquidator.reclaimStake(approvedBeneficiary, ONE_HUNDRED_BITCOIN, [sig1, sig2])
                                                await this.liquidator.reclaimStake(approvedBeneficiary, ONE_HUNDRED_BITCOIN, {from:owner})
                                                assert.equal(0, await this.trust.balanceOf(this.stakedTrust.address))
                                                assert(ONE_HUNDRED_BITCOIN.eq(await this.trust.balanceOf(approvedBeneficiary)))
                                            })
                                            it('can reclaim', async function() {
                                                // const action = web3.utils.sha3('reclaim(address,int256)').slice(0, 10) + addressBytes32(approvedBeneficiary) + uint256Bytes32(ONE_HUNDRED_ETHER)
                                                // const sig1 = await signAction(manager, this.multisigLiquidator.address, 2, action)
                                                // const sig2 = await signAction(owner, this.multisigLiquidator.address, 2, action)
                                                // await this.multisigLiquidator.reclaim(approvedBeneficiary, ONE_HUNDRED_ETHER, [sig1, sig2])
                                                await this.liquidator.reclaim(approvedBeneficiary, ONE_HUNDRED_ETHER, {from:owner})
                                            })
                                            // skipping in current implemention becuase we are not using airswap
                                            it.skip('can reclaim with airswap', async function() {
                                                let expiry = parseInt(Date.now() / 1000) + 12000
                                                await this.tusd.approve(this.airswap.address, ONE_HUNDRED_ETHER, {from:oneHundred})
                                                await this.tusd.mint(oneHundred, ONE_HUNDRED_ETHER, {from:fakeController})
                                                let order = new Order(0, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.tusd.address, this.liquidator.address, ONE_HUNDRED_BITCOIN, this.trust.address)
                                                await order.sign()
                                                await this.liquidator.registerAirswap(order.web3Tuple, {from:owner})
                                                // const action = web3.utils.sha3('reclaim(address,int256)').slice(0, 10) + addressBytes32(approvedBeneficiary) + uint256Bytes32(ONE_HUNDRED_ETHER)
                                                // const sig1 = await signAction(manager, this.multisigLiquidator.address, 2, action)
                                                // const sig2 = await signAction(owner, this.multisigLiquidator.address, 2, action)
                                                // await this.multisigLiquidator.reclaim(approvedBeneficiary, ONE_HUNDRED_ETHER, [sig1, sig2])
                                                await this.liquidator.reclaim(approvedBeneficiary, ONE_HUNDRED_ETHER, {from:owner})
                                            })
                                            it('can claim rewards', async function() {
                                                await this.tusd.mint(this.stakedTrust.address, ONE_ETHER, {from:fakeController})
                                                await this.stakedTrust.transfer(kycAccount, ONE_HUNDRED_BITCOIN.mul(DEFAULT_RATIO), {from:account1})
                                                await this.stakedTrust.claimRewards(account1, {from:kycAccount})
                                                assert(ONE_ETHER.eq(await this.tusd.balanceOf.call(account1)))
                                            })
                                            describe('Unstaking', function() {
                                                beforeEach(async function() {
                                                    const init = await this.stakedTrust.initUnstake(ONE_HUNDRED_BITCOIN.mul(DEFAULT_RATIO), {from:account1})
                                                    this.timestamp = init.logs[2].args.timestamp
                                                })
                                                it('disallows finalizing unstaking', async function() {
                                                    await assertRevert(this.stakedTrust.finalizeUnstake(oneHundred, [this.timestamp], {from:account1}))
                                                })
                                                describe('2 weeks later', function() {
                                                    beforeEach(async function() {
                                                        await timeMachine.advanceTime(14 * 24 * 60 * 60)
                                                    })
                                                    it('allows finalizing unstaking', async function() {
                                                        await this.stakedTrust.finalizeUnstake(oneHundred, [this.timestamp], {from:account1})
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
        })
    })
})
