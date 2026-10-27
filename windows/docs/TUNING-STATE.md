# Strata Models — Tuning State

> Living document. Updated by the tuning process after every phase.
> If interrupted: read "CURRENT PHASE" and "NEXT ACTIONS" to resume.

## Final numbers — both models side by side (2026-10-25)

| | **CYBER-FROST 3.8** (Q4_K_M, 111 GB) | **DeepSeek-V4.1-Flash** (IQ2_XXS, 249 GB) |
|---|---|---|
| Decode (single stream) | **152.6 tok/s** | **29.1 tok/s** |
| Cold prefill (~21K prompt) | 62.6 tok/s | 534.9 tok/s |
| Context | 262K (512K config ready, 146.8 tok/s) | 256K |
| GPU layout | 5090 only; 3080 Ti = vision + display | both: 3080 Ti layers 0-17, 5090 layers 18-39 + head |
| Vision | yes (on 3080 Ti) | off |
| Parallel agents | time-share 1 engine; batch configs: 2×40 or 4×24 tok/s dedicated | time-share 1 engine (no batch support) |
| Prompt cache | RAM, tuned (32 GiB, 12 slots) | automatic + survives restarts on disk |
| Start | `cyber-frost` / [run-cyber-frost.bat](run-cyber-frost.bat) | `deepseek` / [run-deepseek.bat](run-deepseek.bat) |
| Control | `cyber-frost status|stats` | `deepseek status|stop|stats` |
| Key settings | preset `cf-single-262k-long`: `--host-core last`, `spec_min_p 0.5` | preset extra: `--ssd-cache 120 --prefill-chunk 4096 --cpu-threads 48`, tune=skip |

**Rule of thumb:** CYBER-FROST = fast chat/coding + multi-client; DeepSeek = heavy single-agent reasoning at 763B quality.

---

# CYBER-FROST 3.8 — Tuning Campaign State

> Living document. Updated by the tuning process after every phase.
> If interrupted: read "CURRENT PHASE" and "NEXT ACTIONS" to resume.

**Machine:** Windows 11, Threadripper 3960X (24c/48t), 192 GB RAM, RTX 5090 32 GB (nvidia-smi idx 1) + RTX 3080 Ti 12 GB (idx 0, display card), NVMe D:
**Engine:** 0.1.47-windows-x86_64-cuda-cuda13
**Model:** CYBER-FROST-3.8-Q4_K_M.gguf (111 GB, sha256 42f5ba4c…) + prepared pack `packs/cyber-frost-q4_k_m` + MTP `packs/mtp-stock/rt-q2`
**Started:** 2026-10-23 ~01:05 local
**Budget:** 8 hours

## Variants under test

| ID | Config file | Layout | Context | Vision |
|----|-------------|--------|---------|--------|
| A | `configs/strata-cyber-frost-windows.json` | 5090 only (`--gpu 1`) | 262K | 3080 Ti (cuda_device 0) |
| B | `configs/strata-cyber-frost-windows-split.json` | layer split `--gpu 0,1 --layer-split auto` | 262K | 3080 Ti |
| C | `configs/strata-cyber-frost-512k.json` | 5090 only | 512K | 3080 Ti |
| D | `configs/strata-cyber-frost-512k-split.json` | layer split | 512K | 3080 Ti |

## Method

1. Per variant: 15-min tune (`strata tune auto <cfg> --time 15 --use coding --name <preset>`), then benchmark (`bench_ab.py`, 3 runs, warmup first).
2. Best 262K variant gets a long tune (`--mode thorough` / `--time 60+`).
3. Then 512K variants: 15-min tunes, benchmark, long tune on the best.
4. Final: activate the winning tuning preset (`strata presets apply`), set main config, document.

## Known mechanics (learned 2026-10-22)

- Tuning presets key off config choices (model file hash, context, kv, vision…) — GPU flags do NOT differentiate the slot; after tuning multiple same-context variants, re-activate the right preset at the end via `strata presets apply`.
- `serve.server` overlays the active tuning preset at every start automatically.
- `--gpu` alone does NOT split layers; `--layer-split auto` is required (variant B).
- Baselines measured 2026-10-22 (short prompts, noisy): A ≈ 137.5 tok/s decode; B ≈ 125.7 tok/s decode, but prompt ingest better on B (58.6 vs 35.7 tok/s short-prompt avg).
- Prior quick tunes: `cyber-frost` (+26%, spec_min_p 0.5), `cyber-frost (2)` (+20%, spec_min_p 0.7). Both effectively measured on single-5090 hardware.

## CURRENT PHASE

**CAMPAIGN COMPLETE (2026-10-23 ~04:10).** All four variants tuned (15-min + thorough on winners) and benchmarked. Final verdict below. Server restarted with the winning config and health-verified (local + LAN).

## FINAL VERDICT

**Winner: A — single RTX 5090, 262K context, vision on 3080 Ti** (`configs/strata-cyber-frost-windows.json`), active preset `cf-single-262k-long` (+16%: `--host-core last`, `spec_min_p 0.5`).

