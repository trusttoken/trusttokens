const Registry = artifacts.require('RegistryMock')
//const WhitelistedFungibleToken = artifacts.require('WhitelistedFungibleToken')
const MockStakingPool = artifacts.require('MockStakingPool')
const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy')
const MockTrustToken = artifacts.require('MockTrustToken')
const TrueUSD = artifacts.require('TrueUSD')

const bytes32 = require('../true-currencies/test/helpers/bytes32.js')
const assertRevert = require('../true-currencies/test/helpers/assertRevert.js')['default']

const IS_DEPOSIT_ADDRESS = bytes32('isDepositAddress')
const PASSED_KYCAML = bytes32('hasPassedKYC/AML')
const BN = web3.utils.toBN
const ONE_HUNDRED = BN(100).mul(BN(1e18))

contract('StakingPool', function(accounts) {
    const [_, owner, issuer, oneHundred, account1, account2, fakeUniswap, fakeLiquidator] = accounts
    beforeEach(async function() {
        this.registry = await Registry.new({ from: owner });
        this.rewardToken = await TrueUSD.new({ from: issuer });
        this.favoredToken = await MockTrustToken.new({ from: issuer });
        this.pool = await MockStakingPool.new(this.registry.address, this.rewardToken.address, this.favoredToken.address, fakeUniswap, fakeLiquidator, {from: owner})
        await this.rewardToken.setRegistry(this.registry.address, {from: issuer})
        await this.rewardToken.mint(fakeUniswap, ONE_HUNDRED, {from:issuer});
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        await this.favoredToken.mint(fakeUniswap, ONE_HUNDRED, {from:issuer});
        await this.favoredToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
    })
    describe('StakingPool', function() {
        it('Cannot mint to unregistered recipient', async function() {
            await assertRevert(this.token.mint(oneHundred, ONE_HUNDRED))
        })
        async function mintOneHundred() {
            assert.equal(await this.token.totalSupply(), 0)
            await this.registry.subscribe(PASSED_KYCAML, this.token.address, {from: owner})
            await this.registry.setAttributeValue(oneHundred, PASSED_KYCAML, 1, {from: owner})
            await this.token.mint(oneHundred, ONE_HUNDRED, {from: issuer})
            const supply = await this.token.totalSupply()
            assert(supply.eq(ONE_HUNDRED))
            const balance = await this.token.balanceOf(oneHundred)
            assert(balance.eq(ONE_HUNDRED))
        }
        it('Mints, increasing the supply', mintOneHundred)
        it('cannot be transferred to an unregistered recipient', async function() {
            await mintOneHundred.bind(this)()
            await assertRevert(this.token.transfer(account1, ONE_HUNDRED, { from: oneHundred }))
        })
        it('is transferrable', async function() {
            await mintOneHundred.bind(this)()
            await this.registry.setAttributeValue(account1, PASSED_KYCAML, 1, { from: owner })
            await this.token.transfer(account1, ONE_HUNDRED, { from: oneHundred })
            const supply = await this.token.totalSupply()
            assert(supply.eq(ONE_HUNDRED))
            const balance100 = await this.token.balanceOf(oneHundred)
            assert(balance100.eq(BN(0)))
            const balance1 = await this.token.balanceOf(account1)
            assert(balance1.eq(ONE_HUNDRED))
        })
    })
})
