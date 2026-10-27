#!/usr/bin/env python3
"""Cold-prefill test with a guaranteed-fresh prompt. Usage: bench_ds_prefill.py <api_key>"""
import json, random, sys, time, urllib.request

KEY = sys.argv[1]
URL = "http://127.0.0.1:8080/v1/chat/completions"
rng = random.Random(time.time())
words = ("quantum lattice harbor meadow cipher turbine orchard ember voxel prism "
         "harbinger quartz nexus willow cobble fathom drift sparrow onyx").split()
filler = " ".join(rng.choice(words) for _ in range(16000))
REQ = {"model": "deepseek-v4.1-flash", "max_tokens": 8, "reasoning_effort": "low",
       "messages": [{"role": "user", "content": filler + "\n\nReply with exactly: OK"}]}

req = urllib.request.Request(URL, data=json.dumps(REQ).encode(), method="POST",
                             headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
t0 = time.perf_counter()
with urllib.request.urlopen(req, timeout=900) as r:
    body = json.loads(r.read())
dt = time.perf_counter() - t0
ptok = body.get("usage", {}).get("prompt_tokens", 0)
print(f"COLD PREFILL: {ptok} tok in {dt:.1f}s = {ptok/dt:.1f} tok/s")
