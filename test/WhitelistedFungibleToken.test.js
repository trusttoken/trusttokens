const Registry = artifacts.require('RegistryMock')
//const WhitelistedFungibleToken = artifacts.require('WhitelistedFungibleToken')
const MintableWhitelistedFungibleToken = artifacts.require('MintableWhitelistedFungibleToken')
const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy')

const bytes32 = require('../true-currencies/test/helpers/bytes32.js')
const assertRevert = require('../true-currencies/test/helpers/assertRevert.js')['default']

const IS_DEPOSIT_ADDRESS = bytes32('isDepositAddress')
const PASSED_KYCAML = bytes32('hasPassedKYC/AML')
const BN = web3.utils.toBN
const ONE_HUNDRED = BN(100).mul(BN(1e18))

contract('WhitelistedFungibleToken', function(accounts) {
    const [_, owner, issuer, oneHundred, account1, account2] = accounts
    beforeEach(async function() {
        this.registry = await Registry.new({ from: owner })
        this.token = await MintableWhitelistedFungibleToken.new({from: issuer})
        await this.token.setRegistry(this.registry.address, {from: issuer})
    })
    describe('MintableWhitelistedFungibleToken', function() {
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
