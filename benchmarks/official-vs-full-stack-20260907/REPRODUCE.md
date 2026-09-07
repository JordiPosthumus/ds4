# Reproducing the engine comparison

Use an idle, dedicated M3 Ultra or GB10 and the exact model/encoder listed in the results. The frontend allocates full 262,144-token sessions (ten on M3; two on GB10), warms mapped weights and performs substantial GPU work. It does not manage a service, modify a launcher, open an HTTP port or use a production disk KV directory.

The stock source is upstream `f62ca29a308724cde5bc99134ede19104b2a3260`; the complete-stack source is `d311463ea56f8939b44f6e84e38ae0a304da4549`. The latter contains 41 changed files and additional work beyond the 13 PRs. See `STACK-MANIFEST.md` for the scope. Build each revision in a fresh source export with the same toolchain. Keep the runtime source unmodified.

Place `stack_bench.c`, `benchmark.mk`, `build_native.py` and the generated `corpus.txt` together in a private benchmark directory. Under that directory, export the two source revisions into `build/stock` and `build/full`. `build_native.py` builds the normal executables, links the same external frontend against each native engine and runs the host frontend checks. It records the exact commands, executable/object hashes and exit codes. On GB10 it selects `CUDA_ARCH=sm_121a`; on macOS it uses the normal Metal build.

The source revisions are available in the fork containing this report. For example, from the benchmark directory:

```sh
git clone --no-checkout https://github.com/JordiPosthumus/ds4.git sources
mkdir -p build/stock build/full
git -C sources archive f62ca29a308724cde5bc99134ede19104b2a3260 | tar -x -C build/stock
git -C sources archive d311463ea56f8939b44f6e84e38ae0a304da4549 | tar -x -C build/full
```

The analysis scripts require Python 3 and NumPy. `analyze_timing_csvs.py` imports `analyze_benchmark.py`, so keep both files together.

Generate the corpus directly from upstream's `speed-bench/promessi_sposi.txt` at the pinned stock revision:

```python
from pathlib import Path
import hashlib
book = Path('build/stock/speed-bench/promessi_sposi.txt').read_bytes()
assert hashlib.sha256(book).hexdigest() == 'f53e0d80cb2d4492d24ebd63c7000c397b16ae70f9bf09b3763e5d8323ec209f'
doubled = book + book
corpus = doubled + b'\n' + doubled[:65536]
assert hashlib.sha256(corpus).hexdigest() == '443b3169e6b07837484df10b392115f11baa4258232bf91801a025b0967f8807'
with Path('corpus.txt').open('xb') as f:
    f.write(corpus)
```

Build after generating the corpus; the build receipt includes its digest.

```sh
python3 build_native.py build
```

Run `stack-bench` as two separate processes in stock/full order. Its arguments are the model, encoder, corpus, and a new, existing empty output directory, all as absolute paths. The working directory should be the respective source build. Retain the ordinary environment consistently across both arms. In the recorded GB10 runs, `DS4_CUDA_INDEXED_DECODE_GATHER=1` and `DS4_CUDA_Q8_F16_CACHE_RESERVE_MB=4096` were present in both arms; the stock build does not implement the former option. The optional Q8-to-FP16 cache was enabled with its normal allocation policy. Neither cache allocation nor the precision path was artificially fixed for the benchmark. Record the startup allocation decisions for interpretation.

```sh
/path/to/build/stock/stack-bench /path/to/model.gguf /path/to/encoder.gguf /path/to/corpus.txt /path/to/0-stock
/path/to/build/full/stack-bench /path/to/model.gguf /path/to/encoder.gguf /path/to/corpus.txt /path/to/1-full
```

Each command must finish successfully before the next starts. Capture stdout/stderr separately for each process. The frontend writes timing CSVs, full vocabulary traces, resident vectors and the exact teacher-token array. It checks every timed terminal vector against its own untimed reference. A failed process must be disclosed, not included as a completed comparison.

The recorded analysis verifies file digests and equal token arrays, excludes warmups, computes each process's median, then compares the stock and complete-stack medians. The shortened run has one process per build and no reversed-order repeat. The published raw CSVs permit independent calculation. Without independent process repeats, treat numerical differences as observations from this pair; within-process replay checks do not establish cross-process bitwise repeatability. Prefill sweep rows have only one observation per process and should not be presented with the same repeated-trial confidence as decode and continued prefill.

After confirming that both processes exit successfully, the timing-only wrapper can recompute the tables directly from their output folders:

```sh
python3 analyze_timing_csvs.py --pair /path/to/results /path/to/new-timing-summary.json
```

It verifies the expected contexts, four measured trials per shape, warmup exclusion and actual per-trial token counts. It reports timing arithmetic only; successful model execution and numerical replay checks remain separate requirements. The complete recorded analysis additionally checks retained artifact hashes, identical teacher tokens, full-vocabulary vectors and per-token negative log likelihood.

The published `raw/` directories contain the timing CSVs, completed-process receipts, sanitized runtime logs and build identities. Full vector captures and token arrays are retained outside Git; their sizes and SHA-256 digests are in each process's `captured-files.json`. The published analysis JSON contains the complete numerical comparison and per-token NLL values. Re-running the frontend produces new vectors for an independent comparison.
