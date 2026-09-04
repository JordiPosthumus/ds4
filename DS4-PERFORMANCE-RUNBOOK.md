# DS4 Vision-Exp performance notes and A/B runbook

This file preserves the evidence needed to compare the 2026-09-01 selected
upstream integration against the immediately preceding production binary. It
is a measurement note, not a production launcher or permission to stop,
restart, load, unload, or benchmark the model. Jordi chooses the test window.

## Durable performance ledger

`local-performance/` is the machine-readable companion to this runbook. Its
read-only collector converts existing server logs into immutable snapshots
containing request, cache, prefill-chunk, and decode-chunk CSVs; exact binary
and source identity; system metadata; and 32K-token context-bucketed summaries.
It does not call, restart, load, unload, or modify DS4.

Use the two evidence tracks for different decisions:

1. Production snapshots detect suspicious drift, changed cache reuse, cold
   starts, and contention. They are observational because prompt bytes and MoE
   expert routing differ. A live movement of one percent is a watch item, not
   proof of a regression.
2. Fixed-input `ds4-bench` CSVs are the acceptance evidence for a performance
   change. Alternate binaries in A-B-B-A order and preserve the manifest,
   environment, and output-equivalence result.

The first structured production snapshot is
`local-performance/snapshots/20260901-2055-2116-current-production/`. In an
interval with no observed external MLX/MPS model work, it recorded:

- 160K-192K steady decode: median 28.34 t/s across 87 complete 50-token chunks;
- 192K-224K steady decode: median 26.17 t/s across 149 chunks;
- 160K-192K full prefill chunks: median 258.015 t/s across 8 chunks;
- 9 warm starts and 1 cold start, with 85.083% weighted prompt reuse;
- three connected Pi processes and one-active-request admission, so queueing
  affected responsiveness even though execution itself was uncontended.

`local-performance/reference-baselines.csv` preserves the older A/B values in
machine-readable form and explicitly marks the 16:42 MLX-overlapped results as
invalid for regression decisions. See `local-performance/README.md` for the
capture and comparison commands. Future binary changes should get a snapshot
before and after, plus a controlled benchmark when the change can affect model
math, kernels, scheduling, or throughput.

## Binaries under comparison

| Label | Source / file | SHA-256 | Scheduler at startup |
| --- | --- | --- | --- |
| A: immediately before | source rollback `codex/backup-production-pre-pr-evals-20260901T191805Z` at `7c33149`; binary `ds4-server.bak-20260901T193036Z` | `78371b696c93c68321bc41b0dacdb3a7fba01fa5a3f36cb6b9e9c575a6a81ae3` | `resident_sessions=10 max_active_requests=1 prefill_quantum=2048 mixed_prefill_quantum=64` |
| B: selected integration | `codex/main-vision-production-candidate` at `2975454`; installed `ds4-server` | `3997c853b16960726a38f724c35c7445e49eb024ee7934fb720717302ec12ac1` | `resident_sessions=10 max_active_requests=1 prefill_quantum=4096 mixed_prefill_quantum=64` |

The model, vision encoder, 384,000-token context, 4096 engine prefill cap,
ten resident KV slots, one active request, 64-token mixed quantum, cache
directory, and disabled rewind reuse were otherwise the same.

## Preserved pre-change observations (A)

Captured from the production run that started at 14:18:11 local time. The
request used the same `147456`-token disk checkpoint later hit by B:

```text
kv cache hit text tokens=147456 ... load=387.8 ms
chat ctx=147456..195834:48378 TOOLS prompt start
```

Comparable cumulative prefill measurements:

| Suffix progress | Context frontier | A average prefill |
| ---: | ---: | ---: |
| 4,096 | 151,552 | 283.37 t/s |
| 8,192 | 155,648 | 282.35 t/s |
| 16,384 | 163,840 | 278.87 t/s |
| 32,768 | 180,224 | 270.19 t/s |
| 40,960 | 188,416 | 265.97 t/s |
| 45,056 | 192,512 | 264.06 t/s |

Representative uncontended decode observations from the same run:

- `ctx=186841..187369`, 528 generated tokens: `27.20 t/s` average.
- `ctx=190831..194514`: after a brief slow opening, 50-token chunks settled
  at approximately `27.2 t/s` through the end of a 3,683-token generation.
- Several other clean stretches between roughly 160K and 190K context were
  also stable around 27–28 t/s. Transient 5–16 t/s stretches occurred when
  other machine work was active and must not be used as the idle baseline.

## Raw post-change observations (B), invalid as an idle A/B

B started listening at 16:42:44 local time. It hit the identical checkpoint:

```text
kv cache hit text tokens=147456 ... load=624.1 ms
chat ctx=147456..203170:55714 TOOLS prompt start
```

| Suffix progress | Context frontier | B average prefill | B versus A |
| ---: | ---: | ---: | ---: |
| 4,096 | 151,552 | 254.15 t/s | -10.31% |
| 8,192 | 155,648 | 253.12 t/s | -10.35% |
| 16,384 | 163,840 | 250.04 t/s | -10.34% |
| 32,768 | 180,224 | 243.08 t/s | -10.03% |
| 40,960 | 188,416 | 239.49 t/s | -9.96% |
| 45,056 | 192,512 | 237.80 t/s | -9.95% |

Decode was consistently about 14.1 t/s:

- `ctx=194724..195720`, 996 generated tokens: `14.04 t/s` average.
- `ctx=196004..197406`, 1,402 generated tokens: `14.12 t/s` average.
- `ctx=205392..205976`, 584 generated tokens: `14.13 t/s` average.

