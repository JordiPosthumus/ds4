# Unified local production configuration

This is the shared source integration for Jordi's Metal Macs and CUDA GB10
Sparks. A unified source revision does not mean identical models, binaries,
launchers, settings, or simultaneous deployment. Reconciliation is staged only
until the deployment record confirms each host's actual running version.

## Preserved machine settings

| Host | Backend / model | Context / output ceiling | Resident / active | Prefill / mixed | KV budget MiB |
| --- | --- | ---: | ---: | ---: | ---: |
| M3 Ultra, 512 GiB | Metal, Vision-Exp MXFP4 + encoder | 262144 | 10 / 1 | 4096 / 64 | 349525 |
| Spark 1 and Spark 2 | CUDA GB10, Vision-Exp IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8 + encoder | 262144 | 2 / 1 | 2048 / 64 | 349525 |
| M2 Max, 96 GiB | Metal, existing Vision-Exp Q2 + encoder | 65536 | 2 / 1 | 4096 / 64 | 8192 |

The M2 is an additional test host, not a DSG worker. Its existing server must
not be interrupted without permission. Its configuration is not a replacement
default for the M3 or Sparks. Preserve its actual launch script/environment.

On M3 and Sparks, warm weights remain on, continued checkpoint interval is
16384, and cold-anchor ceiling equals total context. Rewind remains disabled;
the Spark optional Q8-to-FP16 cache reserve stays 4096 MiB. Never copy diagnostic
cache sizes, sampling flags, prefill shapes, or context limits into launchers.
Never share a KV directory between different model weights or platforms.

## Launchers and history

The M3's existing start-ds-ds4 / stop-ds-ds4 aliases continue to target this
checkout's ds-ds4-startup.sh / ds-ds4-stop.sh. Preserve the GLM model-specific
aliases and launchers too; integration is not permission to load GLM or the
retired 0731 model. The Sparks keep their existing per-host systemd units,
run-ds4-vision-q2.sh and ds4-vision-q2.env. Do not transplant host-specific paths.

Read the relevant preserved history before changing a host:

- [M3 configuration and validation history](docs/local/M3-PRODUCTION-HISTORY.md)
- [Spark configuration and validation history](docs/local/SPARK-PRODUCTION-HISTORY.md)

The history files intentionally retain older revisions and staged/live dates;
they are not evidence that an old configuration is current. Live process
arguments, environment, binary hash and the deployment record take precedence.
Current M3 and Spark vision-cache keys must remain readable: the independent
upstream vision-provenance PR is not permission for a destructive key migration.

## One integration, independent upstream PRs

codex/production-unified is the intended single integration branch. The old
platform branches remain rollback history during reconciliation, not separate
ongoing development lines. Fork main continues to mirror upstream main.
Each upstream PR stays based on upstream and contains only its coherent fix;
never push local production history or host configuration into an upstream PR.

Before deployment, build and test the same source on each relevant backend.
Require real cold-to-warm and restart/cache checks plus cancellation and tool
continuation checks for shared-state changes. Compare full logits and speed
where scheduling or kernels can affect them. Do not claim ROCm/Strix, M5,
multi-GPU or distributed validation from single-device M2/M3/GB10 tests.

Take timestamped source/configuration/binary backups. Drain only one DSG worker
at a time and wait for admitted work to finish. Separate M2 and Spark tests may
run concurrently when the M2 is explicitly available. Do not launch a second
huge model beside an existing one. Install tested source and binaries together;
preserve every unrelated setting. Verify each host's effective configuration,
real cache reuse, then resume through DSG and require healthy=true,
drained=false, quarantine=null. Never clear quarantine or change recovery
policy manually to force handback.

## M3 short-prefill dispatch update, 2026-09-06