| Variant | Layout | Ctx | Decode tok/s | Prompt tok/s | Active preset |
|---------|--------|-----|-------------|--------------|---------------|
| **A** | 5090 | 262K | **152.6** | **62.6** | `cf-single-262k-long` ★ |
| B | split 0,1 | 262K | 121.3 | 53.6 | `cf-split-262k` |
| C | 5090 | 512K | 146.8 | 65.5 | `cf-single-512k-long` ★ |
| D | split 0,1 | 512K | 99.7 | 55.1 | `cf-split-512k` |

- Layer split loses at both contexts — the 3080 Ti computes its layers ~3.4x slower than the 5090, so every token pays the slow-card latency. The 3080 Ti earns its keep running vision + display instead.
- 512K single-GPU costs only ~4% decode vs 262K and actually ingests prompts slightly faster. To switch: point `run-cyber-frost.bat` (or the serve command) at `configs/strata-cyber-frost-512k.json` — its tuned preset activates automatically.
- Both winning presets are marked active (`strata presets list`); the correct one overlays automatically per config.

## Results log

| Time | Variant | Action | Decode tok/s | Prompt tok/s | Notes |
|------|---------|--------|-------------|--------------|-------|
| 10-22 23:25 | A | bench (untuned-short) | 137.5 | 35.7 | 3-run avg |
| 10-22 23:30 | B | bench | 125.7 | 58.6 | split K=8 auto |
| 10-22 23:16 | A | tune quick | 119.9 | — | preset `cyber-frost` +26% (spec_min_p 0.5) |
| 10-22 23:47 | A(hw) | tune quick | 111.8 | — | preset `cyber-frost (2)` +20% (spec_min_p 0.7) |
| 10-23 01:15 | A | tune 15m → `cf-single-262k` +24% | 118.4 | — | converged spec_min_p 0.5, done in 6 min |
| 10-23 01:25 | A | bench (tuned) | **155.5** | 59.5 | 262K winner |
| 10-23 01:35 | B | tune 15m → `cf-split-262k` +36% | 94.0 | — | spec_min_p 0.5; base confirms split slower |
| 10-23 01:45 | B | bench (tuned) | 121.3 | 53.6 | loses to A |
| 10-23 02:00 | A | tune thorough 59m → `cf-single-262k-long` +16% | — | — | --host-core last + spec_min_p 0.5 |
| 10-23 03:05 | A | bench (long-tuned) | **152.6** | 62.6 | ≈tie w/ 15m tune on decode; prompt +5%; thorough preset kept (26-run measurement, host-core helps under load) |
| 10-23 03:20 | C | tune 15m → `cf-single-512k` +22% | 113.7 | — | spec_min_p 0.5 |
| 10-23 03:30 | C | bench (tuned) | **143.9** | 54.7 | context 524288 confirmed in server banner |
| 10-23 03:40 | D | tune 15m → `cf-split-512k` +24% | 92.7 | — | spec_min_p 0.5, aux_cpus 1 |
| 10-23 03:50 | D | bench (tuned) | 99.7 | 55.1 | loses to C; split slower at both contexts |
| 10-23 03:55 | C | tune thorough 64m → `cf-single-512k-long` +19% | 117.6 | — | --host-core last + spec_min_p 0.7 |
| 10-23 04:05 | C | bench (long-tuned) | **146.8** | 65.5 | 512K winner; only −4% decode vs 262K |
| 10-23 04:10 | A | server restarted + health OK (local & LAN) | — | — | final state: config A + preset cf-single-262k-long |
| 10-23 09:58 | A | cache bump: prompt-cache 8→12, conv-cache 8→32 GiB, slots 4→12 | — | — | fixes multi-client prompt reprocessing (was parked=4 cap, evictions climbing); preset overlay verified intact (--host-core last in engine cmdline); mirrored into 512k config |
| 10-23 10:40 | all | added top-level `"gpu"` key (1 for single, "0,1" for split) | — | — | Monitor tab reads telemetry card from cfg["gpu"] (server.py:8136), not from args --gpu; without it monitor showed adapter 0 (3080 Ti). Takes effect on next server start |
| 10-23 21:45 | B2 | `--batch 2` bench, 2 streams | 40/stream | — | agg 73.6 tok/s; expert cache 7770→6144 slots; PCIe reads +16% |
| 10-23 21:50 | B2m | `--batch 2 --batch-mtp` bench | 42/stream | — | agg 77.8 tok/s; MTP drafting does NOT recover speed in batch |
| 10-23 21:55 | B4m | `--batch 4 --batch-mtp` bench | 21/stream | — | agg 70.2 tok/s — flat vs B2m |

## BATCH VERDICT (2026-10-23)

