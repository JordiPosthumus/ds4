# Spark GB10 production integration

## 2026-09-05 visual-attention memory hardening — rollout in progress

PR #984 (upstream head 40f7f022) is integrated here. Only the CUDA visual
attention score/output workspace changes: above 256 MiB of scores it processes
up to eight independent heads at a time, preserving full attention keys/masks
and precision. Unsplit calls keep their original batch size and unpack kernel.
No model, sampling, context/output, residency/concurrency, launcher, cache,
warm-weight or reserve settings change. All settings listed below remain.

The original 140127-token image request asked for an 18.13 GiB allocation;
the protected candidate replay completed with a 2.33 GiB largest allocation.
This fixes that reproduced workspace failure, not every possible OOM. Final
GB10 tests cover full-output byte comparisons, two input families, ragged groups,
wrapped/image/mask boundaries, 262144 frontier, independent scalar references,
CUDA memcheck/synccheck (zero errors), existing CUDA/server tests, and four
restores of a real image-conditioned 36K prompt. All 4,266,240 final model logits
match baseline through 32 teacher-forced decode steps. CPU/default Mac builds
passed without loading a model there. Affected large attention-call speedups
are 3.85–6.13%; no whole-model decode speedup is claimed.

Final CUDA source SHA256:
a6055b7208f27706e5f2ca066bfda42917ff35e8797e08599a68e8ddf6026083.
Tested Spark 2 server SHA256:
24b20977f11b1c98ab33ffd22fa7cd46364ccb76c81db0d54ad6601af109d3a1.
Spark 2 rollback backup: /home/jordi/ds4-backups/visual-memory-20260905.iN1TA4.
This source is prepared for sequential deployment; live installation, genuine
text/image cold-to-warm acceptance and DSG handback must still be recorded for
each machine before declaring rollout complete. Never clear quarantine manually.

## Previous validated production state

This branch is the Spark integration, not the Mac production branch. The
2026-09-05 shared-scale padding follow-up is deployed on both Sparks. Each
passed installed regressions, effective-configuration and real text/image
cache checks, then returned to DSG healthy, undrained and unquarantined.
Spark 2 returned first; Spark 1's admitted work finished before its update.

Preserved configuration: DeepSeek-V4-Flash-Vision-Exp
IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8 and its existing vision encoder, 262144 total
context/output ceiling, two resident sessions, one active request, 2048-token
prefill chunks, 64-token mixed quantum, 349525 MiB model-specific disk cache,
262144 cold-anchor ceiling, continued checkpoints every 16384 tokens, warm
weights enabled, 4096 MiB optional Q8-to-FP16 cache reserve, rewind disabled.
No launcher, environment, model, cache format, or sampling changes are needed.

The CUDA-only delta adds bounded Q8 raw reads and accelerates GB10 Q8
attention-output prefill. Activation preparation retains the exact maximum
tree/rounding. Exact INT8 MMA reuses existing aligned Q8 weights without an
extra weight allocation or quantization. Its shared scale rows now have one
padding element each, adding 192 bytes of on-chip shared memory per thread
block. This changes addressing, not math. Decode dispatch and all existing
Spark optimizations are preserved. Independent rollback switches are
DS4_CUDA_NO_Q8_0_QUANT_WARPS=1, DS4_CUDA_NO_Q8_MMA_ALIGNED=1 and
DS4_CUDA_NO_Q8_MMA_SCALE_PADDING=1; none is set in normal production.

Source SHA256: 4c2b799bce8616ededddba552f374d3e1d8c105c2e761a08291f256719659e7d.
Native tested CUDA object: b06b7dea330a6d31c7eb95cdbe5dc639974d5f930de21534f4e9e0f75b846b9a.
Padding adds +2.51% prefill at 32K and +1.45% at an unaligned 131K frontier
relative to the already-optimized production path, with 30,768,640 exact float
comparisons in balanced runs. A final host capability guard/comment cleanup
followed those timings. Independent final upstream binaries measured the
complete #979 package at +10.65–10.75% warmed prefill; decode differences were
below 0.6%, not a demonstrated decode improvement. All frontier vectors matched.
The final production object also reproduced the retained baseline's 8,403,200
vocabulary floats at 32768 -> 36864 plus 64 teacher-forced steps, retaining the
encoder, both resident slots and full context allocation. Final 28-shape/eight-
combination API memcheck/synccheck and CUDA regression passed.

Immediate padding rollback is b6fdb1b6 and its verified per-host binary backup;
the older full-Q8 rollback remains 3a0f780e. Deployment must
wait until isolated model tests exit, verify unchanged launch settings and
real text/image cold-to-warm reuse, then resume each maintained Spark through
DSG and confirm drained=false, is_healthy=true, quarantine=null. Never force a resume
by clearing quarantine or altering gateway settings.

The upstream PR branches contain only their individual generic CUDA changes
and tests; this local integration/configuration history is not submitted there.

Spark 1 is an unpacked deployment, not a Git checkout. Its current binary is
484e8699f77a1fd7891dc77b449a0fe82d0f12daebaf2f9cccb29f830530e765;
Spark 2's padding-enabled binary is
67afa96e1370c15574e512a26ae1d2e11358dcff4515f49c5748f5ab3c986cfa.
Padding rollback backups are
/home/jordi/ds4-backups/q8-scale-deploy-20260905.3UhHTl on Spark 1 and
/home/jordi/ds4-backups/q8-scale-deploy-20260905.oOmTdW on Spark 2.
No launcher or model files are copied between hosts. Their separate path-
specific settings remain unchanged; only source/test/object and a locally
relinked executable are installed after a verified idle drain.

System maintenance uses the existing supported Ubuntu/DGX package channels,
preserving their NVIDIA driver pins. As inspected on 2026-09-05, both already
run driver 580.173.02 and DGX OS 7.5.0; no newer supported driver or fwupd
device firmware was offered. Ordinary firmware-package/desktop updates must
not be presented as a confirmed fix for Spark 2's earlier memory-related
instability. Timestamped system and build backups are retained on each host.

Post-maintenance acceptance on both hosts reused all 19 text and 136
image-conditioned prior tokens in separate resident conversations. Spark 2's
first resumed production request also loaded its saved 144666-token vision
checkpoint from disk, leaving only 536 tokens to prefill. Both workers were
verified healthy, undrained and unquarantined at handback on 2026-09-05 UTC.
Startup still logged driver NV_ERR_NO_MEMORY warnings during artifact
preparation on both hosts; initialization continued and the acceptance tests
passed. Their exact cause and the earlier reboot remain unresolved. These
short acceptance checks are not a long-context soak or a new speed benchmark.

Padding follow-up handback: Spark 2 at approximately 02:25 UTC, Spark 1 at
02:39 UTC. Both reused all 19 text and 136 image-conditioned prior tokens in
the post-restart check. Spark 2 also restored a 189373-token disk checkpoint,
leaving only 65 tokens to prefill in its next large conversation. Each live
executable matched its recorded installed hash. The same pre-existing driver
memory warnings appeared during both startups; neither this padding update
nor the earlier package update is a demonstrated fix for the old OOM/reboot.
The upstream optimization remains one clean commit in #979, head 67d0c9f;
the raw-loader bounds fix remains separate in #978.
