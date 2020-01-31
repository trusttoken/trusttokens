const Registry = artifacts.require('RegistryMock')
//const WhitelistedFungibleToken = artifacts.require('WhitelistedFungibleToken')
const StakedToken = artifacts.require('MockStakedToken')
const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy')
const TrustToken = artifacts.require('MockTrustToken')
const TrueUSD = artifacts.require('TrueUSD')

const bytes32 = require('../true-currencies/test/helpers/bytes32.js')
const assertRevert = require('../true-currencies/test/helpers/assertRevert.js')['default']

const IS_DEPOSIT_ADDRESS = bytes32('isDepositAddress')
const IS_REGISTERED_CONTRACT = bytes32('isRegisteredContract')
const PASSED_KYCAML = bytes32('hasPassedKYC/AML')
const BN = web3.utils.toBN
const ONE_HUNDRED = BN(100).mul(BN(1e18))
const DEFAULT_RATIO = BN(2100);

contract('StakedAsset', function(accounts) {
    const [_, owner, issuer, oneHundred, account1, account2, kycAccount, fakeLiquidator] = accounts
    beforeEach(async function() {
        this.registry = await Registry.new({ from: owner });
        this.rewardToken = await TrueUSD.new({ from: issuer });
        this.stakeToken = await TrustToken.new(this.registry.address, { from: issuer });
        this.pool = await StakedToken.new(this.stakeToken.address, this.rewardToken.address, this.registry.address, fakeLiquidator, {from: owner})
        await this.rewardToken.setRegistry(this.registry.address, {from: issuer})
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        await this.stakeToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        await this.registry.subscribe(PASSED_KYCAML, this.pool.address, {from: owner})
        await this.registry.setAttributeValue(kycAccount, PASSED_KYCAML, 1, {from: owner})
        await this.registry.subscribe(IS_REGISTERED_CONTRACT, this.stakeToken.address, {from:owner})
        await this.registry.setAttributeValue(this.pool.address, IS_REGISTERED_CONTRACT, 1, {from:owner})
    })
    describe('Staked Asset', function() {
        it('allows deposit', async function() {
            await this.stakeToken.transfer(this.pool.address, ONE_HUNDRED, {from: oneHundred})
            assert(ONE_HUNDRED.eq(await this.stakeToken.balanceOf(this.pool.address)), "100 staked tokens")
            assert(await this.pool.balanceOf.call(oneHundred), DEFAULT_RATIO.mul(ONE_HUNDRED))
        })
        it('allows liquidator to withdraw and deposit', async function() {
            await this.stakeToken.transfer(this.pool.address, ONE_HUNDRED, {from: oneHundred})

            await this.stakeToken.transferFrom(this.pool.address, fakeLiquidator, ONE_HUNDRED, {from:fakeLiquidator})
            assert(ONE_HUNDRED.eq(await this.stakeToken.balanceOf.call(fakeLiquidator)), "100 withdrawn")

            await this.stakeToken.transfer(this.pool.address, ONE_HUNDRED, {from:fakeLiquidator})
            assert(ONE_HUNDRED.eq(await this.stakeToken.balanceOf.call(this.pool.address)), "100 returned")
            assert.equal(0, this.pool.balanceOf.call(fakeLiquidator), "liquidator does not get any stake")
        })
    })
})