Parallel slots **do not add throughput** for this 111 GB MoE: aggregate stays ~70–88 tok/s in every batch layout (vs 152.6 single-stream tuned). The model is expert-fetch/bandwidth bound, not compute bound — streams thrash each other's expert working sets. Batching only buys *latency fairness* (everyone types at once) at the cost of ~2x total throughput. Configs kept: `configs/strata-cyber-frost-batch2.json`, `-batch2m.json`, `-batch4m.json`, `-batch2m-split.json`, `-batch4m-split.json` (untracked by tuned presets — different identity; would need their own tune). Server restored to config A (single-stream) at 23:35.

| 10-23 21:45 | B2 | `--batch 2` bench, 2 streams | 40/stream | — | agg 73.6 tok/s; expert cache 7770→6144 slots; PCIe reads +16% |
| 10-23 21:50 | B2m | `--batch 2 --batch-mtp` bench | 42/stream | — | agg 77.8 tok/s; MTP drafting does NOT recover speed in batch |
| 10-23 21:55 | B4m | `--batch 4 --batch-mtp` bench | 21/stream | — | agg 70.2 tok/s — flat vs B2m |
| 10-23 23:25 | B2mS | split + `--batch 2 --batch-mtp` | 42/stream | — | agg 77.5 tok/s; PCIe reads drop to +2.4% (3080 Ti holds its own 1108-slot cache for layers 0-7) |
| 10-23 23:30 | B4mS | split + `--batch 4 --batch-mtp` | 24/stream | — | **agg 87.4 tok/s — best multi-client**; +25% vs single-GPU batch4 |

Multi-GPU batch note: total expert cache does NOT grow (3080 Ti 1108 slots + 5090 6582 = 7690 ≈ single 7770) — the 3080 Ti's 8 layers eat its VRAM. But PCIe thrash drops 16%→2.4%, which is why split wins at 4 streams. Still −43% vs single-stream throughput.

