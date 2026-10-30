# CUDA graphs and whole-expert research journal (2026-10-29 / 30)

> Raw working journal from the optimization sessions behind the 2026-10-30 update: every measurement, A/B and dead end,
> in the order they happened. Paths refer to the research workspace, not this repo. The summary is in the root README's notes.

# Whole-expert engine: where it stands (overnight summary, 2026-10-30)

> **Read first (updated about 05:20):** best build **v17** (`versions\v17-ggmlrows`; the D:\strata whole-expert launcher). With the user's settings, all with settle 0: **v17 whole 102.4 s vs normal engine 109.55 s (-6.5%), decode 1.10x**; against the default normal engine (about 119 s) **about -14%**. Gains: (1) `DS4_SETTLE_MS=0`, -8.7% on any engine; (2) the IQ1_M single-token kernel choice (`ds4_gg_cpu.cpp` min_tokens) plus a SIMD fix in ggml's IQ1_M dot, -4.9% more, helps the normal engine too; (3) whole-expert, decode +5% on top. (Earlier closing messages put the time at 09:15-11:45. That was a mistake: the work ran through the night to about 05:20.) Details at the end of this file.

**Best candidate: v15** (`versions\v15-map64` = v13 + 64 GB pull mapping; v13 in `versions\v13-settle`, run with `DS4_WHOLE_EXPERT=1 DS4_WHOLE_PULL=1`; the `D:\strata` whole-expert launcher does this).

| Measurement (fresh cache, 6-turn coding conversation, 400 tokens per turn) | Baseline | v13 |
|---|---:|---:|
| Total conversation time, user launcher settings (single runs) | 118.5 s | **111.0 s (-6.3%)** |
| Total, default settings, same 1 s settle for both | 119.1-119.2 s | **113.0-113.4 s (-5.0%)** |
| Decode, interleaved A/B, turns 3-6 median (v12) | 25.35 tok/s | **27.70 (1.093x)** |
| Short prompts (about 208 tokens) | 70-78 tok/s | 58-74 (about 0.9x) |
| Correctness (hidden states on fixed prompt tokens) | - | same size of difference as baseline's own GPU/CPU placement variation |

**Final interleaved A/B with the user's settings: v15 110.55 vs baseline 119.75 s total conversation time (-7.7%), decode turns 3-6 1.066x, chain per token -7.6%** (v13 before it: -6.3%, 1.043x). Details at the end of this file.

How the 0.395x prototype became a faster engine (each step measured; details below, in order):
1. **v2**: the other GPU runs its share of a layer in its own stream while it would idle, with no host round trip per layer.
2. **v3**: adaptive tiers on both GPUs. The hang from copy streams behind spinning kernels on WDDM was fixed.
3. **v5-v6**: the RAM store keeps the right experts.
4. **v7**: start-of-token overhead (a WDDM submit per layer, copy placement): 1.03x.
5. **v9**: the helper GPU pulls some CPU-lane experts from RAM over PCIe; the per-GPU address mapping and a VRAM cost cap were needed.
6. **v10**: per-GPU tier split (own-layer bias).
7. **v12**: swap copies at each GPU's idle point; between-token overhead 3.2 -> 1.4 ms; 1.093x decode.
8. **v13**: same-tick swaps outside decode, and a 1 s settle. The post-prompt settle was eating the decode gain.

Dead ends, measured: lookahead prefetch of pulls (v14: hits 62% but the extra DMA slows the CPU lane), owner-GPU pull (`DS4_WHOLE_PULL_T3`), pulling earlier (`T2` 3-4), pulling single experts (`T1=1`), CPU-lane job size, SMT threads, NUMA (Windows sees one node; the lane is compute-bound), and a bigger own-layer bias for decode.

Open avenues:
- (a) Short prompts: let the chunk/window paths use the other GPU's tier, so prompts stream less.
- (b) A faster IQ2_XXS/IQ1_M CPU kernel, for example a row-interleaved layout; the lane is compute-bound at about 230 us per expert.
- (c) Confirm v13 with large pages after a reboot.
- (d) A 2 s settle may suit baseline's own default too: a 1 s settle saved baseline about 3 s per conversation.

---
# Whole-expert v4: CPU-lane profile (2026-10-29)

**Correction:** the v3 section's "about 430 us fixed per CPU-lane layer" came from a two-point fit on averages and is wrong. `DS4_LANE_PROF=1` buckets compute by experts per call (baseline, one conversation, 200 tokens per turn):

| Experts per call | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---:|---:|---:|---:|---:|---:|
| Compute (baseline) | 265 us | 507 us | 695 us | 945 us | 1130 us | 1363 us |
| Compute (whole v4) | 309 us | 526 us | 693 us | 898 us | 1086 us | 1296 us |

The lane is linear at about 220-240 us per expert. Store hold is about 3 us. The rest is waiting for RAM-store reads: 66 us per call in baseline, 144 us in whole v3.

v4 change: in whole mode, an expert evicted from either GPU tier is now prefetched into the RAM store (`store->prefetch`). Baseline puts evicted experts there by copying from VRAM (`DS4_STORE_PUT`). In whole mode that copy would need a copy stream, which hangs on WDDM. Store waits dropped from 144 to 108 us per call.

Remaining gap at turn 6 of the conversation: whole 23.6 vs baseline 25.9 tok/s, about 0.91x. RAM-store misses are still higher (1,298 vs 730 per conversation), and single-expert calls are about 15% slower. The likely cause is that more CPU-lane experts are read from the file mapping rather than RAM-store slots; this is not yet proven.

Source: `whole-expert-v4-ds4_model.cu`.

## v5: RAM store kept for CPU-lane experts (2026-10-29)

At load the RAM store preloads the hottest experts outside the owner GPU's VRAM. In whole mode that included about 1,650 experts that the other GPU computes. v5 adds `ExpertStore::forget()` and, every 64 ticks, frees idle store slots holding GPU-resident experts. An evicted expert is read into a store slot by the cache thread (`put_begin`/`put_done` from the file). A store `prefetch` guess does not work for this: `cancel_stale` drops it before the read.

Conversation A/B (baseline/whole/whole/baseline, 6 turns, 400 tokens per turn):

| Version | Whole median | Whole turns 3-6 | Baseline turns 3-6 | Ratio, turns 3-6 |
|---|---:|---:|---:|---:|
| v3 | 20.55 | 22.45 | 24.70 | 0.91x |
| v5 (prefetch on eviction) | 21.50 | 23.15 | 24.50 | 0.945x |
| v5b (put on eviction) | 22.25 | 23.55 | 25.10 | 0.94x |

RAM-store misses are still about 2x baseline (2,773-3,119 vs 1,338-1,392). Prompt processing in whole mode is much slower (19-43 vs 62-73 tok/s). Prompt windows and chunks do not use the other GPU's tier, so its experts are streamed or read on the CPU lane, and after the sweep they come from SSD. That is the next bottleneck.

Correctness: the 48-token smoke outputs are identical to baseline. Long conversation texts cannot be compared across runs: two baseline runs differ from each other too, because the conversation cache from earlier runs is reused.

Sources: `whole-expert-v5-ds4_model.cu`, `whole-expert-v5-ds4_store.hpp`.

## v6a: keep the other GPU's tier in RAM for prompts (2026-10-29)

The sweep now frees store slots only for experts in a layer's own GPU tier; `DS4_WHOLE_FORGET_REMOTE=1` restores v5's behavior. Prompt chunks stream the other GPU's tier from RAM again.

| | Baseline | Whole v6a |
|---|---:|---:|
| Decode, turns 3-6 median | 25.0 tok/s | 23.35 tok/s (0.934x) |
| Prompt rate (turns 3-6) | 64-76 tok/s | 43-53 tok/s |
| RAM store misses per conversation | 1,291-1,492 | 1,265-1,287 |

Store misses are now at baseline level, and prompt rates went from 19-43 up to 43-53 tok/s. Decode did not move, so store misses were not what held decode back. Prompts remain about 0.7x: the owner GPU has fewer of its layers' experts (about 16 vs 33 and 72 vs 129 per layer), so a prompt chunk streams more experts over PCIe. Fixing that needs remote chunk execution queued ahead on the other GPU's own stream.

Launcher for a full test: `D:\strata\run-deepseek-abliterated-largepages-whole-expert.bat`. It is not yet tested with `DS4_SPLIT=14,26`, large pages, `--ablate` or vision.

Sources: `whole-expert-v6-ds4_model.cu`, `whole-expert-v6-ds4_store.hpp`.

## v7: decode critical chain mapped and fixed - first candidate faster than baseline (2026-10-29)

`DS4_CHAIN=1` times each decode token from the service thread. Per layer it records request in to answer out (service) and the previous answer to this request (GPU gap). It also records the gap between a token's last answer and the next token's first request. Before v7 (ms per token):

| | Baseline | Whole v6a |
|---|---:|---:|
| Between tokens | 1.23 | 8.07 |
| 3080 Ti layers: GPU gaps / service | 8.31 / 14.93 | 8.06 / 10.13 |
| Hand-off | 0.61 | 0.57 |
| 5090 layers: GPU gaps / service | 11.03 / 5.86 | 11.25 / 9.24 |

The 5090 cut 4.8 ms of CPU-lane service from the 3080 Ti layers, but the between-token overhead added 6.8 ms. Causes: a `win_submit` (WDDM kernel-mode submit) per remote layer through `xfer_put`; swap copies at the front of the device stream; and the 5090's remote launches queued before the 3080 Ti's first layer. v7 changes:
- `whole_put_k` writes the partial back, and each GPU's batch of remote layers gets one submit.
- Swap copies go on a per-device copy stream with an event. The next tick's table update waits on that event on the device stream; nothing on the host waits.
- The serial path queues the first remote layer, then the owner's layer 0, then the rest.

