# Vendored dependencies

Dependencies are ordinary source files under `lib/`; no package installation, submodule, or network access is needed to build.

- [OpenZeppelin/openzeppelin-contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/dbb6104ce834628e473d2173bbc9d47f81a9eec3): `v5.0.2`, commit `dbb6104ce834628e473d2173bbc9d47f81a9eec3` (6 files).
- [foundry-rs/forge-std](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505): `v1.9.7`, commit `77041d2ce690e692d6e03cc812b57d1ddaa4d505` (30 files).

OpenZeppelin includes only ERC20 and its transitive imports, plus its MIT license. forge-std includes its Solidity source tree and MIT/Apache-2.0 licenses and is used only by tests. All vendored files are unmodified upstream files.

Verify the source snapshot from the repository root with `sha256sum -c DEPENDENCIES.sha256`.
