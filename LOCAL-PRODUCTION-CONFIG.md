# Spark GB10 production integration

This branch is the Spark integration, not the Mac production branch. The
2026-09-05 shared-scale padding follow-up is deployed on Spark 2 and staged on
Spark 1 while its admitted work drains. Spark 2 passed installed regressions,
effective-configuration and real text/image cache checks, then returned to DSG.
Spark 1 still runs the preceding b6fdb1b6 integration until its drain completes.

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

Spark 1 is an unpacked deployment, not a Git checkout. Its preceding binary is
8cee6391ef6c65c86312ad532135e85bd9e5af2a4b14b88cd8893f128bf0bd52;
Spark 2's padding-enabled binary is
67afa96e1370c15574e512a26ae1d2e11358dcff4515f49c5748f5ab3c986cfa.
Its backup is /home/jordi/ds4-backups/q8-scale-deploy-20260905.oOmTdW.
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
