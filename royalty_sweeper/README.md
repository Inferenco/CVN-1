# CVN-1 Royalty Sweeper (Rust)

Permissionlessly sweeps royalties from each NFT’s on-chain royalty escrow into:
- creator payout address
- the NFT’s **Core Vault**

This calls `::vault_ops::sweep_royalty_to_core_vault` (or the batch variant `::vault_ops::sweep_royalty_to_core_vault_many`) for configured NFTs and fungible-asset metadata addresses.

## Prereqs

- Rust toolchain installed
- A funded gas account (private key) for submitting sweep txs

## Environment

- `CEDRA_NODE_URL` (default: `https://testnet.cedra.dev`)
- `CEDRA_PRIVATE_KEY` (required; hex, `0x` prefix ok)
- `CVN1_ADDRESS` (required; published package address, e.g. `0x...`)

## Run

One-shot sweep:

```bash
cargo run --release --manifest-path royalty_sweeper/Cargo.toml -- \
  sweep-once \
  --nft 0x... \
  --fa-metadata 0x...
```

Watch loop (polls balances):

```bash
cargo run --release --manifest-path royalty_sweeper/Cargo.toml -- \
  watch \
  --nft 0x... \
  --fa-metadata 0x... \
  --interval-secs 5 \
  --batch-size 20
```

You can also provide `--nfts-file path.txt` (one address per line, `#` comments allowed).
