# Jordi's DS4 production snapshot

This branch is a recoverable snapshot of the DS4 source and local operating
files used by the Mac Studio production service. It is intentionally separate
from upstream pull-request branches: machine-specific launchers, paths, cache
policy, and historical operating notes do not belong in upstream DS4 PRs.

## Production shape captured here

- DeepSeek-V4-Flash Vision-Exp MXFP4 with its vision encoder.
- 262,144-token context, generation, and cold-checkpoint ceilings.
- Ten resident KV sessions and one active request.
- 4096-token idle prefill slices and 64-token mixed prefill slices.
- Model-specific disk KV storage and cold anchors enabled.
- Live-KV rewind reuse disabled (`DS4_KV_REWIND_REUSE=0`).
- Exact multimodal and tool-continuation cache handling, cancellation recovery,
  canonical text-cache lookup, and graceful checkpoint-preserving shutdown.
- The evaluated Metal indexer stack from upstream PRs #830, #831, and #832,
  including the corrected top-k regression test.

`LOCAL-PRODUCTION-CONFIG.md` is the detailed source of truth. The launchers are
machine-specific and preserve the ordinary `start-ds-ds4` / `stop-ds-ds4` and
GLM fallback workflows. `DS4-PERFORMANCE-RUNBOOK.md` records the controlled
method for detecting throughput regressions.

## Deliberately excluded

This branch does not contain model weights, KV cache files, built binaries,
object files, logs, benchmark dumps, timestamped backups, credentials, or the
large `local-performance/` evidence archive. Those artifacts are either local,
regenerable, too large for Git, or inappropriate for a public fork.

Restoring this branch does not authorize loading a model or restarting a
service. Build and validate in an isolated worktree first, then follow the
restart and acceptance rules in `LOCAL-PRODUCTION-CONFIG.md`.

## Snapshot validation

The snapshot was created from production base `552f6b8` and rebuilt in a clean,
detached worktree on the Apple M3 Ultra. No model was loaded and the live DS4
service was not stopped, signalled, reconfigured, or called.

- `make -j8 ds4-server ds4_test tests/test_indexer_scorers tests/test_topk_ab`
  passed. The only diagnostics were the 27 known macOS 27 deprecation warnings
  for `didModifyRange:` that also occur in clean upstream-based builds.
- `./ds4_test --server` passed.
- `make test-indexer-scorers` passed every legacy/tiled2/tiled4/tiled5 equality
  case, including the 64K compressed frontier.
- `make test-indexer-topk` passed all seven canonical/default/CPU cases,
  including the 31/32-token dispatch boundary, dense ties, odd rows, the 64K
  frontier, and the non-512 fallback.
- `make cpu`, launcher `bash -n`, `git diff --check`, the public-file inventory,
  and a credential-pattern scan passed.

The earlier authorized Vision-Exp real-model cache and kernel measurements are
recorded in `LOCAL-PRODUCTION-CONFIG.md`; they were not rerun merely to publish
this recovery snapshot.
