# Complete deployed runtime versus pristine upstream

This benchmark compares pristine upstream `f62ca29a308724cde5bc99134ede19104b2a3260` with candidate `d311463ea56f8939b44f6e84e38ae0a304da4549`, based directly on that upstream revision. The candidate reproduces the complete deployed runtime from `21e98c129ce20ebb9e5d2de1a1bbf5f991d3795d` while retaining the newer upstream GLM SSD hotness fix. The latter does not execute for the DeepSeek models measured here.

The authoritative definition of the candidate is the complete 41-file patch and its source manifest. This is an integrated runtime, with adapted implementations and additional optimizations; it is not the result of cherry-picking only the 13 PRs below. Production launchers, host settings, model files, cache directories and local history documents are excluded from the candidate. The public upstream README is retained.

## The 13 independently reviewable PRs

| PR | Contribution represented in the integration | What this engine benchmark can measure |
| --- | --- | --- |
| #903 | Save continued checkpoints when a suffix crosses a checkpoint interval | No HTTP or disk-cache timing; checkpoint reuse is established by separate cache evidence |
| #904 | Preserve GLM tool-call separators on replay | Not exercised by the DeepSeek model |
| #927 | Reuse KV when tools append images | No tool/image workflow timing in this text engine sweep |
| #930 | Separate resident sessions from active requests | Full resident capacity is allocated and occupied; active scheduling is not benchmarked |
| #943 | Retry disk KV lookup with token text | No disk-cache timing |
| #960 | Restore the prompt frontier after cancelled generation | Snapshot restore costs are recorded separately; cancellation is not benchmarked |
| #961 | Persist vision KV with exact conditioning provenance | Integration preserves existing production cache identities; it is not a byte-identical PR application or a disk-cache migration |
| #975 | Avoid unstable 512-thread CUDA top-k exchange | CUDA decode throughput as part of the complete stack |
| #978 | Keep exact Q8 MMA loads within tensor bounds | CUDA Q8 prefill as part of the complete stack |
| #979 | Reduce GB10 Q8 attention-output prefill overhead | CUDA prefill as part of the complete stack |
| #984 | Reduce long-context visual-attention scratch | Allocation can affect memory availability; this is not an image-attention speed test |
| #986 | Age the eviction value of unused checkpoints | No disk-cache eviction workload |
| #993 | Opt-in ordered KV gathering for indexed CUDA decode | CUDA decode with `DS4_CUDA_INDEXED_DECODE_GATHER=1` |

The benchmark supplies combined engine context for these PRs. It does not attribute the aggregate gain to any single PR, establish additive gains, or newly measure every server/cache mechanism.

## Additional integrated runtime changes

The complete patch also contains existing Metal dispatch and kernels, including short MXFP4 prefills, top-k merge pruning, raw gathered attention, packed raw rows, inverse-RoPE fusion, FP8 conversion and reduction work. CUDA additions include earlier GB10 decode paths, Q2 decode work, long-context kernels, exact shared-scale padding and within-warp top-k sorting. Shared server code contains production cache/provenance, slot-routing, replay, cancellation and speculative-boundary adaptations. The exact source patch, not this descriptive list, defines the tested bundle.

## Measurement protocol

Each machine runs one stock process and one complete-stack process. The schedule was shortened at the owner’s request to avoid unnecessary repeats. Both arms use the same compiler settings, model and encoder, corpus bytes, teacher tokens, full context, resident count, prefill cap and ordinary kernel/cache settings. The selected model files are read in place; the benchmark never uses the production disk KV directory. No production setting is installed by this evaluation.

Context is 262,144 tokens on both machines. Spark uses CUDA on GB10, the existing Vision-Exp IQ2XXS/w2-Q2K model, two resident sessions and a 2,048-token prefill cap. M3 uses Metal, the existing Vision-Exp MXFP4 model, ten resident sessions and a 4,096-token prefill cap. One resident performs the measured workload; the others remain occupied and are exercised between frontiers. Warm weights remain enabled. Spark retains its normal optional Q8-to-FP16 cache policy and 4,096 MiB reserve; its actual allocation decisions are recorded per process.

Frontiers are 32, 512, 2,048, 8,192, 32,768, 131,072 and 262,016 tokens. At each frontier, 128 fixed corpus tokens are decoded, reaching the full 262,144 capacity at the final frontier. Each process has two warmups and four measured trials. Steady decode excludes the first token and snapshot restore; those costs are separately recorded. A repeated continued prefill uses 128 tokens at each frontier, except 127 at the last frontier to retain the one generation token required by the prefill API. Each arm uses the same prefix and suffix. The increasing-frontier prefill sweep has one timed observation per frontier per process, so its uncertainty differs from the repeated measurements.

Every timed terminal vector must match its own untimed reference bit for bit. Complete vocabulary traces, resident vectors and teacher tokens are retained for comparison across builds. Numerical differences and held-out teacher-token negative log likelihood are reported separately from throughput. There is no independent process repeat from which to measure repeat drift. These short corpus continuations do not establish general model quality or universal losslessness.

Timing summaries compare one process median per build. The four within-process trials are retained; no independent process repeat or reverse-order control is claimed. Small or unstable differences remain uncertain; there is no averaging across hardware or unrelated workloads. Results include flat or slower shapes.
