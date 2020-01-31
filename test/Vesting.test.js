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
    describe('auth', function() {
        let timestamp = parseInt(Date.now() / 1000);
        it('prevents non-owner from issuing', async function() {
            await assertRevert(this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:account1}))
        })
        it('prevents non-owner from canceling', async function() {
            await this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:owner})
            await assertRevert(this.vesting.cancelMint(0), {from:account1})
        })
        it('prevents renounced owner from issuing, canceling, and transfering or claiming ownership', async function() {
            await this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:owner})
            await this.vesting.transferOwnership(owner, {from:owner})
            await this.vesting.renounceOwnership({from:owner})
            await assertRevert(this.vesting.cancelMint(0), {from:owner})
            await assertRevert(this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:owner}))
            await assertRevert(this.vesting.transferOwnership(account1, {from:owner}))
            await assertRevert(this.vesting.claimOwnership({from:owner}))
        })
        it('prevents claiming out of bounds', async function() {
            await this.vesting.claimTokenOwnership({from: owner})
            assertRevert(this.vesting.claim(0, {from: account1}))
            assertRevert(this.vesting.deliver(0, account2, {from: account1}))
        })
    })
    describe('claim', function() {
        it('claims token ownership', async function() {
            await this.vesting.claimTokenOwnership({from: owner})
            assert.equal(await this.token.owner.call(), this.vesting.address)
            assert.equal(await this.token.pendingOwner.call(), ZERO_ADDRESS)
        })
        it('prevents claim and deliver before vest', async function() {
            await this.vesting.claimTokenOwnership({from: owner})
            let timestamp = parseInt(Date.now() / 1000) + 12000;

            await this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:owner})

            assertRevert(this.vesting.claim(0, {from: account1}))
            assertRevert(this.vesting.deliver(0, account2, {from: account1}))
        })
        it('prevents duplicate claim or deliver', async function() {
            await this.vesting.claimTokenOwnership({from: owner})
            let timestamp = parseInt(Date.now() / 1000);
            await this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:owner})
            await this.vesting.claim(0, {from:account1})
            assertRevert(this.vesting.claim(0, {from: account1}))
            assertRevert(this.vesting.deliver(0, account2, {from: account1}))
        })
        it('claim tokens after renunciation', async function() {

            await this.vesting.claimTokenOwnership({from: owner})
            let timestamp = parseInt(Date.now() / 1000);

            const scheduled = await this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:owner})
            assert.equal(await this.vesting.totalSupply.call(), 1)
            assert.equal(await this.vesting.ownerOf.call(0), account1)
            assert.equal(await this.vesting.ownerOf.call(0), account1)
            assert.equal(await this.vesting.balanceOf.call(account1), 1)
            assert.equal(scheduled.logs.length, 2, "MintScheduled, Transfer")
            assert.equal(scheduled.logs[0].event, "MintScheduled")
            assert.equal(scheduled.logs[0].args.tokenId, 0)
            assert.equal(scheduled.logs[0].args.recipient, account1)
            assert(scheduled.logs[0].args.amount.eq(ONE_HUNDRED), "amount not 100")
            assert.equal(scheduled.logs[0].args.activation, timestamp)
            assert.equal(scheduled.logs[1].event, "Transfer")
            assert.equal(scheduled.logs[1].args.from, ZERO_ADDRESS)
            assert.equal(scheduled.logs[1].args.to, account1)

            await this.vesting.renounceOwnership({from: owner})
            assert.equal(await this.vesting.owner.call(), ZERO_ADDRESS)
            assert.equal(await this.vesting.pendingOwner.call(), ZERO_ADDRESS)

            await this.vesting.claim(0, {from: account1})
            assert(ONE_HUNDRED.eq(await this.token.balanceOf.call(account1)))
            assert.equal(0, await this.vesting.totalSupply.call())
            assert.equal(1, await this.vesting.mintOperationCount.call())
        })

        it('claim after transferFrom', async function() {
            await this.vesting.claimTokenOwnership({from: owner})
            let timestamp = parseInt(Date.now() / 1000);

            const scheduled = await this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:owner})
            assert.equal(await this.vesting.totalSupply.call(), 1)
            assert.equal(await this.vesting.ownerOf.call(0), account1)
            assert.equal(await this.vesting.ownerOf.call(0), account1)
            assert.equal(await this.vesting.balanceOf.call(account1), 1)
            assert.equal(scheduled.logs.length, 2, "MintScheduled, Transfer")
            assert.equal(scheduled.logs[0].event, "MintScheduled")
            assert.equal(scheduled.logs[0].args.tokenId, 0)
            assert.equal(scheduled.logs[0].args.recipient, account1)
            assert(scheduled.logs[0].args.amount.eq(ONE_HUNDRED), "amount not 100")
            assert.equal(scheduled.logs[0].args.activation, timestamp)
            assert.equal(scheduled.logs[1].event, "Transfer")
            assert.equal(scheduled.logs[1].args.from, ZERO_ADDRESS)
            assert.equal(scheduled.logs[1].args.to, account1)

            const transfer = await this.vesting.transferFrom(account1, account2, 0, {from:account1})
            assert.equal(transfer.logs.length, 1, "Transfer")
            assert.equal(transfer.logs[0].event, "Transfer")
            assert.equal(transfer.logs[0].args.from, account1)
            assert.equal(transfer.logs[0].args.to, account2)
            assert.equal(transfer.logs[0].args.tokenId, 0, "wrong token id")

            const approveAll = await this.vesting.setApprovalForAll(account1, true, {from:account2})
            assert.equal(approveAll.logs.length, 1, "ApprovalForAll")
            assert.equal(approveAll.logs[0].event, "ApprovalForAll")
            assert.equal(approveAll.logs[0].args.owner, account2)
            assert.equal(approveAll.logs[0].args.operator, account1)
            assert.equal(approveAll.logs[0].args.approved, true)
            assert.equal(await this.vesting.isApprovedForAll.call(account2, account1), true)
            assert.equal(1, await this.vesting.balanceOf.call(account2))
            assert.equal(0, await this.vesting.balanceOf.call(account1))

            const transfer2 = await this.vesting.transferFrom(account2, account1, 0, {from:account1})
            assert.equal(transfer2.logs.length, 1, "Transfer")
            assert.equal(transfer2.logs[0].event, "Transfer")
            assert.equal(transfer2.logs[0].args.from, account2)
            assert.equal(transfer2.logs[0].args.to, account1)
            assert.equal(transfer2.logs[0].args.tokenId, 0)
            assert.equal(0, await this.vesting.balanceOf.call(account2))
            assert.equal(1, await this.vesting.balanceOf.call(account1))

            const claim = await this.vesting.claim(0, {from: account1})
            assert.equal(2, claim.logs.length)
            assert.equal(claim.logs[0].event, "MintClaimed")
            assert.equal(claim.logs[0].args.tokenId, 0)
            assert.equal(claim.logs[0].args.beneficiary, account1)
            assert.equal(claim.logs[1].event, "Transfer")
            assert.equal(claim.logs[1].args.from, account1)
            assert.equal(claim.logs[1].args.to, ZERO_ADDRESS)
            assert.equal(0, await this.vesting.balanceOf.call(account1))
            assert(ONE_HUNDRED.eq(await this.token.balanceOf.call(account1)), "100 not received")
        })
        it('can deliver to another account', async function() {
            await this.vesting.claimTokenOwnership({from: owner})
            let timestamp = parseInt(Date.now() / 1000);

            const scheduled = await this.vesting.scheduleMint(account1, ONE_HUNDRED, timestamp, {from:owner})
            const delivery = await this.vesting.deliver(0, account2, {from: account1})
            assert.equal(2, delivery.logs.length)
            assert.equal(delivery.logs[0].event, "MintClaimed")
            assert.equal(delivery.logs[0].args.tokenId, 0)
            assert.equal(delivery.logs[0].args.beneficiary, account2)
            assert.equal(delivery.logs[1].event, "Transfer")
            assert.equal(delivery.logs[1].args.from, account1)
            assert.equal(delivery.logs[1].args.to, ZERO_ADDRESS)
            assert.equal(0, await this.vesting.balanceOf.call(account2))
            assert(ONE_HUNDRED.eq(await this.token.balanceOf.call(account2)), "100 not received")
        })
    })
})
