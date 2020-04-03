const ProxiableLiquidator = artifacts.require('ProxiableLiquidator')
const LiquidatorFactory = artifacts.require('LiquidatorFactory')
const MockERC20Token = artifacts.require('MockERC20Token')

const ADDRESS = '0x0000000000000000000000000000000000000001'

contract.only('LiquidatorFoactory', async function () {
  beforeEach(async function () {
    this.implementation = await ProxiableLiquidator.new()
    this.factory = await LiquidatorFactory.new(this.implementation.address)
    this.outputToken = await MockERC20Token.new()
    this.stakeToken = await MockERC20Token.new()
  })

  it('has correct config', async function() {
    await this.factory.createLiquidator(ADDRESS, this.outputToken.address, this.stakeToken.address, ADDRESS, ADDRESS)
  })
})