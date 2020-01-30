const Registry = artifacts.require('RegistryMock')
const TrustToken = artifacts.require('MockTrustToken')
const Vesting = artifacts.require('VestingMock')
const BN = web3.utils.toBN
const assertRevert = require('../true-currencies/test/helpers/assertRevert.js')['default']
const ONE_HUNDRED = BN(100).mul(BN(1e18))
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

contract('Vesting', function(accounts) {
    const [_, owner, issuer, oneHundred, account1, account2] = accounts
    beforeEach(async function() {
        this.registry = await Registry.new({ from: owner });
        this.token = await TrustToken.new(this.registry.address, { from: issuer });
        this.vesting = await Vesting.new(this.token.address, {from: owner});
        await this.token.transferOwnership(this.vesting.address, {from: issuer});
    })
    it('claims token ownership', async function() {
        await this.vesting.claimTokenOwnership({from: owner})
        assert.equal(await this.token.owner.call(), this.vesting.address)
        assert.equal(await this.token.pendingOwner.call(), ZERO_ADDRESS)
    })
    it('allows claiming tokens after renunciation', async function() {
        await this.vesting.claimTokenOwnership({from: owner})
        let timestamp = parseInt(Date.now() / 1000);

        const scheduled = await this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:owner})
        assert.equal(await this.vesting.totalSupply.call(), 1)
        assert.equal(await this.vesting.ownerOf.call(0), account1)
        assert.equal(await this.vesting.ownerOf.call(0), account1)
        assert.equal(await this.vesting.balanceOf.call(account1), 1)
        assert.equal(scheduled.logs.length, 2, "MintScheduled, Transfer")
        assert.equal(scheduled.logs[0].event, "MintScheduled")
        assert.equal(scheduled.logs[0].args.nonce, 0)
        assert.equal(scheduled.logs[0].args.recipient, account1)
        assert(scheduled.logs[0].args.amount.eq(ONE_HUNDRED), "amount not 100")
        assert.equal(scheduled.logs[0].args.activation, timestamp)
        assert.equal(scheduled.logs[1].event, "Transfer")
        assert.equal(scheduled.logs[1].args.from, ZERO_ADDRESS)
        assert.equal(scheduled.logs[1].args.to, account1)

        await this.vesting.renounceOwnership({from: owner})
        assert.equal(await this.vesting.owner.call(), ZERO_ADDRESS)
        assert.equal(await this.vesting.pendingOwner.call(), ZERO_ADDRESS)

        console.log(8)
        await this.vesting.claim(0, {from: account1})
        console.log(9)
        assert.equal(await this.token.balanceOf.call(account1), ONE_HUNDRED)
    })
})
