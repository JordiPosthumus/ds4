# Spark GB10 production integration

This branch is the Spark integration, not the Mac production branch. The
2026-09-05 Q8 update is being rolled out to Spark 2 only; Spark 1 remains at
3a0f780e until a separately authorized drain/rollout.

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
extra allocation or quantization. Decode dispatch and all existing Spark
optimizations are preserved. Rollback switches are
DS4_CUDA_NO_Q8_0_QUANT_WARPS=1 and DS4_CUDA_NO_Q8_MMA_ALIGNED=1; they are not
set in normal production.

Source SHA256: 2fe326cb4b38c22b831b11a8cdc97170b5616356d8b80e0423d3d16a1024962a.
Native tested CUDA object: 4b0615ed1d0ef7f84905801d4f2abcac001f7118b1b2e0d667bb67e87fffd2cb.
Balanced tests measured +7.52% prefill at 32K and +4.17% at 131K, with
unchanged logits. Independent upstream binaries confirmed +7.28–7.48%
warmed prefill and unchanged decode. The final integration matched the old
production binary on all 8,403,200 vocabulary floats at 32768 -> 36864 plus
64 teacher-forced tokens, retaining both resident slots and the full context
allocation. Focused API tests and memory checking pass.

Baseline rollback is 3a0f780e and its verified binary backup. Deployment must
wait until isolated model tests exit, verify unchanged launch settings and
real text/image cold-to-warm reuse, then resume only spark2 through DSG and
confirm drained=false, is_healthy=true, quarantine=null. Never force a resume
by clearing quarantine or altering gateway settings.

The upstream PR branches contain only their individual generic CUDA changes
and tests; this local integration/configuration history is not submitted there.
