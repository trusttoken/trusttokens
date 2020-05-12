const TimeOwnedUpgradeabilityProxy = artifacts.require('TimeOwnedUpgradeabilityProxy')
const assertRevert = require('./helpers/assertRevert.js')
const timeMachine = require('ganache-time-traveler')

contract('TimeOwnedUpgradeabilityProxy', function(accounts) {
    let address

    beforeEach(async () => {
    address = web3.eth.accounts.create().address
    this.timeOwnedUpgradeabilityProxy = await TimeOwnedUpgradeabilityProxy.new();
    })

    it('does not allow upgrade after certain time passes', async () => {
        await timeMachine.advanceTime(60 * 60 * 24 * 124 + 10)
        await assertRevert(this.timeOwnedUpgradeabilityProxy.upgradeTo(address))
    })

    it('allows upgrade before some, but not enough time passes', async () => {
        await timeMachine.advanceTime(60 * 60 * 24 * 124 - 10)
        await this.timeOwnedUpgradeabilityProxy.upgradeTo(address)
        assert(address == await this.timeOwnedUpgradeabilityProxy.implementation())
    })

    it('allows upgrade before certain time passes', async () => {
        await this.timeOwnedUpgradeabilityProxy.upgradeTo(address)
        assert(address == await this.timeOwnedUpgradeabilityProxy.implementation())
    })

    it('allows set before certain time passes', async () => {
        await timeMachine.advanceTime(60 * 60 * 24 * 124 - 10)
        await this.timeOwnedUpgradeabilityProxy.setExpiration()
        await timeMachine.advanceTime(20)
        await this.timeOwnedUpgradeabilityProxy.upgradeTo(address)
        assert(address == await this.timeOwnedUpgradeabilityProxy.implementation())
    })

    it('does not allow set after certain time passes', async () => {
        await timeMachine.advanceTime(60 * 60 * 24 * 124 + 10)
        await assertRevert(this.timeOwnedUpgradeabilityProxy.setExpiration())
    })
})