Interleaved conversation A/B, baseline/whole/whole/baseline (6 turns, 400 tokens per turn):

| | Baseline | Whole v7 |
|---|---:|---:|
| Decode median | 24.65 tok/s | **25.10 tok/s (1.018x)** |
| Decode, turns 3-6 median | 25.00 tok/s | **25.75 tok/s (1.03x)** |
| Chain total (ms per token) | 41.1-41.7 | 40.4-41.4 |
| Prompt, turns 3-6 | 62-73 tok/s | 45-55 tok/s (about 0.75x) |

Whole mode was equal to or faster than baseline in every turn from 2 to 6 in both whole runs. Remaining levers: between tokens is still 2.2-2.6 vs 1.2 ms; the 5090's own layers carry about 3 ms more CPU-lane service, since their owner tier is smaller; and prompts are still slower. The 48-token smoke outputs are identical to baseline.

Sources: `whole-expert-v7-ds4_model.cu`, `whole-expert-v7-ds4_store.hpp`. The D:\strata whole-expert launcher picks up this build.

## CPU lane and RAM-store experiments (baseline mode, 2026-10-29)

`DS4_LANE_PROF=1`, `DS4_WHOLE_TRACE=1`, one fresh server per row. Compute is per CPU-lane call, by number of experts in the call.

| Run | 1 expert | 4 experts | Decode (3 turns x 200 tokens) |
|---|---:|---:|---|
| Reference, 24 threads | 262 us | 939 us | 25.0 / 24.1 / 24.6 |
| Hot rerun of the same call (weights partly in L3) | 267 us | 949 us | (diagnostic) |
| SMT, 48 threads (`DS4_CPU_SMT=1`) | 460 us | 1864 us | 15.1 / 15.4 / 15.4 |
| 12 threads | 394 us | 1604 us | 19.3 / 19.4 / 19.7 |
| 32-row jobs (`DS4_LANE_RB=32`) | 271 us | 949 us | 24.5 / 23.8 / 24.4 |
| 16-row jobs | 262 us | 998 us | 24.0 / 24.9 / 23.9 |

- The CPU lane is **compute-bound**. Recomputing immediately with the weights partly cached costs the same time, so RAM bandwidth is not the limit. At about 35-40 GB/s-equivalent it uses about half of the 77 GB/s AIDA64 read rate.
- Windows sees the 3960X as one NUMA node, with memory interleaved through the IO die. Given the compute-bound result, a NUMA BIOS change (NPS/L3-as-NUMA) is not expected to help, and it would need NUMA-split expert storage in the engine.
- SMT hurts badly: siblings share the vector units, and the GPU-launch and service threads lose their cores. 24 threads, one per core, is right.
- Job granularity (64/32/16 rows) makes no difference. Scaling from 12 to 24 threads is only 1.5x, which is consistent with lower all-core boost clocks, not load imbalance.
- The lever is the IQ2_XXS CPU kernel itself (`gg::iq_cpu_gate_up`/`iq_cpu_down`, AVX2 on Zen 2). Because the CPU leaves about 37 GB/s of RAM bandwidth unused, letting the GPUs compute some RAM experts over PCIe would also not compete much with the CPU lane.

RAM store size (6 turns x 300 tokens):

| `--ssd-cache` | Misses | Store wait per call | Decode median |
|---|---:|---:|---:|
| 120 | 1,055 | 56.4 us | 24.75 tok/s |
| 135 | 366 | 20.5 us | 25.45 tok/s (+2.8%, single run) |

## v9-pull: the helper GPU computes some CPU-lane experts from the RAM store (opt-in, 2026-10-29)

`DS4_WHOLE_PULL=1` (whole mode only). In each whole-mode decode layer, the helper GPU also takes some of the layer's CPU-lane experts. If a layer has n CPU-lane picks, it takes the last m (m = 1 for n >= 2, m = 2 for n >= 5) whose RAM store slot is GPU-visible. It copies them from RAM into 2 staging slots over PCIe (`whole_pull_k`) and computes them together with its own tier's experts. The CPU lane skips exactly those picks. Both sides decide from the same tables, which change only between tokens (`own_tab`, `remote_tab`, `pull_tab` on the helper GPU, and their host mirrors), so the split is deterministic. Store slots the helper may read are "visible": pinned against eviction, published by `store_sync`, and withdrawn when the expert moves into a GPU tier (`pull_moved`).

Problems found and fixed while bringing it up:
- The store's registered memory has a different device address on each GPU, not the host address ("not the identity"). `pull_addr` translates through each chunk's own `cudaHostGetDevicePointer` on the helper GPU.
- Mapping the whole 90-120 GB store for the GPUs cost all remaining VRAM on both GPUs (WDDM page tables; measured 495/443 MiB free before preload, 0 after), and the first window failed out of memory. It is not system RAM: the mapping registers the store's existing pages. `DS4_WHOLE_PULL_GB` (default 48) maps only the store's first chunks, which hold its hottest preloaded experts. 16 and 48 GB cost no visible VRAM (439/445 MiB free); 80 GB failed again. Reducing `--ssd-cache` would not help, because it would cost RAM-store hits and the limit is in mapped size.
- Staging space is 2 expert slots per GPU (about 21 MB), not 8.
- Copy-Item keeps a file's old timestamp, so a restored source is not rebuilt. `versions\README.md` documents setting the timestamp.

First readings with 2 turns x 200 tokens: about 1.8 pulled experts per token at 16 GB mapped and about 11 at 48 GB. The 48-token smoke outputs are identical to baseline. The interleaved benchmark with `DS4_CHAIN` (baseline / pull / v7 / pull / baseline) is running.

