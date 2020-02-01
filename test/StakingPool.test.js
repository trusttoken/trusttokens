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
const ONE_ETHER = BN(1e18)
const ONE_HUNDRED_ETHER = BN(100).mul(ONE_ETHER)
const ONE_BITCOIN = BN(1e8)
const ONE_HUNDRED_BITCOIN = BN(100).mul(ONE_BITCOIN)
const DEFAULT_RATIO = BN(2000);

contract('StakedAsset', function(accounts) {
    const [_, owner, issuer, oneHundred, account1, account2, kycAccount, fakeLiquidator] = accounts
    beforeEach(async function() {
        this.registry = await Registry.new({ from: owner });
        this.rewardToken = await TrueUSD.new({ from: issuer });
        this.stakeToken = await TrustToken.new(this.registry.address, { from: issuer });
        this.pool = await StakedToken.new(this.stakeToken.address, this.rewardToken.address, this.registry.address, fakeLiquidator, {from: owner})
        await this.rewardToken.setRegistry(this.registry.address, {from: issuer})
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED_ETHER, {from:issuer});
        await this.stakeToken.mint(oneHundred, ONE_HUNDRED_BITCOIN, {from:issuer});
        await this.registry.subscribe(PASSED_KYCAML, this.pool.address, {from: owner})
        await this.registry.setAttributeValue(kycAccount, PASSED_KYCAML, 1, {from: owner})
        await this.registry.subscribe(IS_REGISTERED_CONTRACT, this.stakeToken.address, {from:owner})
        await this.registry.subscribe(IS_REGISTERED_CONTRACT, this.rewardToken.address, {from:owner})
        await this.registry.setAttributeValue(this.pool.address, IS_REGISTERED_CONTRACT, 1, {from:owner})
    })
    describe('Staked Asset', function() {
        it('allows deposit', async function() {
            await this.stakeToken.transfer(this.pool.address, ONE_HUNDRED_BITCOIN, {from: oneHundred})
            assert(ONE_HUNDRED_BITCOIN.eq(await this.stakeToken.balanceOf(this.pool.address)), "100 staked tokens")
            assert(await this.pool.balanceOf.call(oneHundred), DEFAULT_RATIO.mul(ONE_HUNDRED_ETHER))
        })
        it('allows liquidator to withdraw and deposit', async function() {
            await this.stakeToken.transfer(this.pool.address, ONE_HUNDRED_BITCOIN, {from: oneHundred})

            await this.stakeToken.transferFrom(this.pool.address, fakeLiquidator, ONE_HUNDRED_BITCOIN, {from:fakeLiquidator})
            assert(ONE_HUNDRED_BITCOIN.eq(await this.stakeToken.balanceOf.call(fakeLiquidator)), "100 withdrawn")

            await this.stakeToken.transfer(this.pool.address, ONE_HUNDRED_BITCOIN, {from:fakeLiquidator})
            assert(ONE_HUNDRED_BITCOIN.eq(await this.stakeToken.balanceOf.call(this.pool.address)), "100 returned")
            assert.equal(0, await this.pool.balanceOf.call(fakeLiquidator), "liquidator does not get any stake")
        })
        it('awards to stakers, maintains remainder, claims, transfers unclaimed rewards', async function() {
            // oneHundred: 45, account1: 25, account2: 20, kycAccount: 10
            await this.stakeToken.transfer(kycAccount, BN(10).mul(ONE_BITCOIN), {from: oneHundred})
            await this.stakeToken.transfer(account1, BN(25).mul(ONE_BITCOIN), {from: oneHundred})
            await this.stakeToken.transfer(account2, BN(20).mul(ONE_BITCOIN), {from: oneHundred})
            // all stake
            await this.stakeToken.transfer(this.pool.address, BN(45).mul(ONE_BITCOIN), {from: oneHundred})
            await this.stakeToken.transfer(this.pool.address, BN(25).mul(ONE_BITCOIN), {from: account1})
            await this.stakeToken.transfer(this.pool.address, BN(20).mul(ONE_BITCOIN), {from: account2})
            await this.stakeToken.transfer(this.pool.address, BN(10).mul(ONE_BITCOIN), {from: kycAccount})

            assert(ONE_HUNDRED_BITCOIN.eq(await this.stakeToken.balanceOf.call(this.pool.address)))
            const oneHundredStake = BN(45).mul(ONE_BITCOIN).mul(DEFAULT_RATIO)
            assert(oneHundredStake.eq(await this.pool.balanceOf.call(oneHundred)))

            const award1 = await this.rewardToken.transfer(this.pool.address, BN(10).mul(ONE_ETHER), {from:oneHundred})
            assert(BN(9).mul(ONE_ETHER).div(BN(2)).eq(await this.pool.unclaimedRewards.call(oneHundred)))
            assert(BN(5).mul(ONE_ETHER).div(BN(2)).eq(await this.pool.unclaimedRewards.call(account1)))
            assert(BN(2).mul(ONE_ETHER).eq(await this.pool.unclaimedRewards.call(account2)))
            assert(ONE_ETHER.eq(await this.pool.unclaimedRewards.call(kycAccount)))

            // no immediate reward
            const award2 = await this.rewardToken.transfer(this.pool.address, BN(10).mul(ONE_BITCOIN), {from:oneHundred})
            assert(BN(9).mul(ONE_ETHER).div(BN(2)).eq(await this.pool.unclaimedRewards.call(oneHundred)))
            assert(BN(5).mul(ONE_ETHER).div(BN(2)).eq(await this.pool.unclaimedRewards.call(account1)))
            assert(BN(2).mul(ONE_ETHER).eq(await this.pool.unclaimedRewards.call(account2)))
            assert(ONE_ETHER.eq(await this.pool.unclaimedRewards.call(kycAccount)))

            // remainder accrues
            const award3 = await this.rewardToken.transfer(this.pool.address, BN(10).mul(ONE_ETHER).sub(BN(10).mul(ONE_BITCOIN)), {from:oneHundred})
            assert(BN(9).mul(ONE_ETHER).eq(await this.pool.unclaimedRewards.call(oneHundred)))
            assert(BN(5).mul(ONE_ETHER).eq(await this.pool.unclaimedRewards.call(account1)))
            assert(BN(4).mul(ONE_ETHER).eq(await this.pool.unclaimedRewards.call(account2)))
            assert(BN(2).mul(ONE_ETHER).eq(await this.pool.unclaimedRewards.call(kycAccount)))

            // claim reward
            const claim2 = await this.pool.claimRewards(kycAccount, {from:kycAccount})
            assert.equal(0, await this.pool.unclaimedRewards.call(kycAccount))
            assert(BN(2).mul(ONE_ETHER).eq(await this.rewardToken.balanceOf.call(kycAccount)))

            // transfer unclaimed rewards
            const transfer = await this.pool.transfer(kycAccount, oneHundredStake, {from:oneHundred})
            assert.equal(0, await this.pool.unclaimedRewards.call(oneHundred))
            console.log(await this.pool.unclaimedRewards.call(kycAccount))
            assert(BN(9).mul(ONE_ETHER).sub(await this.pool.unclaimedRewards.call(kycAccount)).lt(await this.pool.totalSupply.call()))

            const claim9 = await this.pool.claimRewards(kycAccount,{from:kycAccount})
            assert.equal(0, await this.pool.unclaimedRewards.call(kycAccount))
            assert(BN(11).mul(ONE_ETHER).sub(await this.rewardToken.balanceOf.call(kycAccount)).lt(await this.pool.totalSupply.call()))
        })
    })
})
