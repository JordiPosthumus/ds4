# Pristine upstream versus the complete integrated runtime

Measured on one GB10 Spark and one M3 Ultra. The source comparison is pristine upstream `f62ca29a308724cde5bc99134ede19104b2a3260` versus complete-stack `d311463ea56f8939b44f6e84e38ae0a304da4549`, based directly on that revision. This bundle contains the integration of 13 independently reviewable PRs **and additional Metal, CUDA and shared runtime changes**. The figures describe the complete bundle; they do not isolate or add the gains of individual PRs.

**GB10 Spark:** decode changes range from +5.09% to +20.14%; continued-prefill changes range from +1.11% to +3.93%. At 262,016 context, decode changes from 10.91 to 13.10 tok/s (+20.14%). The tables include every measured shape, including slower ones.

**M3 Ultra:** decode changes range from -4.26% to +5.46%; continued-prefill changes range from +20.17% to +30.13%. At 262,016 context, decode changes from 25.53 to 25.70 tok/s (+0.63%). The tables include every measured shape, including slower ones.

**M3 follow-up:** the short-decode slowdown did not reproduce in a reversed-order comparison or a replay of the exact original full-runtime executable. The original observations below are retained, but do not establish a repeatable −4.26% patch regression. See the [causal controls, independent repeats and limits](m3-attribution/README.md).

See [the exact scope](STACK-MANIFEST.md) and [reproduction instructions](REPRODUCE.md). All comparisons below are within the same machine and model.

| Machine | Backend and model | Context | Resident / active | Prefill cap |
| --- | --- | ---: | ---: | ---: |
| GB10 Spark, 128 GB class | CUDA; Vision-Exp IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8 + encoder | 262144 | 2 / 1 | 2048 |
| M3 Ultra, 512 GiB | Metal; Vision-Exp MXFP4Experts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out + encoder | 262144 | 10 / 1 | 4096 |

The model filenames are `DeepSeek-V4-Flash-Vision-Exp-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8.gguf` on Spark and `DeepSeek-V4-Flash-Vision-Exp-MXFP4Experts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out.gguf` on M3. Both use `DeepSeek-V4-Flash-Vision-Encoder.gguf`. Compiler and platform details are recorded in `toolchains.json` and the native-build receipts.

Both builds receive the same corpus and teacher tokens, and occupy every resident session. Each machine uses one stock process followed by one complete-stack process. Decode and continued prefill have two warmups and four timed trials per shape per process. Each table compares the medians of the four trials within each process. These original full sweeps have no independent process repeat or reversed-order control; treat their changes as observed paired results rather than precise general speed guarantees. The later M3 short-context controls are reported separately above. Raw CSVs retain the individual trials.

Warm weights and ordinary kernel/cache settings remain enabled. Spark uses `DS4_CUDA_INDEXED_DECODE_GATHER=1` and its existing 4096 MiB optional Q8-to-FP16 cache reserve in both arms; stock ignores the gathering option. The adaptive cache is not disabled or forced to a fixed allocation. Its actual startup decisions are part of the captured evidence.

## Steady decode

128 teacher tokens per frontier. The rate excludes the first token and snapshot restore time; both are recorded separately. The final run reaches exactly 262144 tokens.

| Context | Spark stock tok/s | Spark stack tok/s | Change | M3 stock tok/s | M3 stack tok/s | Change |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 19.144 | 20.135 | +5.18% | 43.326 | 43.495 | +0.39% |
| 512 | 18.980 | 19.978 | +5.26% | 44.080 | 43.014 | -2.42% |
| 2048 | 18.650 | 19.600 | +5.09% | 43.361 | 42.329 | -2.38% |
| 8192 | 15.433 | 17.687 | +14.60% | 38.973 | 37.314 | -4.26% |
| 32768 | 14.564 | 16.826 | +15.53% | 36.628 | 37.593 | +2.63% |
| 131072 | 12.604 | 14.853 | +17.85% | 30.240 | 31.891 | +5.46% |
| 262016 | 10.906 | 13.103 | +20.14% | 25.533 | 25.695 | +0.63% |

## Continued prefill

128 new tokens per frontier, except 127 at 262016 because the prefill API requires one token of generation room. Snapshot restore time is excluded.

