const TimeOwnedUpgradeabilityProxy = artifacts.require('TimeOwnedUpgradeabilityProxy')
const assertRevert = require('./helpers/assertRevert.js')
const timeMachine = require('ganache-time-traveler')

contract('TimeOwnedUpgradeabilityProxy', function(accounts) {
    let address

    const getCurrentExpirationTimestamp = async () => parseInt((await this.timeOwnedUpgradeabilityProxy.expiration()).toString())

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
        const currentExpiration = await getCurrentExpirationTimestamp()
        await this.timeOwnedUpgradeabilityProxy.setExpiration(currentExpiration + 30)
        await timeMachine.advanceTime(20)
        await this.timeOwnedUpgradeabilityProxy.upgradeTo(address)
        assert(address == await this.timeOwnedUpgradeabilityProxy.implementation())
    })

    it('does not allow to upgrade if extended time already passes', async () => {
        await timeMachine.advanceTime(60 * 60 * 24 * 124 - 10)
        const currentExpiration = await getCurrentExpirationTimestamp()
        await this.timeOwnedUpgradeabilityProxy.setExpiration(currentExpiration + 30)
        await timeMachine.advanceTime(40)
        await assertRevert(this.timeOwnedUpgradeabilityProxy.upgradeTo(address))
    })

    it('does not allow set after certain time passes', async () => {
        await timeMachine.advanceTime(60 * 60 * 24 * 124 + 10)
        await assertRevert(this.timeOwnedUpgradeabilityProxy.setExpiration(60 * 60 * 24 * 124))
    })
})