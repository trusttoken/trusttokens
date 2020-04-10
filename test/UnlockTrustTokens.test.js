const Registry = artifacts.require('RegistryMock')
const TrustToken = artifacts.require('MockTrustToken')
const Unlock = artifacts.require('UnlockTrustTokens')
const Vault = artifacts.require('TrustTokenVault')
const BN = web3.utils.toBN
const assertRevert = require('./helpers/assertRevert.js')
const ONE_HUNDRED = BN(100).mul(BN(1e18))
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const TRUST_TOKEN_MINT_AMOUNT = 10000000000000000000000000 //BN(100000000000000000).mul(BN(1e8))

contract('Unlock', function(accounts) {
    const [_, owner, issuer, oneHundred, account1, account2] = accounts
    beforeEach(async function() {
        this.registry = await Registry.new({ from: owner });
        this.token = await TrustToken.new(this.registry.address, { from: issuer });
        this.vault = await Vault.new(this.token.address, {from: owner});
        this.unlock = await Unlock.new(this.vault.address, {from: owner});

        //await this.token.transferOwnership(this.unlock.address, {from: issuer});
        await this.token.transferOwnership(this.vault.address, {from: issuer});
        await this.vault.transferOwnership(this.unlock.address, {from: owner});
    })
    describe('erc721', function() {
        it('name', async function() {
            assert.equal("Unclaimed TRUST", await this.unlock.name.call())
        })
        it('symbol', async function() {
            assert.equal("SOON:TRUST", await this.unlock.symbol.call())

        })
    })
    describe('auth', function() {
        let timestamp = parseInt(Date.now() / 1000);
        it('prevents non-owner from issuing', async function() {
            await assertRevert(this.unlock.scheduleUnlock(account1, ONE_HUNDRED, timestamp, {from:account1}))
        })
        it('prevents non-owner from canceling', async function() {
            await this.unlock.scheduleUnlock(account1, ONE_HUNDRED, timestamp, {from:owner})
            await assertRevert(this.unlock.cancelUnlock(0), {from:account1})
        })
        it('prevents renounced owner from issuing, canceling, and transfering or claiming ownership', async function() {
            await this.unlock.scheduleUnlock(account1, ONE_HUNDRED, timestamp, {from:owner})
            await this.unlock.transferOwnership(owner, {from:owner})
            await this.unlock.renounceOwnership({from:owner})
            await assertRevert(this.unlock.cancelUnlock(0), {from:owner})
            await assertRevert(this.unlock.scheduleUnlock(account1, ONE_HUNDRED, timestamp, {from:owner}))
            await assertRevert(this.unlock.transferOwnership(account1, {from:owner}))
            await assertRevert(this.unlock.claimOwnership({from:owner}))
        })
        it('prevents claiming token out of bounds', async function() {
            await this.vault.claimTokenOwnership({from: owner})
            await this.unlock.claimVaultOwnership({from: owner})
            await assertRevert(this.unlock.claim(0, {from: account1}))
            await assertRevert(this.unlock.deliver(0, account2, {from: account1}))
        })
    })
    describe('mint trusttokens', function() {
        it('mint', async function() {
            await this.vault.claimTokenOwnership({from: owner})
            await this.vault.mintTrustTokens({from: owner});
            assert.equal(TRUST_TOKEN_MINT_AMOUNT, await this.vault.vaultBalance.call())
        })
    })
    describe('claim', function() {
        it('claims token ownership', async function() {
            await this.vault.claimTokenOwnership({from: owner})
            assert.equal(await this.token.owner.call(), this.vault.address)
            assert.equal(await this.token.pendingOwner.call(), ZERO_ADDRESS)
        })
        it('claims vault ownership', async function() {
            await this.unlock.claimVaultOwnership({from: owner})
            assert.equal(await this.vault.owner.call(), this.unlock.address)
            assert.equal(await this.vault.pendingOwner.call(), ZERO_ADDRESS)
        })
        it('prevents claim and deliver before unlock', async function() {
            await this.vault.claimTokenOwnership({from: owner})
            await this.vault.mintTrustTokens({from: owner});
            await this.unlock.claimVaultOwnership({from: owner})

            let timestamp = parseInt(Date.now() / 1000) + 12000;

            await this.unlock.scheduleUnlock(account1, ONE_HUNDRED, timestamp, {from:owner})

            await assertRevert(this.unlock.claim(0, {from: account1}))
            await assertRevert(this.unlock.deliver(0, account2, {from: account1}))
        })
        it('prevents duplicate claim or deliver', async function() {
            await this.vault.claimTokenOwnership({from: owner})
            await this.vault.mintTrustTokens({from: owner});
            await this.unlock.claimVaultOwnership({from: owner})
            let timestamp = parseInt(Date.now() / 1000);
            await this.unlock.scheduleUnlock(account1, ONE_HUNDRED, timestamp, {from:owner})
            await this.unlock.claim(0, {from:account1})
            await assertRevert(this.unlock.claim(0, {from: account1}))
            await assertRevert(this.unlock.deliver(0, account2, {from: account1}))
        })
        it('claim tokens after renunciation', async function() {
            await this.vault.claimTokenOwnership({from: owner})
            await this.vault.mintTrustTokens({from: owner});
            await this.unlock.claimVaultOwnership({from: owner})

            let timestamp = parseInt(Date.now() / 1000);

            const scheduled = await this.unlock.scheduleUnlock(account1, ONE_HUNDRED, timestamp, {from:owner})
            assert.equal(await this.unlock.totalSupply.call(), 1)
            assert.equal(await this.unlock.ownerOf.call(0), account1)
            assert.equal(await this.unlock.ownerOf.call(0), account1)
            assert.equal(await this.unlock.balanceOf.call(account1), 1)
            assert.equal(scheduled.logs.length, 2, "UnlockScheduled, Transfer")
            assert.equal(scheduled.logs[0].event, "UnlockScheduled")
            assert.equal(scheduled.logs[0].args.tokenId, 0)
            assert.equal(scheduled.logs[0].args.recipient, account1)
            assert(scheduled.logs[0].args.amount.eq(ONE_HUNDRED), "amount not 100")
            assert.equal(scheduled.logs[0].args.activation, timestamp)
            assert.equal(scheduled.logs[1].event, "Transfer")
            assert.equal(scheduled.logs[1].args.from, ZERO_ADDRESS)
            assert.equal(scheduled.logs[1].args.to, account1)

            await this.unlock.renounceOwnership({from: owner})
            assert.equal(await this.unlock.owner.call(), ZERO_ADDRESS)
            assert.equal(await this.unlock.pendingOwner.call(), ZERO_ADDRESS)

            await this.unlock.claim(0, {from: account1})
            assert(ONE_HUNDRED.eq(await this.token.balanceOf.call(account1)))
            assert.equal(0, await this.unlock.totalSupply.call())
            assert.equal(1, await this.unlock.unlockOperationCount.call())
        })

        it('claim after transferFrom', async function() {
            await this.vault.claimTokenOwnership({from: owner})
            await this.vault.mintTrustTokens({from: owner});
            await this.unlock.claimVaultOwnership({from: owner})
            let timestamp = parseInt(Date.now() / 1000);

            const scheduled = await this.unlock.scheduleUnlock(account1, ONE_HUNDRED, timestamp, {from:owner})
            assert.equal(await this.unlock.totalSupply.call(), 1)
            assert.equal(await this.unlock.ownerOf.call(0), account1)
            assert.equal(await this.unlock.ownerOf.call(0), account1)
            assert.equal(await this.unlock.balanceOf.call(account1), 1)
            assert.equal(scheduled.logs.length, 2, "UnlockScheduled, Transfer")
            assert.equal(scheduled.logs[0].event, "UnlockScheduled")
            assert.equal(scheduled.logs[0].args.tokenId, 0)
            assert.equal(scheduled.logs[0].args.recipient, account1)
            assert(scheduled.logs[0].args.amount.eq(ONE_HUNDRED), "amount not 100")
            assert.equal(scheduled.logs[0].args.activation, timestamp)
            assert.equal(scheduled.logs[1].event, "Transfer")
            assert.equal(scheduled.logs[1].args.from, ZERO_ADDRESS)
            assert.equal(scheduled.logs[1].args.to, account1)

            const transfer = await this.unlock.transferFrom(account1, account2, 0, {from:account1})
            assert.equal(transfer.logs.length, 1, "Transfer")
            assert.equal(transfer.logs[0].event, "Transfer")
            assert.equal(transfer.logs[0].args.from, account1)
            assert.equal(transfer.logs[0].args.to, account2)
            assert.equal(transfer.logs[0].args.tokenId, 0, "wrong token id")

            const approveAll = await this.unlock.setApprovalForAll(account1, true, {from:account2})
            assert.equal(approveAll.logs.length, 1, "ApprovalForAll")
            assert.equal(approveAll.logs[0].event, "ApprovalForAll")
            assert.equal(approveAll.logs[0].args.owner, account2)
            assert.equal(approveAll.logs[0].args.operator, account1)
            assert.equal(approveAll.logs[0].args.approved, true)
            assert.equal(await this.unlock.isApprovedForAll.call(account2, account1), true)
            assert.equal(1, await this.unlock.balanceOf.call(account2))
            assert.equal(0, await this.unlock.balanceOf.call(account1))

            const transfer2 = await this.unlock.transferFrom(account2, account1, 0, {from:account1})
            assert.equal(transfer2.logs.length, 1, "Transfer")
            assert.equal(transfer2.logs[0].event, "Transfer")
            assert.equal(transfer2.logs[0].args.from, account2)
            assert.equal(transfer2.logs[0].args.to, account1)
            assert.equal(transfer2.logs[0].args.tokenId, 0)
            assert.equal(0, await this.unlock.balanceOf.call(account2))
            assert.equal(1, await this.unlock.balanceOf.call(account1))

            const claim = await this.unlock.claim(0, {from: account1})
            assert.equal(2, claim.logs.length)
            assert.equal(claim.logs[0].event, "UnlockClaimed")
            assert.equal(claim.logs[0].args.tokenId, 0)
            assert.equal(claim.logs[0].args.beneficiary, account1)
            assert.equal(claim.logs[1].event, "Transfer")
            assert.equal(claim.logs[1].args.from, account1)
            assert.equal(claim.logs[1].args.to, ZERO_ADDRESS)
            assert.equal(0, await this.unlock.balanceOf.call(account1))
            assert(ONE_HUNDRED.eq(await this.token.balanceOf.call(account1)), "100 not received")
        })
        it('can deliver to another account', async function() {
            await this.vault.claimTokenOwnership({from: owner})
            await this.vault.mintTrustTokens({from: owner});
            await this.unlock.claimVaultOwnership({from: owner})
            let timestamp = parseInt(Date.now() / 1000);

            const scheduled = await this.unlock.scheduleUnlock(account1, ONE_HUNDRED, timestamp, {from:owner})
            const delivery = await this.unlock.deliver(0, account2, {from: account1})
            assert.equal(2, delivery.logs.length)
            assert.equal(delivery.logs[0].event, "UnlockClaimed")
            assert.equal(delivery.logs[0].args.tokenId, 0)
            assert.equal(delivery.logs[0].args.beneficiary, account2)
            assert.equal(delivery.logs[1].event, "Transfer")
            assert.equal(delivery.logs[1].args.from, account1)
            assert.equal(delivery.logs[1].args.to, ZERO_ADDRESS)
            assert.equal(0, await this.unlock.balanceOf.call(account2))
            assert(ONE_HUNDRED.eq(await this.token.balanceOf.call(account2)), "100 not received")
        })
    })
})
