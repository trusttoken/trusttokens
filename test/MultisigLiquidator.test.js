const Liquidator = artifacts.require('LiquidatorMock')
const BN = web3.utils.toBN
const ONE_HUNDRED = BN(100).mul(BN(1e18))
const assertRevert = require('@trusttoken/registry/test/helpers/assertRevert.js')
const MockTrustToken = artifacts.require('MockTrustToken')
const TrueUSD = artifacts.require('MockERC20Token')
const Airswap = artifacts.require('Swap')
const AirswapERC20TransferHandler = artifacts.require('AirswapERC20TransferHandler')
const TransferHandlerRegistry = artifacts.require('TransferHandlerRegistry')
const UniswapFactory = artifacts.require('uniswap_factory')
const UniswapExchange = artifacts.require('uniswap_exchange')
const MultisigLiquidator = artifacts.require("MultisigLiquidatorMock");
const Registry = artifacts.require('RegistryMock')
const { Order, hashDomain } = require('./lib/airswap.js')
const { signAction } = require('./lib/multisigLiquidator.js')
const Types = artifacts.require('Types')
const ERC20_KIND = '0x36372b07'
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const ZERO_BYTES32 = '0x0000000000000000000000000000000000000000000000000000000000000000'
const bytes32 = require('@trusttoken/registry/test/helpers/bytes32.js')
const AIRSWAP_VALIDATOR = bytes32('AirswapValidatorDomain')
const APPROVED_BENEFICIARY = bytes32('approvedBeneficiary')
const { addressBytes32, uint256Bytes32 } = require('./lib/abi.js')


