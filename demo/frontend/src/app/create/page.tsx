"use client";

import { useState } from "react";
import Link from "next/link";
import { ConnectButton } from "@/components/ConnectButton";
import { useWallet } from "@/components/wallet-provider";
import { CVN1_ADDRESS, getCollectionAddrFromTx, buildInitCollectionPayload } from "@/lib/cvn1";

// Full-length CEDRA FA metadata address (padded to 64 chars)
const CEDRA_FA = "0x000000000000000000000000000000000000000000000000000000000000000a";

interface CollectionConfig {
    name: string;
    description: string;
    uri: string;
    creatorRoyaltyBps: number;
    vaultRoyaltyBps: number;
    mintVaultBps: number;
    mintPrice: number;
    isRedeemable: boolean;
    maxSupply: number;  // v4: 0 = unlimited
}

export default function CreatePage() {
    const { connected, account, signAndSubmitTransaction } = useWallet();
    const [config, setConfig] = useState<CollectionConfig>({
        name: "My Vaulted Collection",
        description: "NFTs with built-in dual vaults",
        uri: "https://example.com/collection.json",
        creatorRoyaltyBps: 250,
        vaultRoyaltyBps: 250,
        mintVaultBps: 5000,
        mintPrice: 50,
        isRedeemable: true,
        maxSupply: 0,  // v4: 0 = unlimited
    });

    const [creating, setCreating] = useState(false);
    const [created, setCreated] = useState(false);
    const [txHash, setTxHash] = useState<string>("");
    const [collectionAddr, setCollectionAddr] = useState<string>("");
    const [error, setError] = useState<string | null>(null);

    const handleCreate = async () => {
        if (!connected || !account) {
            setError("Please connect your wallet first");
            return;
        }

        setCreating(true);
        setError(null);

        try {
            const payload = buildInitCollectionPayload(
                config.name,
                config.description,
                config.uri,
                config.creatorRoyaltyBps,
                config.vaultRoyaltyBps,
                config.mintVaultBps,
                BigInt(Math.floor(config.mintPrice * 1e8)),
                CEDRA_FA,
                [],
                account.address?.toString() || "",
                config.maxSupply  // v4
            );

            const result = await signAndSubmitTransaction({
                data: payload,
            });

            setTxHash(result.hash);

            const addr = await getCollectionAddrFromTx(result.hash);
            if (addr) {
                setCollectionAddr(addr);
            }

            setCreated(true);
        } catch (err) {
            console.error("Create failed:", err);
            setError(err instanceof Error ? err.message : "Create failed");
        } finally {
            setCreating(false);
        }
    };

    const vaultAmount = (config.mintPrice * config.mintVaultBps) / 10000;
    const creatorAmount = config.mintPrice - vaultAmount;
    const totalRoyaltyBps = config.creatorRoyaltyBps + config.vaultRoyaltyBps;

    return (
        <main className="min-h-screen bg-gradient-to-br from-slate-950 via-slate-900 to-slate-950">
            {/* Header */}
            <header className="border-b border-slate-700/50 backdrop-blur-sm bg-slate-900/50">
                <div className="max-w-7xl mx-auto px-6 py-4 flex items-center justify-between">
                    <Link href="/" className="flex items-center gap-3 hover:opacity-80 transition-opacity">
                        <span className="text-2xl">💎</span>
                        <span className="text-xl font-bold bg-gradient-to-r from-violet-400 to-fuchsia-400 bg-clip-text text-transparent">
                            CVN-1 v6
                        </span>
                    </Link>
                    <div className="flex items-center gap-4">
                        <Link href="/" className="text-slate-400 hover:text-white text-sm">Home</Link>
                        <Link href="/mint" className="text-slate-400 hover:text-white text-sm">Mint</Link>
                        <Link href="/explore" className="text-slate-400 hover:text-white text-sm">Explore</Link>
                        <ConnectButton />
                    </div>
                </div>
            </header>

            <div className="max-w-5xl mx-auto px-6 py-12">
                <div className="text-center mb-10">
                    <h1 className="text-4xl font-bold text-white mb-3">Create Collection</h1>
                    <p className="text-slate-400">Deploy a vaulted NFT collection with dual vault architecture</p>
                </div>

                {error && (
                    <div className="mb-6 p-4 bg-red-500/20 border border-red-500/50 rounded-xl text-red-400 text-center">
                        {error}
                    </div>
                )}

                {!connected && (
                    <div className="mb-6 p-6 bg-violet-500/10 border border-violet-500/30 rounded-xl text-center">
                        <p className="text-violet-300 mb-2">Connect your wallet to create a collection</p>
                        <p className="text-sm text-slate-400">Click &quot;Connect&quot; in the header</p>
                    </div>
                )}

                {!created ? (
                    <div className="grid lg:grid-cols-5 gap-8">
                        {/* Config Panel */}
                        <div className="lg:col-span-3 space-y-6">
                            {/* Collection Info */}
                            <div className="bg-slate-800/50 border border-slate-700/50 rounded-2xl p-6">
                                <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                                    <span>📝</span> Collection Info
                                </h2>
                                <div className="space-y-4">
                                    <div>
                                        <label className="block text-sm text-slate-400 mb-1">Name</label>
                                        <input
                                            type="text"
                                            value={config.name}
                                            onChange={e => setConfig({ ...config, name: e.target.value })}
                                            className="w-full px-4 py-3 bg-slate-900/50 border border-slate-700 rounded-xl text-white focus:border-violet-500 focus:outline-none"
                                        />
                                    </div>
                                    <div>
                                        <label className="block text-sm text-slate-400 mb-1">Description</label>
                                        <textarea
                                            value={config.description}
                                            onChange={e => setConfig({ ...config, description: e.target.value })}
                                            className="w-full px-4 py-3 bg-slate-900/50 border border-slate-700 rounded-xl text-white focus:border-violet-500 focus:outline-none resize-none"
                                            rows={2}
                                        />
                                    </div>
                                    <div>
                                        <label className="block text-sm text-slate-400 mb-1">Metadata URI</label>
                                        <input
                                            type="text"
                                            value={config.uri}
                                            onChange={e => setConfig({ ...config, uri: e.target.value })}
                                            className="w-full px-4 py-3 bg-slate-900/50 border border-slate-700 rounded-xl text-white focus:border-violet-500 focus:outline-none font-mono text-sm"
                                        />
                                    </div>
                                </div>
                            </div>

                            {/* Mint Configuration */}
                            <div className="bg-slate-800/50 border border-slate-700/50 rounded-2xl p-6">
                                <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                                    <span>⚡</span> Mint Settings
                                </h2>
                                <div className="space-y-5">
                                    <div>
                                        <div className="flex justify-between mb-2">
                                            <label className="text-sm text-slate-400">Mint Price</label>
                                            <span className="text-sm font-medium text-white">
                                                {config.mintPrice === 0 ? "FREE" : `${config.mintPrice} CEDRA`}
                                            </span>
                                        </div>
                                        <input
                                            type="range"
                                            min="0"
                                            max="500"
                                            value={config.mintPrice}
                                            onChange={e => setConfig({ ...config, mintPrice: Number(e.target.value) })}
                                            className="w-full accent-violet-500"
                                        />
                                    </div>
                                    <div>
                                        <div className="flex justify-between mb-2">
                                            <label className="text-sm text-slate-400">Mint → Core Vault %</label>
                                            <span className="text-sm font-medium text-indigo-400">
                                                {config.mintVaultBps / 100}%
                                            </span>
                                        </div>
                                        <input
                                            type="range"
                                            min="0"
                                            max="10000"
                                            step="100"
                                            value={config.mintVaultBps}
                                            onChange={e => setConfig({ ...config, mintVaultBps: Number(e.target.value) })}
                                            className="w-full accent-indigo-500"
                                        />
                                        <p className="text-xs text-slate-500 mt-1">% of mint price seeded to Core Vault (long-term)</p>
                                    </div>
                                </div>
                            </div>

                            {/* Royalty Configuration */}
                            <div className="bg-slate-800/50 border border-slate-700/50 rounded-2xl p-6">
                                <h2 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
                                    <span>💰</span> Secondary Sale Royalties
                                </h2>
                                <div className="space-y-5">
                                    <div>
                                        <div className="flex justify-between mb-2">
                                            <label className="text-sm text-slate-400">Creator Royalty</label>
                                            <span className="text-sm font-medium text-white">{config.creatorRoyaltyBps / 100}%</span>
                                        </div>
                                        <input
                                            type="range"
                                            min="0"
                                            max="1000"
                                            step="25"
                                            value={config.creatorRoyaltyBps}
                                            onChange={e => setConfig({ ...config, creatorRoyaltyBps: Number(e.target.value) })}
                                            className="w-full accent-blue-500"
                                        />
                                        <p className="text-xs text-slate-500 mt-1">Creator portion (paid on sweep)</p>
                                    </div>

                                    <div>
                                        <div className="flex justify-between mb-2">
                                            <label className="text-sm text-slate-400">Core Vault Royalty</label>
                                            <span className="text-sm font-medium text-white">{config.vaultRoyaltyBps / 100}%</span>
                                        </div>
                                        <input
                                            type="range"
                                            min="0"
                                            max="1000"
                                            step="25"
                                            value={config.vaultRoyaltyBps}
                                            onChange={e => setConfig({ ...config, vaultRoyaltyBps: Number(e.target.value) })}
                                            className="w-full accent-emerald-500"
                                        />
                                        <p className="text-xs text-slate-500 mt-1">Vault portion (swept into the traded NFT’s Core Vault)</p>
                                    </div>

                                    <div className="text-xs text-slate-400 flex justify-between">
                                        <span>Total Royalty</span>
                                        <span className={totalRoyaltyBps > 10000 ? "text-red-400" : "text-slate-200"}>
                                            {totalRoyaltyBps / 100}%
                                        </span>
                                    </div>
                                </div>
                            </div>

                            {/* Redeemable Toggle */}
                            <div className="bg-slate-800/50 border border-slate-700/50 rounded-2xl p-6">
                                <label className="flex items-center gap-4 cursor-pointer">
                                    <input
                                        type="checkbox"
                                        checked={config.isRedeemable}
                                        onChange={e => setConfig({ ...config, isRedeemable: e.target.checked })}
                                        className="w-5 h-5 accent-violet-500"
                                    />
                                    <div>
                                        <span className="text-white font-medium">🔥 Redeemable Core Vault</span>
                                        <p className="text-sm text-slate-400">Holders can burn NFT to claim Core + Rewards vaults</p>
                                    </div>
                                </label>
                            </div>

                            {/* Max Supply (v4) */}
                            <div className="bg-slate-800/50 border border-slate-700/50 rounded-2xl p-6">
                                <label className="block">
                                    <span className="text-white font-medium flex items-center gap-2">
                                        📊 Max Supply
                                        <span className="text-xs text-slate-400">(0 = unlimited)</span>
                                    </span>
                                    <input
                                        type="number"
                                        min="0"
                                        value={config.maxSupply}
                                        onChange={e => setConfig({ ...config, maxSupply: Math.max(0, parseInt(e.target.value) || 0) })}
                                        className="mt-2 w-full bg-slate-900 border border-slate-600 rounded-lg px-4 py-2 text-white"
                                        placeholder="0 = unlimited"
                                    />
                                    <p className="mt-1 text-sm text-slate-400">
                                        {config.maxSupply === 0 ? "Unlimited mints allowed" : `Limited edition: ${config.maxSupply} NFTs max`}
                                    </p>
                                </label>
                            </div>
                        </div>

                        {/* Preview Panel */}
                        <div className="lg:col-span-2">
                            <div className="bg-slate-800/50 border border-slate-700/50 rounded-2xl p-6 sticky top-6">
                                <h2 className="text-lg font-semibold text-white mb-4">Preview</h2>

                                {/* Collection Preview */}
                                <div className="bg-gradient-to-br from-violet-500/10 to-fuchsia-500/10 rounded-xl p-4 mb-6 border border-violet-500/20">
                                    <div className="text-3xl mb-2">💎</div>
                                    <h3 className="font-bold text-white text-lg">{config.name}</h3>
                                    <p className="text-sm text-slate-400 line-clamp-2">{config.description}</p>
                                </div>

                                {/* Mint Split Visual */}
                                <div className="mb-6">
                                    <div className="text-sm text-slate-400 mb-2">Mint Split</div>
                                    <div className="flex h-4 rounded-full overflow-hidden mb-2">
                                        <div
                                            className="bg-gradient-to-r from-indigo-500 to-violet-500"
                                            style={{ width: `${config.mintVaultBps / 100}%` }}
                                        />
                                        <div
                                            className="bg-slate-600"
                                            style={{ width: `${100 - config.mintVaultBps / 100}%` }}
                                        />
                                    </div>
                                    <div className="flex justify-between text-xs">
                                        <span className="text-indigo-400">🔒 {vaultAmount} → Core Vault</span>
                                        <span className="text-slate-400">{creatorAmount} → Creator</span>
                                    </div>
                                </div>

                                {/* Stats */}
                                <div className="space-y-3 mb-6">
                                    <div className="flex justify-between text-sm">
                                        <span className="text-slate-400">Mint Price</span>
                                        <span className="text-white font-medium">
                                            {config.mintPrice === 0 ? "FREE" : `${config.mintPrice} CEDRA`}
                                        </span>
                                    </div>
                                    <div className="flex justify-between text-sm">
                                        <span className="text-slate-400">Creator Royalty</span>
                                        <span className="text-white">{config.creatorRoyaltyBps / 100}%</span>
                                    </div>
                                    <div className="flex justify-between text-sm">
                                        <span className="text-slate-400">Core Vault Royalty</span>
                                        <span className="text-white">{config.vaultRoyaltyBps / 100}%</span>
                                    </div>
                                    <div className="flex justify-between text-sm">
                                        <span className="text-slate-400">Total Royalty</span>
                                        <span className="text-white">{totalRoyaltyBps / 100}%</span>
                                    </div>
                                    <div className="flex justify-between text-sm">
                                        <span className="text-slate-400">Redeemable</span>
                                        <span className={config.isRedeemable ? "text-green-400" : "text-red-400"}>
                                            {config.isRedeemable ? "Yes" : "No"}
                                        </span>
                                    </div>
                                </div>

                                {/* Create Button */}
                                <button
                                    onClick={handleCreate}
                                    disabled={creating || !connected}
                                    className="w-full py-4 px-4 rounded-xl bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white font-bold hover:opacity-90 transition-opacity disabled:opacity-50 disabled:cursor-not-allowed"
                                >
                                    {creating ? "Creating..." : "Deploy Collection"}
                                </button>
                            </div>
                        </div>
                    </div>
                ) : (
                    /* Success */
                    <div className="max-w-md mx-auto text-center">
                        <div className="bg-emerald-500/20 border border-emerald-500/50 rounded-2xl p-8 mb-6">
                            <span className="text-6xl mb-4 block">✅</span>
                            <h2 className="text-2xl font-bold text-white mb-2">Collection Deployed!</h2>
                            <p className="text-slate-400 mb-4">{config.name}</p>
                            {collectionAddr && (
                                <div className="bg-slate-900/50 p-4 rounded-xl mb-4 text-left">
                                    <p className="text-xs text-slate-400 mb-1">Collection Address</p>
                                    <p className="text-sm font-mono text-white break-all">{collectionAddr}</p>
                                </div>
                            )}
                            {txHash && (
                                <p className="text-xs text-slate-500 font-mono break-all">
                                    TX: {txHash}
                                </p>
                            )}
                        </div>
                        <Link
                            href={collectionAddr ? `/mint?collection=${collectionAddr}` : "/mint"}
                            className="inline-block py-4 px-8 rounded-xl bg-gradient-to-r from-violet-600 to-fuchsia-600 text-white font-bold hover:opacity-90"
                        >
                            Start Minting →
                        </Link>
                    </div>
                )}
            </div>
        </main>
    );
}
