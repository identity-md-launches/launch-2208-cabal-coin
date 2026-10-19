# Cabal Coin (CABAL)

Cabal Coin is a fixed-supply ERC-20 for Ethereum. Its constructor mints the entire supply to the immediate deployer (`msg.sender`) once.

| Property | Value |
| --- | --- |
| Contract | `src/CabalCoin.sol:CabalCoin` |
| Name | `Cabal Coin` |
| Symbol | `CABAL` |
| Decimals | `18` |
| Supply | `1,000,000,000 CABAL` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor value | `0 ETH` |
| Initial recipient | Immediate deployer; the factory during the IMD launch |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

`INITIAL_SUPPLY` is the named supply constant in base units. All token amounts accepted by the contract use base units: one CABAL is `10^18` units. The constructor makes no external calls and requires no configuration or existing contracts.

## Behavior and assumptions

The requested token uses ordinary ERC-20 transfers and allowances, implemented by the vendored OpenZeppelin ERC20. A successful transfer delivers the exact requested amount and returns `true`. Invalid operations revert with OpenZeppelin ERC-20 custom errors. Transfers of zero tokens between valid addresses succeed and emit `Transfer`; transfers to the zero address revert, including zero-value transfers. Self-transfers preserve balances and require sufficient funds.

`approve` replaces the caller's allowance for a spender, and zero revokes it. `transferFrom` requires that caller's allowance and sufficient sender balance; finite allowances decrease by the amount spent. An allowance of `type(uint256).max` is treated as unlimited and does not decrease. A reverted transfer preserves both balances and allowances. `approve` emits `Approval`; `transferFrom` emits `Transfer` and does not emit `Approval` when spending allowance in this OpenZeppelin version. Integrations should query `allowance` for its current value.

There are no transfer taxes, burns, rebases, maximum-wallet restrictions, trading switches, vesting, permits, owner, privileged roles, pause/blacklist functions, upgrade paths, or external mint functions. Supply cannot change after construction. The deployer holds ordinary tokens and has no special authority over any subsequent holder. The source inherits internal mint/burn helpers, but only the constructor calls mint and no callable function exposes either helper.

Transfers do not call recipients or other external contracts. Tokens can therefore be transferred to contracts that cannot return them, including the token itself; there is no recovery mechanism. The contract has no payable entry point, ETH withdrawal, or token rescue function.

## Build and test

From this repository root, with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x12f9aac5621487dd0560b4260d01a3bedb1e6f64227c917b1bf677edd26867db forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`; no download or submodule initialization is required. Exact upstream versions, commits, and checksums are in [DEPENDENCIES.md](DEPENDENCIES.md). Foundry's compiler is a toolchain prerequisite, not a repository dependency. The configuration enables neither FFI nor filesystem cheatcode permissions.

Tests require no RPC, fork, wallet, environment reads, or environment writes. The command above supplies the verification seed to Foundry itself. Fuzzing uses 512 cases per fuzz test; the stateful invariant uses 128 sequences of 64 calls with unexpected reverts treated as failures.

- `test/CabalCoin.t.sol`: metadata, single constructor mint and events, exact transfers, boundary amounts, self/zero transfers, approvals/revocation, finite and unlimited allowance, unauthorized spending, atomic reverts, absent admin/mint/burn functions, deployment size, forbidden opcodes, and four fuzz properties.
- `test/CabalCoinLaunch.t.sol`: CREATE2 deployment to a factory, complete initial factory balance, exact 10%/85%/5% token transfers, a distributor claim, and transfers in both pool directions. These are token-side flow checks, not an actual Uniswap pool or pricing simulation.
- `test/CabalCoinInvariant.t.sol`: a separate balance/allowance model over randomized transfer, approve, and transferFrom sequences, including self-transfers. It checks all modeled balances and allowances, conservation of the full supply, and fixed metadata.

Recorded local verification: `forge build` passed with Solidity 0.8.26; `forge test` passed all 34 tests with the seed above, including 2,048 fuzz cases and 8,192 invariant calls with zero reverts; `forge fmt --check` passed. Every vendored file also passed its recorded SHA-256 checksum.

## Deployment parameters and responsibilities

Deploy the creation bytecode for `CabalCoin` directly, without a proxy or initializer. The build artifact is `out/CabalCoin.sol/CabalCoin.json`; its `bytecode.object` requires no linked libraries or constructor arguments. `forge inspect src/CabalCoin.sol:CabalCoin bytecode` prints the creation code. Deployment requires zero attached ETH and no owner, recipient, router, oracle, or signer argument.

On the specified Ethereum launch (chain ID 1), IMD's factory is the immediate deployer and receives all `10^27` units. Calling a generic helper to deploy would instead give that helper the entire supply, so the launch must use the intended factory. No allocation is performed by the token constructor. The launch system handles the 10% swarm distribution, 85% pool allocation, and 5% remainder under the supplied launch terms. The token needs no exemptions to make those transfers exact. Pool pricing, paired currency, fees, liquidity settlement, and claims remain responsibilities of the external launch system.

The separate launch workflow supplies the manifest and deploys the accepted artifact. This project supplies the token only, with zero application contracts; it does not supply a launch manifest or broadcast any transaction. Before launch, the deployer should independently review the artifact and confirm the compiler settings, metadata, supply and factory recipient. After deployment, the launch operator should verify source on the explorer and confirm the mint event, final allocations and pool behavior.

## After launch

No owner settings, initialization calls, keepers, or administrative maintenance are required. Holders control transfers and approvals. Holders and integrating applications are responsible for validating destination and spender addresses and choosing allowance amounts. Prefer the amount needed for an operation; an unlimited allowance authorizes the spender to use future balances as well. When replacing an existing nonzero allowance, applications should account for the standard ERC-20 approval ordering risk, for example by first revoking it and waiting for confirmation.

There is no operator who can undo a transfer, recover lost keys, freeze a holder, or repair deployed bytecode. Any replacement token would require a separate deployment and migration process.

The supplied security reference was considered for access control, supply arithmetic, allowance behavior, external calls and deployment restrictions. Local tests and source review do not replace an independent security review before release. Slither and Mythril are not part of the recorded checks. The supplied protected tests depend on the external launch verifier's factory/pool harness, manifest and environment; the local suite does not claim to execute that integration harness.
