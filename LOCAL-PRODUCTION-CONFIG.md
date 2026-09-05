# Spark GB10 production integration

This branch is the Spark integration, not the Mac production branch. The
2026-09-05 Q8 update was validated and deployed on Spark 2, then installed on
Spark 1 during its separately authorized drained system-maintenance window.
Both have the same CUDA source/object and were returned to DSG after reboot,
effective-configuration verification and real text/image cache-reuse checks.

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
real text/image cold-to-warm reuse, then resume each maintained Spark through
DSG and confirm drained=false, is_healthy=true, quarantine=null. Never force a resume
by clearing quarantine or altering gateway settings.

The upstream PR branches contain only their individual generic CUDA changes
and tests; this local integration/configuration history is not submitted there.

Spark 1 is an unpacked deployment with source verified against 3a0f780e before
applying the Q8 delta. Its locally relinked binary is
8cee6391ef6c65c86312ad532135e85bd9e5af2a4b14b88cd8893f128bf0bd52;
Spark 2's is 86137abdbbb4fbd4935818c31c5ef5bd37a5b3d08c1eb408e0d01cd7b4600de6.
Both use the exact CUDA object above. Spark 1's full model-free CUDA regression
passed before the system update. No launcher or model files were copied
between hosts. Their separate path-specific settings remain unchanged.

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
