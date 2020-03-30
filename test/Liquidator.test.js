const Liquidator = artifacts.require('LiquidatorMock')
const BN = web3.utils.toBN
const ONE_ETHER = BN(1e18)
const ONE_HUNDRED_ETHER = BN(100).mul(ONE_ETHER)
const assertRevert = require('@trusttoken/factory/test/helpers/assertRevert.js')
const MockTrustToken = artifacts.require('MockTrustToken')
const TrueUSD = artifacts.require('TrueUSD')
const Airswap = artifacts.require('Swap')
const AirswapERC20TransferHandler = artifacts.require('AirswapERC20TransferHandler')
const TransferHandlerRegistry = artifacts.require('TransferHandlerRegistry')
const UniswapFactory = artifacts.require('uniswap_factory')
const UniswapExchange = artifacts.require('uniswap_exchange')
const Registry = artifacts.require('RegistryMock')
const { Order, hashDomain } = require('./lib/airswap.js')
const Types = artifacts.require('Types')
const ERC20_KIND = '0x36372b07'
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const ZERO_BYTES32 = '0x0000000000000000000000000000000000000000000000000000000000000000'
const bytes32 = require('@trusttoken/factory/test/helpers/bytes32.js')
const AIRSWAP_VALIDATOR = bytes32('AirswapValidatorDomain')
const APPROVED_BENEFICIARY = bytes32('approvedBeneficiary')

