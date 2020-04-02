# TrustToken README
TrustToken is a general assurance system. You provide assurance on any assurance opportunity, you get rewards in exchange for taking on risk. Each assurance opportunity has a pre-defined trigger for when TrustToken assurance is liquidated.

## 0. Setup
```
git submodule update --init --recursive
npm install
brew install python3
brew install gmp leveldb
python3 -m venv vyper-env
source ~/vyper-env/bin/activate
pip install vyper==0.1.0b4
```
## 1. TrustToken Token Smart Contract
1. The TrustToken token smart contract will be behind an upgradable proxy which will allow it to be upgraded by our team (similar to the TrueUSD smart contract)
2. GasBoost will be supported similar to TUSD
3. Initial minting version
   1. Minting enabled
   2. Transfers are disabled
   3. Upgrade will occur once all tokens have been minted for purchasers and the company. Only the owner key can perform the upgrade to the final version.
4. Upgraded final version
   1. Minting disabled
   2. Transfers enabled
5. Supports AutoSweep
## 2. TrustToken Assurance Smart Contracts
1. You can stake only TrustTokens
2. Stake is transferable and is represented as a fungible ERC20 token.
   1. The staking opportunity itself will not be an ERC20 token, it'll just have a bunch of children that are ERC20 tokens (one for each asset)
   2. Each staking opportunity has a name which is a string, we are not going to enforce uniqueness
   3. TRUST staked on "TUSD" will have symbol "TRUST:TUSD"
   4. Unclaimed rewards are transferred with TRUST:TUSD and TUSD:TUSD as they are transferred.
      1. Justification: Unclaimed rewards stay in the pool until they are claimed by an account that has passed KYC. If you sell your staked tokens or transfer your stake to another account you control, your unclaimed rewards travel with your stake. This allows you to move your stake to a multisig or between exchange accounts without unstaking or claiming. This prevents unclaimed rewards from becoming stuck in systems that don't know about them.
   5. This token will be on a whitelist if and only if staking itself requires a whitelist
   6. Stake that's in the process of being pulled out is not a tradable ERC20 token
3. Staking rewards are given out proportionally to stake in the smart contract when the staking reward comes in
4. You must be on the Registry's KYC/AML list in order to claim rewards
   1. The claimer can specify a recipient address, and either the recipient address or the claimer must be KYC'd in the registry
5. Slashing stake
   1. Slashing stake will dilute the value of TRUST:TUSD and sTUSD by pulling TUSD and TRU
   2. See Liquidation Contract section below
6. The TrustToken staking smart contract will be behind an upgradable proxy which will allow it to be easily upgraded by the owner multisig and then the auditor multisig
7. You must wait for 21 days to pull out stake
   1. You don't get rewards when you are in this pending state
   2. Your stake can be slashed while you are in this pending state
   3. If pulling out all stake would leave behind unclaimed rewards, they are distributed to the remaining stakers.
## 3. Liquidation Contract
1. Slashing stake
   1. Stake is slashed proportionally for everyone with respect to the obtainable TrueCurrency value.
      1. Ergo more TRUST will be sold by prior value, though less by resulting value
   2. Only as much stake as is required to fill the declared deficit will be liquidated
   3. TRUST can be sold for TUSD atomically via Airswap or similar if registered offers are better than Uniswap. TRUST will never be sold at a worse slippage than is achievable in the primary Uniswap. Supported exchanges may include:
      1. Airswap
      2. Uniswap V1
      3. Uniswap V2: TRUST/TUSD
      4. Uniswap V2: 2-hop pairings (eg TRUST/MKR;MKR/TUSD)
      5. Uniswap V2: TRUST:TUSD/TUSD (in the case all TRUST is liquidated)
      6. Uniswap V2: sTUSD/TUSD (in the case all TUSD is liquidated)
   4. If the TrustTokens cannot be liquidated for enough due TrueCurrency, all TrustTokens will be liquidated, and the remaining loss will come from:
      1. Unclaimed dividends to TrustTokens
      2. Staked TrueCurrencies
      3. Unclaimed TrueCurrency Dividends
   5. If the slash amount is greater than the obtainable TrueCurrency, all assets in the contract are slashed to zero, and all obtainable TrueCurrency is burned
      1. In this case the contract will deploy a copy of itself and redirect future deposits and rewards to the copy.
   6. TrueCurrency from stake or from TRUST sale is burned by the smart contract in order to bring the market cap down to be in line with the assets backing it
## 4. Staking Factory
The goal of the staking factory is that anyone (including but not limited to TrustToken) can create new things to stake on. For example:
* stocks
* bonds
* trusted off-chain financial opportunity
* uncollateralized loans
* Smart contract bugs
