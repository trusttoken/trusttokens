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
    const [_, owner, issuer, oneHundred, account1, account2, kycAccount, fakeUniswap, fakeLiquidator] = accounts
    beforeEach(async function() {
        this.registry = await Registry.new({ from: owner });
        this.rewardToken = await TrueUSD.new({ from: issuer });
        this.favoredToken = await MockTrustToken.new(this.registry.address, { from: issuer });
        this.pool = await MockStakingPool.new(this.registry.address, this.rewardToken.address, this.favoredToken.address, fakeUniswap, fakeLiquidator, {from: owner})
        await this.rewardToken.setRegistry(this.registry.address, {from: issuer})
        await this.rewardToken.mint(fakeUniswap, ONE_HUNDRED, {from:issuer});
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        await this.favoredToken.mint(fakeUniswap, ONE_HUNDRED, {from:issuer});
        await this.favoredToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        //await this.registry.subscribe(PASSED_KYCAML, this.favoredToken.address, {from: owner})
        await this.registry.setAttributeValue(oneHundred, PASSED_KYCAML, 1, {from: owner})
        await this.registry.setAttributeValue(kycAccount, PASSED_KYCAML, 1, {from: owner})
    })
    describe('StakingPool', function() {
        it('creates staking opportunity', async function() {
            await this.pool.createStakingOpportunity(this.favoredToken.address);
        })

        it('creates staking opportunity', async function() {
            await this.pool.createStakingOpportunity(this.favoredToken.address);
        })
    })
})
