const Registry = artifacts.require('RegistryMock')
//const WhitelistedFungibleToken = artifacts.require('WhitelistedFungibleToken')
const StakedToken = artifacts.require('MockStakedToken')
const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy')
const TrustToken = artifacts.require('MockTrustToken')
const TrueUSD = artifacts.require('TrueUSD')
const StakingOpportunityFactory = artifacts.require('StakingOpportunityFactory')
const StakedTokenProxyImplementation = artifacts.require('StakedTokenProxyImplementation')

const bytes32 = require('../true-currencies/test/helpers/bytes32.js')
const assertRevert = require('../true-currencies/test/helpers/assertRevert.js')['default']
const writeAttributeFor = require('../true-currencies/registry/test/helpers/writeAttributeFor.js')

const IS_DEPOSIT_ADDRESS = bytes32('isDepositAddress')
const IS_REGISTERED_CONTRACT = bytes32('isRegisteredContract')
const PASSED_KYCAML = bytes32('hasPassedKYC/AML')
const BN = web3.utils.toBN
const ONE_ETHER = BN(1e18)
const ONE_HUNDRED_ETHER = BN(100).mul(ONE_ETHER)
const ONE_BITCOIN = BN(1e8)
const ONE_HUNDRED_BITCOIN = BN(100).mul(ONE_BITCOIN)
const DEFAULT_RATIO = BN(2000);


contract('StakingOpportunityFactory', function(accounts) {
    const [_, owner, issuer, oneHundred, account1, account2, kycAccount, fakeLiquidator] = accounts
    beforeEach(async function() {
        this.registry = await Registry.new({ from: owner });
        this.rewardToken = await TrueUSD.new({ from: issuer });
        this.stakeToken = await TrustToken.new(this.registry.address, { from: issuer });
        await this.rewardToken.setRegistry(this.registry.address, {from: issuer})
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED_ETHER, {from:issuer});
        await this.stakeToken.mint(oneHundred, ONE_HUNDRED_BITCOIN, {from:issuer});
        await this.registry.setAttributeValue(kycAccount, PASSED_KYCAML, 1, {from: owner})
        this.implementation = await StakedTokenProxyImplementation.new()
        this.factory = await StakingOpportunityFactory.new(this.registry.address, this.implementation.address)
        await this.registry.setAttributeValue(this.factory.address, writeAttributeFor(IS_REGISTERED_CONTRACT), 1, {from:owner})
    })
    describe('syncAttributeValues', function() {
        it('syncs attribute value', async function() {
            const created = await this.factory.createStakingOpportunity(this.stakeToken.address, this.rewardToken.address, fakeLiquidator);
            console.log(created.logs)
            //await this.factory.syncAttributeValues(PASSED_KYCAML, [
        })
    })
    describe('createStakingOpportunity', function() {
        // TODO
    })
})