Jordi authorized installing the validated short-prefill extraction from
[Ivan Fioravanti's PR #954](https://github.com/antirez/ds4/pull/954). The runtime
delta is 16 added and 10 removed lines in `ds4_metal.m` on production `960e973`.
It enables existing resident pre-M5 MXFP4 specializations for eligible
32–2,047-token prefills; established quality, residency and tensor-parallel
guards remain. No kernels, arithmetic, sampling or checkpoint formats change.
The included regression fixture and Makefile target protect the dispatch gates.
Only the M3 serving executable is deployed; other command-line binaries and
other hosts retain their previous deployments.

On M3 Ultra / 512 GiB with the existing Vision-Exp MXFP4 model, paired engine
prefill gains were 16.42% at 512 new tokens, 6.31% at 2,047, 17.85% for 91 new
tokens after 110,290 cached, and 15.98% for 128 after 261,888 cached. The
2,048-token control was flat. These exclude HTTP/restore overhead and establish
no ordinary decode-speed gain. Independent process confirmation, byte-exact
full-vocabulary traces through full context, guarded GPU cases, image suffixes,
ten live sessions, cancellation/tool replay and bidirectional disk reuse passed.
The final near-capacity reference drift and corrected API fixture-order failure
are disclosed in the full report.

All machine settings in the table above remain unchanged. Normal `start-ds-ds4`
uses the improvement without extra flags. The existing aggregate rollback
`DS4_METAL_DISABLE_PRE_M5_MXFP4_MOE_SMALL_PREFILL` is documented for a separately
authorized rollback; it is absent from production's environment. Rewind remains
disabled and cold-anchor checkpoints remain enabled. Rollback needs matching
source and serving binary restoration during authorized DSG maintenance; it
requires no KV deletion or conversion.

Installed serving binary SHA256:
`8ca6acc68a256ebe05fc7c334a80de2aa437febf73af0a3c3cc69677e95d7e2c`.
Previous serving binary SHA256:
`59e0ed435b08814a99608c31958fa2f22fcddc7e2737ee43d4e077b45c740b15`.

The timestamped backup and live deployment receipt are in
`local-performance/prefill-attribution-20260906T174237Z/production-install-20260906T203740Z/`.
The measured evidence is
[LOSSLESS-SHORT-PREFILL-RESULTS.md](local-performance/prefill-attribution-20260906T174237Z/LOSSLESS-SHORT-PREFILL-RESULTS.md).

## Upstream integration candidate, 2026-09-07

Current upstream `c0a6119` is merged in an isolated shared candidate. This is
not a deployment record: the M3 retains `f443516`, and the Sparks and M2 retain
their verified `960e973` installations until an explicit later deployment.
Validation proceeds on the M2 first, then on one idle Spark reserved through
DSG. Every machine keeps its per-host settings above and its DSG registration.
The M2 remains a separate test host outside DSG.

The merge retains local cache provenance, cancellation restoration, scheduler
ownership, kernel paths and M3 short-prefill dispatch. Upstream's speculative
rewind/rebuild path supersedes the old narrow GLM-only tail handler; exactly
one boundary handler restores the retained prefix and verifies checkpoint
position and image identity. A fallback that rebuilds compressed history first
retires the request's cancellation checkpoint; fast rewinds retain it. This
extends the existing destructive-rebuild invariant to upstream's new boundary
path. Direct speculation remains unavailable to session-
batched serving. The existing optional `DS4_RETAIN_LAUNCH_PLIST` preservation
hook is carried into tracked source without changing its default behavior.

Native/backend, real-model numerical and performance, tool/cancellation,
capacity and bidirectional cache tests are required before accepting this
candidate. Passing M2 tests does not establish CUDA correctness, M3-specific
performance, 262144 capacity, or ten-resident behavior. DSpark activation and
production rollout are separate decisions.

## Shared Metal decode candidate, 2026-09-07

The candidate extends the existing gathered attention staging to eligible raw-only
rows on pre-M5 Apple Silicon. M2 gains the same inverse-RoPE fusion already used
on M3, with the established quality, SSD-streaming and tensor-parallel exclusions.
A raw fallback clears an unconsumed fusion intent before the caller applies its
standalone inverse rotation. The kernels, arithmetic/reduction order, model and
cache format remain unchanged. The earlier M3 short-prefill dispatch stays enabled.

The default dispatch has explicit evaluation/rollback controls:
`DS4_METAL_DISABLE_DECODE_RAW_GATHERED_ATTN`,
`DS4_METAL_DISABLE_DECODE_RAW_PACKED32`, and
`DS4_METAL_DISABLE_M2_ATTN_INV_ROPE_FUSE`. They are absent from ordinary launchers;
setting one requires a separately authorized rollback. None of the model,
context/output, resident/active, prefill, warm-weight or checkpoint settings above
changes. Cold anchors remain enabled; live-KV rewind remains disabled.

`make test-metal-decode-raw-attention` compares eighteen mode transitions for each
of 86 cases, including ring wrap, retained outputs, inverse rotation, quality and
shape fallbacks, FP16/F32 compressed rows, exact 8192-row acceptance and rejection
above it. Full-capacity text/image/resident traces and API/cache acceptance are
separate requirements. Per-machine comparison and serving receipts are recorded
under `local-performance/upstream-integration-m2-20260907T013000Z/`; this section
alone does not assert a deployment. The owner authorized selecting a validated
faster build independently for each host, with original source/binary/cache
rollback retained and DSG handback verified.
