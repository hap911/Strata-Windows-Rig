# Windows setup walkthrough

> [!WARNING]
> **AUTHORIZED RESEARCH ONLY:** Use this experimental software only for research and defensive
> security testing in environments you own or have explicit permission to test. Never use it for
> unlawful, harmful or unauthorized activity. Uncensored output may be harmful or wrong. You are
> responsible for your use and generated output. The software is provided **"as is", without
> warranty**; to the maximum extent permitted by law, the authors and contributors disclaim all
> liability. Read the [full legal disclaimer](../README.md#legal-disclaimer--authorized-research-only).

How to reproduce this rig from a bare Windows 11 machine. Paths below are the ones on the
reference machine (`D:\strata`, Strata in `%LOCALAPPDATA%\Strata`) — adjust to yours.

Reference hardware: Threadripper 3960X 24c/48t, 192 GB RAM, RTX 5090 32 GB + RTX 3080 Ti 12 GB,
NVMe. It will run on less (single GPU, 128 GB RAM) at lower speed; the `--ssd-cache` size and
`DS4_SPLIT` are the first things to retune.

**Current base: upstream Strata 0.2.13 / DeepSeek engine 0.1.59** (rebased 2026-11-11). The engine
has CUDA-graph decode (~34.5 tok/s average on the reference rig with the desktop in use, ~38 on a quiet
desktop; up from ~26–30). What changed:
[root README notes](../README.md#notes--2026-11-11-upstream-0213--engine-0159-the-rig-runs-in-any-engine-folder).

## Quick path: the StrataRig release (no compiler)

Download [StrataRig-0.1.59-r1](https://github.com/hap911/Strata-Windows-Rig/releases/tag/StrataRig-0.1.59-r1),
extract it and run `Setup.bat`. It installs official Strata if missing, lets Strata set up DeepSeek once, installs the
patched engine and adapter (if Strata's engine is a newer version, it installs anyway and warns - the launchers run the
newest rig build in that folder). Details:
[release/README.md](release/README.md). Older releases remain for their engine versions.

The rest of this page is the manual build and tuning walkthrough.

## 0. Prereqs

- [Strata Terminal](https://github.com/Niko1221/Strata) installed (PowerShell:
  `irm https://github.com/Niko1221/Strata/releases/latest/download/install.ps1 | iex`), then open
  a new terminal so `strata` is on PATH.
- For building the patched engine: Visual Studio 2022 Build Tools (MSVC 14.44+), CMake, and the
  CUDA 13 toolkit. Skip the build if you only want the stock engine + scripts.
- The model files from the links in the [root README](../README.md). Nothing model-sized is in
  this repo.

## 1. Stock DeepSeek first

Let Strata download and pack the model the normal way (this also creates the preset):

```bat
strata launch --family deepseek41 --yes --no-tui
rem pick: IST-DAS 2.00bpw, 256K context, both GPUs
```

Verify it serves, note the speed (~19-20 tok/s stock), stop it: `strata launch --stop`.

Copy the two tuned presets from [`presets/`](presets/) into `%APPDATA%\Strata\launch-presets\`,
then edit them: fresh `api_key`, your GPU order, your paths. The launchers pass the measured
settings on top: `--ssd-cache 135 --prefill-chunk 4096 --cpu-threads 48 --reserve-mib 1200,100`
(per-GPU reserve-mib only parses on the patched engine; 1.2 GB on the GPU that drives the desktop keeps
it out of memory pressure — at 900 MiB, with a browser open, decode measured ~24.5 instead of ~34.5
tok/s). Lower `ssd-cache` if you have less than 192 GB of RAM.

## 2. Patched engine (ablate, per-GPU reserve, large pages, CUDA graphs)

```bat
git clone -b windows-rig https://github.com/hap911/Strata-Windows-Rig D:\strata\strata-src
cd D:\strata\strata-src
windows\build-strata-engine.bat configure
windows\build-strata-engine.bat build
windows\build-strata-engine.bat install
```

`configure` also drops the IQ1_M CPU-kernel fix into the downloaded ggml
([patches/ggml-iq1m-simd-signs.patch](patches/ggml-iq1m-simd-signs.patch)). `install` copies the build
into `windows\rig\engine\<version>\` — **outside Strata's folders, so an engine update cannot delete it** —
and saves the official exe+dll of the matching folder into `windows\rig\official\<version>\`.
The launchers switch the rig build in at every start (see the next section); `restore-official-engine.bat`
puts the official one back.

**After a Strata engine update** (Strata does this by itself and deletes the old engine folder):
the launchers find the new folder, see there is no rig build for its version, and start the OFFICIAL
engine (no abliteration, no graphs) with a message saying so — they never swap in a mismatched build,
which is what broke the setup on 2026-11-08. To get the patches back: pull this repo, rebuild if the
engine version changed, and run `windows\build-strata-engine.bat install` again. `strata components
rollback` can also return Strata's engine to the previous version from the signed feed.

## 3. Large pages (one-time)

```bat
windows\grant-lock-pages.bat    rem one UAC prompt
```

Then **sign out and back in** (a reboot works too). Without the privilege the engine logs a line
and falls back to 4 KB pages — harmless. Measured on the reference rig, large pages give **no speed
change** (80.6/79.9 s vs 79.8/79.7 s on the 6-turn test); they lock the RAM store and slow the start a
little, so this step is optional. The log line `RAM store: ... on 2 MB large pages` confirms they are on.

## 4. The abliteration adapter

Download the BoldingBuilds rank-1 L22 GGUF (link in the root README) to
`D:\strata\adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf`. The abliterated
launcher passes it as `--ablate`. The stock launcher doesn't — same weights, two personalities.

## 5. Native vision

Upstream Strata ships DeepSeek vision since 0.2.7: the launchers pass `--vision on` and there is no
server patch to apply anymore. The steps below are for the legacy 0.1.51 setup only.

1. Download the official vision shard (~970 MB) from the DeepSeek-V4.1-Flash-1017 checkpoint
   into `%LOCALAPPDATA%\Strata\Strata-data\models\vision\`.
2. Repack the model pack with the tower — exact, verified recipe in
   [docs/repack-vision2.log](docs/repack-vision2.log) (`tools/dsv41/vision_pack.py` + pack_gguf
   `--vision`; the pack grows by 0.97 GB).
3. Apply the server patch to the installed control component:

   ```bat
   cd %LOCALAPPDATA%\Strata\components\control\0.1.51
   git apply D:\strata\strata-src\windows\patches\ds4-native-vision-0.1.51.patch
   ```

   (Back up `serve\` first. A `strata update` that replaces the control component removes the
   patch — re-apply afterwards.)

`/health` should now report `"images": true`.

## Strata's own updates

- `strata launch` does not update the engine by itself unless the installed engine is older than what
  the model needs (Strata's `MIN_ENGINE`, 0.1.46) — a rig build reports the version it was built from
  (0.1.58 now), so launches leave it alone.
- `strata update` (or an app update) replaces the engine and deletes the old folder. That is a manual
  step: after it, the launchers **run the newest rig build in the current folder anyway** (the rig engine
  accepts the Terminal's command line, verified against a newer folder) and warn that the build is older.
  So the patches keep working across upstream updates; re-porting onto the newest upstream is optional.
  The rig builds live outside Strata's folders and are never lost.
- If you want to hold the engine at its current version anyway, point Strata at a local feed with
  `STRATA_UPDATE_FEED=<dir>` (a signed feed folder); `strata update` then finds nothing newer there.

## 6. Run

```bat
windows\run-deepseek-abliterated-largepages-graphs.bat        rem daily driver (CUDA graphs on)
windows\run-deepseek-largepages.bat                           rem stock model, same engine gains
windows\run-deepseek-abliterated-largepages.bat               rem abliterated without graphs (A/B only)
windows\run-deepseek-abliterated-largepages-whole-expert.bat  rem whole-expert experiment (~1-2% slower)
windows\deepseek-abliterated.bat status                       rem status / stop / stats helper
windows\restore-official-engine.bat                           rem put Strata's official engine back
```

| Launcher (engine 0.1.58 base, reserve 1200,100) | 6-turn test | decode |
|---|---|---|
| `run-deepseek-abliterated-largepages-graphs.bat` | ~85 s | ~34.5 tok/s with the desktop in use (30.8–37.4); ~38 on a quiet desktop |
| `run-deepseek-abliterated-largepages-whole-expert.bat` | ~+1-2% slower | ~33–34 tok/s |
| `run-deepseek-abliterated-largepages.bat` (no CUDA graphs) | ~100 s | ~26–27 tok/s |
| previous launcher (before 2026-10-30) | ~119 s | ~26 tok/s |

6-turn coding conversation (2.7K + 5×0.2K prompt tokens, 400 generated each turn), fresh cache each
run, the launchers' settings, reference rig. The 3080 Ti drives the desktop: with a browser open its
kernel gaps grow (~7 ms/token) and with a 900 MiB reserve they grew to ~11 (memory pressure) — the
1200 MiB reserve is what keeps decode at ~34.5.

First start commits ~135 GB to the RAM store and takes 1-3 minutes. The server listens on
`127.0.0.1:8080` (OpenAI + Anthropic APIs); use `--access lan` in the preset if other machines
need it, and keep the API key set.

## Verify against my numbers

```bat
python windows\bench_ds.py <your-api-key>          rem decode tok/s, same method as the journal
python windows\bench_ds_prefill.py <your-api-key>  rem cold-prefill tok/s on a 21K prompt
python windows\par_ds.py <your-api-key>            rem multi-stream behaviour
```

Same-method comparison only: the wall-clock benchmark reads lower than the engine-log counting
method (both are in [docs/TUNING-STATE.md](docs/TUNING-STATE.md) — that journal records every
measurement, every failed experiment, and every rollback point).
