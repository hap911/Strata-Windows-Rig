# Journal: upstream 0.2.13 / engine 0.1.59, 2026-11-11

> Working journal for the 2026-11-11 update behind `StrataRig-0.1.59-r1`. Measurements on the reference
> rig (Threadripper 3960X, 192 GB DDR4, RTX 5090 + RTX 3080 Ti that drives the desktop), same harness and
> settings as the earlier journals: 6-turn coding conversation, 400 generated tokens a turn, fresh
> conversation slots each run, `--ssd-cache=135`, `--reserve-mib=1200,100`, `DS4_SPLIT=14,26`,
> `DS4_SETTLE_MS=0`, `DS4_ATTN_GRAPH=1`, the abliteration adapter on.

## The update and the fix

Strata updated the DeepSeek engine to 0.1.59 (release 0.2.13, published 11-09) and deleted the 0.1.58
folder at 12:54. The launcher first fell back to the official engine (no abliteration, no graphs).

**The fix** is in `windows\rig\use-rig-engine.bat` (and the release's `StrataRig.ps1`): when there is no
rig build for the folder's version, the **newest rig build runs in that folder anyway**. The rig engine
accepts the Terminal's command line, which is the only reason a mismatch was refused before; verified
end to end on 2026-11-11 at 15:00 with the 0.1.58 rig build in the 0.1.59 folder: `strata launch` started
it, no "unknown option", the abliteration adapter loaded, `/health` reported `loaded:true` `images:true`,
one completion answered (80 tokens in 3066 ms = 26.09 tok/s, cold first reply), CUDA0 445 MiB free with
the 1200,100 reserve. So upstream engine updates no longer stop the patched engine; the warning says the
build is older, and re-porting onto the newest upstream is optional.

## Rebase onto 0.2.13 / engine 0.1.59

- Upstream diff from 0.2.12 touches only `src/dsv41/sampler_stat_main.cu`, which we do not patch, so
  `port.py` applied **97 of 97 hunks, 0 rejected** onto `strata-0159`.
- llama.cpp pin unchanged (`3cf03257`), so the IQ1_M ggml fix carries over.
- One compile problem: the diagnostic `atexit` lambda added on 11-08 references member counters and
  cannot convert to a plain `void(*)()`; replaced with a periodic stats print inside `attn_graph`
  (diagnostic only, no behaviour change). The build then compiled cleanly for sm_86/89/120 + PTX.
- Installed as `windows\rig\engine\0.1.59` (outside Strata's folders) with the official exe+dll saved in
  `windows\rig\official\0.1.59`; `versions\v26-upstream0159` keeps the source snapshot.

## Speed of the 0.1.59 build (measured 2026-11-11, ~15:50-16:10)

Same harness, same settings (`--ssd-cache=135`, `--reserve-mib=1200,100`, split 14,26, graphs on, adapter on):

| build | total | decode, turns |
|---|---|---|
| 0.1.59 (this release) | **93.7 / 93.6 s** | 29.2–36.8 / 29.0–36.0 (**avg ~32**) |
| 0.1.58 (same patches) | **85 / 86 s** (11-08) | 31.8–37.4 / 31.7–36.9 (**avg ~34.4**) |

Placement is identical (687 experts on the 3080 Ti, 445 MiB free, no drafter loaded), so the 0.1.59 build
is about **5% slower** than the 0.1.58 one. Byte check on 0.1.59: **128,000 parts, 0 differences**.

Graph stats (`DS4_ATTN_GRAPH` counters): over 2,400 decoded tokens there were
**558,000 instantiations, 350,882 in-place updates and 206,954 update failures**. A failure destroys the
executable graph, so the next token instantiates it again - about 36% of launches.

**Root cause of the failures (per-part tally, 2-turn run):** failures by part 0..7 = **6000, 0, 28500, 0,
5992, 0, 28462, 0**. Parts 2 (FFN input, routing, route_publish, shared expert) and 6 (output projections,
allreduce, ablate, hc post) fail on ~89% of their launches; parts 0 (attention projections) and 4 (indexer)
on ~19%; parts 1 (sparse attention), 3 (expert gate/up + down) and 5 (window rows) never fail. Every failure
returns CUDA result code **2 (topology changed)** and the offending node is **type 5 (empty node)**. The
failing parts are exactly those whose captured lambda calls the F16 matrix-vector helper (`mv`, which uses
cuBLAS `cublasGemmEx`); the parts without it never fail. Under CUDA 13.4's relaxed stream capture, cuBLAS's
enqueue is captured as an empty node whose count/position varies per call, so the graph's topology differs
every token and the update fails.

**Cost:** over 186,000 launches the host spent **4,319 ms instantiating, 2,599 ms updating and 6,122 ms
launching** - about 70 us per launch, i.e. tens of milliseconds per token (at ~240 launches a token). The
same overhead exists in the 0.1.58 build (same code, same cuBLAS), so it does not by itself explain the 5%
delta to 0.1.58; that may also include upstream 0.2.13 decode changes (placement was identical).

**Fix candidate, not yet applied:** keep the cuBLAS `mv` calls outside the captured regions (graph only the
engine's own kernels), or cache one executable graph per observed topology variant, so updates succeed and
no instantiation is needed per token. Needs a GPU test window.


(The 0.1.58 build's own counters existed but were only printed at exit, which the harness kills; its
re-instantiation rate is therefore not recorded for comparison.)
