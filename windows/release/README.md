# StrataRig 0.1.54-r1 — patched DeepSeek engine for Strata

Runs DeepSeek-V4.1-Flash-1017 (763B, IST-DAS 2.00 bpw) through [Strata](https://github.com/Niko1221/Strata)
with this repo's engine patches: CUDA-graph decode (~38 tok/s on the reference rig, vs ~26–29 tuned
stock), runtime abliteration (`--ablate`), per-GPU VRAM reserves, a faster CPU expert lane.

**Experimental, authorized research only** — read the
[legal disclaimer](https://github.com/hap911/Strata-Windows-Rig#legal-disclaimer--authorized-research-only).

## Requirements

- Windows 10/11 x64, NVIDIA driver **580.65 or newer**
- NVIDIA **RTX 30, 40 or 50** series (sm_86, sm_89, sm_120; newer cards via PTX). RTX 20 and older are not supported.
- Enough memory for DeepSeek-V4.1-Flash: the reference rig has 44 GB VRAM (5090 + 3080 Ti) and 192 GB RAM;
  with less RAM it runs slower (the setup sizes the RAM expert cache to your machine).
- ~260 GB free disk for the model (Strata downloads it).

## Install

1. Extract this zip anywhere.
2. Double-click **`Setup.bat`**. It:
   - installs official Strata if you don't have it (asks first; the official one-line installer, no admin rights),
   - lets Strata download and set up DeepSeek once if it hasn't yet (asks first; ~250 GB),
   - checks that Strata's DeepSeek engine is **0.1.54** — the version this build is made for — and changes
     nothing if it isn't,
   - stores the patched engine in `%LOCALAPPDATA%\StrataRig`, backs up Strata's official engine exe once,
   - downloads the abliteration adapter (459 MB, MIT, SHA-256 checked),
   - writes `%LOCALAPPDATA%\StrataRig\StrataRig.config.json` sized to your RAM and CPU.
3. Start with **`%LOCALAPPDATA%\StrataRig\Start-DeepSeek-Rig.bat`** (abliterated) or
   **`Start-DeepSeek-Rig-Stock.bat`** (stock model). The server answers on `http://127.0.0.1:8080/v1`
   (OpenAI and Anthropic APIs), as with plain Strata.

## When Strata updates

Strata updates its engine by itself. Each start checks the version: if Strata's engine is no longer
0.1.54, the launcher **does not** swap in this build and runs Strata's official engine instead (no
abliteration, no speed-ups) and tells you so. Install the matching StrataRig release from
[Releases](https://github.com/hap911/Strata-Windows-Rig/releases) to get them back.
`Restore-Official-Engine.bat` puts Strata's official engine back at any time.

## Tuning (`StrataRig.config.json`)

| key | default | meaning |
|---|---|---|
| `ssd_cache_gb` | RAM − 56 GB, max 135 | RAM cache for experts that fit in no GPU — the biggest speed lever |
| `cpu_threads` | logical CPUs | CPU expert lane threads |
| `context` | `256k` | context length |
| `reserve_mib` | (Strata default) | VRAM to leave free, per GPU: `"900,100"` keeps 900 MiB on a desktop GPU |
| `ds4_split` | (engine's own) | layers per GPU, e.g. `"14,26"` for a 12 GB + 32 GB pair |
| `cuda_graphs` | `true` | CUDA-graph decode, the main speed-up (byte-identical output) |
| `large_pages` | `false` | 2 MB pages for the RAM cache; needs "Lock pages in memory"; no measured gain |

Reference settings (RTX 3080 Ti + RTX 5090, 192 GB, Threadripper 3960X): `ssd_cache_gb` 135,
`cpu_threads` 48, `reserve_mib` "900,100", `ds4_split` "14,26".

## What's in the zip

| file | |
|---|---|
| `engine\strata-dsv41.exe`, `engine\strata_kq.dll` | the patched engine (built from branch `windows-rig`, sm_86/89/120 + PTX) |
| `StrataRig.ps1` | setup / start / status / restore |
| `Setup.bat`, `Start-DeepSeek-Rig*.bat`, `Restore-Official-Engine.bat` | double-click wrappers |
| `manifest.json` | the engine version and GPUs this build is for |
| `SHA256SUMS.txt` | checksums of every file |

The engine uses the CUDA libraries (cuBLAS) that Strata's own DeepSeek engine package installs; none are
bundled here. Source, build scripts and all measurements: https://github.com/hap911/Strata-Windows-Rig.
MIT license, as upstream Strata.
