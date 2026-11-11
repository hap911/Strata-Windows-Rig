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

## Speed (to be filled by the live test)

The 0.1.58 build measured on 11-08 (same harness): 31.8-36.9 / 31.7-36.9 tok/s (avg ~34.4) with the
desktop in use, prompts 398.9 tok/s, graph check 128,000 parts byte-identical. The 0.1.59 build's own
numbers are recorded here after its live benchmark.