| 10-24 00:25 | B2mS | tune 15m → `cf-b2m-split` +29% | — | — | spec_min_p 0.5 |
| 10-24 00:35 | B4mS | tune 15m → `cf-b4m-split` +31% | — | — | spec_min_p 0.7 |
| 10-24 00:45 | B2mS | bench tuned, 2 streams | 40/stream | — | agg 77.3 tok/s — unchanged (bandwidth-bound, tune can't help) |
| 10-24 00:50 | B4mS | bench tuned, 4 streams | 24/stream | — | agg 86.3 tok/s — unchanged |

Both multi-client configs are now tuned and ready: `configs/strata-cyber-frost-batch2m-split.json` (preset cf-b2m-split) and `-batch4m-split.json` (preset cf-b4m-split). Presets auto-apply per config. Multi-client mode final: ~24 t/s × 4 streams (batch4) or ~40 t/s × 2 streams (batch2).

## NEXT ACTIONS

**None — campaign complete.** All steps 1–6 done. Server running with config A at http://<YOUR-LAN-IP>:8080 (262K, vision on). To resume tuning later: rerun step 4/5 pattern with `tune-cf.bat` and record here.

---

# DeepSeek-V4.1-Flash (IST-DAS IQ2_XXS 2.00bpw, 256K) — 2026-10-25

Engine: `strata-dsv41.exe` 0.1.51 (install\engine-dsv41), launch preset `ist-das-2-00bpw-256k`.
Layer split auto: 3080 Ti layers 0-17 (762 experts VRAM), 5090 layers 18-39+head (2918 experts), 11680 experts CPU lane (~100 GB).

## Settings applied (preset `extra` + `D:\strata\run-deepseek.bat`)

- `--ssd-cache 120` (GB RAM store for hottest experts; default auto-sized much smaller. Log: 11425 experts / 88.7 GB read in)
- `--prefill-chunk 4096` (default 8192)

## Results (bench_ds.py / bench_ds_prefill.py, 21K-token cold prompt)

| Metric | Baseline (defaults) | Tuned | Δ |
|--------|--------------------|-------|---|
| Decode | 19.4 tok/s | **29.1 tok/s** | +50% |
| Cold prefill 21K | 146.8 tok/s | **534.9 tok/s** | 3.6× |

Notes: conversation slots persist on disk across restarts (`launch\ds4-slots`) — repeat prompts benchmark the cache, use fresh prompts. Engine defaults to 24 CPU threads; untested knob: `--cpu-threads`. Start: `run-deepseek.bat` or `strata launch --preset "IST-DAS-2.00bpw 256K"` (extra is in the preset itself).

## DeepSeek follow-up experiments (2026-10-25 evening)

| Variant | Decode tok/s | Verdict |
|---------|-------------|---------|
| ssd-cache 120 + chunk 4096 (dual-GPU, 48 thr) | **29.1** | FINAL — in preset + run-deepseek.bat |
| + reserve-mib 2048 | 27.8 | worse; Task Manager "shared GPU memory" (~3.9 GB/card) is pinned staging buffers, NOT paging — harmless |
| + cpu-threads 24 (physical only) | 26.8 | worse; SMT helps on Threadripper (unlike the tip's Intel) |
| single 5090 only (--gpus 1 --tp 1) | 26.3 | worse; dual-GPU split helps DeepSeek (3080 Ti holds layers 0-17 + own expert cache, lightens CPU lane) |

Final preset extra: `--ssd-cache 120 --prefill-chunk 4096 --cpu-threads 48`. tp 2 + layer-split auto stay default.
CAUTION: `strata launch --set` values PERSIST into the preset's `extra` — experimental flags must be cleaned from `%APPDATA%\Strata\launch-presets\ist-das-2-00bpw-256k.json` after testing.

## Preset system bypassed (2026-10-25 23:05)

After a Strata update, saved tunings were invalidated ("the graphics card changed"). Per user decision (overclocking experiments; no re-tuning), all tuned values are now HARDCODED as engine args in every config: `--spec-min-p` (0.5 or 0.7 per variant) and `--host-core last` (single-GPU variants). Verified: main config runs 152.1 tok/s with flags in cmdline — identical to preset-tuned speed. Preset warnings at startup are now cosmetic and can be ignored (or delete presets via `strata presets delete`).

## -fixed variants (2026-10-25 23:10)

All 6 configs reverted to clean (no hardcoded tuning). Frozen-tuned copies created as `configs\*-fixed.json` (same logs as originals, model names suffixed -fixed). Daily driver: `cyber-frost-fixed` / [run-cyber-frost-fixed.bat](run-cyber-frost-fixed.bat) → `strata-cyber-frost-windows-fixed.json` (--spec-min-p 0.5 --host-core last). Multi-client fixed: `strata-cyber-frost-batch4m-split-fixed.json`. Plain originals = clean baseline for future re-tunes.

## Abliterated DeepSeek via patched engine (2026-10-26 evening)

**What:** DeepSeek-V4.1-Flash now runs abliterated (far fewer refusals) at FULL speed by projecting the
BoldingBuilds rank-1 refusal-direction adapter out of every layer's attention + MoE writes at runtime.
Nothing on disk changed in the model; no requantization. HumanEval-neutral per the adapter's author
(95.1% → 95.7%, refusals 98.3% → 4.2% on Maya).

**How it was built:**
- Adapter: `D:\strata\adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf` (438 MB, HF BoldingBuilds).
- `--ablate` comes from project-maya PR #469 (JoshBolding, open/not merged). Maya's own engine lacks
  Strata's `--ssd-cache`, so the PR was ported onto **Strata's own source** (github.com/Niko1221/Strata)
  at commit `562a0c2e` (= the exact tree engine 0.1.51 was built from). Patched tree + build:
  `D:\strata\strata-src` branch `ablate-0.1.51` (commit "port --ablate from project-maya PR 469").
- Build toolchain installed this session: VS 2022 Build Tools (MSVC 14.44), CMake 4.4.4, CUDA 13.4
  (the pre-existing `CUDA\v13.2` folder was a 12 KB empty stub — nothing could compile against it).
  Build script: `D:\strata\build-strata-engine.bat` (configure|build). Flags:
  `-DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_DSV41=ON -DSTRATA_PORTABLE=ON -DCMAKE_CUDA_ARCHITECTURES=86;120`.
- Engine binaries live in `%LOCALAPPDATA%\Strata\install\engine-dsv41\0.1.51-windows-x86_64-cuda-cuda13\`:
  `strata-dsv41.exe.stock-0.1.51` (original, 68,197,376 B), `strata-dsv41.exe.ablate` (patched, 76,177,408 B).
  **The launchers swap the active `strata-dsv41.exe` before starting**: run-deepseek.bat restores stock,
  run-deepseek-abliterated.bat copies in the patched one. The Strata component signature/sha256 is NOT
  re-verified at launch — swapping is safe, but a Strata engine UPDATE will overwrite the patched binary
  (rebuild or copy `strata-dsv41.exe.ablate` back in afterwards).

**Usage:** `deepseek-abliterated.bat` (start/status/stop/stats, mirrors deepseek.bat) →
`run-deepseek-abliterated.bat` → preset `IST-DAS-2.00bpw 256K abliterated`
(`%APPDATA%\Strata\launch-presets\ist-das-2-00bpw-256k-abliterated.json`) = tuned preset + `--ablate`.
Engine log confirms: `ds4: abliteration: ... adapter (direction layer 22), scale 1, projected out of every
layer's attention and MoE writes`. Optional `--ablate-scale F` (1 = full removal, >1 over-projects).

**Speed (3 fresh-session runs each, 800 max tokens, warm):**
stock 0.1.51: 25.7 / 26.1 tok/s · patched+ablate: 25.3 / 27.7 / 28.7 tok/s → **parity; ablation is free**
(measured ~3% cost on 4×3090 by the author; below noise here). Beware: the FIRST 1-2 runs after a server
start are 20-30% slower (expert store warming) — earlier "patched is slower" readings were that artifact.

## Native-CPU build experiment — FAILED, portable build kept (2026-10-26 late)

Question: was the patched build's CPU usage/speed hurt by STRATA_PORTABLE=ON (AVX2 baseline, GGML_NATIVE=OFF)?
Measured first, then tested a native build.

**Controlled CPU measurement** (typeperf on strata-dsv41 during a fixed 900-token decode):
patched portable build ≈ 1600 (% Processor Time units, 100 = 1 logical core) ≈ 16 of 48 logical processors
≈ **33% of total CPU — identical to stock**. The earlier "54% vs 34%" reading was situational (benchmark
back-to-back load / warmup), not a build defect.

**Native build** (build-strata-engine.bat configure-native: no PORTABLE, GGML_NATIVE=ON, /arch:AVX2 on
CXX + CUDA host, UCRT+MSVC redist DLLs staged next to the exe): ran but SLOWER — 16.8 then 6.0 tok/s
(vs 25-30 on portable). MSVC's ggml native CPU path on Zen2 is a known-flaky route; not worth chasing.
Reverted. `strata-dsv41.exe.ablate` = the PORTABLE patched build again (verified 24.9 / 30.4 tok/s after
restore). Native experiment binary kept at `D:\strata\strata-src\build-native\Release\` (do not use);
the previous portable build is also backed up as `strata-dsv41.exe.ablate-portable` in the engine dir
(identical to .ablate now). Redist DLLs (api-ms-win-*, ucrtbase, msvcp140*, vcruntime140*, vccorlib140)
were copied into the engine dir for the native test — harmless, leave them.

**Conclusion: the portable build is the final one. CPU% and speed are at stock parity; there is nothing
left to gain from CPU-targeted rebuilds on this box.**

## VRAM reserve for the desktop GPU (2026-10-26 night)

The 3080 Ti drives the Windows desktop AND holds DeepSeek layers [0,17]. Engine default `--reserve-mib 600`
(per GPU) still left it only **212 MiB free** after load (5090: 587 MiB) — Windows was already paging desktop
allocations to shared GPU memory. Event log check (7 days): no TDR/driver resets/DWM hangs; nvlddmkm ID 153
bursts only inside engine load/test windows (incl. the failed native-build test) — no desktop-instability events.

Fix: `--reserve-mib 900` added to BOTH DeepSeek presets (`ist-das-2-00bpw-256k.json` and
`...-abliterated.json`). Result: 3080 Ti free 212 → **439 MiB** (39 experts moved to the 120 GB RAM store),
5090 free 587 → 885 MiB. Speed unchanged or better (36-37 tok/s on the post-restart runs vs 25-30 before).
Note: an earlier `reserve-mib 2048` test cost ~4.5% speed; 900 is the sweet spot.

## Per-GPU VRAM reserves (2026-10-26, second engine patch)

Stock `--reserve-mib N` applies one value to every GPU. Patched the engine (strata-src commit
"--reserve-mib N,M,...: per-GPU VRAM reserves in devs order") to accept a comma list: first value = first GPU
in use, second = second GPU, etc. One value behaves exactly as before (backward compatible).
Sites changed: ds4_model.hpp (Options.reserve_mib_dev), ds4_model.cu (reserve_b(d) helper + all 6 budget
sites), ds4_main.cpp (list parsing, validated whole numbers).

Current setting in both DeepSeek presets: `--reserve-mib 1000,500`
  - CUDA0 = RTX 3080 Ti (desktop): reserve 1000 → **680 MiB free** after load (was 212 at default)
  - CUDA1 = RTX 5090: reserve 500 → 469 MiB free, 2930 experts in VRAM (up from 2883 at uniform 900)
Speed: 35.6 / 36.4 tok/s — same as uniform 900, i.e. the extra desktop headroom is free.
Engine binary updated in place (`strata-dsv41.exe.ablate`, 76,181,504 B); portable build, includes both
patches (--ablate + per-GPU reserve).

## Per-GPU reserve enforced in launchers (2026-10-26)

`run-deepseek.bat` and `run-deepseek-abliterated.bat` now also pass `--set reserve-mib=1000,500` (verified:
the strata CLI forwards the comma value intact; engine cmdline shows `--reserve-mib 1000,500`, 3080 Ti 680 MiB
free / 5090 469 MiB free). The setting now lives in three places: both preset JSONs + both run-*.bat files,
so a preset reset won't lose it. Cyber-frost (Qwen) launchers intentionally untouched — its engine has its own
`--vram-reserve-mib 1600` already, and per the user it doesn't rely on the 3080 Ti.
Caveat: the STOCK dsv41 binary parses "1000,500" as 1000 (atoll stops at the comma) — reserving 1 GB on BOTH
GPUs. Harmless (~60 fewer experts on the 5090); per-GPU only works with the patched engine.

## Zen 2 kernel optimization pass (2026-10-26, ongoing) — maya_zen2_kernel_dossier.md verified + Windows levers

Dossier verification + Windows adaptation appended to maya_zen2_kernel_dossier.md as PART 9. Summary of what the
engine ALREADY does right (no change needed): PDEP avoided on pre-Zen 3 (own AVX2 rows + CPUID family dispatch,
ds4_gg_cpu.cpp:95), no _mm_dp_ps anywhere, 24-thread CPU lane = physical cores.

Backups: D:\strata\backups\2026-10-26-pre-zen2\ (all three engine binaries) + git tag `pre-zen2-work`
(= ablate + reserve-mib patches). Rollback: re-copy any backed-up exe over the active strata-dsv41.exe.

Benchmark method note: `bench_ds.py` wall-clock (300-tok essay prompt, reasoning_effort=low) reads LOWER than the
engine-log method (counting prompt): idle baseline = **20.0 tok/s** bench_ds vs ~35-36 tok/s engine-log. Same-method
A/B only. Real user traffic at 163K context: ~26 tok/s (engine log), CPU lane 3.7% of experts.

### Lever A — MSVC PGO: FAILED (parked)
- /GL on CUDA host code (-Xcompiler=/GL) + /LTCG:PGINSTRUMENT: server loads, first inference crashes
  ("ds4 gguf mv: invalid resource handle", "exl3 mv failed").
- /GL on C++ only: server loads, first inference hangs (no crash lines; request never completes).
- pgosweep/pgomgr staged at VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64; build script kept
  (D:\strata\build-strata-zen2.bat, configure-instrument/configure-pgo) if ever revisited.

### Lever B — large pages for the 120 GB expert store: CODE SHIPPED, awaiting privilege
- Windows never used large pages (Linux gets THP via madvise); MEM_LARGE_PAGES now behind DS4_STORE_LARGE=1,
  fallback to 4 KB with a log line. Commit 4d933bc4 on branch ablate-0.1.51.
- Binary staged as strata-dsv41.exe.zen2lp (76,183,552 B) next to .ablate; active exe untouched.
- New launcher: D:\strata\run-deepseek-abliterated-largepages.bat (existing launchers NOT modified).
- One-time setup for the user: D:\strata\grant-lock-pages.bat (one UAC) then SIGN OUT/IN (no reboot needed).
- Risk cleared: GPU zero-copy (DS4_STORE_ZC) is off and requires exactly 1 GPU — dual-GPU never engages it, so
  large pages can't break GPU visibility. Expect slower server start (120 GB committed+locked up front).
- After sign-in: launch via the largepages bat, expect "RAM store: 120.x GB on 2 MB large pages (locked...)" in the
  engine log, then bench_ds A/B vs 20.0 tok/s.

### Lever C — power plan: switched to High performance (measurement contaminated)
- Was "AMD Ryzen Balanced". bench A/B invalid (user traffic mid-bench: decode collapsed to 3.6-8 tok/s under
  contention, recovered after). Plan left on High performance; re-measure when the box is idle.

### Lever B validation + Lever C clean numbers (2026-10-26 ~23:25)
- SeLockMemoryPrivilege GRANTED to <COMPUTER-NAME>\<WINDOWS-USER> via grant-lock-pages.ps1 (fixed [ushort]->[uint16] for PS5.1).
  Token gets it at next sign-in only.
- zen2lp binary validated live: launched via run-deepseek-abliterated-largepages.bat; engine log shows the expected
  fallback line ("DS4_STORE_LARGE=1 but SeLockMemoryPrivilege is not granted ... - 4 KB pages") and runs normally.
- Clean bench_ds.py decode on the FRESH zen2lp server: 28.1 tok/s (High performance) vs 26.1 tok/s (Balanced) ->
  power plan = ~+7-8%; plan left on High performance. Both well above the 20.0 measured on the OLD long-running
  server (fresh-restart effect ~+6 tok/s; exact attribution uncertain, noted honestly).
- NEXT: after user sign-out/in, restart via the same largepages bat; expect "RAM store: 120.x GB on 2 MB large pages
  (locked, committed up front)" in the engine log + slower start; then bench_ds A/B vs 28.1.

### Lever B — large pages: FINAL (2026-10-26 ~23:40, after reboot)
- Reboot put SeLockMemoryPrivilege in the user token; engine log confirms: "RAM store: 120.3 GB on 2 MB large pages
  (locked, committed up front)". Startup NOT measurably slower (preload still ~18 s).
- bench_ds.py decode A/B (fresh server, High performance both): 4 KB pages 28.1 tok/s -> large pages 28.6 tok/s
  (runs 27.9/28.5/29.4) = noise-level flat. KEPT ON (no cost, maybe +2%).
- 4-stream parallel test (par_ds.py): aggregate 20.4 tok/s = single-stream speed, streams finish one after another ->
  THIS ENGINE SERIALIZES REQUESTS (batch=1, queue). No concurrent-decode TLB scenario exists to exploit.
- WHY FLAT (root cause): in this dual-GPU config the CPU lane computes only ~3.7-4% of experts (engine log) -
  decode is GPU-bound, so CPU-side kernel/TLB levers have almost no headroom. The dossier's levers target
  CPU-bound configs (single GPU / CPU-only); they are correctly implemented but not the bottleneck HERE.
- Net gains this pass: power plan +7-8%, fresh-restart recovery ~+6 tok/s, large pages ~free. PGO parked.
  Rollback: git tag pre-zen2-work; binaries in D:\strata\backups\2026-10-26-pre-zen2\;
  large pages off = launch via run-deepseek-abliterated.bat (no DS4_STORE_LARGE).

### GPU-side: layer split rebalanced toward the 5090 (2026-10-26 ~23:55) — WIN
- Engine's --layer-split flag is ignored (ds4_main.cpp:1306 "this engine balances its own split"); the auto split
  minimizes PROMPT streaming (minimax over VRAM shortfall, ds4_model.cu:2182-2227), NOT the decode pipeline's
  slowest stage. Override exists: DS4_SPLIT=a,b env (trunk layers per group, drafter stays on first card).
- A/B (fresh server, large pages, High performance, bench_ds decode):
  auto 18/22 = 28.6 | 15/25 = 28.9 | **14/26 = 29.9 (best)** | 12/28 = 28.7 tok/s
- Shipped: DS4_SPLIT=14,26 added to run-deepseek-abliterated-largepages.bat (my launcher; user's originals untouched).
  3080 Ti: layers [0,13], 816 experts VRAM, 764 MiB free. 5090: layers [14,39]+head, 2871 experts, 479 MiB free.
- Note: --vram-experts headroom is negligible (~1.2 GB free total ~= +130 of 15360 experts, +0.8%) - not pursued.
  DSpark draft stays off by design (132 GB routed >> 43 GB VRAM; verify rounds would read 3.3x token bytes).

### 5090-only test (more CPU offload) — WORSE, reverted (2026-10-26 ~00:05)
- --gpu 1 (5090 only, all 40 layers + head, 2633 of 15360 experts in VRAM, 12727 on CPU lane, large pages on):
  bench_ds decode 27.3 tok/s vs 29.2-29.9 with dual-GPU 14/26. The 3080 Ti stage earns its keep when given a
  small share (14 layers); pushing more onto the DDR4 CPU lane loses. FINAL = dual-GPU DS4_SPLIT=14,26.

### Stock model gets the same gains (2026-10-27 00:05)
- New D:\strata\run-deepseek-largepages.bat: stock preset ("IST-DAS-2.00bpw 256K") + zen2lp engine binary
  (ablate dormant without the flag) + DS4_STORE_LARGE=1 + DS4_SPLIT=14,26. Stock preset's gpu list verified
  intact [0,1]. run-deepseek.bat untouched as the plain-stock fallback. NOT benchmarked (stock config untested
  tonight; the split was measured on the abliterated preset - same model/weights, expected to transfer).

## 2026-10-27 - DeepSeek vision question: NOT POSSIBLE in Strata 0.1.51 (investigated, reverted)

User hit `400: this server was started without the vision encoder` and asked about CPU vision.
Findings (source-verified in D:\strata\strata-src):
- The dsv41 ENGINE has full vision support (from the Project Maya import): tower loads on the first GPU
  before the layer split (ds4_model.cu load_vision), GENI takes a DSI1 raw-RGB pictures file.
- The Strata API server (serve/server.py) has NO ds4 image path: its vision flow only drives the Qwen-style
  external mmproj encoder (strata-vision), whose embeddings format the ds4 engine does not read.
- docs/DEEPSEEK41.md: "Not in this version: ... pictures (--vision is ignored with a warning)".
- Open feature request: Strata community issue #3937 "Opt-in API image input for DeepSeek-V4.1-Flash-1017
  using the native vision engine". Third-party runtime table (localrigcheck, 2026-10-26): "text only".
- So: no --vision cpu/on/off makes image API work for DeepSeek. Cyber-frost (Qwen) stays the vision model.

What was done and undone:
- Downloaded the vision tower source (970 MB, sha256-verified) into Strata-data\models\vision\ and packed it
  in with tools/dsv41/vision_pack.py + pack_gguf --vision (worked: "vision 0.97 GB" in --pack-info).
- Then REVERTED the pack to D:\strata\backups\2026-10-27-pre-vision-pack\ (ds4.txt/tensors.txt restored):
  the tower would load silently (~0.97 GB on the 3080 Ti) every launch for zero API benefit.
- Kept models\vision\ (970 MB source + vision.bin/json): if a future Strata adds ds4 vision, re-run
  pack_gguf with --vision (recipe in repack log D:\strata\repack-vision.log).
- Removed the ineffective --vision cpu flag from run-deepseek-abliterated-largepages.bat and
  run-deepseek-largepages.bat.
- Server restarted via run-deepseek-abliterated-largepages.bat: loaded in ~75 s, health ok, images:false (by design).

## 2026-10-27 (afternoon) - ds4 NATIVE VISION: built, working, patched server

DeepSeek now reads images through the normal API (OpenAI image_url + Anthropic image blocks) - the
"started without the vision encoder" 400 is gone; /health reports "images": true.

How it works (the engine had everything; the server needed a bridge):
- The pack's own fixture template (serve/fixtures/deepseek41/chat_template.jinja) already writes one
  <|deepseek_image|> (token 129264) per image part, in place, in message+part order.
- New serve/ds4vision.py: sizes each picture the way the tower wants (sides to multiples of 14, span
  nh*(nw+1)+2 <= 1024 image tokens, LANCZOS downscale if bigger), expands each placeholder in the ids to
  its full span (every position carries 129264), writes the engine's DSI1 file (raw RGB + span starts) and
  hands it to the unchanged GENI plumbing. The engine's own tower (0.97 GB, loads on the 3080 Ti / CUDA0
  before the layer split) does the encoding. No mmproj, no external encoder, no CPU path needed.
- server.py: 2 small edits marked "ds4vision" (construct Ds4Vision for arch deepseek41; ds4 branch in
  prepare()). Health/UI see vision non-None, so images advertise automatically.

Measured (RTX 3080 Ti + RTX 5090, abliterated preset, 2026-10-27):
- Decode 28.8-30.0 tok/s vs 29.9 pre-vision baseline = noise, no real cost from the tower's ~1 GB.
- First end-to-end image request: 21 s (encode + prefill + 300 tokens); test image of shapes+text
  described correctly (D:\strata\ds4_test.png).

Versioning / revert:
- Original serve/ tree: D:\strata\backups\2026-10-27-pre-ds4vision\ (full copy + ORIGINAL-HASHES.txt).
- Patch: D:\strata\patches\ds4-native-vision-0.1.51.patch (new file serve/ds4vision.py + 2 hunks).
- Revert = restore serve/ from the backup (or delete ds4vision.py and revert the 2 hunks) + repack
  without --vision if the tower should leave the pack (backup of pre-vision pack metadata:
  D:\strata\backups\2026-10-27-pre-vision-pack\). Pack WITH the tower: current state.
- A `strata update` replacing the control component removes the patch: re-apply the .patch afterwards.
- Vision source kept at Strata-data\models\vision\ (checkpoint shard + vision.bin/json); repack recipe
  in D:\strata\repack-vision2.log.

Limits: max 1024 image tokens a picture (~1260x1260 px); bigger pictures are downscaled. Image URLs,
data: URLs, local paths and tool-result images all supported. Upstream feature request: Strata #3937.

### Vision test matrix (2026-10-27, all passed)
- T1 single image: correct shapes/colors/text read ("42, yellow"). 7.0 s.
- T2 follow-up on same image: correct, 2.3 s (prefix + pixel-hash span cache reuse, no re-encode).
- T3 two images in one message: both identified in the right order (red circle; green triangle). 8.9 s.
- T4 second image mid-conversation: cross-image comparison across turns correct. 9.9 s.
- T5 text-only: unchanged. 1.2 s.
- Known remaining edge (upstream #3937 scope): images inside TOOL RESULTS that the template reorders
  to match tool_calls order may pair with the wrong placeholder. User/assistant images are fine.

### #3937 hardening round (2026-10-27 evening) - validation matrix status
Code: template_image_order() replicates the fixture template's section 1+2 message walk (tool-result merge,
tool_calls-order sort), so the DSI1 payload always pairs with the placeholders the template actually emits;
count divergence fails loudly, never silently. Maya MIT attribution in the ds4vision.py header.
Bugs found and fixed this round: phantom image part (assistant message leaked into the parts list);
_image_source crashes on serve's normalized {"type":"image","source": <string>} parts (own _src_of now).

Tests (real checkpoint, RTX 3080 Ti + 5090, abliterated):
PASSED  single image; two images one message (order); follow-up same image (2.3 s, span cache reuse);
        second image mid-conversation (cross-image compare); text-only unchanged;
        swapped pixels with identical token ids -> engine's FNV pixel hash invalidates reuse (answer tracks
        the new image); tool images in both send orders pair consistently (see note); literal placeholder
        text in a plain message -> rendered as text, answered normally, no corruption.
NOTE    serve 0.1.51 drops tool_call_id when building tool messages (server.py:5808, frontend.py:651), so the
        template's tool_calls-order reorder never fires in practice; arrival order rules on both sides.
        ds4vision carries the transcribed reorder logic for the day a handler preserves the ids.
UNRUN   encoder parity vs DeepSeek's Torch reference (vision_pack.py verified the tower bit-for-bit against
        the official checkpoint instead); upstream CLI/setup opt-in wiring (local patch enables whenever the
        pack has the tower - the pack IS the explicit opt-in); AMD/Mac backends (CUDA-only box here).
Patch: D:\strata\patches\ds4-native-vision-0.1.51.patch (self-contained: ds4vision.py + 2 server.py hunks).
