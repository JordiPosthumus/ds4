# M3 short-decode attribution follow-up

The original −4.26% result at 8,192 tokens did not reproduce. In the reversed-order comparison, the complete runtime was faster at every short frontier. Replaying the byte-identical original complete-runtime executable also reproduced the faster readings, with byte-identical output traces. The first pair therefore does not establish a repeatable short-decode regression caused by a patch. No production rollback or PR withdrawal is justified by that result alone.

This corrects the interpretation of the original observation. It does not erase its raw data, establish a universal speedup, identify the physical cause of process variation, or validate every component of the bundle independently. No runtime patch or production setting was changed during this investigation.

## Native repeats

Same M3 Ultra, model, encoder, 262144 capacity, ten occupied residents, one active session, prefill cap 4096, warm weights, corpus and 128 teacher tokens. Two warmups and four timed trials per frontier. Rates exclude snapshot restore and the first decoded token. The follow-up first runs full then stock through 32/512/2048/8192; the original run used stock then full and continued through full capacity. All native measurements precede the added causal controls.

| Context | Original stock | Original full | Original change | Repeated stock | Repeated full | Reversed change | Original full executable replay |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 43.326 | 43.495 | +0.39% | 43.073 | 45.377 | +5.35% | 45.227 |
| 512 | 44.080 | 43.014 | -2.42% | 43.868 | 45.028 | +2.64% | 44.888 |
| 2048 | 43.361 | 42.329 | -2.38% | 43.214 | 44.308 | +2.53% | 44.182 |
| 8192 | 38.973 | 37.314 | -4.26% | 38.841 | 39.744 | +2.33% | 39.580 |

Rates are tok/s and each entry is the median of four trials within one process. Do not pool the trials as independent process repeats or treat the second pair as a precise replacement percentage. The original executable replay is an additional full-runtime process, not another paired stock run. Its controller reads the original progress marker and stops only its owned benchmark process after all requested timings and vectors are flushed, avoiding the unrequested long sweep. The resulting SIGTERM is intentional; this is not claimed as a completed full-capacity sweep.

## Same-process causal controls

Each context uses a saved private prefix payload and the same teacher tokens. Modes are interleaved A/B/B/A twice after one warmup A/B/B/A block: two warmups and four measured trials for each mode. Neither mode changes production. The complete vocabulary is captured after each of 128 decoded tokens; snapshot loading does not restore prior logits.

| Context | Full raw default | Full raw legacy | Default advantage | Stock native prefix | Stock imported full prefix | Imported-prefix change |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 512 | 45.085 | 44.937 | +0.329% | 43.691 | 43.680 | -0.026% |
| 8192 | 39.754 | 39.677 | +0.195% | 38.666 | 38.685 | +0.048% |

The raw-attention default is slightly faster in these interleaved checks. Its default/legacy traces match bit for bit: 33,095,680 F32 values across the two contexts. The legacy mode uses the existing `DS4_METAL_DISABLE_DECODE_RAW_GATHERED_ATTN` switch only inside the evaluation process. This rules against that path as the explanation for the original short-context slowdown in this workload.

Prefix origin is effectively flat in the stock process. At 512 tokens, full and stock also produce byte-identical decode traces when given the identical full prefix. At 8192, they still differ on the same prefix (two argmax differences in 128 vectors), where the changed top-k selector is active. This experiment does not separately attribute that numerical difference or establish a quality regression. Native stock/full prefill states differ; the bundle remains unproven as universally lossless. `analysis.json` retains the complete numerical comparison summaries.

## Why these controls

The runtime diff contains only a few paths relevant to these M3 timings. Raw-only gathered attention applies to the first two Flash layers; FP8 KV conversion/maximum reduction and the simdgroup-zero matvec reduction execute during decode. The changed top-k selector is inactive at 512 and 2048 with this model and threshold, but active at 8192. M2-only activation, CUDA changes and server/cache/image API work do not execute in these steady M3 engine timings. Small-prefill dispatch and prefill scoring can affect incoming state, which is why prefix origin was controlled separately. No individual PR was withdrawn based on a correlation with the complete bundle.

The new causal frontends link against the exact previously sealed runtime object files; runtime sources, objects and previous executables were not rebuilt. The additional replay uses the exact original full benchmark executable, so its faster readings cannot be attributed to the newly linked frontend. Each build reproduces its original complete output traces at all four frontiers. System thermal/performance-warning observations did not report warnings, but they do not measure clocks or prove the cause of the variation.

## Preservation and reproduction

Both maintenance windows waited for admitted work, backed up the original service and retained checkpoint versions, and restored the identical source, binary, arguments and environment. Retained disk lookup and actual text/image cold-to-warm reuse passed before all workers returned healthy and undrained. Capacity, resident/active counts, prefill, model/encoder, warm weights, cold anchors and disabled rewind were preserved. The benchmark used private snapshots and never opened production disk KV.

Build `causal_frontend.c` separately against each pinned runtime using `benchmark.mk` with `STACK_BENCH_SOURCE`, `CAUSAL_OBJECT` and `CAUSAL_BINARY` set to separate output paths. Invoke the full frontend with `MODEL ENCODER CORPUS OUTPUT_DIRECTORY -`; invoke stock afterward with its own output directory and the full output directory as its final argument. Create the output directories first. The original executable replay uses the original frontend and its original four arguments, ending after the 8192 PASS marker. Preserve the hardware, occupancy, corpus and timing controls above.

Raw follow-up CSVs, captured-file hashes, source/binary provenance and the full comparison summary are included here. Run `python3 analyze_timings.py` to recompute the follow-up medians from these CSVs. The original CSVs remain under `../raw/m3/`. Large traces and private payloads remain retained with their hashes. Future speed claims need repeated process comparisons with matched preceding workloads; four trials within one process cannot bound process-to-process variation.
