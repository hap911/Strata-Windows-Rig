# Journal: rebase onto upstream 0.2.12 / engine 0.1.58, 2026-11-08

> Working journal for the 2026-11-08 rebase behind `StrataRig-0.1.58-r1`. Measurements on the reference
> rig (Threadripper 3960X, 192 GB DDR4, RTX 5090 + RTX 3080 Ti that drives the desktop), same harness
> and settings as the 2026-10-30 journal: 6-turn coding conversation, 400 generated tokens a turn,
> fresh conversation slots each run, `--ssd-cache=135`, `DS4_SPLIT=14,26`, `DS4_SETTLE_MS=0`,
> `DS4_ATTN_GRAPH=1`, the abliteration adapter on.

## What broke

Strata updated its DeepSeek engine on 2026-11-08 at 14:08 to 0.1.58 (release 0.2.12, published 11-07) and
deleted the 0.1.54 folder. The patched `strata-dsv41.exe` lived in that folder; the source patches were
intact (`strata-0154`, `versions\`, `build-rel`).

## The rebase

- Upstream 0.2.12 downloaded; `strata-0158` = its full tree + the whole patch delta ported from
  `strata-0154` (which is 0.2.8 + the patches). `port.py` applied **86 of 95 hunks unchanged; 9 merged by
  hand**: the `--ablate` usage text, the per-GPU reserve field, the abliteration hooks, and the CUDA-graph
  wrappers. Upstream had refactored: the attention body became `attn_core()` with renamed locals (`q`,
  `o_r`, `topk_r`, an `AttnSeq` A), and `cache_queue()` became `void`.
- The graph layout became 6 parts: part 0 (projections, `layer()`), part 1 (sparse attention + finish,
  `attn_core`), part 4 (indexer), part 5 (window rows), part 2/3 (`layer()`), and part 6 (output
  projections + allreduce + ablate + hc post). Two port slips surfaced at compile time - a misplaced
  closing fragment in `attn_core`'s head and our `return queued;` in a now-`void` function - both fixed.
- Build: `build-rel2`, sm_86-real;89-real;120 + PTX (RTX 30/40/50), IQ1_M ggml fix, large-page pieces.
- Check: `DS4_ATTN_GRAPH_CHECK=1` compared **128,000 graph-launched parts with plain launches, 0
  differences**.

## Where the speed went (and came back)

First runs of the new build gave 26-28 tok/s where the 0.1.54 build had measured 34-41 on 2026-10-30.
Same-day old-vs-new interleaved runs showed the old build also at 27.3 - so the machine had changed, not
the port. The `DS4_CHAIN` timing chain showed it: the **3080 Ti's kernel gaps** (the card that drives the
monitor) grew from **4.68 ms/token** (10-30) to **11.65-13.45**, while the 5090's stayed ~6.3 with graphs
(14.2-14.4 without: graphs were still working on the 5090). With `--reserve-mib=900,100` and a browser
open, CUDA0 had **204 MiB free** (10-30 quiet: 801) - the desktop's memory pressure stalled GPU0's
kernels and the 5090's graph launches behind them.

The sweep (6-turn runs, chain on):

| config | decode tok/s (turns) | GPU0 gaps | GPU1 gaps | GPU1 CPU service |
|---|---|---|---|---|
| 14,26 reserve 900,100 (cold) | 23.8-26.4 | 11.08 | 14.44 | 6.1 |
| **14,26 reserve 1200,100** | **30.8-37.4** | **7.02** | **6.32** | 7.2 |
| 8,32 reserve 1200,100 | 29.0-32.9 | 8.74 | 7.88 | 11.0 |
| 6,34 reserve 1200,100 | 26.8-31.8 | 9.69 | 8.39 | 12.8 |
| 14,26 reserve 900,100 (warm) | 29.0-31.6 | 10.37 | 6.32 | 6.9 |

Conclusions:
- **Reserve 1200,100 is the fix**: it gives the desktop card headroom; GPU0 gaps fall ~11 -> ~7 and the
  5090's graphs work again. Decode ~34.5 tok/s with the desktop in use.
- **Splits 8,32 and 6,34 are worse**: GPU0's gaps stay high because the compositor interleaves there
  regardless of layer count, and moving layers to the 5090 grows the CPU-lane service (11.0/12.8 vs 7.2)
  and the between-token/hand-off time (2.0/2.3 vs 1.35).
- The user changed the monitor from 120 Hz to 60 Hz during the last runs; the confirming run's GPU0 gaps
  fell 7.02 -> 6.86 and decode held at 31.8-36.9 (avg 34.5).
- Prompts are faster than 10-30: 398.9 tok/s on the 2736-token prompt (was ~317-335).

## Update-proof install

- The build is stored in `windows\rig\engine\0.1.58\` (and locally `D:\strata\rig\engine\0.1.58\`) -
  outside Strata's folders, which updates delete - plus the official exe+dll of that folder in
  `official\0.1.58\`.
- Launchers: `windows\rig\use-rig-engine.bat` finds Strata's current engine folder, computes its version
  from the folder name, and copies the matching rig build in at every start. No build for the version ->
  it starts the official engine and prints what to do. A mismatched build is never swapped in.
- Strata's own behaviour: `strata launch` only updates when the engine is older than `MIN_ENGINE`
  (0.1.46) - a rig build reports 0.1.58, so launches leave it alone; `strata update` replaces it and is
  the explicit step to avoid (or to follow with `build-strata-engine.bat install`).
