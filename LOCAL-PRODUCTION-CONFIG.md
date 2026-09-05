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
