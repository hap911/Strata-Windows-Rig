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

## Quick path: no build, no JSON editing

If you already installed default Strata and launched a supported stock DeepSeek model once, use the
[guided Windows release](https://github.com/hap911/Strata/releases/tag/windows-rig-0.1.51.3) instead of
the manual steps below. It supports the official IST-DAS 1.75, 2.00 and 2.25 bpw presets on engine
0.1.51. Stop Strata, extract the release, and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-StrataDeepSeek.ps1
strata launch --preset "DeepSeek Vision Abliterated" --yes
powershell -ExecutionPolicy Bypass -File .\Test-StrataDeepSeek.ps1
```

The first command installs the patched engine and server, prepares the pinned adapter and official
vision tower, and creates the preset while preserving your existing launch choices. The last command
checks native vision and the running engine's adapter. Your stock preset is not changed.

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
then edit them: fresh `api_key`, your GPU order, your paths. The presets carry the measured
settings: `--ssd-cache 120 --prefill-chunk 4096 --cpu-threads 48 --reserve-mib 1000,500`
(reserve-mib per-GPU only parses correctly on the patched engine; stock reads just the first
value, which is harmless).

## 2. Patched engine (ablate + per-GPU reserve + large pages)

```bat
git clone -b windows-rig <this repo> D:\strata\strata-src
cd D:\strata\strata-src
windows\build-strata-engine.bat configure
windows\build-strata-engine.bat build
```

Copy the result next to the stock engine (do NOT overwrite stock):

```bat
set ENG=%LOCALAPPDATA%\Strata\install\engine-dsv41\0.1.51-windows-x86_64-cuda-cuda13
copy %ENG%\strata-dsv41.exe %ENG%\strata-dsv41.exe.stock-0.1.51
copy build\Release\strata-dsv41.exe %ENG%\strata-dsv41.exe.zen2lp
```

The launchers swap `strata-dsv41.exe.zen2lp` over the active exe at start and the stock launcher
swaps the stock one back — that is how both variants coexist. A Strata engine update overwrites
the active exe; just re-copy.

## 3. Large pages (one-time)

```bat
windows\grant-lock-pages.bat    rem one UAC prompt
```

Then **sign out and back in** (a reboot works too). Without the privilege the engine logs a line
and falls back to 4 KB pages — harmless, just no gain.

## 4. The abliteration adapter

Download the BoldingBuilds rank-1 L22 GGUF (link in the root README) to
`D:\strata\adapters\DeepSeek-V4.1-Flash-1017-Abliteration-rank1-L22.gguf`. The abliterated
launcher passes it as `--ablate`. The stock launcher doesn't — same weights, two personalities.

## 5. Native vision (optional but recommended)

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

## 6. Run

```bat
windows\run-deepseek-abliterated-largepages.bat   rem daily driver
windows\run-deepseek-largepages.bat               rem stock model, same engine gains
windows\deepseek-abliterated.bat status           rem status / stop / stats helper
```

First start commits ~120 GB to the RAM store and takes 1-3 minutes. The server listens on
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
