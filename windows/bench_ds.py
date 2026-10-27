#!/usr/bin/env python3
"""Benchmark the CURRENTLY RUNNING server (no restart). Usage: bench_ds.py <api_key> [label]"""
import json, sys, time, urllib.request

KEY = sys.argv[1]
LABEL = sys.argv[2] if len(sys.argv) > 2 else "run"
URL = "http://127.0.0.1:8080/v1/chat/completions"

def chat(payload, timeout=900):
    req = urllib.request.Request(URL, data=json.dumps(payload).encode(), method="POST",
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = json.loads(r.read())
    return body, time.perf_counter() - t0

DECODE_REQ = {"model": "deepseek-v4.1-flash", "max_tokens": 300, "reasoning_effort": "low",
              "messages": [{"role": "user", "content": "Write a Python function that checks whether a string is a palindrome, ignoring case and punctuation. Include a docstring and two example calls."}]}

# ~8K-token prompt for the prefill test
filler = ("The quick brown fox jumps over the lazy dog near the riverbank while engineers discuss "
          "quantization, memory bandwidth, expert routing, and cache locality in sparse models. ") * 700
PREFILL_REQ = {"model": "deepseek-v4.1-flash", "max_tokens": 8, "reasoning_effort": "low",
               "messages": [{"role": "user", "content": filler + "\n\nReply with exactly: OK"}]}

print(f"== {LABEL} ==")
chat(DECODE_REQ)  # warmup
decs = []
for i in range(3):
    body, dt = chat(DECODE_REQ)
    tok = body.get("usage", {}).get("completion_tokens", 0)
    decs.append(tok / dt)
    print(f"decode run {i+1}: {tok} tok in {dt:.1f}s = {tok/dt:.1f} tok/s")
print(f"DECODE AVG: {sum(decs)/len(decs):.1f} tok/s")

prefs = []
for i in range(2):
    body, dt = chat(PREFILL_REQ)
    ptok = body.get("usage", {}).get("prompt_tokens", 0)
    prefs.append(ptok / dt)
    print(f"prefill run {i+1}: {ptok} tok in {dt:.1f}s = {ptok/dt:.1f} tok/s")
print(f"PREFILL AVG: {sum(prefs)/len(prefs):.1f} tok/s")