contract('Liquidator', function(accounts) {
    const [_, owner, issuer, oneHundred, approvedBeneficiary, account2, kycAccount, fakePool] = accounts
    beforeEach(async function() {
        this.uniswapFactory = await UniswapFactory.new();
        this.uniswapTemplate = await UniswapExchange.new();
        this.uniswapFactory.initializeFactory(this.uniswapTemplate.address)
        this.registry = await Registry.new({ from: owner });
        this.rewardToken = await TrueUSD.new({ from: issuer });
        this.stakeToken = await MockTrustToken.new(this.registry.address, { from: issuer });
        this.outputUniswapAddress = (await this.uniswapFactory.createExchange(this.rewardToken.address)).logs[0].args.exchange
        this.outputUniswap = await UniswapExchange.at(this.outputUniswapAddress)
        this.stakeUniswap = await UniswapExchange.at((await this.uniswapFactory.createExchange(this.stakeToken.address)).logs[0].args.exchange)
        await this.rewardToken.setRegistry(this.registry.address, {from: issuer})
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED_ETHER, {from:issuer});
        await this.stakeToken.mint(oneHundred, ONE_HUNDRED_ETHER, {from:issuer});
        //await this.registry.subscribe(PASSED_KYCAML, this.stakeToken.address, {from: owner})
        //await this.registry.setAttributeValue(oneHundred, PASSED_KYCAML, 1, {from: owner})
        //await this.registry.setAttributeValue(kycAccount, PASSED_KYCAML, 1, {from: owner})
        this.transferHandler = await AirswapERC20TransferHandler.new({from: owner})
        this.transferHandlerRegistry = await TransferHandlerRegistry.new({from: owner})
        this.transferHandlerRegistry.addTransferHandler(ERC20_KIND, this.transferHandler.address,{from:owner})
        this.types = await Types.new()
        await Airswap.link('Types', this.types.address)
        await this.rewardToken.approve(this.outputUniswap.address, ONE_HUNDRED_ETHER, {from: oneHundred})
        await this.stakeToken.approve(this.stakeUniswap.address, ONE_HUNDRED_ETHER, {from: oneHundred})
        let expiry = parseInt(Date.now() / 1000) + 12000
        await this.outputUniswap.addLiquidity(ONE_HUNDRED_ETHER, ONE_HUNDRED_ETHER, expiry, {from:oneHundred, value:1e17})
        await this.stakeUniswap.addLiquidity(ONE_HUNDRED_ETHER, ONE_HUNDRED_ETHER, expiry, {from:oneHundred, value:1e17})
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED_ETHER, {from:issuer});
        await this.stakeToken.mint(oneHundred, ONE_HUNDRED_ETHER, {from:issuer});
        this.airswap = await Airswap.new(this.transferHandlerRegistry.address, {from: owner})
        this.liquidator = await Liquidator.new(this.registry.address, this.rewardToken.address, this.stakeToken.address, this.outputUniswap.address, this.stakeUniswap.address, {from: owner})
        await this.liquidator.setPool(fakePool, {from:owner})
        await this.registry.subscribe(AIRSWAP_VALIDATOR, this.liquidator.address, {from: owner})
        await this.registry.subscribe(APPROVED_BENEFICIARY, this.liquidator.address, {from: owner})
        await this.registry.setAttributeValue(this.airswap.address, AIRSWAP_VALIDATOR, hashDomain(this.airswap.address), {from: owner})
        await this.registry.setAttributeValue(approvedBeneficiary, APPROVED_BENEFICIARY, 1, {from: owner})
        await this.rewardToken.approve(this.airswap.address, ONE_HUNDRED_ETHER, {from: oneHundred})
        await this.stakeToken.approve(this.liquidator.address, ONE_HUNDRED_ETHER, { from: fakePool })
    })
    describe('Auth', function() {
        let nonce = 0
        let expiry = parseInt(Date.now() / 1000) + 12000
        it('prevents non-owner from reclaiming', async function() {
            await assertRevert(this.liquidator.reclaim(approvedBeneficiary, ONE_HUNDRED_ETHER), {from:account2})
            await assertRevert(this.liquidator.reclaimStake(approvedBeneficiary, ONE_HUNDRED_ETHER), {from:account2})
        })
        it('prevents non-approved beneficiary', async function() {
            await assertRevert(this.liquidator.reclaim(account2, ONE_HUNDRED_ETHER, {from:owner}))
        })
        it('prevents liquidation of zero', async function() {
            await assertRevert(this.liquidator.reclaim(approvedBeneficiary, BN(0), {from:owner}))
        })
        it('prevents registering orders with non-airswap validator', async function() {
            await this.stakeToken.transfer(fakePool, BN(100), {from: oneHundred})
            let order = new Order(nonce, expiry, this.liquidator.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign()
            await assertRevert(this.liquidator.registerAirswap(order.web3Tuple))
        })
        it('prevents tiny orders', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order.sign()
            await assertRevert(this.liquidator.registerAirswap(order.web3Tuple))
        })
        it('prevents used nonces', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign()
            await this.airswap.cancel([nonce], {from:oneHundred})
            await assertRevert(this.liquidator.registerAirswap(order.web3Tuple))
        })
        it('enforces nonce minimum', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign()
            await this.airswap.cancelUpTo(nonce + 1, {from:oneHundred})
            await assertRevert(this.liquidator.registerAirswap(order.web3Tuple))
        })
        it('prevents invalid signatures', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign()
            order.s = '5555555555555555555555555555555555555555555555555555555555555555'
            await assertRevert(this.liquidator.registerAirswap(order.web3Tuple))
        })
        it('prevents invalid signatory', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from:oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign(account2)
            await assertRevert(this.liquidator.registerAirswap(order.web3Tuple))
        })
    })
    describe('reclaimStake', function() {
        const stakeAmount = ONE_HUNDRED_ETHER.div(BN(4))
        beforeEach(async function() {
            await this.stakeToken.transfer(fakePool, stakeAmount, {from: oneHundred})
        })
        it('reclaims and redeposits stake', async function() {
            await this.liquidator.reclaimStake(approvedBeneficiary, stakeAmount, {from:owner})
            assert(stakeAmount.eq(await this.stakeToken.balanceOf.call(approvedBeneficiary)))

            await this.stakeToken.approve(this.liquidator.address, stakeAmount, {from:approvedBeneficiary})

            await this.liquidator.returnStake(approvedBeneficiary, stakeAmount)
            assert(stakeAmount.eq(await this.stakeToken.balanceOf.call(fakePool)))
        })
    })
    describe('Airswap', function() {
        let nonce = 0
        let expiry = parseInt(Date.now() / 1000) + 12000
        it('registers a swap', async function() {
            const senderAmount = ONE_HUNDRED_ETHER
            await this.stakeToken.transfer(fakePool, senderAmount, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, senderAmount, this.stakeToken.address)
            await order.sign()
            const registered = await this.liquidator.registerAirswap(order.web3Tuple)
            assert(registered.logs.length == 1)
            assert(registered.logs[0].event == "LimitOrder")
            const trade = await this.liquidator.head.call()
            assert.equal(registered.logs[0].args.order, trade)
            const next = await this.liquidator.next.call(trade)
            const orderInfo = await this.liquidator.airswapOrderInfo.call(trade)
            assert(next == ZERO_ADDRESS)
            assert(orderInfo.nonce == nonce)
            assert(orderInfo.expiry == expiry)
            assert(orderInfo.signerKind == ERC20_KIND)
            assert(orderInfo.signerWallet == oneHundred)
            assert(orderInfo.signerToken == this.rewardToken.address)
            assert(orderInfo.signerAmount == ONE_HUNDRED_ETHER)
            assert(orderInfo.signerId == 0)
            assert(orderInfo.senderKind == ERC20_KIND)
            assert(orderInfo.senderWallet == this.liquidator.address)
            assert(orderInfo.senderToken == this.stakeToken.address)
            assert(orderInfo.senderAmount == senderAmount)
            assert(orderInfo.senderId == 0)
            assert(orderInfo.affiliateKind == ERC20_KIND)
            assert(orderInfo.affiliateWallet == ZERO_ADDRESS)
            assert(orderInfo.affiliateToken == ZERO_ADDRESS)
            assert(orderInfo.affiliateAmount == 0)
            assert(orderInfo.affiliateId == 0)
            assert(orderInfo.validator == this.airswap.address)
            assert(orderInfo.signatory == oneHundred)
            assert(['0x01','0x45'].includes(orderInfo.version))
            assert(['27', '28'].includes(orderInfo.v))
            assert(orderInfo.r.length == 66)
            assert(orderInfo.r != ZERO_BYTES32)
            assert(orderInfo.s.length == 66)
            assert(orderInfo.s != ZERO_BYTES32)
            nonce += 1
        })
        it('executes a swap', async function() {
            const senderAmount = ONE_HUNDRED_ETHER.div(BN(4))
            await this.stakeToken.transfer(fakePool, senderAmount, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, senderAmount, this.stakeToken.address)
            await order.sign()
            await this.liquidator.registerAirswap(order.web3Tuple)
            const trade = await this.liquidator.head.call()
            const next = await this.liquidator.next.call(trade)
            const orderInfo = await this.liquidator.airswapOrderInfo.call(trade)
            assert(next == ZERO_ADDRESS)
            assert(orderInfo.nonce == nonce)
            assert(orderInfo.expiry == expiry)
            assert(orderInfo.signerKind == ERC20_KIND)
            assert(orderInfo.signerWallet == oneHundred)
            assert(orderInfo.signerToken == this.rewardToken.address)
            assert(orderInfo.signerAmount == ONE_HUNDRED_ETHER)
            assert(orderInfo.signerId == 0)
            assert(orderInfo.senderKind == ERC20_KIND)
            assert(orderInfo.senderWallet == this.liquidator.address)
            assert(orderInfo.senderToken == this.stakeToken.address)
            assert(orderInfo.senderAmount == senderAmount)
            assert(orderInfo.senderId == 0)
            assert(orderInfo.affiliateKind == ERC20_KIND)
            assert(orderInfo.affiliateWallet == ZERO_ADDRESS)
            assert(orderInfo.affiliateToken == ZERO_ADDRESS)
            assert(orderInfo.affiliateAmount == 0)
            assert(orderInfo.affiliateId == 0)
            assert(orderInfo.validator == this.airswap.address)
            assert(orderInfo.signatory == oneHundred)
            assert(['0x01','0x45'].includes(orderInfo.version))
            assert(['27', '28'].includes(orderInfo.v))
            assert(orderInfo.r.length == 66)
            assert(orderInfo.r != ZERO_BYTES32)
            assert(orderInfo.s.length == 66)
            assert(orderInfo.s != ZERO_BYTES32)
            await this.stakeToken.transfer(account2, await this.stakeToken.balanceOf(oneHundred), {from: oneHundred})
            assert.equal(orderInfo.senderAmount, await this.stakeToken.balanceOf(fakePool))
            assert.equal(orderInfo.signerAmount, await this.rewardToken.balanceOf(oneHundred))
            let reclaimed = await this.liquidator.reclaim(approvedBeneficiary, orderInfo.signerAmount, {from:owner})
            assert.equal(reclaimed.logs.length, 2, "Fill and Liquidated")
            let fillEvent = reclaimed.logs[0]
            assert.equal(fillEvent.event, "Fill")
            assert.equal(fillEvent.args.order, trade)
            let liquidationEvent = reclaimed.logs[1]
            assert.equal(liquidationEvent.event, "Liquidated")
            assert.equal(orderInfo.signerAmount,liquidationEvent.args.debtAmount, "stake amount mismatch")
            assert.equal(orderInfo.senderAmount,liquidationEvent.args.stakeAmount, "stake amount mismatch")
            assert(BN(orderInfo.signerAmount).eq(await this.rewardToken.balanceOf(approvedBeneficiary)))
            assert(BN(orderInfo.senderAmount).eq(await this.stakeToken.balanceOf(oneHundred)))
            assert(BN(0).eq(await this.stakeToken.balanceOf(fakePool)))
        })
        describe('handles out of gas', function() {
            const N = 40
            beforeEach(async function() {
                await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
                const senderAmount = ONE_HUNDRED_ETHER.div(BN(N))
                await this.rewardToken.mint(oneHundred, BN(N).mul(ONE_HUNDRED_ETHER), {from:issuer})
                for (let i = 0; i < N; i++) {
                    let order = new Order(nonce, expiry, this.airswap.address, oneHundred, BN(N).mul(ONE_ETHER), this.rewardToken.address, this.liquidator.address, senderAmount, this.stakeToken.address)
                    await order.sign()
                    await this.liquidator.registerAirswap(order.web3Tuple)
                    const trade = await this.liquidator.head.call()
                    const next = await this.liquidator.next.call(trade)
                }
            })
            it('stops doing airswap when low on gas', async function() {
                const reclaimed = await this.liquidator.reclaim(approvedBeneficiary, BN((N * N + N) / 2).mul(ONE_ETHER), {from:owner, gas:500000})
                assert(reclaimed.logs.length < 79, reclaimed.logs.length)
            })
            async function checkList() {
                let head = await this.liquidator.head.call()
                const visited = {}
                let headOrderInfo = await this.liquidator.airswapOrderInfo.call(head)
                while (head != ZERO_ADDRESS) {
                    visited[head] = true
                    let next =  await this.liquidator.next.call(head)
                    const nextOrderInfo = await this.liquidator.airswapOrderInfo.call(next)
                    assert(BN(nextOrderInfo.signerAmount).lte(BN(headOrderInfo.signerAmount)), [nextOrderInfo.signerAmount, headOrderInfo.signerAmount])
                    assert(next != head)
                    headOrderInfo = nextOrderInfo
                    head = next;
                    assert(!visited[next])
                }
            }
            it('stops pruning when low on gas and leaves it sane', async function() {
                await this.rewardToken.approve(this.airswap.address, 0, {from:oneHundred})
                await checkList.bind(this)()
                const pruned1 = await this.liquidator.prune({gas:70000})
                await checkList.bind(this)()
                const pruned2 = await this.liquidator.prune({gas:100000})
                await checkList.bind(this)()
                assert(pruned1.logs.length < pruned2.logs.length, [pruned1.logs.length, pruned2.logs.length])
            })
        })
        it('tolerates swap failure', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign()
            const registration = await this.liquidator.registerAirswap(order.web3Tuple)
            assert.equal(1, registration.logs.length)
            assert.equal(registration.logs[0].event, "LimitOrder")
            const trade = await this.liquidator.head.call()
            assert.equal(registration.logs[0].args.order, trade)
            await this.rewardToken.transfer(account2, ONE_HUNDRED_ETHER, {from:oneHundred})
            const reclaimed = await this.liquidator.reclaim(approvedBeneficiary, ONE_HUNDRED_ETHER, {from:owner})
            assert.equal(3, reclaimed.logs.length, "Cancel, LiquidationError, and Liquidated")
            let cancelEvent = reclaimed.logs[0]
            assert.equal(cancelEvent.event, "Cancel")
            assert.equal(cancelEvent.args.order, trade)
            let errorEvent = reclaimed.logs[1]
            assert.equal(errorEvent.event, "LiquidationError")
            assert.equal(errorEvent.args.order, trade)
            let liquidationEvent = reclaimed.logs[2]
            assert.equal(liquidationEvent.event, "Liquidated")
        })
        it('prunes insufficient balance', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign()
            const registration = await this.liquidator.registerAirswap(order.web3Tuple)
            assert.equal(1, registration.logs.length)
            assert.equal(registration.logs[0].event, "LimitOrder")
            const trade = await this.liquidator.head.call()
            assert.equal(registration.logs[0].args.order, trade)
            await this.rewardToken.transfer(account2, ONE_HUNDRED_ETHER, {from:oneHundred})
            const pruned = await this.liquidator.prune()
            assert.equal(pruned.logs.length, 1, "Cancel")
            assert.equal(pruned.logs[0].event, "Cancel")
            assert.equal(pruned.logs[0].args.order, trade)
            const head = await this.liquidator.head.call()
            assert.equal(head, ZERO_ADDRESS)
        })
        it('prunes insufficient allowance', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign()
            const registration = await this.liquidator.registerAirswap(order.web3Tuple)
            assert.equal(1, registration.logs.length)
            assert.equal(registration.logs[0].event, "LimitOrder")
            const trade = await this.liquidator.head.call()
            assert.equal(registration.logs[0].args.order, trade)
            await this.rewardToken.approve(this.airswap.address, 0, {from:oneHundred})
            const pruned = await this.liquidator.prune()
            assert.equal(pruned.logs.length, 1, "Cancel")
            assert.equal(pruned.logs[0].event, "Cancel")
            assert.equal(pruned.logs[0].args.order, trade)
            const head = await this.liquidator.head.call()
            assert.equal(head, ZERO_ADDRESS)
        })
        it('prunes invalidated nonce', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign()
            const registration = await this.liquidator.registerAirswap(order.web3Tuple)
            assert.equal(1, registration.logs.length)
            assert.equal(registration.logs[0].event, "LimitOrder")
            const trade = await this.liquidator.head.call()
            assert.equal(registration.logs[0].args.order, trade)
            await this.airswap.cancel([nonce], {from:oneHundred})
            const pruned = await this.liquidator.prune()
            assert.equal(pruned.logs.length, 1, "Cancel")
            assert.equal(pruned.logs[0].event, "Cancel")
            assert.equal(pruned.logs[0].args.order, trade)
            const head = await this.liquidator.head.call()
            assert.equal(head, ZERO_ADDRESS)
        })
        it('prunes minimum nonce', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign()
            const registration = await this.liquidator.registerAirswap(order.web3Tuple)
            assert.equal(1, registration.logs.length)
            assert.equal(registration.logs[0].event, "LimitOrder")
            const trade = await this.liquidator.head.call()
            assert.equal(registration.logs[0].args.order, trade)
            await this.airswap.cancelUpTo(nonce + 1, {from:oneHundred})
            const pruned = await this.liquidator.prune()
            assert.equal(pruned.logs.length, 1, "Cancel")
            assert.equal(pruned.logs[0].event, "Cancel")
            assert.equal(pruned.logs[0].args.order, trade)
            const head = await this.liquidator.head.call()
            assert.equal(head, ZERO_ADDRESS)
        })
        it('prunes: keep, drop, keep', async function() {
            await this.stakeToken.transfer(fakePool, BN(6), {from: oneHundred})
            await this.rewardToken.transfer(account2, BN(10), {from: oneHundred})
            await this.rewardToken.approve(this.airswap.address, BN(10), {from:account2})
            let order3 = new Order(nonce, expiry, this.airswap.address, oneHundred, BN(3), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order3.sign()
            await this.liquidator.registerAirswap(order3.web3Tuple)
            let order2 = new Order(nonce, expiry, this.airswap.address, account2, BN(2), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order2.sign()
            await this.liquidator.registerAirswap(order2.web3Tuple)
            let order1 = new Order(nonce, expiry, this.airswap.address, oneHundred, BN(1), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order1.sign()
            await this.liquidator.registerAirswap(order1.web3Tuple)
            const trade3 = await this.liquidator.head.call()
            const trade3Info = await this.liquidator.airswapOrderInfo.call(trade3)
            assert.equal(trade3Info.signerAmount, BN(3))
            const trade2 = await this.liquidator.next.call(trade3)
            const trade2Info = await this.liquidator.airswapOrderInfo.call(trade2)
            assert.equal(trade2Info.signerAmount, BN(2))
            const trade1 = await this.liquidator.next.call(trade2)
            const trade1Info = await this.liquidator.airswapOrderInfo.call(trade1)
            assert.equal(trade1Info.signerAmount, BN(1))
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
            // verify that nothing prunes yet
            await this.liquidator.prune()
            assert.equal(await this.liquidator.next.call(ZERO_ADDRESS), trade3)
            assert.equal(await this.liquidator.next.call(trade3), trade2)
            assert.equal(await this.liquidator.next.call(trade2), trade1)
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
            // invalidate middle order
            await this.rewardToken.transfer(oneHundred, BN(10), {from:account2})
            // prune middle order
            const pruned = await this.liquidator.prune()
            assert.equal(pruned.logs.length, 1, "Cancel")
            assert.equal(pruned.logs[0].args.order, trade2)
            assert.equal(await this.liquidator.next.call(ZERO_ADDRESS), trade3)
            assert.equal(await this.liquidator.next.call(trade3), trade1)
            assert.equal(await this.liquidator.next.call(trade2), ZERO_ADDRESS)
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
        })
        it('prunes: drop, keep, keep', async function() {
            await this.stakeToken.transfer(fakePool, BN(6), {from: oneHundred})
            await this.rewardToken.transfer(account2, BN(10), {from: oneHundred})
            await this.rewardToken.approve(this.airswap.address, BN(10), {from:account2})
            let order3 = new Order(nonce, expiry, this.airswap.address, account2, BN(3), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order3.sign()
            let order2 = new Order(nonce, expiry, this.airswap.address, oneHundred, BN(2), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order2.sign()
            let order1 = new Order(nonce, expiry, this.airswap.address, oneHundred, BN(1), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order1.sign()
            await this.liquidator.registerAirswap(order1.web3Tuple)
            await this.liquidator.registerAirswap(order2.web3Tuple)
            await this.liquidator.registerAirswap(order3.web3Tuple)
            const trade3 = await this.liquidator.head.call()
            const trade3Info = await this.liquidator.airswapOrderInfo.call(trade3)
            assert.equal(trade3Info.signerAmount, BN(3))
            const trade2 = await this.liquidator.next.call(trade3)
            const trade2Info = await this.liquidator.airswapOrderInfo.call(trade2)
            assert.equal(trade2Info.signerAmount, BN(2))
            const trade1 = await this.liquidator.next.call(trade2)
            const trade1Info = await this.liquidator.airswapOrderInfo.call(trade1)
            assert.equal(trade1Info.signerAmount, BN(1))
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
            // verify that nothing prunes yet
            await this.liquidator.prune()
            assert.equal(await this.liquidator.next.call(ZERO_ADDRESS), trade3)
            assert.equal(await this.liquidator.next.call(trade3), trade2)
            assert.equal(await this.liquidator.next.call(trade2), trade1)
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
            // invalidate first order
            await this.rewardToken.transfer(oneHundred, BN(10), {from:account2})
            // prune middle order
            const pruned = await this.liquidator.prune()
            assert.equal(pruned.logs.length, 1, "Cancel")
            assert.equal(pruned.logs[0].args.order, trade3)
            assert.equal(await this.liquidator.next.call(ZERO_ADDRESS), trade2)
            assert.equal(await this.liquidator.next.call(trade3), ZERO_ADDRESS)
            assert.equal(await this.liquidator.next.call(trade2), trade1)
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
        })
        it('prunes: keep, drop, drop', async function() {
            await this.stakeToken.transfer(fakePool, BN(6), {from: oneHundred})
            await this.rewardToken.transfer(account2, BN(10), {from: oneHundred})
            await this.rewardToken.approve(this.airswap.address, BN(10), {from:account2})
            let order3 = new Order(nonce, expiry, this.airswap.address, oneHundred, BN(3), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order3.sign()
            let order2 = new Order(nonce, expiry, this.airswap.address, account2, BN(2), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order2.sign()
            let order1 = new Order(nonce, expiry, this.airswap.address, account2, BN(1), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order1.sign()
            await this.liquidator.registerAirswap(order2.web3Tuple)
            await this.liquidator.registerAirswap(order3.web3Tuple)
            await this.liquidator.registerAirswap(order1.web3Tuple)
            const trade3 = await this.liquidator.head.call()
            const trade3Info = await this.liquidator.airswapOrderInfo.call(trade3)
            assert.equal(trade3Info.signerAmount, BN(3))
            const trade2 = await this.liquidator.next.call(trade3)
            const trade2Info = await this.liquidator.airswapOrderInfo.call(trade2)
            assert.equal(trade2Info.signerAmount, BN(2))
            const trade1 = await this.liquidator.next.call(trade2)
            const trade1Info = await this.liquidator.airswapOrderInfo.call(trade1)
            assert.equal(trade1Info.signerAmount, BN(1))
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
            // verify that nothing prunes yet
            await this.liquidator.prune()
            assert.equal(await this.liquidator.next.call(ZERO_ADDRESS), trade3)
            assert.equal(await this.liquidator.next.call(trade3), trade2)
            assert.equal(await this.liquidator.next.call(trade2), trade1)
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
            // invalidate first order
            await this.rewardToken.transfer(oneHundred, BN(10), {from:account2})
            // prune middle order
            const pruned = await this.liquidator.prune()
            assert.equal(pruned.logs.length, 2, "Cancel, Cancel")
            assert.equal(pruned.logs[0].args.order, trade2)
            assert.equal(pruned.logs[1].args.order, trade1)
            assert.equal(await this.liquidator.next.call(ZERO_ADDRESS), trade3)
            assert.equal(await this.liquidator.next.call(trade3), ZERO_ADDRESS)
            assert.equal(await this.liquidator.next.call(trade2), ZERO_ADDRESS)
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
        })
        it('prunes: drop, drop, drop', async function() {
            await this.stakeToken.transfer(fakePool, BN(6), {from: oneHundred})
            await this.rewardToken.transfer(account2, BN(10), {from: oneHundred})
            await this.rewardToken.approve(this.airswap.address, BN(10), {from:account2})
            let order3 = new Order(nonce, expiry, this.airswap.address, account2, BN(3), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order3.sign()
            let order2 = new Order(nonce, expiry, this.airswap.address, account2, BN(2), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order2.sign()
            let order1 = new Order(nonce, expiry, this.airswap.address, account2, BN(1), this.rewardToken.address, this.liquidator.address, BN(1), this.stakeToken.address)
            await order1.sign()
            await this.liquidator.registerAirswap(order2.web3Tuple)
            await this.liquidator.registerAirswap(order1.web3Tuple)
            await this.liquidator.registerAirswap(order3.web3Tuple)
            const trade3 = await this.liquidator.head.call()
            const trade3Info = await this.liquidator.airswapOrderInfo.call(trade3)
            assert.equal(trade3Info.signerAmount, BN(3))
            const trade2 = await this.liquidator.next.call(trade3)
            const trade2Info = await this.liquidator.airswapOrderInfo.call(trade2)
            assert.equal(trade2Info.signerAmount, BN(2))
            const trade1 = await this.liquidator.next.call(trade2)
            const trade1Info = await this.liquidator.airswapOrderInfo.call(trade1)
            assert.equal(trade1Info.signerAmount, BN(1))
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
            // verify that nothing prunes yet
            await this.liquidator.prune()
            assert.equal(await this.liquidator.next.call(ZERO_ADDRESS), trade3)
            assert.equal(await this.liquidator.next.call(trade3), trade2)
            assert.equal(await this.liquidator.next.call(trade2), trade1)
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
            // invalidate first order
            await this.rewardToken.transfer(oneHundred, BN(10), {from:account2})
            // prune middle order
            const pruned = await this.liquidator.prune()
            assert.equal(pruned.logs.length, 3, "Cancel, Cancel, Cancel")
            assert.equal(pruned.logs[0].args.order, trade3)
            assert.equal(pruned.logs[1].args.order, trade2)
            assert.equal(pruned.logs[2].args.order, trade1)
            assert.equal(await this.liquidator.next.call(ZERO_ADDRESS), ZERO_ADDRESS)
            assert.equal(await this.liquidator.next.call(trade3), ZERO_ADDRESS)
            assert.equal(await this.liquidator.next.call(trade2), ZERO_ADDRESS)
            assert.equal(await this.liquidator.next.call(trade1), ZERO_ADDRESS)
        })
        it('tolerates delegated signatories', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from:oneHundred})
            await this.airswap.authorizeSigner(account2, {from:oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign(account2)
            const registered = await this.liquidator.registerAirswap(order.web3Tuple)
            assert.equal(registered.logs.length, 1)
            assert.equal(registered.logs[0].event, 'LimitOrder')
            const executor = registered.logs[0].args.order
            assert.equal(executor, await this.liquidator.next.call(ZERO_ADDRESS))
        })
        it('prunes revoked signatories', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from:oneHundred})
            await this.airswap.authorizeSigner(account2, {from:oneHundred})
            let order = new Order(nonce, expiry, this.airswap.address, oneHundred, ONE_HUNDRED_ETHER, this.rewardToken.address, this.liquidator.address, ONE_HUNDRED_ETHER, this.stakeToken.address)
            await order.sign(account2)
            await this.liquidator.registerAirswap(order.web3Tuple)
            await this.airswap.revokeSigner(account2, {from:oneHundred})
            await this.liquidator.prune()
            assert.equal(ZERO_ADDRESS, await this.liquidator.next.call(ZERO_ADDRESS))
        })
    })
    describe('UniswapV1', function() {
        it('Liquidates all stake', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            let reclaimed = await this.liquidator.reclaim(approvedBeneficiary, ONE_HUNDRED_ETHER, {from:owner})
            assert.equal(reclaimed.logs.length, 1, "only one liquidation")
            assert.equal(reclaimed.logs[0].event, "Liquidated")
            assert(reclaimed.logs[0].args.stakeAmount.eq(ONE_HUNDRED_ETHER), "all stake liquidated")
            let debtAmount = BN("33233233333634234806")
            assert(reclaimed.logs[0].args.debtAmount.gte(debtAmount), "maximum debt")
            assert(BN(0).eq(await this.stakeToken.balanceOf(fakePool)))
            assert(debtAmount.lte(await this.rewardToken.balanceOf(approvedBeneficiary)))
        })
        it('Liquidates most stake', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED_ETHER, {from: oneHundred})
            const debt = BN("33233233333634234806")
            const expectedStakeLiquidated = BN("0x56bc75e2d630ff468")
            let reclaimed = await this.liquidator.reclaim(approvedBeneficiary, debt, {from:owner})
            assert.equal(reclaimed.logs.length, 1, "only one liquidation")
            assert.equal(reclaimed.logs[0].event, "Liquidated")
            assert(reclaimed.logs[0].args.debtAmount.eq(debt), "debt filled")
            assert(reclaimed.logs[0].args.stakeAmount.eq(expectedStakeLiquidated), "stake liquidated")
            assert(debt.eq(await this.rewardToken.balanceOf(approvedBeneficiary)), "debt reclaimed")
        })
    })
})
