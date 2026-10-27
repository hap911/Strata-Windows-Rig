#!/usr/bin/env python3
"""Parallel throughput against the RUNNING DeepSeek server. Usage: par_ds.py <key> <streams> [tokens]"""
import json, sys, threading, time, urllib.request

KEY, N, TOK = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]) if len(sys.argv) > 3 else 300
URL = "http://127.0.0.1:8080/v1/chat/completions"
res = [None] * N

def worker(i):
    p = {"model": "deepseek-v4.1-flash", "max_tokens": TOK, "reasoning_effort": "low",
         "messages": [{"role": "user", "content": f"Session {i}. Write a Python function checking palindromes, ignoring case and punctuation, with a docstring and two examples."}]}
    req = urllib.request.Request(URL, data=json.dumps(p).encode(), method="POST",
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=900) as r:
        body = json.loads(r.read())
    res[i] = (body.get("usage", {}).get("completion_tokens", 0), time.perf_counter() - t0)

t0 = time.perf_counter()
ths = [threading.Thread(target=worker, args=(i,)) for i in range(N)]
[t.start() for t in ths]
[t.join() for t in ths]
wall = time.perf_counter() - t0
tot = sum(r[0] for r in res if r)
for i, r in enumerate(res):
    if r: print(f"  stream {i}: {r[0]} tok in {r[1]:.1f}s = {r[0]/r[1]:.1f} tok/s")
print(f"TOTAL: {tot} tok in {wall:.1f}s = {tot/wall:.1f} tok/s aggregate ({N} streams)")
