# Practical assessment of the 13 PRs

This assessment reuses the completed standalone tests, targeted model checks and documented production evidence. It is not another audit or another round of per-PR benchmarks. The new Spark/M3 comparison measures the complete integrated runtime, which also includes other optimizations.

**There is no PR in this set that the completed evidence identifies as a known bad change.** The useful distinction is between supported fixes, workload-dependent features and performance claims that need careful scope. Passing tests is evidence for the tested cases, not a guarantee for every model and backend.

The combined run is mixed on M3: continued prefill improves 20–30%, while decode changes range from -4.26% to +5.46%, and the 8K prefix sweep is 5.01% slower. Spark decode improves 5–20% across the measured contexts. These are one-pair observations of the entire bundle, including additional changes; they do not identify an individual PR as the cause of a slower or faster shape. The bundle also changes numerical outputs and is not established as universally lossless.

| PR | Assessment | Why it is useful; limit on the claim |
| --- | --- | --- |
| [#903](https://github.com/antirez/ds4/pull/903) | Supported cache fix | Saves continued checkpoints after crossing an interval from an unaligned restore. Helps avoid repeated prefill later; does not accelerate decode. |
| [#904](https://github.com/antirez/ds4/pull/904) | Supported, GLM-specific fix | Preserves tool-call separators during replay. Rendering regressions support it; the current DeepSeek benchmark does not exercise GLM or establish a GLM model result. |
| [#927](https://github.com/antirez/ds4/pull/927) | Supported live-cache feature | Reuses an unchanged prefix when a tool appends an image. Useful for that workflow; ordinary decode and appended-image disk recovery are different mechanisms. |
| [#930](https://github.com/antirez/ds4/pull/930) | Useful workload control | Separates retained sessions from simultaneous inference. Supported admission behavior; the best active-request count depends on latency and throughput needs. |
| [#943](https://github.com/antirez/ds4/pull/943) | Supported cache fix | Finds an existing checkpoint when equivalent tokens have different text spelling. Avoids cold prefill on affected misses; not a kernel speedup. |
| [#960](https://github.com/antirez/ds4/pull/960) | Supported Metal recovery fix | Restores a reusable prompt after cancellation. Checkpoint creation has measured time/memory costs; this is not a CUDA rollback or a general live-rewind feature. |
| [#961](https://github.com/antirez/ds4/pull/961) | Supported vision-cache feature | Persists exact image-conditioned KV across restart while rejecting changed conditioning. Supported by standalone restart evidence; the deployed integration adapts provenance to preserve its existing cache identities. |
| [#975](https://github.com/antirez/ds4/pull/975) | Supported CUDA stability fix | Avoids the problematic 512-thread top-k exchange. The earlier streaming speed measurement does not isolate the geometry fix itself. |
| [#978](https://github.com/antirez/ds4/pull/978) | Supported CUDA memory-safety fix | Keeps exact Q8 reads within allocation bounds, with fixture and sanitizer evidence. Useful independently of whether whole-model speed improves. |
| [#979](https://github.com/antirez/ds4/pull/979) | Supported, path-specific optimization | Improves eligible GB10 Q8 prefill. Earlier targeted timings support that path; it is not a decode optimization or an additive whole-model percentage. |
| [#984](https://github.com/antirez/ds4/pull/984) | Supported capacity improvement | Reduces large visual-attention scratch so long-context image requests can fit. Memory savings are the main result; individual attention-call timings are not whole-model gains. |
| [#986](https://github.com/antirez/ds4/pull/986) | Useful, workload-dependent cache policy | Ages stale checkpoint value under cache pressure. Retention behavior has targeted evidence; benefit depends on the cache budget and request mix. |
| [#993](https://github.com/antirez/ds4/pull/993) | Supported, opt-in CUDA optimization | Ordered gathering targets supported long-context indexed decode. Earlier isolated measurements and standalone output/sanitizer checks support it; short contexts and unsupported shapes do not get the same benefit. |

The uncertain claims are broad ones: “every PR makes inference faster,” “the individual percentages add up,” “the complete-stack gain belongs to these 13 alone,” or “a short timing comparison proves universal model quality.” We should not make those claims.

The shared comparison uses one stock/stack process pair on Spark and one on M3, retaining four timing trials inside each process. Existing standalone validation remains the evidence for each PR's individual mechanism.
