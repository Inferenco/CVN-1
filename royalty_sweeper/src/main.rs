use anyhow::{anyhow, Context, Result};
use cedra_sdk::{
    bcs,
    move_types::{
        identifier::Identifier,
        language_storage::{ModuleId, TypeTag},
    },
    rest_client::{cedra_api_types::ViewFunction, Client},
    transaction_builder::TransactionBuilder,
    types::{
        account_address::AccountAddress,
        chain_id::ChainId,
        transaction::{EntryFunction, TransactionPayload},
        CedraCoinType, CoinType, LocalAccount,
    },
};
use clap::{Parser, Subcommand};
use std::{
    collections::BTreeSet,
    fs,
    path::PathBuf,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::time::sleep;
use url::Url;

#[derive(Debug, Parser)]
#[command(name = "cvn1_royalty_sweeper")]
#[command(about = "Sweeps CVN-1 royalties into creator payout + NFT core vault")]
struct Cli {
    #[arg(long, env = "CEDRA_NODE_URL", default_value = "https://testnet.cedra.dev")]
    cedra_node_url: Url,

    #[arg(long, env = "CEDRA_PRIVATE_KEY")]
    cedra_private_key: String,

    #[arg(long, env = "CVN1_ADDRESS")]
    cvn1_address: AccountAddress,

    #[arg(long, default_value_t = 30)]
    timeout_secs: u64,

    #[arg(long, default_value_t = 5_000)]
    max_gas_amount: u64,

    #[arg(long, default_value_t = 100)]
    gas_unit_price: u64,

    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Sweep a single NFT once
    SweepOnce {
        #[arg(long)]
        nft: AccountAddress,

        #[arg(long)]
        fa_metadata: AccountAddress,

        /// Submit sweep tx even if the view reports 0 balance
        #[arg(long, default_value_t = false)]
        force: bool,
    },

    /// Poll escrows and sweep when balance is non-zero
    Watch {
        /// NFT address (repeatable)
        #[arg(long)]
        nft: Vec<AccountAddress>,

        /// Path to a file containing NFT addresses (one per line, '#' comments ok)
        #[arg(long)]
        nfts_file: Option<PathBuf>,

        #[arg(long)]
        fa_metadata: AccountAddress,

        #[arg(long, default_value_t = 5)]
        interval_secs: u64,

        /// Maximum NFTs to sweep per transaction (uses on-chain batching)
        #[arg(long, default_value_t = 20)]
        batch_size: usize,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    // Load .env file if present (from current dir or royalty_sweeper dir)
    let _ = dotenvy::dotenv();
    let _ = dotenvy::from_filename("royalty_sweeper/.env");

    let cli = Cli::parse();

    let api_client = Client::new(cli.cedra_node_url.clone());

    let chain_id = api_client
        .get_index()
        .await
        .context("get chain id")?
        .into_inner()
        .chain_id;

    let mut gas_account = LocalAccount::from_private_key(&cli.cedra_private_key, 0)
        .context("parse CEDRA_PRIVATE_KEY")?;
    refresh_sequence_number(&api_client, &mut gas_account)
        .await
        .context("get gas account sequence number")?;

    let cvn1_address = cli.cvn1_address;
    let timeout_secs = cli.timeout_secs;
    let max_gas_amount = cli.max_gas_amount;
    let gas_unit_price = cli.gas_unit_price;

    match cli.command {
        Command::SweepOnce {
            nft,
            fa_metadata,
            force,
        } => {
            sweep_one(
                &api_client,
                chain_id,
                &mut gas_account,
                cvn1_address,
                nft,
                fa_metadata,
                timeout_secs,
                max_gas_amount,
                gas_unit_price,
                force,
            )
            .await?;
        },
        Command::Watch {
            nft,
            nfts_file,
            fa_metadata,
            interval_secs,
            batch_size,
        } => {
            let mut nfts = BTreeSet::<AccountAddress>::new();
            for addr in nft {
                nfts.insert(addr);
            }
            if let Some(path) = nfts_file {
                for addr in read_addresses_file(&path).context("read --nfts-file")? {
                    nfts.insert(addr);
                }
            }
            if nfts.is_empty() {
                return Err(anyhow!("watch mode requires --nft and/or --nfts-file"));
            }

            loop {
                let mut due = Vec::<(AccountAddress, u64)>::new();
                for nft_addr in nfts.iter().copied() {
                    match view_royalty_escrow_balance(
                        &api_client,
                        cvn1_address,
                        nft_addr,
                        fa_metadata,
                    )
                    .await
                    {
                        Ok(balance) => {
                            if balance > 0 {
                                due.push((nft_addr, balance));
                            }
                        },
                        Err(err) => {
                            eprintln!("balance check failed for {nft_addr}: {err:#}");
                        },
                    }
                }

                if due.is_empty() {
                    sleep(Duration::from_secs(interval_secs)).await;
                    continue;
                }

                for chunk in due.chunks(std::cmp::max(1, batch_size)) {
                    let nft_addrs: Vec<AccountAddress> =
                        chunk.iter().map(|(addr, _)| *addr).collect();
                    let total_balance: u64 = chunk.iter().map(|(_, bal)| *bal).sum();

                    if let Err(err) = submit_sweep_many_tx(
                        &api_client,
                        chain_id,
                        &mut gas_account,
                        cvn1_address,
                        &nft_addrs,
                        fa_metadata,
                        timeout_secs,
                        max_gas_amount,
                        gas_unit_price,
                    )
                    .await
                    {
                        eprintln!(
                            "batch sweep failed (nfts={}, total_balance={}): {err:#}",
                            nft_addrs.len(),
                            total_balance
                        );

                        if let Err(refresh_err) =
                            refresh_sequence_number(&api_client, &mut gas_account).await
                        {
                            eprintln!("sequence refresh failed: {refresh_err:#}");
                        }
                    } else {
                        println!(
                            "batch swept nfts={}, total_balance={}",
                            nft_addrs.len(),
                            total_balance
                        );
                    }
                }

                sleep(Duration::from_secs(interval_secs)).await;
            }
        },
    }

    Ok(())
}

fn read_addresses_file(path: &PathBuf) -> Result<Vec<AccountAddress>> {
    let contents = fs::read_to_string(path)
        .with_context(|| format!("read file {}", path.display()))?;
    let mut out = Vec::new();
    for (idx, raw) in contents.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let addr = line
            .parse::<AccountAddress>()
            .with_context(|| format!("parse address at {}:{}", path.display(), idx + 1))?;
        out.push(addr);
    }
    Ok(out)
}

async fn sweep_one(
    api_client: &Client,
    chain_id: u8,
    gas_account: &mut LocalAccount,
    cvn1_address: AccountAddress,
    nft: AccountAddress,
    fa_metadata: AccountAddress,
    timeout_secs: u64,
    max_gas_amount: u64,
    gas_unit_price: u64,
    force: bool,
) -> Result<()> {
    let escrow_balance = view_royalty_escrow_balance(api_client, cvn1_address, nft, fa_metadata)
        .await
        .unwrap_or(0);

    if escrow_balance == 0 && !force {
        return Ok(());
    }

    submit_sweep_tx(
        api_client,
        chain_id,
        gas_account,
        cvn1_address,
        nft,
        fa_metadata,
        timeout_secs,
        max_gas_amount,
        gas_unit_price,
    )
    .await?;

    println!(
        "swept nft={} fa_metadata={} escrow_balance={}",
        nft, fa_metadata, escrow_balance
    );

    Ok(())
}

async fn view_royalty_escrow_balance(
    api_client: &Client,
    cvn1_address: AccountAddress,
    nft: AccountAddress,
    fa_metadata: AccountAddress,
) -> Result<u64> {
    let view = ViewFunction {
        module: ModuleId::new(
            cvn1_address,
            Identifier::new("vault_views").expect("valid identifier"),
        ),
        function: Identifier::new("get_royalty_escrow_balance").expect("valid identifier"),
        ty_args: vec![],
        args: vec![
            bcs::to_bytes(&nft).context("bcs encode nft addr")?,
            bcs::to_bytes(&fa_metadata).context("bcs encode fa_metadata addr")?,
        ],
    };

    let mut ret = api_client
        .view_bcs::<Vec<u64>>(&view, None)
        .await
        .context("view get_royalty_escrow_balance")?
        .into_inner();
    ret.pop().ok_or_else(|| anyhow!("view returned no values"))
}

async fn refresh_sequence_number(api_client: &Client, gas_account: &mut LocalAccount) -> Result<()> {
    let seq = api_client
        .get_account_sequence_number(gas_account.address())
        .await
        .context("get account sequence number")?
        .into_inner();
    gas_account.set_sequence_number(seq);
    Ok(())
}

async fn submit_sweep_tx(
    api_client: &Client,
    chain_id: u8,
    gas_account: &mut LocalAccount,
    cvn1_address: AccountAddress,
    nft: AccountAddress,
    fa_metadata: AccountAddress,
    timeout_secs: u64,
    max_gas_amount: u64,
    gas_unit_price: u64,
) -> Result<()> {
    let payload = TransactionPayload::EntryFunction(EntryFunction::new(
        ModuleId::new(
            cvn1_address,
            Identifier::new("vault_ops").expect("valid identifier"),
        ),
        Identifier::new("sweep_royalty_to_core_vault").expect("valid identifier"),
        vec![],
        vec![
            bcs::to_bytes(&nft).context("bcs encode nft object addr")?,
            bcs::to_bytes(&fa_metadata).context("bcs encode fa_metadata object addr")?,
        ],
    ));

    let expiration_timestamp_secs =
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .context("read current time")?
            .as_secs()
            + timeout_secs;

    let builder = TransactionBuilder::new(
        payload,
        expiration_timestamp_secs,
        ChainId::new(chain_id),
        gas_fee_type_tag(),
    )
    .sender(gas_account.address())
    .sequence_number(gas_account.sequence_number())
    .max_gas_amount(max_gas_amount)
    .gas_unit_price(gas_unit_price);

    let signed_txn = gas_account.sign_with_transaction_builder(builder);
    if let Err(err) = api_client.submit_and_wait(&signed_txn).await {
        let _ = refresh_sequence_number(api_client, gas_account).await;
        return Err(err).context("submit sweep tx");
    }

    gas_account.increment_sequence_number();
    Ok(())
}

async fn submit_sweep_many_tx(
    api_client: &Client,
    chain_id: u8,
    gas_account: &mut LocalAccount,
    cvn1_address: AccountAddress,
    nfts: &[AccountAddress],
    fa_metadata: AccountAddress,
    timeout_secs: u64,
    max_gas_amount: u64,
    gas_unit_price: u64,
) -> Result<()> {
    let payload = TransactionPayload::EntryFunction(EntryFunction::new(
        ModuleId::new(
            cvn1_address,
            Identifier::new("vault_ops").expect("valid identifier"),
        ),
        Identifier::new("sweep_royalty_to_core_vault_many").expect("valid identifier"),
        vec![],
        vec![
            bcs::to_bytes(&nfts).context("bcs encode nft addresses")?,
            bcs::to_bytes(&fa_metadata).context("bcs encode fa_metadata object addr")?,
        ],
    ));

    let expiration_timestamp_secs =
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .context("read current time")?
            .as_secs()
            + timeout_secs;

    let builder = TransactionBuilder::new(
        payload,
        expiration_timestamp_secs,
        ChainId::new(chain_id),
        gas_fee_type_tag(),
    )
    .sender(gas_account.address())
    .sequence_number(gas_account.sequence_number())
    .max_gas_amount(max_gas_amount)
    .gas_unit_price(gas_unit_price);

    let signed_txn = gas_account.sign_with_transaction_builder(builder);
    if let Err(err) = api_client.submit_and_wait(&signed_txn).await {
        let _ = refresh_sequence_number(api_client, gas_account).await;
        return Err(err).context("submit batch sweep tx");
    }

    gas_account.increment_sequence_number();
    Ok(())
}

fn gas_fee_type_tag() -> TypeTag {
    CedraCoinType::type_tag()
}
