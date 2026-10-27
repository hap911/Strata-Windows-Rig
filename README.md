# Strata — experimental Windows rig build

**Status: experimental version.** Expect bugs, rough edges and breaking changes. This is a research
snapshot, not a stable or production-ready release. Test it in an isolated environment and keep backups.

**Author of the Windows rig patches, scripts, presets and documentation:** hap911
(<lvesely911@gmail.com>). Upstream Strata and third-party components remain credited to their
respective authors; this notice does not claim authorship of their work.

**A 763-billion-parameter model, uncensored, with vision, at 262K context — chatting at ~30 tokens
per second on a desktop PC.** No datacenter. No API bill. One RTX 5090, one RTX 3080 Ti, 192 GB of
RAM, and a pile of patches on top of [Strata](https://github.com/Niko1221/Strata).

This snapshot is the exact state my machine runs. The engine patches are included in this source
snapshot; the Windows scripts, presets and docs live in [`windows/`](windows/). Model weights are
**not** in this repo — links below.

> [!WARNING]
> ## Legal disclaimer — authorized research only
>
> **This experimental software is provided solely for legitimate research, security testing and
> defensive work in environments that you own or have explicit permission to test.** If you do not
> own a system, obtain the system owner's authorization before testing it. Permission must cover the
> systems, data, accounts and activities involved.
>
> **Do not use this software or any model output to violate the law, breach computer systems,
> evade access controls, steal or expose data, harm people, infringe rights, or interfere with
> services.** This software is not a penetration-testing authorization, and no part of this
> repository grants permission to test any third-party system.
>
> Abliteration and uncensored operation can remove safety behavior. Model output may be harmful,
> unlawful, misleading or wrong. **You are responsible for reviewing output, applying appropriate
> safeguards, complying with applicable laws and third-party licenses, and for every consequence of
> your use.** Do not deploy this software in production, safety-critical systems or public-facing
> services without your own security review and controls.
>
> **THE SOFTWARE AND ANY GENERATED OUTPUT ARE PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT ANY
> WARRANTY OF ANY KIND, EXPRESS OR IMPLIED. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE
> AUTHORS AND CONTRIBUTORS DISCLAIM ALL LIABILITY FOR ANY CLAIM, LOSS, DAMAGE, COST OR OTHER
> CONSEQUENCE ARISING FROM OR RELATED TO THEIR USE, MISUSE OR INABILITY TO BE USED. USE THEM
> ENTIRELY AT YOUR OWN RISK. IF YOU DO NOT ACCEPT THESE TERMS, DO NOT USE THIS SOFTWARE.**

> The upstream project, its docs and its license: [README.upstream.md](README.upstream.md).
> Everything here stays MIT, same as upstream. The Maya-sourced pieces carry their own MIT
> attribution in the file headers.

---

## What this box does

| | **DeepSeek-V4.1-Flash-1017** (the reason for this fork) |
|---|---|
| Size | 763B total / ~16B active MoE, 2.00 bpw (IQ2_XXS, 249 GB) |
| Context | 262,144 tokens |
| Decode, single stream | **~29–30 tok/s** |
| Prefill, maximum in local serve log | **772.1 tok/s** |
| Refusals | abliterated at runtime (see below) |
| Vision | **yes — native tower on the 3080 Ti** (patched in; upstream ships text-only) |
| Multi-client | serial queue |

Measured on: Windows 11, Threadripper 3960X (24c/48t), 192 GB DDR4, RTX 5090 32 GB +
RTX 3080 Ti 12 GB (drives the desktop), NVMe. The benchmark numbers are from
[windows/docs/TUNING-STATE.md](windows/docs/TUNING-STATE.md) — a running journal with the full
methodology, the failures (PGO, native MSVC build, layer-split traps), and the rollback points.
The prefill maximum is the highest of 1,778 completions in the active local serve log: 54,986 new
tokens read in 71.213 s, with another 10,767 prompt tokens reused. The highest rate with zero
reused tokens is **741.8 tok/s** (70,962 tokens in 95.661 s).

For scale: DeepSeek-V4.1-Flash is roughly twice the size of what fit in a high-end workstation a
year ago. 20 tok/s is the floor with a completely full 250K context. It reads images, follows
multi-turn conversations across turns, and answers questions stock DeepSeek refuses.

## The uncensored part

The weights on disk are the stock IST-DAS quant. The uncensoring is a **rank-1 abliteration
adapter** (438 MB) that the engine projects out of every layer's attention and MoE writes *at
runtime*, each launch, in milliseconds — no requantization, no 250 GB rematerialize, fully
reversible by launching without the flag.

- Adapter: [BoldingBuilds/DeepSeek-V4.1-Flash-1017-Abliteration-LoRA-GGUF](https://huggingface.co/BoldingBuilds/DeepSeek-V4.1-Flash-1017-Abliteration-LoRA-GGUF) (refusal direction, layer 22).
- Runtime support: `--ablate <file>` ported from project-maya PR #469 onto Strata's engine
  (included in this snapshot). `--ablate-scale` tunes the strength.
- Adapter author's measurements on Maya: refusals 98.3% → 4.2%, HumanEval 95.1% → 95.7%
  (capability-neutral). On this rig, ablation costs **zero speed** (25.3–28.7 vs 25.7–26.1 tok/s
  stock, same-session A/B).

This build is meant only for authorized security research and defensive testing under the legal
disclaimer above. You are responsible for what you generate.

## The engine patches (this snapshot vs upstream 0.2.6 / engine 0.1.51)

1. **`--ablate`** — runtime abliteration adapters (port of project-maya PR #469, MIT).
2. **`--reserve-mib N,M,...`** — per-GPU VRAM reserves in device order, so the 3080 Ti that also
   drives the Windows desktop keeps 1 GB free while the 5090 keeps 0.5 GB. One value behaves
   exactly as upstream.
3. **`DS4_STORE_LARGE=1`** — the ~120 GB expert RAM store goes on 2 MB large pages on Windows
   (with a clean 4 KB fallback when SeLockMemoryPrivilege is missing).
4. **Native DeepSeek vision in the API server** — `serve/ds4vision.py` + two small `server.py`
   hunks: sizes pictures the way the tower wants, expands the chat template's `<|deepseek_image|>`
   placeholders to full spans, and feeds the engine's GENI/DSI1 path. Upstream 0.1.51 ships the
   dsv41 engine with the full Maya vision tower but no server route to it
   ([issue #3937](https://github.com/Niko1221/Strata/issues/3937)); this closes that gap locally.
   Also available as a self-contained patch: [windows/patches/ds4-native-vision-0.1.51.patch](windows/patches/ds4-native-vision-0.1.51.patch).

Plus the environment levers that don't need code: `DS4_SPLIT=14,26` layer split rebalanced toward
the 5090 (29.9 vs 28.6 tok/s on the engine's auto split), `--ssd-cache 120` (the big one: 21 → 39+
tok/s territory by keeping the CPU-lane experts in RAM instead of re-reading ~65 GB from SSD per
answer), `--prefill-chunk 4096`, `--cpu-threads 48`, High performance power plan.

## Vision that actually works

The official 0.97 GB vision tower from the DeepSeek checkpoint is packed into the model pack and
loads on the 3080 Ti before the layer split. Images come in through the normal OpenAI
(`image_url`) and Anthropic (`image` block) APIs — URLs, data URIs, local paths, tool results.

Real-checkpoint test matrix (all passing, details in the tuning journal): single image, two
images in one message in order, follow-up on the same image in 2.3 s (span cache, no re-encode),
cross-image comparison mid-conversation, pixel-hash cache invalidation when the pixels change
under identical tokens, text-only requests unchanged. Decode cost of carrying the tower: none
measurable (28.8–30.0 vs 29.9 tok/s baseline).

## Models (download links, not in this repo)

- Language model: [ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF](https://huggingface.co/ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF) — the IQ2_XXS 2.00 bpw file (~249 GB).
- Vision tower: the official vision shard from the DeepSeek-V4.1-Flash-1017 checkpoint (~970 MB);
  repack recipe in [windows/docs/repack-vision2.log](windows/docs/repack-vision2.log).
- Abliteration adapter: [BoldingBuilds rank-1 L22 GGUF](https://huggingface.co/BoldingBuilds/DeepSeek-V4.1-Flash-1017-Abliteration-LoRA-GGUF) (~438 MB).

Model licenses (DeepSeek etc.) apply to the weights and are between you and the model authors.

## Run it

### Easiest: prebuilt engine + guided setup

Start with the default Strata Terminal and a stock DeepSeek model you have launched once. The guided
setup supports the official IST-DAS 1.75, 2.00 and 2.25 bpw presets on engine 0.1.51. Stop Strata,
download and extract the
[guided Windows release](https://github.com/hap911/Strata/releases/tag/windows-rig-0.1.51.3), then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-StrataDeepSeek.ps1
```

The setup installs the patched engine and vision server with backups, downloads and verifies the pinned
adapter and official vision tower, adds the tower to the model pack, and creates a new preset. It keeps
your GPU, context, port, API key and tuning choices. The stock preset stays unchanged. No compiler or
JSON editing is needed.

Start the new preset with the normal Strata command:

```bat
strata launch --preset "DeepSeek Vision Abliterated" --yes
```

Then check the running setup from the extracted release folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-StrataDeepSeek.ps1
```

The read-only check requires `/health` to report `images=true`, checks the engine's `--ablate` argument,
and verifies the adapter's size and SHA-256. Point anything OpenAI-compatible at
`http://127.0.0.1:8080/v1` (or the port preserved from your stock preset).

### Build it yourself

The full manual walkthrough, including the one-time large-pages privilege and build scripts, is in
**[windows/README.md](windows/README.md)**. The short version:

```bat
rem one-time, admin: allow large pages, then sign out/in
windows\grant-lock-pages.bat

rem patched engine (once per Strata engine update)
windows\build-strata-engine.bat configure
windows\build-strata-engine.bat build

rem daily driver
windows\run-deepseek-abliterated-largepages.bat
```