| Context | Spark stock tok/s | Spark stack tok/s | Change | M3 stock tok/s | M3 stack tok/s | Change |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 189.454 | 196.166 | +3.54% | 228.501 | 274.593 | +20.17% |
| 512 | 188.452 | 195.861 | +3.93% | 221.869 | 270.725 | +22.02% |
| 2048 | 173.377 | 179.079 | +3.29% | 206.702 | 250.746 | +21.31% |
| 8192 | 165.360 | 170.510 | +3.11% | 196.387 | 241.770 | +23.11% |
| 32768 | 162.621 | 168.666 | +3.72% | 186.203 | 233.714 | +25.52% |
| 131072 | 154.934 | 159.390 | +2.88% | 154.703 | 201.308 | +30.13% |
| 262016 | 66.338 | 67.075 | +1.11% | 111.732 | 144.345 | +29.19% |

## Increasing-prefix prefill

Each frontier extends the prior retained prefix. This sweep has one observation per frontier per build. It is descriptive evidence with less repetition than decode and continued prefill.

| Context | Spark stock tok/s | Spark stack tok/s | Change | M3 stock tok/s | M3 stack tok/s | Change |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 36.517 | 59.848 | +63.89% | 75.373 | 87.207 | +15.70% |
| 512 | 435.959 | 501.851 | +15.11% | 406.502 | 457.040 | +12.43% |
| 2048 | 691.699 | 764.352 | +10.50% | 564.757 | 581.493 | +2.96% |
| 8192 | 681.725 | 748.932 | +9.86% | 589.534 | 559.985 | -5.01% |
| 32768 | 663.153 | 727.610 | +9.72% | 536.591 | 543.838 | +1.35% |
| 131072 | 626.219 | 681.325 | +8.80% | 378.008 | 441.138 | +16.70% |
| 262016 | 510.600 | 542.646 | +6.28% | 240.739 | 306.934 | +27.50% |

## Numerical evidence

All completed processes passed finite full-vocabulary checks, expected-position checks and bitwise comparison of every timed terminal vector with its own untimed reference. The following table compares the saved traces, continued-prefill vectors and occupied-resident vectors across processes. These measurements describe this finite set of workloads, not universal model quality.

| Machine | Comparison | F32 values compared | Different bit patterns | Argmax differences / vectors | Maximum absolute difference | RMS difference |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| spark | Stock / stack | 118549760 | 116739758 | 48 / 917 | 6.60488701 | 0.313455464 |
| m3 | Stock / stack | 125789440 | 123979395 | 27 / 973 | 6.73206973 | 0.262139576 |

The full bundle is not a universal lossless or bitwise-equivalent optimization. The table above records the observed numerical changes separately from timing.

spark: 7 of 7 continued-prefill terminal vectors matched bit for bit across builds.

m3: 0 of 7 continued-prefill terminal vectors matched bit for bit across builds.


Teacher-token negative log likelihood uses the same 896 continuation tokens per process. Lower values mean greater probability assigned to these particular observed tokens; this small corpus sample does not establish a general quality ranking.

| Machine | Stock mean NLL | Stack mean NLL | Stack minus stock |
| --- | ---: | ---: | ---: |
| spark | 1.73842562 | 1.74089828 | +0.00247265 |
| m3 | 1.06533781 | 1.05977439 | -0.00556342 |

## Validation and scope

Both revisions passed clean native builds and host frontend checks on both machines. The same external frontend is compiled against each revision’s own public headers; runtime source is uninstrumented. Models, encoder files and production serving settings were preserved. The private engine comparison uses no production disk KV directory.

Each worker was reserved separately through DSG, admitted work completed before stopping, and its original service was restored afterward. Exact source/binary/settings checks, retained checkpoint lookup checks and real text/image cold-to-warm reuse passed before returning each worker healthy, undrained and unquarantined.

The first Spark attempt successfully decoded through full capacity but then used an invalid final prefill length of 262144, which the public API rejected because it requires one generation token. The external harness was corrected to use 127 final prefill tokens; runtime source and capacity were unchanged. That partial attempt is retained and excluded from all completed-comparison figures above.

The original repeat schedule was shortened to one completed pair per machine. Spark was stopped after its completed pair; an unmeasured repeat had just started and is excluded. An initial M3 maintenance check rejected an old unmatched cancellation log entry before stopping the service. The corrected check used a current completed zero-generation request before the successful M3 run. These maintenance events are not runtime benchmark failures.

This engine sweep does not measure HTTP latency, tool/image cache-hit benefits, queue scheduling, cancellation latency or disk-cache eviction workloads. Those PRs retain their separate correctness and workflow evidence. The GLM-specific replay change is not exercised by these DeepSeek models. No per-PR marginal gain, other quantization, other GPU, multi-GPU or general quality result is inferred.