Those raw figures are roughly 10% worse for prefill and 48% worse for decode,
but they are confounded and must not be attributed to B.

### Confirmed confounder

An independent MLX/Metal speech-transcription job started at 16:40:38, two
minutes before B, and overlapped every B sample above:

```text
PID 25074
python -u -m assistant.transcribe
--file /Users/jordiposthumus/Assistant/recordings/2026-09-01/15-31-47-267.wav
RSS approximately 8 GB
```

`lsof` showed `mlx`, `libmlx.dylib`, `mlx.metallib`, and active Apple Metal
shader caches in that process. It consumed roughly 50–72% of one CPU core,
while the machine remained about 87% CPU-idle and 66% memory-free. The likely
shared bottleneck was therefore GPU/unified-memory bandwidth, not CPU or RAM
capacity. No Qwen Image MPS process was present. The transcription job was not
stopped or modified.

Consequently, the raw B numbers prove that external MLX work materially affects
DS4; they do not prove that the selected DS4 changes regress performance.

## First clean live observation after the confounder ended

At 18:18–18:21 local time on 2026-09-01, process inspection found no
`assistant.transcribe`, Qwen Image MPS, or other obvious MLX/MPS model job.
Memory was 97% free, the service remained at one active request, and requests
ran sequentially without overlapping decode/prefill work. Three long decode
stretches were stable:

- `ctx=164429..167264`, 2,835 generated tokens: `28.92 t/s` average.
- `ctx=167308..168569`, 1,261 generated tokens: `28.88 t/s` average.
- `ctx=169384..170723`, 1,339 generated tokens: `28.68 t/s` average.

The closest preserved A observation is `ctx=166055..167279`, 1,224 generated
tokens at `28.02 t/s`. B's `28.92 t/s` in the same context neighborhood is
about 3.2% faster. This is strong evidence that the decode-kernel integration
is working as intended once external Metal contention is removed. It is still
an observational production comparison rather than the alternating fixed-input
A/B below.

Only short 40–643-token suffix prefills occurred in this clean window. They are
dominated by fixed overhead and cannot validate the 2048-versus-4096 idle
prefill scheduler change; that remains part of the formal speed run.

## Formal no-contention speed run

Run only after Jordi explicitly approves the window and all ordinary model
work is idle.

1. Preserve the production state.
   - Record the installed binary hash, source head, launchd arguments, PID,
     cache directory, free memory, compressor/swap state, and thermal state.
   - Do not change the model, quantization, context, sampling profile, ten
     resident slots, one-active-request cap, or rewind setting.
   - Use a dedicated benchmark KV directory so the production checkpoint pool
     is not polluted or evicted.

2. Prove the machine is uncontended before every trial.
   - No `assistant.transcribe`, Qwen Image MPS, other MLX/MPS process, second
     local model server, model download/copy, or Spotlight/storage scan doing
     material work.
   - Confirm CPU idle, memory pressure, swap delta, and that DS4 has no queued
     or active request before starting.
   - A process merely being resident is not enough to disqualify a trial; an
     active Metal client or changing memory/swap/thermal state is.

3. Use one fixed request fixture for both binaries.
   - Prepare a deterministic synthetic OpenAI request outside the production
     cache: a stable large prefix/checkpoint plus a fixed suffix large enough
     to measure at the same 4,096 through 45,056-token frontiers above.
   - Use an explicit seed and the production sampling settings for decode, with
     a sufficiently long requested completion. Preserve the exact request bytes
     and response token/text result for equivalence checking.
   - Warm model pages before timing. Exclude model load, page warmup, checkpoint
     creation, and the first cache load from kernel throughput measurements;
     report them separately.

4. Alternate binaries rather than running all of one first.
   - Preferred order: A, B, B, A (or A, B, A if time is limited).
   - Restart only with explicit approval, wait for readiness and idle thermal
     state, and verify the binary SHA after every switch.
   - Never run A and B simultaneously.

5. Record separately:
   - disk checkpoint load time and exact hit token count;
   - cumulative and per-chunk prefill t/s at identical context frontiers;
   - time to first generated token;
   - decode t/s in 50-token chunks, reporting the first 100 tokens separately
     from steady state;
   - total wall time, output token count, cache stores, errors, memory pressure,
     and swap delta;
   - exact output equivalence with the explicit seed.

6. Interpret conservatively.
   - The 4096 idle scheduler change should not be called a win unless matched
     trials beat or at least equal A; its upstream M3 Ultra result was only a
     small few-percent effect.
   - The three decode kernel changes are intended to be bit-exact and modestly
     faster. A repeatable B regression greater than 2% warrants an isolated
     bisection of those three commits rather than acceptance.
   - If B remains near 14 t/s with all competing Metal clients absent while A
     returns near 27 t/s, immediately treat that as a real regression and
     retain A as the production rollback.
   - If both recover to their uncontended range, the earlier slowdown belongs
     to shared Metal/unified-memory contention, not the integration.

## Candidate bisection if B fails

The performance-affecting changes can be isolated without mixing cache and
correctness work:

1. `f8f8b77` — branch-free E4M3FN rounding.
2. `acf3ffa` — final matvec reduction only in simdgroup 0.
3. `08bf164` — `simd_max` FP8 KV amax reduction, plus local width guard
   `2975454`.
4. `81049d6` — idle scheduler follows the 4096 engine cap (prefill only).

The response-ID change, tool-role image parsing, and KV model-weight
fingerprint are not decode-loop performance candidates. Do not withdraw or
alter those merely because a contended run was slow.