contract('MultisigLiquidator', function(accounts) {
    const [_, owner, issuer, oneHundred, approvedBeneficiary, auditor, anotherAccount, fakePool] = accounts
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
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        await this.stakeToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        this.transferHandler = await AirswapERC20TransferHandler.new({from: owner})
        this.transferHandlerRegistry = await TransferHandlerRegistry.new({from: owner})
        this.transferHandlerRegistry.addTransferHandler(ERC20_KIND, this.transferHandler.address,{from:owner})
        this.types = await Types.new()
        await Airswap.link('Types', this.types.address)
        await this.rewardToken.approve(this.outputUniswap.address, ONE_HUNDRED, {from: oneHundred})
        await this.stakeToken.approve(this.stakeUniswap.address, ONE_HUNDRED, {from: oneHundred})
        let expiry = parseInt(Date.now() / 1000) + 12000
        await this.outputUniswap.addLiquidity(ONE_HUNDRED, ONE_HUNDRED, expiry, {from:oneHundred, value:1e17})
        await this.stakeUniswap.addLiquidity(ONE_HUNDRED, ONE_HUNDRED, expiry, {from:oneHundred, value:1e17})
        await this.rewardToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        await this.stakeToken.mint(oneHundred, ONE_HUNDRED, {from:issuer});
        this.airswap = await Airswap.new(this.transferHandlerRegistry.address, {from: owner})
        this.liquidator = await Liquidator.new(this.registry.address, this.rewardToken.address, this.stakeToken.address, this.outputUniswap.address, this.stakeUniswap.address, {from: owner})
        await this.liquidator.setPool(fakePool, {from:owner})
        await this.registry.subscribe(AIRSWAP_VALIDATOR, this.liquidator.address, {from: owner})
        await this.registry.subscribe(APPROVED_BENEFICIARY, this.liquidator.address, {from: owner})
        await this.registry.setAttributeValue(this.airswap.address, AIRSWAP_VALIDATOR, hashDomain(this.airswap.address), {from: owner})
        await this.registry.setAttributeValue(approvedBeneficiary, APPROVED_BENEFICIARY, 1, {from: owner})
        await this.rewardToken.approve(this.airswap.address, ONE_HUNDRED, {from: oneHundred})
        await this.stakeToken.approve(this.liquidator.address, ONE_HUNDRED, { from: fakePool })

        this.multisig = await MultisigLiquidator.new([owner, auditor, issuer], this.liquidator.address)
    })
    describe('Self Operations', function() {
        it('updates owners', async function() {
            assert.equal(await this.multisig.owners.call(0), owner, "first owner mismatch")
            assert.equal(await this.multisig.owners.call(1), auditor, "second owner mismatch")
            assert.equal(await this.multisig.owners.call(2), issuer, "third owner mismatch")
            assert.equal(await this.multisig.nonce.call(), 0)

            const action = web3.utils.sha3('updateOwner(address,address)').slice(0,10) + addressBytes32(owner) + addressBytes32(anotherAccount)
            const sig1 = await signAction(issuer, this.multisig.address, 0, action)
            const sig2 = await signAction(auditor, this.multisig.address, 0, action)
            const updated = await this.multisig.msUpdateOwner(owner, anotherAccount, [sig1, sig2])

            assert.equal(await this.multisig.owners.call(0), anotherAccount, "first owner mismatch")
            assert.equal(await this.multisig.owners.call(1), auditor, "second owner mismatch")
            assert.equal(await this.multisig.owners.call(2), issuer, "third owner mismatch")
            assert.equal(await this.multisig.nonce.call(), 1)
        })
    })
    describe('Liquidator Operations', function() {
        beforeEach(async function() {
            await this.liquidator.transferOwnership(this.multisig.address, {from:owner})
            const action = web3.utils.sha3('claimOwnership()').slice(0, 10)
            const sig1 = await signAction(issuer, this.multisig.address, 0, action)
            const sig2 = await signAction(owner, this.multisig.address, 0, action)
            await this.multisig.claimOwnership([sig1, sig2])
        })
        it('sets pool', async function() {
            const action = (web3.utils.sha3('setPool(address)').slice(0, 10) + addressBytes32(approvedBeneficiary)).toLowerCase()
            const sig1 = await signAction(issuer, this.multisig.address, 1, action)
            const sig2 = await signAction(owner, this.multisig.address, 1, action)
            const reclaimed = await this.multisig.setPool(approvedBeneficiary, [sig1, sig2])
            assert.equal(reclaimed.logs.length, 1, "Action")
            assert.equal(reclaimed.logs[0].event, "Action")
            assert.equal(reclaimed.logs[0].args.nonce, 1, "first nonce")
            assert.equal(reclaimed.logs[0].args.owner1, issuer, "incorrect owner1")
            assert.equal(reclaimed.logs[0].args.owner2, owner, "incorrect owner2")
            assert.equal(reclaimed.logs[0].args.action, action, "different action")
        })
        it('reclaims', async function() {
            const action = (web3.utils.sha3('reclaim(address,int256)').slice(0, 10) + addressBytes32(approvedBeneficiary) + uint256Bytes32(ONE_HUNDRED)).toLowerCase()
            const sig1 = await signAction(issuer, this.multisig.address, 1, action)
            const sig2 = await signAction(owner, this.multisig.address, 1, action)
            const reclaimed = await this.multisig.reclaim(approvedBeneficiary, ONE_HUNDRED, [sig1, sig2])
            assert.equal(reclaimed.logs.length, 1, "Action")
            assert.equal(reclaimed.logs[0].event, "Action")
            assert.equal(reclaimed.logs[0].args.nonce, 1, "first nonce")
            assert.equal(reclaimed.logs[0].args.owner1, issuer, "incorrect owner1")
            assert.equal(reclaimed.logs[0].args.owner2, owner, "incorrect owner2")
            assert.equal(reclaimed.logs[0].args.action, action, "different action")
        })
        it('reclaimStake', async function() {
            await this.stakeToken.transfer(fakePool, ONE_HUNDRED, {from:oneHundred})

            const action = (web3.utils.sha3('reclaimStake(address,uint256)').slice(0, 10) + addressBytes32(approvedBeneficiary) + uint256Bytes32(ONE_HUNDRED)).toLowerCase()
            const sig1 = await signAction(issuer, this.multisig.address, 1, action)
            const sig2 = await signAction(owner, this.multisig.address, 1, action)
            const reclaimed = await this.multisig.reclaimStake(approvedBeneficiary, ONE_HUNDRED, [sig1, sig2])
            assert.equal(reclaimed.logs.length, 1, "Action")
            assert.equal(reclaimed.logs[0].event, "Action")
            assert.equal(reclaimed.logs[0].args.nonce, 1, "first nonce")
            assert.equal(reclaimed.logs[0].args.owner1, issuer, "incorrect owner1")
            assert.equal(reclaimed.logs[0].args.owner2, owner, "incorrect owner2")
            assert.equal(reclaimed.logs[0].args.action, action, "different action")
        })
    })
    describe('auth', function() {
        it('checks first signature', async function() {
            const action = web3.utils.sha3('updateOwner(address,address)').slice(0,10) + addressBytes32(owner) + addressBytes32(anotherAccount)
            const somethingElse = web3.utils.sha3('updateOwner(address,address)').slice(0,10) + addressBytes32(anotherAccount) + addressBytes32(owner)
            const sig1 = await signAction(issuer, this.multisig.address, 0, somethingElse)
            const sig2 = await signAction(auditor, this.multisig.address, 0, action)
            await assertRevert(this.multisig.msUpdateOwner(owner, anotherAccount, [sig1, sig2]))
        })
        it('checks second signature', async function() {
            const action = web3.utils.sha3('updateOwner(address,address)').slice(0,10) + addressBytes32(owner) + addressBytes32(anotherAccount)
            const somethingElse = web3.utils.sha3('updateOwner(address,address)').slice(0,10) + addressBytes32(anotherAccount) + addressBytes32(owner)
            const sig1 = await signAction(issuer, this.multisig.address, 0, action)
            const sig2 = await signAction(auditor, this.multisig.address, 0, somethingElse)
            await assertRevert(this.multisig.msUpdateOwner(owner, anotherAccount, [sig1, sig2]))
        })
        it('requires signatures from different parties', async function() {
            const action = web3.utils.sha3('updateOwner(address,address)').slice(0,10) + addressBytes32(owner) + addressBytes32(anotherAccount)
            const sig1 = await signAction(auditor, this.multisig.address, 0, action)
            const sig2 = await signAction(auditor, this.multisig.address, 0, action)
            await assertRevert(this.multisig.msUpdateOwner(owner, anotherAccount, [sig1, sig2]))
        })
    })
})