Versions: `versions\` keeps sources and, for v7 and v9-pull, the built binaries. See `versions\README.md`.

### v9-pull benchmark (interleaved baseline / v9-pull / v7 / v9-pull / baseline, 6 turns x 400 tokens, 2026-10-29)

| Run | Turns 1-6 decode (tok/s) |
|---|---|
| baseline | 25.6, 25.1, 25.3, 26.3, 22.7, 25.2 |
| v9-pull | 23.7, 26.3, 27.2, 28.0, 24.7, 27.6 |
| v7 (pull off) | 23.5, 24.7, 25.9, 28.2, 23.6, 27.1 |
| v9-pull | 23.9, 26.2, 27.3, 28.1, 24.0, 27.8 |
| baseline | 25.1, 25.2, 25.1, 26.0, 22.9, 25.1 |

| Median | Baseline | v7 | v9-pull |
|---|---:|---:|---:|
| All turns | 25.15 | 25.30 (1.006x) | **26.75 (1.064x)** |
| Turns 3-6 | 25.15 | 26.50 (1.054x) | **27.45 (1.091x)** |

v9-pull was faster than baseline in every turn from 2 to 6, in both runs. Against the single v7 run in between, it gained about 3.6% in turns 3-6.

Critical chain (`DS4_CHAIN=1`, ms per token):

| | Baseline | v7 | v9-pull |
|---|---:|---:|---:|
| Between tokens | 1.16-1.17 | 2.35 | 2.29-2.48 |
| 3080 Ti layers: GPU gaps / service | 7.4-7.5 / 14.4-14.6 | 7.81 / 9.20 | 7.6-7.8 / 8.95-9.01 |
| Hand-off | 0.60 | 0.56 | 0.54 |
| 5090 layers: GPU gaps / service | 11.0-11.1 / 5.5-5.7 | 11.25 / 8.84 | 11.0-11.1 / 8.16-8.19 |
| Total | 40.3 | 40.0 | 38.7-38.9 |

The helper GPUs pulled about 24,000 experts per run (about 10 per token). CPU-lane picks fell from 135-141k (v7) to 112-118k. When a layer also has CPU experts, the helper's partial now sometimes arrives after the CPU lane: the extra wait is 24.7 us average, versus 0.3 us in v7. RAM-store misses are unchanged.

Remaining gaps against baseline: between tokens +1.2 ms; the 5090's own layers carry +2.6 ms of CPU-lane service, because global placement gives part of the 5090 to the 3080 Ti's layers. Next: owner-GPU pulls for layers with 4+ CPU experts, the between-token overhead, and the 5090 tier split.

## v10: per-GPU tier split (own-layer bias) (2026-10-30, overnight)

Placement now fills each GPU (5090 first) by heat, with its own layers' experts weighted by `DS4_WHOLE_OWN_BIAS`. The cache adapts tier contents, not tier sizes, so the bias sets how much of each GPU serves its own layers. Every trunk layer now has the other GPU as its helper even with an empty remote tier (`whole_layer`), so pulls work on all 40 layers. The log reports each GPU's split ("N experts of its own layers, M of the other GPU's").

Sweep with pull on, one 6-turn x 400-token run each (bias 1.0 = the two v9 runs):

| Bias | Decode turns 3-6 median | Chain total | 3080 Ti / 5090 layers' CPU service | Prompt (turns 3-6) |
|---|---:|---:|---|---:|
| 1.0 | 27.45 | 38.7-38.9 | 9.0 / 8.2 ms | 48-55 |
| 1.5 | 27.9 | 38.9 | 9.1 / 7.4 | 55-56 |
| 2 | 27.5 | 38.7 | 10.0 / 6.7 | 52-61 |
| 3 | 27.3 | 39.3 | 11.3 / 6.0 | 55-61 |

The bias moves CPU-lane time from the 5090's layers to the 3080 Ti's, as intended. Decode stays flat within noise (about +-0.5 tok/s), because what one side saves the other side pays. Prompts gain about 10% from bias 1.5 on: owner tiers are larger, so prompt chunks stream less. **Default is now 2.** At bias 2 the split is 3080 Ti 610 own / 0 other, and 5090 2,180 own / 740 other.

## v11: owner-GPU pull (opt-in `DS4_WHOLE_PULL_T3`)

From T3 CPU-lane picks on, the owner GPU also pulls one expert: the earliest visible one the helper does not take (`owner_pick_k`, right after routing, into its own staging slot, computed with its own experts). The service applies the same rule, and an owner-taken pick does not wait for the helper's partial. The helper rule's thresholds are now tunable (`DS4_WHOLE_PULL_T1`/`_T2`, default 2/5). Visibility is shared: a slot is pullable only if both GPUs have an address for it. Smoke output with T3=4 is identical to baseline. Sweep T3 = off / 4 / 3 running.

Versions: `versions\v10-split`, `versions\v11-ownerpull` (sources and binaries).

### v11 result: owner pull does not pay (default off)

| T3 | Owner pulls per run | Decode turns 3-6 median | Chain total |
|---|---:|---:|---:|
| off | 0 | 26.5 | 38.87 |
| 4 | 1,568 | 27.05 | 39.10 |
| 3 | 3,350 | 27.5 | 38.93 |

With helper pulls and bias 2, few layers still have 3 or more CPU-lane picks. The owner's copy lengthens its own layer path (5090-side GPU gaps +0.3-0.45 ms). `DS4_WHOLE_PULL_T3` stays available, default 0.

## v12: the remaining between-token overhead found and removed

`DS4_CHAIN` now splits the gap between tokens (forward-thread timestamps) and reports the host tick:

| Between tokens (ms) | Baseline | v11 | v12 |
|---|---:|---:|---:|
| Last answer -> head done | 0.31 | 0.31 | 0.31 |
| -> next forward (host tick, sampling) | 0.37 | 0.72 | 0.52 |
| -> layer 0's request | 0.51 | 2.05-2.22 | **0.59** |
| Total between tokens | 1.19 | 3.06-3.26 | **1.41** |

Things that were not the cause: the host queueing (layer 0 queued 0.61 ms after the forward starts), and a missing WDDM flush (an explicit `win_submit` after layer 0 changed nothing; it stays as a harmless flush). The cause was the swap copies. v7 put them on a copy stream at the tick, and under WDDM they ran ahead of the next token's layer 0 on the same GPU, about 0.5 ms each and about one per GPU per token. v12 queues each read swap's copy on the device's own stream at its idle point in the next whole window: the helper GPU (5090) at token start before its first stage kernel, and the owner (3080 Ti) right after its hand-off. The next tick applies the swap without an event. Prompt windows have no idle point, so swaps not copied by then go on the copy stream as before.

v12 single run (4 turns x 400): 24.8 / 27.3 / 28.3 / 28.3 tok/s, chain total 37.72 ms vs about 39.8 for baseline. Smoke output identical. The interleaved A/B is running. Version: `versions\v12-idlecopy`.

### v12 interleaved A/B (baseline / v12 / v12 / baseline, 6 turns x 400 tokens, pull on, bias 2)

| Run | Turns 1-6 decode (tok/s) | Chain total |
|---|---|---:|
| baseline | 25.5, 25.7, 25.0, 26.5, 22.6, 25.5 | 40.12 |
| v12 | 25.8, 26.8, 27.5, 29.3, 26.9, 27.4 | 37.04 |
| v12 | 24.7, 28.0, 28.2, 29.2, 24.9, 27.9 | 37.33 |
| baseline | 25.2, 25.5, 25.3, 26.4, 22.3, 25.4 | 40.30 |

| Median | Baseline | v12 |
|---|---:|---:|
| All turns | 25.45 | **27.45 (1.079x)** |
| Turns 3-6 | 25.35 | **27.70 (1.093x)** |

Chain per token, baseline vs v12: between tokens 1.14 vs 1.35; 3080 Ti layers gaps 7.4 vs 7.7, service 14.6 vs 9.9; hand-off 0.60 vs 0.55; 5090 layers gaps 11.05 vs 11.1, service 5.5 vs 6.5. Prompt rate turns 3-6: baseline 67-75, v12 49-57 tok/s (about 0.77x). v12 is the best candidate so far: `versions\v12-idlecopy`, with `DS4_WHOLE_EXPERT=1 DS4_WHOLE_PULL=1`.

### Pull thresholds and correctness (2026-10-30, overnight)

Pull threshold sweep, one 6-turn run each, decode turns 3-6 median (v12 default T1=2, T2=5: 27.5-27.7):

| Setting | Decode | Helper extra wait in CPU layers |
|---|---:|---:|
| T2=4 | 27.3 | 34 us |
| T2=3 | 27.15 | 56 us |
| T1=1 (pull single CPU experts too) | 27.5 | 24 us; pull-only layers now 250 us each |

A pull costs about 250 us on the helper, about the same as one CPU expert. Pulling earlier makes the helper finish after the CPU. The defaults stay.

**Correctness.** Long greedy outputs cannot be compared across runs: two fresh baseline conversations (cleared slot cache) differ from the first character, because the adaptive cache's swap timing changes which device computes an expert. The server returns no logprobs with this engine. So I compared hidden states. `DS4_DUMP_H` (serial path) dumps every layer's residual stream for every window: smoke prompts, 8 tokens, about 85 M floats. `compare_dumps.py` compares in pure Python (numpy is not installed; I did not install packages).

| vs baseline run 1 | Per-slice relative diff median / p90 / p99 / max | Overall relative L2 | Max abs |
|---|---|---:|---:|
| baseline run 2 | 0 / 0 / 0 / 0 (bit-identical) | 0 | 0 |
| baseline, `--reserve-mib 2500,2500` (other expert placement) | 7.97% / 15.2% / 32.1% / 50.2% | 9.5e-4 | 433 |
| v12 | 8.05% / 15.2% / 33.1% / 77.7% | 2.9e-3 | 2775 |

v12's per-layer differences have the same distribution as baseline's own when experts merely run on a different device (GPU vs CPU arithmetic). Open item: the overall L2 and max-abs are about 3x the reference, driven by a few large-magnitude values. Worth locating (which layer and token), but not a sign of a broken path.

Follow-up on the open item: restricted to the first prompt's 47 tokens (fixed input, so no sampling divergence can feed back), v12's hidden-state difference to baseline equals baseline's own placement variation: overall relative L2 2.76e-4 vs 2.55e-4, max abs 37.4 vs 43.6, per-slice median 7.0% vs 6.9%, p99 17.6% vs 20.9%. The larger decode-token differences (token 108, layer 28) come after generated tokens diverged, not from the whole-expert path. **Correctness: equivalent to baseline within its own GPU/CPU placement variation.** Scripts: `compare_dumps.py`, `whole-expert-tests\prompt_diff.py`, `whole-expert-tests\locate_diff.py`.

## Whole-conversation view: prompts were eating the decode gain (2026-10-30, overnight)

A fresh-cache 6-turn conversation (2,706-token first prompt, then about 208-token prompts, 400 tokens decoded per turn), total wall time:

| | Total | Turn 1 prompt | Turn 2 prompt | Turns 3-6 prompt | Decode turns 3-6 |
|---|---:|---:|---:|---:|---:|
| baseline | 121.6 s | 225 tok/s | 70.6 | 71-78 | 24.3-26.0 |
| v12, bias 2 | 121.4 s | 185 | **38.0** | 59-61 | 25.5-28.4 |
| v12, bias 4 | 122.9 s | 186 | 39.7 | 63-66 | 24.7-28.0 |
| v12, bias 10 (about baseline placement + pulls) | - | - | - | 66-70 | 24.4-27.1 (no gain) |

Bias 10 shows the decode gain comes from the 5090's tier for the 3080 Ti's layers (the whole-expert idea), not from pulls alone: 3080 Ti layers' CPU-lane service stays at 14.8 ms per token without it.

**Cause of the prompt loss: `cache_settle`** (cache swaps after each chunked prompt, budget `DS4_SETTLE_MS`, 6 s):

| Settle after | baseline | v12 |
|---|---|---|
| 2,706-token prompt | 1,278 swaps, 4,162 ms | 768 swaps, 6,010 ms (budget hit) |
| 208-token prompt | 92 swaps, 330 ms | 287 swaps, 2,559 ms |

v12 deferred every swap's copy to the next decode token's idle point. Settle has no decode token, so each swap went pending, then to the copy stream, then was applied a tick later. **v13:** outside decode tokens (no spinning kernels), a read swap is copied on its device's own stream and applied in the same tick. A pinned buffer is freed when its copy's event completes (`wbuf_hold` holds buffer and device). Turn 2's prompt went from 38 to 61.6 tok/s, and short-prompt settles now take 250-470 ms. Total 118.3 s.

Settle follow-ups:
- With 4 cache threads and same-tick apply, "nothing in flight" no longer meant "nothing to move". The loop stopped after 8 swaps and the adaptation moved to turn 2. Whole mode now stops only when a round queued nothing and no buffer is busy, and uses 4 cache threads by default.
- Fully settling after the big prompt (1,468 swaps) still uses the 6 s budget: total 119.4 s.
- The "lazy" runs (settle stopped early) totaled **112.0-113.6 s**, with turn 1 decode faster (25.8 vs 23.2). The post-prompt settle looks largely wasted for this workload: the prompt's heat is not decode's. Baseline spends about 4.2 s on it too, so this is a baseline tuning question as well. Running now: baseline and v13 each with `DS4_SETTLE_MS=1000`, against baseline at 6000.

Versions: `versions\v13-settle` (sources; its binary is saved after the current test).

### Settle budget, both modes (fresh cache, 6-turn conversation, total wall time)

| Run | Total | Turn 1 prompt | Turn 1 decode | Short prompts (turns 3-6) | Decode turns 3-6 |
|---|---:|---:|---:|---:|---:|
| baseline, settle 6000 ms (default) | 122.1 s | 220 | 21.8 | 72-76 | 23.0-26.4 |
| baseline, settle 1000 ms | 119.2 s | 294 | 22.3 | 70-76 | 22.7-26.6 |
| **v13, settle 1000 ms** | **113.0 s** | 282 | 25.3 | 60-68 | 25.4-28.6 |
| **v13, settle 1000 ms** | **113.4 s** | 278 | 25.7 | 64-66 | 25.1-28.0 |
| baseline, settle 1000 ms | 119.1 s | 298 | 21.6 | 71-77 | 22.7-26.3 |

**v13 against baseline with the same settle budget: -5.0% total conversation time. Against the default baseline: -7.3%.** The post-prompt settle is mostly wasted for both modes on this workload: a 1 s budget saves baseline about 3 s too. Whole mode now defaults to `DS4_SETTLE_MS=1000`; baseline's default is untouched.

Remaining gap: short prompts (windows and small chunks) run at about 0.88x baseline, because the owner tiers are smaller and the window path treats the other GPU's tier as CPU-lane. `versions\v13-settle` = v12 + same-tick swaps outside decode, 4 cache threads, the settle stop rule, and the 1 s settle default (whole mode). Smoke output identical.

### v13 with the user's launcher settings, and the bias default

Bias on v13, total conversation time: 2 = 113.8 s, 3 = 113.2 s, 4 = 114.2 s (within noise). Bias 3 had the best short prompts (66-72 tok/s), so **the default is now 3** (split at the user's settings: 3080 Ti 698 own / 0 other, 5090 2,587 own / 279 other).

The user's launcher settings: `DS4_SPLIT=14,26`, `DS4_STORE_LARGE=1`, `--ssd-cache 135`, `--reserve-mib 900,100`, abliteration adapter. One fresh 6-turn run each:

| | Total | Turn 1 prompt | Decode turns 1-6 | Short prompts |
|---|---:|---:|---|---:|
| baseline | 118.5 s | 218 | 22.2, 25.5, 25.6, 27.3, 23.6, 26.3 | 68-78 |
| **v13** | **111.0 s (-6.3%)** | 308 | 24.8, 27.1, 26.2, 28.3, 26.1, 26.7 | 58-74 |

Large pages failed with err 1450 (fragmented RAM after a night of tests) and fell back to 4 KB pages, so v13 with large pages and the store mapping is not yet tested. The 5090 ends with 49 MiB free under the 100 MiB reserve, tight but stable through the run. The D:\strata whole-expert launcher now sets `DS4_WHOLE_PULL=1`, with a comment on `DS4_WHOLE_PULL_GB` if the first request runs out of memory. `versions\v13-settle` holds this final build.

## Final interleaved A/B, user launcher settings (2026-10-30, about 05:40)

`DS4_SPLIT=14,26`, `DS4_STORE_LARGE=1` (fell back to 4 KB pages: err 1450), `--ssd-cache 135`, `--reserve-mib 900,100`, abliteration adapter; fresh cache per run; v13 defaults (`DS4_WHOLE_PULL=1`, bias 3, settle 1 s). Baseline uses its own defaults (settle 6 s).

| Run | Total | Decode turns 1-6 (tok/s) | Turn 1 prompt | Short prompts | Chain per token |
|---|---:|---|---:|---:|---:|
| baseline | 118.8 s | 22.1, 25.2, 25.1, 27.4, 24.0, 26.0 | 219 | 72-80 | 40.54 ms |
| v13 | 110.7 s | 25.2, 27.4, 26.4, 28.5, 25.3, 26.8 | 295 | 59-74 | 37.75 ms |
| v13 | 112.6 s | 23.3, 26.7, 26.5, 28.7, 24.9, 26.9 | 305 | 57-76 | 38.60 ms |
| baseline | 119.6 s | 21.7, 25.2, 25.0, 27.2, 23.7, 26.0 | 219 | 69-80 | 40.88 ms |

- **Total conversation time: v13 111.65 s vs baseline 119.2 s (-6.3%).**
- Decode, turns 3-6 median: 26.65 vs 25.55 tok/s (1.043x).
- Turn 1 decode: +11%.
- Chain per token: -6.5%. 3080 Ti layers' CPU service 8.5 vs 10.4 ms; 5090 layers' 7.7-8.3 vs 8.5-8.8 ms; between tokens 1.42-1.47 vs 1.11 ms.

With the user's 14/26 split, baseline is already better balanced than with the auto 18/22 split used in most tests, so the decode gain is smaller (1.04x vs 1.09x). The whole-conversation gain holds at about 6%.

Bias at the user's split (14/26, single runs): 1.5 = 111.2 s (3080 Ti / 5090 layers' service 6.9 / 9.2 ms), 2 = 111.2 s (7.6 / 8.6), 3 = 110.7 / 112.6 s (8.5 / 7.7-8.3). Chain about 37.7 ms in all three. The bias trades CPU-lane time between the two GPUs' layers at a constant total, so the default stays 3.

### Where to go next (not started)
1. **Short prompts (about 0.93x).** The window path (prompts under 96 tokens, verify windows) treats the other GPU's tier as CPU-lane. The chunked path streams everything outside the owner tier. Extending the helper's stage kernel to T > 1 windows (a per-token loop, partials `rem_part[slot][t]`) would cover the window path. For chunks, the helper would need a queued-ahead `run_set` over the chunk's rows of its tier's experts, with device-side bounds. Larger work, but the same pattern as decode.
2. **The CPU-lane kernel** (about 230 us per IQ2/IQ1 expert, compute-bound on Zen 2 AVX2): a row-interleaved weight layout (as ik_llama.cpp's `_R4` types) is the known lever.
3. **v13 with large pages after a reboot.** It falls back to 4 KB pages when RAM is fragmented, which is what happened in tonight's tests.
4. **Baseline settle.** A 1 s post-prompt settle also saved baseline about 3 s per conversation (122.1 -> 119.2 s); worth a look for the normal engine too.

## v14: lookahead prefetch for pulls (opt-in `DS4_WHOLE_PF`, measured negative, default off) (2026-10-30, about 07:00)

Idea: a pull costs the helper about 250 us, mostly the PCIe copy. The engine's routing lookahead guesses layer l+1's experts during layer l. Of the CPU-lane decode picks, **62.0%** were in the lookahead's top-k guesses a layer before (a new counter in the `DS4_WHOLE_TRACE` output). v14:
- After its share of layer l (partial sent), the helper selects the first P guesses for l+1 that are CPU-lane and visible in the store (`whole_pf_select_k`) and copies them into prefetch slots.
- At l+1, picks among them are computed without a copy. The service applies the same choice from the previous layer's request.
- The lookahead's own store prefetch (`ahead_ask`) stays off unless `DS4_AHEAD` is set.
- Prefetches are tagged with the target request's seq, so a stale one is never used.

Smoke output identical. Default settings, one fresh 6-turn run each, same build:

| | Total | Prefetched picks used | CPU-lane layer request -> answer |
|---|---:|---:|---:|
| v13 (`DS4_WHOLE_PF=0`) | **113.3 s** | - | 629 us |
| P=1 | 116.2 s | 14,340 | 653 us |
| P=2 | 117.1 s | 18,582 | 668 us |

The hits are real: pull-only layers drop to 64-77 us from 130. But about 38% of the copies are wasted on wrong guesses, and the extra DMA reads (about 9-18 GB/s) slow every CPU-lane layer by 4-6%: the CPU lane is compute-bound on its own but shares the memory controller with the DMA. A net loss, so it stays off. A better predictor or a cheaper wrong guess would be needed.

Versions: `versions\v14-prefetch` (v13 + the opt-in prefetch; identical to v13 with defaults). **v13 remains the recommended build.**

## v15: more of the RAM store mapped for pulls (2026-10-30, after 07:00)

`DS4_WHOLE_PULL_GB` (how much of the store the GPUs may read, so which CPU-lane experts are pullable). One fresh 6-turn run each:

| Mapped | Config | Total | Helper pulls | VRAM free after mapping (3080 Ti / 5090) |
|---|---|---:|---:|---|
| 48 GB (v13) | default | 113.3 s | about 22,000 | 518 / 443 MiB |
| 64 GB | default | 111.9 s | 29,402 | 516 / 443 MiB |
| 72 GB | default | 111.5 s | 34,946 | 518 / 443 MiB |
| 80 GB | default | fails out of memory | - | 0 / 0 |
| 64 GB | user launcher | 111.0 s (v13: 110.7 / 112.6) | 31,497 | (run completed) |

Mapping costs no VRAM up to 72 GB, then fails abruptly at 80 GB. It is a cliff, probably a GPU address-space or aperture limit rather than page-table memory. More mapped means more pullable CPU-lane experts: -1.2 to -1.6% at the default split, within noise at the user's split. **Default is now 64 GB** (a margin below the cliff). `versions\v15-map64` = v14 with the 64 GB default (prefetch still off). It is the recommended build.

### v15 long-run stability (default config, one server, 6 turns x 1,200 tokens, about 6,900 decode tokens)

Decode per turn: 26.3, 28.3, 27.5, 29.1, 27.0, 26.4 tok/s. Prompts of 467-847 tokens ran at 112-154 tok/s. The running averages of the timing chain only improve as the caches adapt: between tokens 1.49 -> 1.25 ms; 3080 Ti layers' service 13.0 -> 11.2 ms; GPU gaps flat at 7.4 / 10.8 ms. No errors, failed reads or out-of-memory over the run. No sign of a leak (held swap buffers, pull tables) or of slowing down.

### v15 final interleaved A/B, user launcher settings (baseline / v15 / v15 / baseline)

| Run | Total | Decode turns 1-6 | Chain per token |
|---|---:|---|---:|
| baseline | 120.1 s | 22.1, 24.9, 25.2, 27.2, 24.0, 26.2 | 40.64 ms |
| v15 | 110.7 s | 24.0, 27.1, 27.0, 29.0, 25.7, 27.9 | 37.79 ms |
| v15 | 110.4 s | 24.5, 27.2, 26.9, 29.0, 25.6, 27.8 | 37.66 ms |
| baseline | 119.4 s | 21.2, 25.0, 25.2, 27.3, 23.5, 26.6 | 41.11 ms |

- **Total conversation time: 110.55 vs 119.75 s (-7.7%).**
- Decode, turns 3-6 median: 27.4 vs 25.7 tok/s (1.066x).
- Chain per token: -7.6%.
- Big prompt: 301-304 vs 200-227 tok/s. Short prompts: 58-76 vs 70-79 tok/s.

v15 also beats v13 at the user's split (v13: -6.3% and 1.043x).

Considered and not started, chunked-prompt help from the other GPU: at bias 3 the 5090 holds about 280 experts of the 3080 Ti's layers, so a 208-token prompt would stream about 2.5 GB less (about 100 ms, 3-4% of the prompt). That is small for a large change to the layer-major prompt path. It becomes worth doing only with a lower bias (more remote tier).

### Cache swap margin (v15, default config, one run each)

`DS4_CACHE_MARGIN` 1.1 = 112.1 s (3,092 swaps), 1.25 (default) = 111.9 s, 1.5 = 112.1 s (2,251 swaps). It changes the swap count, not the speed, so the default stays.

### Morning status (about 08:40)

v15 (`versions\v15-map64`) is the recommended build and what the D:\strata whole-expert launcher runs:
- **-7.7% total conversation time** against baseline with the user's settings (interleaved A/B), decode 1.066x;
- correctness equivalent to baseline's own placement variation;
- stable over about 6,900 decode tokens on one server.

Explored after midnight and measured as no gain or negative: owner pull, pull thresholds, lookahead prefetch (v14), bias at the user's split, cache margin. Still open:
- short prompts (about 0.93x);
- large pages with the store mapping (untested; the RAM was fragmented);
- a faster CPU-lane kernel;
- a shorter post-prompt settle for the normal engine (it saved baseline about 3 s per conversation).

### CPU lane: threads and the expert kernels by type (about 09:00)

**Lane threads with v15** (default config, one run each): `--cpu-threads` 48 (24 lane threads) = 111.9 s, 44 = 111.3 s, 40 = 112.3 s. Within noise: leaving cores free for the service thread or kernel launches gains nothing.

**CPU-lane compute per expert, by the layer's expert types** (`DS4_LANE_PROF`, baseline, 3 turns x 300 tokens; ggml types 16 = IQ2_XXS, 17 = IQ2_XS, 29 = IQ1_M):

| gate/up / down | Calls | Experts per call | us per expert | with `DS4_GG_IQ256=1` |
|---|---:|---:|---:|---:|
| IQ1_M / IQ1_M | 9,558-11,026 | 3.7 | **255** | 255 |
| IQ1_M / IQ2_XXS | 1,443-1,669 | 3.7-3.8 | 234-240 | 245 |
| IQ2_XS / IQ1_M | 2,891-3,382 | 2.6 | 216-217 | 218 |
| IQ2_XXS / IQ1_M | 4,913-5,824 | 2.9 | 205-206 | 221 |
| IQ2_XS / IQ2_XS | 588-662 | 2.3 | 193-195 | 199 |
| IQ2_XXS / IQ2_XS | 1,850 | 1.9 | 193 | 215 |

- **IQ1_M is the costliest CPU expert type despite the fewest bytes** (1.75 vs 2.06 bits per weight), and IQ1_M/IQ1_M layers carry most of the lane's calls. A faster IQ1_M decode kernel is the most targeted CPU-side lever.
- This build's CPU lane runs ggml-cpu's row dots (`gg_cpu_*`). Strata's `own_rows` path is not compiled into it, so `DS4_IQ_OWN` has no effect. Strata's AVX2 i-quant rows (`DS4_GG_IQ256=1`, forced for single tokens) are slower for IQ2 and equal for IQ1_M, so the default choice is right. There is no free kernel switch left. A new IQ1_M kernel (for example a row-interleaved layout, as in ik_llama.cpp) is a separate project.

**IQ1_M on Zen 2, checked:** ggml's AVX2 `ggml_vec_dot_iq1_m_q8_K` has a BMI2 path that does 12 `_pdep_u64` per 256-weight block. PDEP is microcoded and very slow on Zen 1/2, which would have explained IQ1_M's cost. This build does not use it: `GGML_BMI2=OFF`, and the ggml-cpu target defines only `GGML_AVX2`, `GGML_FMA` and `GGML_F16C`. The fallback path runs: eight 8-byte `iq1s_grid` loads per 64 weights via `_mm256_set_epi64x`, plus sign and scale handling. That is the inherent cost of the format's layout, so a faster IQ1_M CPU lane needs a repacked (row-interleaved) weight layout, a separate project. (Note for anyone building ggml for this CPU: keep `GGML_BMI2` off.)

## v16: no post-prompt settle in whole mode (about 10:00)

Settle budget on v15 (default config, one run each, total for 6 turns): 1000 ms = 111.9 s, 500 ms = 110.2 s, **0 ms = 108.2 s**. Short prompts at 0 ms reached 74-79 tok/s, the same as baseline's 70-79, closing the short-prompt gap. Decode was unchanged (25.2-28.8 tok/s): the cache adapts during decode anyway, so the settle only cost prompt time. **Whole mode now defaults to `DS4_SETTLE_MS=0`**; baseline's default is untouched.

Smoke check: identical to baseline's 48-token output. (An apparent mismatch came from a stale baseline reference file left by an 8-token dump run; regenerated, it matches.) `versions\v16-nosettle` holds v16. Running now, with the user's settings: an interleaved A/B including baseline with settle 0, so the gain is not credited to the settle change alone.

### v16 final interleaved A/B with the user's settings, separating the settle effect (about 10:45)

Order: baseline (default) / baseline (settle 0) / v16 / v16 / baseline (settle 0) / baseline (default). Fresh cache per run; 6 turns x 400 tokens.

| Run | Total | Decode turns 1-6 | Turn 1 prompt | Short prompts |
|---|---:|---|---:|---:|
| baseline default (settle 6 s) | 120.1 s | 21.8, 25.9, 25.6, 27.5, 23.5, 26.3 | 198 | 72-84 |
| baseline settle 0 | 109.0 s | 25.1, 26.0, 25.9, 27.4, 23.9, 26.3 | 387 | 79-87 |
| v16 | 106.8 s | 23.4, 27.7, 27.5, 29.4, 26.1, 27.7 | 349 | 76-82 |
| v16 | 105.9 s | 24.6, 27.5, 27.3, 29.4, 26.4, 28.0 | 344 | 76-82 |
| baseline settle 0 | 108.3 s | 25.6, 26.1, 25.9, 27.6, 24.7, 26.7 | 365 | 81-85 |
| baseline default | 117.9 s | 22.2, 25.6, 25.2, 27.6, 24.3, 26.5 | 220 | 72-78 |

| Average total | |
|---|---:|
| baseline default | 119.0 s |
| baseline, `DS4_SETTLE_MS=0` | 108.65 s (**-8.7%**, the normal engine alone) |
| **v16** | **106.35 s** (-2.1% vs baseline settle 0; **-10.6% vs default baseline**) |

Decode turns 3-6 median: v16 27.6 vs baseline-settle-0 26.1 tok/s (**1.057x**). Prompts: v16 0.92x (big) and about 0.95x (short) of baseline-settle-0.

**Conclusion:** most of the conversation-level gain found tonight is the post-prompt settle, and it applies to the normal engine too: `set DS4_SETTLE_MS=0` in the normal launcher is worth about 8.7% on this workload. Whole-expert itself adds about 5.7% decode and about 2% total on top. Its remaining cost is prompt streaming (smaller owner tiers).

### v16 bias re-check at the user's settings (settle 0; total for 6 turns, one run each unless noted)

| Bias | Total |
|---|---:|
| 2 | 106.6 s |
| 3 (default) | 106.8 / 105.9 s |
| 5 | 105.0 / 107.2 s |
| 8 | 106.3 s |

All within run-to-run noise (about +-1 s). With the settle gone, the bias only trades prompt rate (higher bias: short prompts up to 80-90 tok/s) against decode, at a constant total. The default stays 3. The placement knobs are exhausted at this point. Further gains would need new mechanisms: the other GPU helping prompt chunks, or a faster IQ1_M CPU kernel (a row-interleaved layout).

## IQ1_M CPU kernel research (2026-10-30, about 04:00-05:00)

(A correction first: in earlier closing messages I put the time at "09:15-11:45, the night is over". That was wrong. I estimated the clock instead of checking it, and the machine clock read 04:31 when I checked. Work continued.)

`iq1m-bench\iq1m_bench.c` is a standalone microbenchmark of an IQ1_M x Q8_K row dot, one expert gate matrix (2304 x 4096, 2.06 MB), single thread, best of 30. Every variant was checked bit for bit against A on all 2304 rows:

| Variant | Time | Rate | vs A |
|---|---:|---:|---:|
| A: ggml AVX2, as this build compiles it (no BMI2) | 1046 us | 1.97 GB/s | 1.00x |
| B: grid rows by AVX2 gathers | 1711 us | 1.21 GB/s | 0.61x (gathers are slow on Zen 2) |
| C: two weight rows per call | 1086 us | 1.90 GB/s | 0.96x |
| **D: sign vectors from qh in SIMD** (AND, compare, OR instead of 8 conditionals) | **831 us** | **2.48 GB/s** | **1.26x** |
| E: D + grid indices in SIMD | 884 us | 2.33 GB/s | 1.18x |

D was put into an isolated copy of ggml (`llamacpp-whole`, which the whole-expert build now uses). It made **no difference in the engine** (IQ1_M lane time 255.5 us per expert, unchanged), and output is identical. The engine's decode CPU lane does not use ggml's IQ1_M dot: Strata has its own AVX2 IQ1_M rows (`src/kernels/cpu/iq_avx2_rows.inl`, `row_dot_iq1m`), which already compute indices and signs in SIMD and precompute the activation pair sums. The patched copy is harmless and stays.

**Scaling on the 3960X** (D, rows split evenly, one thread per physical core; topology checked, logical CPUs pair as 0/1, 2/3, ...):

| Threads | In cache (2.06 MB) | Per thread | Streamed from RAM (132 MB) |
|---:|---:|---:|---:|
| 1 | 2.43 GB/s | 2.43 | - |
| 6 | 14.7 GB/s | 2.45 | 14.2 GB/s |
| 12 | 28.9 GB/s | 2.41 | 28.6 GB/s |
| 24 | 43.3 GB/s | 1.80 | 35.3 GB/s |

Linear up to 12 cores, then only 1.2-1.5x from 12 to 24, even in cache. Per-thread speed drops by about a quarter at 24 threads. This is consistent with the 280 W package power limit pulling all-core AVX2 clocks down (likely, not measured: clock readings were not available). It matches the lane's own thread test earlier (12 -> 24 threads: 1.5x). The engine's CPU lane reaches about 24 GB/s of IQ1_M expert weights (6.2 MB per expert in 255 us), about 70% of this simple kernel's streamed rate at 24 threads. The remaining headroom (at most about 1.4x on the CPU lane) lies in the lane's overhead around the kernel (job split, quantization, SwiGLU), not in the dot product, and needs deeper lane changes. Not pursued tonight.

### Long outputs: v16 vs baseline, both with settle 0 (user settings, 6 turns x 1,200 tokens, interleaved, about 04:25-04:57)

Generated lengths differ between runs (greedy, but not bit-repeatable), so the comparison is per decoded token, prompts included:

| Run | Total | Decoded tokens | ms per decoded token |
|---|---:|---:|---:|
| baseline settle 0 | 272.9 s | 6,580 | 41.5 |
| v16 | 274.2 s | 6,833 | 40.1 |
| v16 | 265.6 s | 6,683 | 39.7 |
| baseline settle 0 | 295.8 s | 7,137 | 41.4 |

v16 is about 3.8% less time per decoded token. Decode-rate median over all turns: 27.2 vs 26.15 tok/s (1.04x), consistent with the 400-token runs (1.057x). With the settle fixed in both, whole-expert's remaining advantage on this machine and split is about 4-6% on decode-heavy work.

## v17: the CPU lane's IQ1_M kernel choice (about 05:00-05:30)

The engine's own CPU-lane benchmark (`ds4_gg_bench --expert`: gate+up+SwiGLU, quantize, down, 64-row jobs, 24 threads, experts streamed far beyond L3, every mode bit-identical) shows the single-token IQ1_M default leaving speed on the table:

| Expert types (gate/up / down) | ggml rows | auto (the engine's default) | Strata's own rows |
|---|---:|---:|---:|
| IQ1_M / IQ1_M | **47.5 GB/s** | 34.5 | 34.4 |
| IQ2_XXS / IQ1_M | **55.2** | 48.4 | 44.4 |
| IQ2_XXS / IQ2_XXS | 59.9 | 60.1 | 52.1 |
| IQ2_XS / IQ2_XS | 59.8 | 62.4 | 58.8 |

("ggml rows" here is the patched copy with variant D's SIMD signs; the original ggml rows are about 1.26x slower on IQ1_M, about 38 GB/s.)

**Why:** `ds4_gg_cpu.cpp` sends IQ1_M to Strata's rows from one token, because ggml's IQ1_M dot uses `_pdep_u64` when built with BMI2, which Zen 1/2 run in microcode (1.8 GB/s measured by the authors on an EPYC). This repo's portable build has `GGML_BMI2=OFF`, so ggml takes its table path, which is faster than Strata's rows at one token.

**v17 change** (`ds4_gg_cpu.cpp`, `min_tokens`): IQ1_M uses Strata's rows from one token only where `ggml_cpu_has_bmi2()`; otherwise it follows the same two-token rule as the other types. The build also uses the patched ggml copy (`llamacpp-whole`, variant D in `ggml_vec_dot_iq1_m_q8_K`). Both are bit-identical: smoke output matches baseline.

Engine CPU lane, IQ1_M/IQ1_M experts, baseline mode, 3 turns x 300 tokens:

| Engine | us per expert |
|---|---:|
| default (Strata rows) | 255 |
| `DS4_GG_IQ256=0`, original ggml | 232 (-9%) |
| `DS4_GG_IQ256=0`, patched ggml (v17's kernel) | **194 (-24%)** |

Mixed IQ1_M layers improve similarly: 205-231 -> 187-195 us. **This helps the normal engine as well:** `DS4_GG_IQ256=0` alone takes 9% off IQ1_M experts in an unmodified 0.1.52 build of this kind (the installed `.zen2lp` binary may be built differently and is untested), and the patched kernel adds the rest. Running: the final A/B with v16 (normal engine, settle 0), v17 baseline mode, and v17 whole.

Versions: `versions\v17-ggmlrows` (sources, including `ds4_gg_cpu.cpp` and the patched `ggml-cpu-x86-quants.c`, plus binaries). The build is now configured with `FETCHCONTENT_SOURCE_DIR_STRATA_LLAMACPP=llamacpp-whole`.

### v17 final A/B (user settings, all with settle 0, about 04:40-05:20)

Order: B16 / W17 / B17 / W17 / B17 / B16. B16 = the v16 binary in baseline mode (the normal engine with `DS4_SETTLE_MS=0`); B17 = the v17 binary in baseline mode (the normal engine plus the IQ1_M kernel change); W17 = v17 whole-expert with pull.

| Config | Totals | Average | Decode turns 3-6 median | vs B16 |
|---|---|---:|---:|---:|
| B16 | 110.3 / 108.8 s | 109.55 s | 26.2 tok/s | - |
| B17 | 103.9 / 104.4 s | 104.15 s | 27.5 | -4.9% total, 1.05x decode |
| **W17** | **102.7 / 102.1 s** | **102.4 s** | **28.9** | **-6.5% total, 1.10x decode** |

Against the default normal engine (settle 6 s, earlier interleaved runs today about 119 s on this workload), v17 whole-expert is about -14% total conversation time. Peak decode 30.6 tok/s.

**Where tonight's gains come from:**

| Change | Engine | Gain |
|---|---|---|
| Post-prompt settle off (`DS4_SETTLE_MS=0`) | any engine, one env var | about -8.7% |
| IQ1_M single-token kernel choice + SIMD signs | normal engine too (needs this build) | about -4.9% more |
| Whole-expert (other GPU's tier + pulls) | needs this build | about -1.7% more total, decode +5% |

### CPU lane: kernel vs per-call overhead (v17, about 05:30)

`DS4_PROF` per CPU-lane call (baseline mode, 2.97 experts a call): prep 0.018 ms, gate+up 0.352 ms, h-quant 0.022 ms, down 0.176 ms. With about 4.5 MB of gate+up and 2.2 MB of down weights per expert (an IQ1_M/IQ2_XXS mix), the phases run at about 38 and 37 GB/s.

The engine's own benchmark runs the same pipeline code at 47-60 GB/s (`ds4_gg_bench --expert`), but in one parallel pass over about 400 experts: thousands of 64-row jobs, no barrier between experts. The engine lane works on the 2-4 experts of one layer per call, with a barrier after gate/up and after down and a partial last round of jobs each time. Both use 4 KB pages, so TLB is not the difference: per-call structure costs about 20-35% of the lane's throughput.

Recovering it would mean changing the lane's scheduling. Two candidates:
- (a) Overlap a layer's down phase with the next layer's gate/up. Not possible as is: the next layer's input depends on this layer's output.
- (b) Finer jobs only for the last round. The `DS4_LANE_RB` 16/32/64 test showed no gain, so the tail is not the main cost; barrier and wake latency and cache effects remain.

This would help the normal engine equally. Not pursued: moderate expected gain, invasive change.

### v17 long-run stability (user settings, one server, 6 turns x 1,200 tokens, finished about 05:29)

Decode per turn: 27.6, 29.1, 28.6, 30.3, 27.7, 28.6 tok/s, about 6,850 decoded tokens. The running chain average improved from 37.9 ms per token (first 400 tokens) to **34.x ms** over 6,400 tokens (v16 at the same settings: 37.7 ms). CPU-lane service on the 3080 Ti / 5090 layers is 6.8 / 6.4 ms per token (v16: 8.3 / 7.9). The only log line flagged was the known large-page fallback (err 1450). No errors, no slowdown.

IQ2_XXS check (`iq1m-bench\iq2xxs_bench.c`, single thread, one 2304 x 4096 matrix, bit-checked): ggml's AVX2 dot loads the 8-byte sign patterns from `keven_signs_q2xs`. Computing them in SIMD instead (7 bits + parity, broadcast, AND, compare) is bit-identical but **slower: 1048 vs 754 us (0.72x)**. ggml's IQ2_XXS dot already runs at 3.23 GB/s a thread, against IQ1_M's 1.97 (2.48 with the v17 fix). IQ1_M's branchy sign construction was the special case; no similar easy win for IQ2_XXS.

### Decode GPU stages (v17 whole, user settings, about 3,000 tokens of context, about 05:50)

`DS4_PROF` per-stage GPU time per decode token, both devices summed (now printed with `DS4_CHAIN`; profiling adds some overhead):

| Stage | ms per token |
|---|---:|
| attention (mixing, projections, indexer, sparse attention, output projection) | **11.96** |
| routing + shared expert | 4.84 |
| experts gate/up (GPU-resident) | 1.86 |
| down + combine | 1.99 |
| waiting for the CPU lane | 16.40 |
| between layers | 0.22 |

Of the about 19.8 ms of GPU gaps in the timing chain, **attention is about 12 ms (about 0.3 ms per layer)**. It grows with context length. It is the same in both engines and the largest remaining GPU-side block. The earlier kernel candidates (A-G) targeted the expert kernels, not attention. Next-step candidate: a finer split of the attention stage (sparse attention vs indexer vs projections) at a long context.

## Decode GPU attention split (v17 + profiling marks, about 05:40)

Diagnostic build only: three extra `prof_mark` points in `layer()`'s decode attention (stages 12/13/14), printed by `DS4_PROF=1 DS4_CHAIN=1`
as "ds4 chain attention split". No behaviour change. One whole-mode run, user settings, 6 turns (decode 23.8-29.7 tok/s, normal for this run).
Steady state, ms per token with both GPUs summed:

| stage | ms |
|---|---|
| hc mix + norm + q/kv/compressor projections + q finish | 5.15 |
| kv finish, window ring, compression, indexer + top-k | 1.67 |
| sparse attention kernel | 2.65 |
| output projections (wo_a, wo_b) + hc post | 3.11 |
| routing + shared expert | 4.78 |
| experts gate/up | 1.75 |
| **waiting for the CPU lane** | **14.8-18.9** |
| down + post | 2.00 |

Conclusions:
- Attention (~12.6 ms) has no single hot spot. About 8.3 ms of it is dense GEMVs at T=1 (projections), which are weight-bandwidth-bound;
  the sparse attention kernel itself is only 2.65 ms. Speeding up attention would mean fusing the many small GEMVs, which is a
  large kernel project with at most a few ms to gain.
- The CPU-lane wait is still the biggest single item, larger than all attention. That remains the main target: fewer CPU-lane
  experts (more GPU pulls or better caching), or a faster CPU lane. Large pages (needs a reboot; err 1450 now) are the cheapest untested idea.
- The recommended build is unchanged: `versions\v17-ggmlrows`. The profiling build is in `build-whole-expert\Release` and behaves the same.

## Forced DSpark (about 05:45): not viable
`--dspark on` loaded the draft model into VRAM, which left the 3080 Ti holding 0 experts, and the server exited during the run. The engine's automatic "not loaded" choice is right on this hardware.

## v18: CPU lane without the gate/up -> down barrier (about 05:45-06:05)
`cpu_experts_iq` now runs gate/up and down as one pool batch. Each expert's down jobs wait only for that expert's gate/up jobs, and the last of those quantizes its h. Jobs are claimed in order, so this cannot deadlock. Each row runs the same calls, so the output bits are the same. `DS4_LANE_FUSE=0` restores the old two-phase path.
Interleaved A/B, whole mode, user settings, 2 runs each:

| | total s | CPU lane per call (1.8 experts) |
|---|---|---|
| fused (v18) | 105.8, 105.2 | 0.339 ms |
| two-phase (v17) | 107.1, 107.1 | 0.369 ms (gate+up 0.238, h-quant 0.014, down 0.117) |

The CPU lane is about 8% faster per call; whole runs are about 1.5% faster in total, consistent over every turn pair. This applies to the normal engine as well (the same code path). Saved as `versions\v18-lanefuse`; the launcher's build folder now has v18.

### v18 in the normal engine (baseline mode, about 06:05)
Same interleaved A/B in baseline mode (DS4_PROF on in all runs): fused 105.7 and 106.0 s, two-phase 107.5 and 108.3 s (about **-2%**). CPU lane per call (2.4 experts): 0.406 vs 0.446 ms (-9%). So the change helps both engines equally.
In these runs, whole mode (105.2-105.8 s) is only marginally faster than baseline (105.7-106.0 s). Both runs here have profiling on, and earlier measurements gave W17 102.4 vs B17 104.15, which is also a small gap. The decode advantage of whole mode is about 1.10x per token, but over the whole conversation it is about 1.5-2%.

### GPU poll and thread count with v18 (about 06:10-06:30)
- The GPU's wait for the lane's answer (`wait_seq_kernel`, `mx_wait_kernel`) sleeps 200 ns between polls, far below one PCIe read. That is not a source of latency.
- Whole mode, v18, profiling **off**, interleaved: 32 threads 100.4 / 102.1 s, 48 threads 99.9 / 100.4 s. Keep 48 (the launcher's setting).
- v18 whole without profiling is about **100.2 s**, against W17's 102.4 s (about -2%) and B16's 109.55 s (about -8.5%).
- `DS4_LANE_RB` with the fused lane: 32 rows 99.9 / 101.0 s, 64 rows 100.9 / 100.2 s. No difference; keep the default 64.

### Where things stand (about 06:40)
Recommended: **v18** (`versions\v18-lanefuse`, in the launcher's build folder), with the launcher's settings, about 100 s on the 6-turn test against 109.55 s for the normal engine with settle 0. Remaining ideas, all larger projects: fusing the attention GEMVs (at most a few ms per token), large pages (needs a reboot), and scheduling the CPU lane across layers (blocked by the data dependence between layers).

### Why decode attention costs 12.6 ms per token (analysis, about 06:50)
- In the prompt path, attention for a whole 2,706-token prompt took **71 ms** across all layers. One decode token takes **12.6 ms**. The work is about 2,700x smaller but the time only about 6x smaller, so decode attention is not limited by computation.
- Counting the launches in `layer()`'s decode attention gives about 25 small kernels per layer: hc mix, norm, projections, the finish kernels, ring copies, compressor, indexer GEMVs, scoring, top-k, sparse attention, output GEMVs, ablate and hc post. Across 43 layers that is about 1,000 dependent kernels per token, roughly **10-12 us each**: launch, ramp-up and drain on a GPU that is mostly idle within each kernel. That matches the measured 12.6 ms. The weight reads alone (a few GB across both GPUs) account for only about 2-3 ms.
- Windows hardware-accelerated GPU scheduling is already on (`HwSchMode=2`, read only), so there is no setting to gain from.
- **This is now the largest remaining target: up to about 8 ms of about 33 ms per token (about 20-25%).** It needs one of:
  1. **CUDA graphs** for each layer's decode attention. The arguments change per token (position, rows, top-k limits), so this means capturing once and updating each token with `cudaGraphExecUpdate` or kernel-node parameter updates, plus making the host-side `Rows`/`AttnRows` values device-side. It is not done anywhere in the engine yet.
  2. **Kernel fusion**: for example hc mix + pre-norm + the q/kv GEMVs in one kernel, and the finish kernels folded into the GEMV epilogues. Each fusion saves about 10 us per layer per kernel removed.
  Both are multi-day changes to the engine's core path with a bit-exactness check. They are not safe to start unattended, so they are left for a decision.

### Attention by device confirms latency-bound kernels (about 07:05)
A per-device split was added to the DS4_PROF print (diagnostic only). In a 3-turn whole run with `DS4_SPLIT=14,26`, CUDA0 is the 3080 Ti with 14 layers and CUDA1 is the 5090 with 26+ layers. Times are ms per token:

| | projections | indexer | sparse attn | output | routing |
|---|---|---|---|---|---|
| 3080 Ti (14 layers) | 1.91 | 0.49 | 1.00 | 1.35 | 1.59 |
| 5090 (~29 layers) | 3.26 | 1.18 | 1.63 | 1.75 | 3.18 |

Per layer, the 5090 is only about 10-35% faster than the 3080 Ti (projections about 0.11 vs 0.14 ms), though it has about 2x the memory bandwidth and far more compute. If the weight reads were the limit, it would be about 2x faster. This supports the analysis above: decode attention is limited by per-kernel latency and serial dependencies, so **CUDA graphs or kernel fusion** are the way forward. Neither is attempted yet (a multi-day core-path change).

## v19: decode attention as CUDA graphs (about 07:10-08:00) - **largest single gain of the night**
Two pure-kernel runs of `layer()`'s decode attention are now captured each token into a CUDA graph and launched as one unit (`attn_graph`):
(1) hc mix, pre-norm, q/kv projections and q finish; (2) sparse attention, o finish, output projections, ablate and hc post.
Each layer and part keeps its instantiated graph and updates it in place each token (`cudaGraphExecUpdate`). The capture mode is thread-local. Prompts, profiling runs and tensor-parallel layers are not affected. A slot that fails to capture falls back to the old path permanently and logs a line. Opt-in with `DS4_ATTN_GRAPH=1`; the whole-expert launcher now sets it.

**Correctness:** `DS4_ATTN_GRAPH_CHECK=1` reruns each part as plain launches right after its graph and compares the output byte for byte (q or q_r, and the new residual h2). Over 2 whole-mode turns, **60,000 parts compared, 0 differ**, with 0 capture failures. Cross-run hidden-state dumps cannot decide this question: baseline vs baseline with graphs off already differs from the prompt on (slice 2) in this harness.

**Speed:** interleaved A/B, whole mode, user settings, 6 turns, profiling off:

| | total s | decode tok/s per turn |
|---|---|---|
| graph on (v19) | 90.9, 89.9 | 30.7-36.1 |
| graph off (v18) | 99.5, 100.4 | 26.0-31.4 |

That is **-9.7% total, about +14% decode**. Against the normal engine with settle 0 (B16, 109.55 s), v19 whole is about **-17.5%**. In baseline mode (dump runs, so slower overall) decode went from 19.4/20.9 to 20.9/22.8 tok/s, so graphs help the normal path as well.
The kernel-latency analysis above predicted this: one graph per part removes most of the gaps between kernels.
Next: the same treatment for the indexer part (~1.7 ms), routing + shared (~4.8 ms) and down + post (~2 ms), where those contain no host decisions.

## v20: graphs extended to routing + shared expert and down + post (about 08:00-08:45)
Two more parts of each decode layer are now graphs, under the same `DS4_ATTN_GRAPH=1` switch:
- part 2: FFN hc mix and pre-norm, gate GEMV, lookahead gates, `route_publish` (the request to the CPU lane, a kernel writing host-mapped memory) and the shared expert;
- part 3: expert down, ablate, hc post and the pre copy, on the single-device token path.
Check run (`DS4_ATTN_GRAPH_CHECK=1`; part 2 is not rerun because that would publish twice): **92,000 parts compared, 0 differ**, with no capture failures.

Interleaved A/B, whole mode, user settings, `DS4_ATTN_GRAPH=1` in both:

| | total s | decode tok/s |
|---|---|---|
| v20 | 84.6, 83.7 | 32.6-40.0 |
| v19 | 91.6, 89.9 | 29.3-36.0 |

That is **-7% vs v19**. Cumulative: **v20 whole 84.2 s vs the normal engine with settle 0 at 109.55 s (-23%)**, and about -29% vs the default normal engine (~119 s). The launcher's build folder holds v20, and the launcher sets `DS4_ATTN_GRAPH=1`.

## v21: one graph for each layer's expert stage (about 09:00)
Part 3's graph now also holds zc staging, the owner pull kernels, expert gate/up and the wait for the CPU lane's answer (`wait_seq`), so each decode layer runs as 4 graphs plus the indexer's plain launches. Check run: **92,000 parts compared, 0 differ**.
Interleaved A/B (both `DS4_ATTN_GRAPH=1`): **v21 82.1 / 82.2 s, v20 84.3 / 84.4 s (-2.6%)**.

### Summary of the night (as of about 09:00)
| build | whole 6-turn total (user settings) |
|---|---|
| normal engine, default (~119 s) / settle 0 (109.55 s) | reference |
| v17 | 102.4 s |
| v18 (fused CPU lane) | ~100.2 s |
| v19 (graphs: attention) | ~90.4 s |
| v20 (graphs: + routing/shared, down/post) | ~84.2 s |
| **v21 (graphs: + expert gate/up and wait)** | **~82.15 s (-25% vs settle-0 normal, about -31% vs default)** |

`versions\v21-graphffn` is in `build-whole-expert\Release`. The whole-expert launcher sets `DS4_ATTN_GRAPH=1`. Remaining plain launches: the indexer/compressor part, which has host-side branches and cross-device replication.

## v22: indexer and window-row graphs - no gain (real clock about 07:30-08:10)
Clock correction: the 'about 08:00-09:00' times in the v19-v21 sections were estimates and ran ahead. The real clock was 07:29 when v22 started.
v22 adds part 4 (indexer q GEMV, finish, weights, scores, candidate blocks, top-k) and part 5 (ring to ext, kv finish, ext to ring). The check run compared **98,000 parts with 0 differences**. Part 5 is not rechecked, because rerunning it would move the ring.
Interleaved A/B: v22 82.7 / 81.3 s, v21 82.3 / 81.7 s, so **no difference**. The remaining gaps there are small next to the CPU-lane wait. **v21 stays the recommended build** (simpler). v22 is kept in versions\ only.

### Timing chain on v21 (real clock about 07:55)
`DS4_CHAIN=1`, whole mode, graphs on, 6 turns, ms per token over 2,000 tokens:
between tokens 1.41 | 3080 Ti side: GPU gaps 4.68, CPU-lane service 6.48 | hand-off 0.48 | 5090 side: GPU gaps 6.21, CPU-lane service 7.48 | **total 26.7 ms** (v17: about 34 ms).
The GPU gaps fell from about 20 ms to **10.9 ms**. **The CPU lane (about 14 ms, 52%) is now the dominant cost.** It runs at about 36-40 GB/s against 47-60 GB/s for the same kernels in one large pass, and 77 GB/s for AIDA64 reads.
Next avenues, in order: (1) large pages for the RAM store (needs a reboot; it failed with err 1450 at start); (2) more GPU pulls now that the GPUs have idle time (raise `DS4_WHOLE_PULL` T1/T2: earlier a dead end, but the balance has changed); (3) the CPU lane's remaining per-call overhead.

### Pull thresholds on v21 (real clock about 08:00-08:45)
Interleaved, 2 runs each: default (T1=2, T2=5) 82.6 / 83.1 s; more pulls (T1=1, T2=3) 84.3 / 83.9 s (worse); owner pull T3=3 83.0 / 82.9 s (same). **Keep the defaults.** The helper GPU's pulls run at PCIe speed and still do not beat the CPU lane on these experts.

## Graphs in the normal engine: the best setup (real clock about 08:45)
v21 build, **baseline mode** (no `DS4_WHOLE_EXPERT`), settle 0, interleaved: **graphs on 80.9 / 80.0 s, graphs off 100.5 / 100.5 s (-20%)**.
This is slightly faster than whole-expert mode with graphs (about 82 s). Once the GPU gaps are gone, moving experts between the GPUs no longer pays for its swap traffic and its larger CPU lane. **Recommendation: the normal engine path with CUDA graphs.**
New launcher: `d:\strata\run-deepseek-abliterated-largepages-graphs.bat`. It is the same as the whole-expert launcher but without `DS4_WHOLE_EXPERT`/`DS4_WHOLE_PULL`, and it sets `DS4_SETTLE_MS=0` and `DS4_ATTN_GRAPH=1`. The user's normal launcher is unchanged.
Against the default normal engine (~119 s), this is about **-33%**.

### Normal-mode graph check (real clock 08:11)
`DS4_ATTN_GRAPH_CHECK=1` in baseline mode (the recommended setup), 2 turns: **92,000 parts compared, 0 differ**, no capture failures. The graphs are verified in both modes.

### ssd-cache with graphs, normal mode (real clock about 08:50)
Interleaved: 120 GB 84.6 / 81.5 s, 135 GB 81.4 / 81.3 s. 135 is the same or slightly better; keep the launcher's 135.
Decode with graphs (normal mode, ssd-cache 135, per turn): 34.2, 38.4, 37.4, 41.0, 34.4, 38.9, an average of **37.4 tok/s**. Without graphs and with the original CPU lane (DS4_PROF on): about 26.4 tok/s.

### v22 vs v21 in normal mode (real clock about 09:20)
v22 81.3 / 82.5 s, v21 81.1 / 81.1 s. No gain in normal mode either. **v21 stays recommended** and is in `build-whole-expert\Release`.

## Port to upstream Strata 0.2.8 / engine 0.1.54 (real clock about 09:30-10:05)
Strata updated itself to engine 0.1.54 and deleted the 0.1.52 folder. The official 0.1.54 exe has no `--ablate`, so the launchers now copy the test build into the 0.1.54 folder (the official exe is kept as `strata-dsv41.exe.official`).
Port: the official 0.2.7 and 0.2.8 sources were downloaded to `upstream\`. Our full delta (the user's Windows patches in `strata-candidate` plus v18-v22 in `strata-whole-expert`, 10 engine files) was applied onto 0.2.8 hunk by hunk (`port.py`, exact context): **86 of 94 hunks applied cleanly, 8 merged by hand**. Those 8 were the `--ablate` usage text, the per-GPU reserve field, and the abliteration/graph wrappers around code where upstream added dump hooks and Metal `#if`s. Both versions pin the same llama.cpp commit, so the `llamacpp-whole` IQ1_M override carries over.
Result: `strata-0154` (source), `build-0154` (build), `versions\v23-upstream0154`. It builds with no errors, `--ablate` loads, and `DS4_ATTN_GRAPH_CHECK` compared **10,000 parts with 0 differences** (a partial run, stopped so it would not disturb the user's own server). **Not yet benchmarked**; the launchers still use v21.

### v23 benchmark (real clock about 10:45)
Normal mode, graphs on, user settings: full `DS4_ATTN_GRAPH_CHECK` run compared **98,000 parts with 0 differences**. Interleaved 6-turn runs: **v23 80.9 / 81.8 s, v21 81.6 / 81.8 s**, average decode about 37.6 vs 37.4 tok/s. The same speed on the current upstream base. v23 is now in `build-whole-expert\Release`, which both launchers copy from.

## v24: large pages in 1 GB pieces (real clock about 11:35)
Large pages never turned on: the store asked Windows for 135 GB in ONE `MEM_LARGE_PAGES` allocation, which failed with err 1450 even right after a reboot and with 189.5 GB free (Windows needs that many free 2 MB runs at once). A probe in the user's session showed the privilege is granted and **30 x 1 GB large-page allocations succeed** while the server holds its 135 GB. v24 falls back to 1 GB pieces placed end to end at one reserved address range, so the store's code sees one block. It frees them piece by piece. If any piece fails, it frees them all and uses 4 KB pages as before. Builds cleanly; installed in `build-whole-expert\Release`. Not yet run or measured. All earlier benchmarks (v17-v23) used **ssd-cache=135 on 4 KB pages**.

### Large pages measured (v24, real clock about 12:15)
Normal mode, graphs on, ssd-cache 135, interleaved. Large pages really were on (one 135.4 GB allocation, right after the user's server stopped). In the 4 KB runs `DS4_STORE_LARGE=0` was set, which prints no store line; the log lines shown for them were left over from the large-page runs.
| | total s | average decode tok/s |
|---|---|---|
| 2 MB large pages | 80.6, 79.9 | 38.5, 38.7 |
| 4 KB pages | 79.8, 79.7 | 38.5, 38.5 |
**No measurable gain.** The CPU lane's ~36-40 GB/s is not TLB-bound. Large pages lock 135 GB up front and slow the start, so they are optional; leaving `DS4_STORE_LARGE=1` on is harmless.
