# Local DS4 production configuration

This file records the authoritative local DS4 setup for Jordi's Mac Studio. It
exists so a future agent can distinguish deliberate production choices from
temporary experiments. The executable sources of truth are the model-specific
launcher scripts named below; this document explains why their defaults are
set this way.

Launcher shutdown correction, 2026-09-03: the DeepSeek launcher now registers
the same arguments, environment, log paths, and RunAtLoad/KeepAlive lifecycle
using a transient launchd plist with `ExitTimeOut=120`. `launchctl submit`
silently used a five-second deadline even though our stop script waited 120
seconds; that could kill the server partway through resident KV persistence.
This Mac's launchd reports an effective 60 seconds for the requested 120;
the eight-second shutdown fixture completes instead of being killed at five.
This installs no login item and changes no model, context, sampling, concurrency,
prefill, or cache settings. The server still receives one graceful stop signal.
Backups and validation are in `local-performance/validation-20260903T0345Z/`.

Live handback, 2026-09-03 00:50 ADT: PID 68701 is HTTP-ready with the unchanged
production binary (`8f5d993a...`), Vision-Exp MXFP4, 262144 context/output/cold
ceiling, ten residents, one active request, and effective prefill quanta
4096/64. Launchd arguments and `/v1/models` were checked. All five occupied
slots completed shutdown saves before the isolated model tests. Swap remained
415.38 MiB. The gateway was left drained for Jordi; no production inference
was issued after restart. V6 PR candidate code was tested separately and was
not installed. See `local-performance/PR-VALIDATION-RESULTS-20260903-V6.md`.

Next-start context change, 2026-09-02 16:47 ADT: Jordi requested exactly
262144 tokens of total context for the Mac DS4 server. The DeepSeek launcher
defaults for context, generation ceiling, and cold-anchor ceiling are now
262144; Pi's local `ds4/deepseek-v4-flash` contextWindow and maxTokens match.
This is one shared context budget for prompt, generated reasoning, and answer,
not separate input/output allowances. All other model, sampling, vision,
concurrency, cache-directory/budget, kernel and launcher settings are preserved.
Timestamped backups use suffix `20260902T194716Z`.
The running process has not been restarted and still uses 300000. A currently
observed 265104-token prompt exceeds the next-start limit; compact it before
resuming under 262144. Live enforcement and cache recovery at the new context
remain post-restart validation, not claims from these file edits.

Live update, 2026-09-02 14:01 ADT: Jordi explicitly authorized immediate
interruption/restart. PID 89144 received one graceful SIGTERM at 14:00:40,
persisted vision checkpoints at 234490 and 225280 tokens plus a text checkpoint
at 137425 tokens, and exited with status 0. The existing launchd job restarted
the tested binary as PID 2818 at 14:01:10; HTTP readiness was logged at 14:01:24
and `/v1/models` was verified. Effective configuration remains Vision-Exp,
300000 context/output, ten resident sessions, one active request, 4096/64
prefill quanta, rewind disabled, and the same model-specific KV directory.
Swap stayed at 431.38 MiB. No post-restart inference has yet been issued by this
agent, so real continuation reuse remains to be checked on the owner's resume.
Evidence: `local-performance/RESTART-20260902-1401.md`.

Pre-restart staging, 2026-09-02 13:55 ADT: OpenAI tool-continuation hardening and
prefill-boundary realignment are built and have passed focused server tests,
CPU compilation, ASan/UBSan, and independent static review. Local source SHA256
`07ef86d6377fa57efa1fdc8c6c0df6614c187a9b4e9fcc8ad2dd6af18fec9e61`,
binary SHA256
`8f5d993a66325a0a07ff5c81541e2c2e9d54bccba4a35c25915f585fbefdd572`.
PID 89144 started at 13:06 and still runs the earlier build. Jordi authorized
the next restart, but active jobs must first become idle/paused. No launcher,
model, sampling, context, active/resident limit, rewind, or disk format changed.
See `local-performance/PR-AUDIT-PACKETS-20260902-V4.md` for frozen sources,
upstream scope, tests, and the unproven cancellation-to-replay boundary.

Earlier baseline audit: 2026-09-02 (main-based Vision-Exp production candidate at
`552f6b8`; cancellation rollback, canonical disk lookup, graceful launcher
shutdown, and exact image-conditioned disk persistence are validated. The live
PID 67249 started at 11:17 before the latest rebuild and was not interrupted;
the new binary becomes effective only on the owner's next restart. The
DeepSeek launcher and Pi model metadata cap context, generation, and cold
anchors at 300,000 tokens).

The preserved pre/post performance evidence, the confirmed MLX transcription
confounder, and the no-contention A/B procedure are in
`DS4-PERFORMANCE-RUNBOOK.md`. Machine-readable production snapshots, historical
reference points, comparison thresholds, and the controlled-benchmark manifest
are under `local-performance/`. The collector is log-only and must never be
treated as permission to call or restart the model. Do not judge the 2026-09-01
integration from the contended 16:42 run or run the formal comparison without
Jordi choosing the test window.

# CURRENT MODEL-SPECIFIC PRODUCTION CONFIGURATIONS

DeepSeek-V4-Flash Vision-Exp is the currently running service and Pi default.
GLM-5.3-Flash remains available through its model-specific launcher, and the
backward-compatible `start-ds` shortcut still names GLM. The older DeepSeek
section further down this file is retained as historical background.

The validated DeepSeek V4 Flash MXFP4 0731 GGUF was restored to the local
`gguf/` directory on 2026-08-31 as a byte-for-byte verified copy; the external
backup remains intact. **Do not load, warm, benchmark, start, or point any
launcher/symlink at this restored model unless Jordi has first discussed and
explicitly approved that load.** Creating its named launcher and alias is not
authorization to invoke it, and its presence on the internal disk is not
authorization to change the active model or production configuration.

## Normal operation

```sh
alias start-ds-glm53f="/Users/jordiposthumus/ds4/ds-glm53f-start.sh"
alias stop-ds-glm53f="/Users/jordiposthumus/ds4/ds-glm53f-stop.sh"
alias start-ds-ds4="/Users/jordiposthumus/ds4/ds-ds4-startup.sh"
alias stop-ds-ds4="/Users/jordiposthumus/ds4/ds-ds4-stop.sh"

# Backward-compatible shortcuts remain GLM-5.3-Flash:
alias start-ds="/Users/jordiposthumus/ds4/ds-glm53f-start.sh"
alias stop-ds="/Users/jordiposthumus/ds4/ds-glm53f-stop.sh"
```

`start-ds-glm53f` (and its backward-compatible `start-ds` shortcut) starts the
GLM-5.3-Flash Q4 resident service with one batched
session and ordinary decoding (MTP off) with no extra flags.
It refuses to start if the Metal wired-memory limit is below 481,280 MiB
(`sysctl -n iogpu.wired_limit_mb`; it resets on reboot — restore with
`sudo sysctl -w iogpu.wired_limit_mb=498073`).

`start-ds-ds4` is the separately named DeepSeek V4 Flash Vision-Exp MXFP4
launcher. It preserves the served/Pi model ID `deepseek-v4-flash`, adds the
matching 0.9 GiB encoder with `--vision`, and defaults to ten resident KV
sessions with one active request (`--batched-session 10
--max-active-requests 1`). This lets up to ten conversations retain live KV
without allowing a prefill and decode to fragment each other. Additional
requests wait in the reuse-aware server queue, and an eleventh unrelated
conversation may still evict a resident checkpoint. Explicit
`DS4_BATCHED_SESSIONS=N`,
`DS4_MAX_ACTIVE_REQUESTS=N`, or `--batched N` overrides remain available for
controlled evaluations. Its default context, generation limit, and cold-anchor
ceiling are all 262,144 tokens (`DS4_CTX`, `DS4_TOKENS`, and
`DS4_COLD_MAX_TOKENS` remain explicit overrides). The launcher uses its own
cache directory,
`/tmp/ds4-kv-deepseek-v4-flash-vision-exp`; the incompatible 0731 cache is
preserved and never offered to Vision. The previous 0731 MXFP4 file remains
the rollback model on the external backup disk. The first Vision load was
owner-authorized; future stop/restart decisions remain owner-controlled.

At 11:51 and 12:06 on 2026-09-02, two OpenAI chat tool-result continuations
silently chose empty slots and cold-prefilled 201,142 and 205,260 tokens even
though the owning multimodal frontier was still resident. The staged local
binary now binds a trailing OpenAI `tool_call_id` set to the unique slot that
generated it, verifies the exact live frontier, normalized pre-call history,
tool schemas, and image-conditioned state, and appends only the new tool-result
suffix. Unknown, stale, partial, duplicate, edited-history, and image-mismatch
cases retain the existing full-replay fallback. This is independent of live-KV
rewind, which remains disabled. The focused server suite, sanitizer run, and
CPU-only server compilation pass. The initial shortcut has demonstrated live
Pi cache hits; its latest hardened version still needs post-restart validation.

The hardened binding additionally checks the exact published assistant content,
ordered calls, explicit replayed reasoning, and token frontier. It is retired
before unrelated disk/sync replacement and refuses synthetic tool-text repairs
or unconsumed speculative output. Dispatch waits only for the matching producer
to publish, never for unrelated busy slots. Canonical tool-result concatenation
does not append a second EOS token.

The local prefill adjustment realigns idle 4096-token slices after a vision
span, instead of repeatedly splitting each later pass into 3951 plus 145 tokens
for the observed span ending at 41105. It preserves image-span atomicity and
the mixed 64-token fairness quantum. This is a scheduling-boundary change, not
a kernel/model-math change or a measured end-to-end speedup claim. It is kept
out of the clean OpenAI continuation PR because upstream's idle quantum is 2048.

The 2026-09-01 concurrency-2 evaluation admitted a 240,302-token cold prefill
and a second request restored at 181,471 tokens. Before overlap, the cold
prefill ran around 338–365 t/s. With the second request decoding, the first
prefill fell to roughly 90–100 t/s in 64-token mixed slices while the decoder
produced 50 tokens in 44.6 seconds (1.12 t/s). The fairness benefit did not
offset the large loss in aggregate progress, so the normal default remains one
active request.

Both models bind `127.0.0.1:8000`, so only one may run at a time. A model start
refuses to replace the other model automatically and asks for the matching
stop alias. Their launchd labels, lock files, logs, and KV directories are
separate, so a stop command cannot target the other model by accident.

The old `start-ds-1` shortcut was removed on 2026-08-29 because it silently
enabled the slower experimental MTP path. A deliberate single-session MTP
evaluation remains available as
`DS4_MTP=1 DS4_KV_REWIND_REUSE=0 ds-startup.sh --single`; it uses the same
service label and port, so invoking it replaces the running DS4 instance and
queues extra requests FIFO. The normal `start-ds` path also now has one
resident session, but remains in batched-server mode rather than the separate
non-batched debug mode.

## Authoritative defaults (GLM-5.3-Flash)

| Setting | Production value | Reason |
| --- | ---: | --- |
| Hardware | Mac Studio, M3 Ultra, 512 GB unified memory | Target machine |
| Checkout | `/Users/jordiposthumus/ds4` | Canonical source, alias target, production binary, `gguf` directory |
| Branch | `codex/main-vision-production-candidate` at `552f6b8` | Main/Vision integration plus the audited local cache/speculative-boundary reconciliation, request-cancellation rollback, exact image-conditioned disk persistence, and the selected upstream changes documented below. Immediate source rollback is `codex/backup-production-pre-vision-disk-20260902T050000Z` at `7d61f2b`; exact rollback binaries are retained with timestamps. |
| Model | `gguf/GLM-5.3-Flash-Q4_K.gguf` (178 GiB, antirez Q4_K, resident — no SSD streaming) | Highest-quality DS4-executable GLM-5.3 quant (FP8 artifact is not yet executable in DS4) |
| Endpoint | `127.0.0.1:8000` | Local OpenAI-compatible service |
| Served model IDs | `glm-5.2` (thinking off), `glm-5.2-reasoner` (thinking on, `reasoning_effort` honored), aliases `glm-5.3-flash` / `glm-5.3-flash-no-think` | IDs reuse the GLM-5.2 namespace in this branch; name field reads "GLM 5.3 Flash" |
| Context | 384000 tokens | Below the 393216 Think Max threshold; the resident full-attention window stays fixed at 4096 tokens (longer context reads the compact DSA cache) |
| Token limit | 384000 | Matches configured context ceiling |
| Resident sessions | 1 (`DS4_BATCHED_SESSIONS=1`) | Owner-selected stability/isolation setting (2026-08-31). The normal server remains in batched mode, so additional requests queue instead of occupying another resident KV slot. Values up to 6 remain available only for deliberate concurrency evaluation. |
| KV disk | `/tmp/ds4-kv-batched`, 349525 MiB (about 341.3 GiB) | Reused DeepSeek directory (swept clean before cutover; model content is now GLM-only). Cold-anchor checkpoints on by default; `DS4_KV_COLD_MAX_TOKENS=0` disables. macOS empties /tmp on a 3-day cycle — cold-start cost only. |
| KV rewind reuse | disabled (`DS4_KV_REWIND_REUSE=0`, local kill-switch patch) | 2026-08-25 incident class (cross-session state bleed). Enabling requires a dedicated concurrent-isolation regression first. |
| Batched slot routing | reuse-aware, then staleness-aware eviction (upstream PR #765, adapted locally) | A Pi subthread that merely shares the system/tools prefix no longer overwrites the main chat while an empty slot exists. Actual token/text/visible/tool-state reuse wins; otherwise empty slots win, then checkpoints idle at least one hour, then the shortest recent checkpoint. The reuse probe honors `DS4_KV_REWIND_REUSE=0`. |
| GLM-5.3 memory guard | upstream fraction/reserve guard (no per-rank ceiling) | The rewritten branch removed the fixed 110 GiB per-rank ceiling entirely. The guard is now fraction (0.99) + reserve + wired-limit based, with a special-case 24 GiB reserve for 480–640 GiB hosts running a model ≥80% of host memory (exactly this machine + Q4). The obsolete `DS4_GLM53_PER_RANK_CAP_GIB` launcher export and false “Rank cap” summary were removed on 2026-08-29; no runtime behavior changed because this branch already ignored the variable. Acceptance gates unchanged: swap must not grow from idle, system stays responsive; guard report (`DS4_GLM_MEMORY_GUARD_REPORT=1`) logged on first load. Fallback: Q2 resident. |
| MTP | disabled in production (`DS4_MTP=0`, no MTP flags); single-session MTP evaluation requires an explicit command | A 2026-08-29 Q4 long-context run averaged 15.3 t/s versus the established ~20 t/s batched ordinary-decode baseline. Accepted MTP cycles barely broke even while rejected cycles were expensive. The normal one-session batched path runs ordinary decoding and does not pass MTP flags. |
| Vision | enabled (`DS4_VISION=1`, `--vision gguf/GLM-5.3-Flash-Vision-Encoder.gguf`) | GLM 5.3 vision encoder sidecar (1.1 GiB, from `zai-org/GLM-5.3-Flash` rev `84c6a6a` via `./download_model.sh glm53-vision`). Metal-backend only — this host's backend. Encoder weights load once at startup but only run on requests carrying images, so text throughput and resident cost are unchanged. `DS4_VISION=0` starts text-only. pi's `ds4` model entry has `input: ["text","image"]`. Repeated historical images may reuse the same slot's live KV only when every stored token span, token count, and 32-byte embedding fingerprint matches. A newly appended image may reuse the old live frontier only when every earlier prompt token and image identity remains exact and the new image begins at or after that frontier. Changed, missing, moved, replaced, or earlier-inserted images cold-prefill. Starting with next-start commit `552f6b8`, evict and shutdown checkpoints with an exact complete image set are disk-keyed by image count, token spans, and 32-byte encoder fingerprints plus canonical token text. Exact replay may therefore survive a slot eviction or process restart; changed, moved, missing, additional, or text-only images cannot select that entry. Appended-image disk reuse remains deliberately unsupported in this first version and falls back safely. |
| Prefill / mixed prefill chunk | not set / 64 (no-op for GLM) | GLM-5.3 is KDA-native: it ignores `--prefill-chunk` and overrides the mixed quantum (server logs 1024; the GLM graph uses its own 2048-token indexed prefill chunk). |
| Warm weights | enabled | Avoid first-request weight warmup |
| Sampling (pi) | temperature 1.0, top-p 0.95, min-p 0.0 | Matches the official GLM-5.3-Flash checkpoint sampling profile (`temperature=1.0`, `top_p=0.95`); explicit `min_p=0.0` prevents DS4's local 0.05 default from adding an extra filter. With production MTP off, every token follows this ordinary sampling path. |
| launchd label | `com.vonbling.ds-glm53` (runner `com.vonbling.ds-runner`, port 8000) | Distinct from DeepSeek's `com.vonbling.ds4-0731` label |
| Lock | `/tmp/ds4-glm53f-server.lock` | Model-specific; the DeepSeek stop command cannot consume it |
| Log | `/tmp/ds4-glm53f-start.log` | Model-specific startup, cache, prefill, and generation diagnostics |

## Local code provenance (GLM-5.3 branch)

Upstream `glm-5.3-flash` at `767e517` (2026-08-29) plus six local patches and
the two commits from upstream PR #765:

1. `ds4_server.c` — `DS4_KV_REWIND_REUSE` kill-switch around the GLM live
   prefix rewind (upstream default ON, no kill switch; incident class
   2026-08-25). Default 0 = disabled. Rebased onto the rewritten branch;
   the `live_prefix_rewind_target` call site was unchanged upstream.

2. `ds4_server.c` — port of upstream PR #894 (`fix GLM thinking-visible
   cache keys`, kk's commit `10833ab`, applied as `/tmp/pr894-fix.patch`):
   `build_toolless_thinking_visible_text()` now emits GLM-syntax visible
   keys (keeps the opening `illow` tag, trims assistant content, no DeepSeek
   EOS) instead of the DeepSeek replay shape. Without it, every thinking+tool
   turn misses the session cache and re-prefills ~40K tokens (~105 s at
   ~380 t/s prefill). Includes GLM-specific regression test
   `test_glm_thinking_checkpoint_canonical_matches_future_prompt` (runs in
   `./ds4_test --server`). Watch upstream #894; if it merges with a different
   shape, rebase onto the upstream version.

3. `ds4_server.c` — exact sampled GLM tool text now remains in its valid live
   tokenization whenever the rendered bytes already match. The earlier local
   forced canonicalization was removed after audit: byte-identical text with a
   different valid BPE spelling is not evidence that the live graph is wrong,
   and retokenizing it can itself discard a valid prefix.

4. `ds4_server.c` — preserve the GLM line separator between assistant text and
   an exact raw tool block. One newline is added only when neither the rendered
   content nor the raw sampled block already supplies one. Parser-to-replay
   tests cover empty content plus exact one- and two-newline sampled forms.

5. `ds4_server.c` (`41f43db`, hardened by `1d6e38a`) — a partial speculative
   block may retain live KV only for the proven GLM-5.3 case: a two-token block
   with exactly its first token retained, followed by a valid checkpoint at the
   requested frontier. Every other partial block is invalidated and rebuilt on
   the next request; it is never logged as a successful rewind. Production MTP
   remains disabled, and no public rewind API or agent/TP behavior was widened.

6. `ds4_kvstore.c` (`6aee6a5`, hardened by `1d6e38a`) — continued checkpoints now save at the first valid live
   position at or beyond the next interval frontier. Previously the code
   required an exact global multiple. A real Pi run restored a 9,703-token cold
   anchor and then advanced in 2,048-token GLM chunks; that sequence can never
   equal a multiple of 16,384, so it wrote no continued recovery checkpoint and
   a later canonicalization failure fell all the way back to 9,703. The fixed
   sequence saves at 17,895, 34,279, and subsequent crossed frontiers. Disk
   restores and full rebuilds reset the per-slot scheduler to the exact restored
   frontier, including zero; interval alignment is range-checked in `int64_t`.
   This does not change live-session selection or enable rewind reuse.

7. `ds4.[ch]`, `ds4_server.c` (`45d469e`, `edd92d5`) — adapted upstream PR
   #765's reuse-aware slot probe and staleness-aware eviction tiers onto the
   GLM branch. The router now asks the same question as request execution:
   whether the request can actually reuse token, rendered-text, visible
   thinking, Responses, or Anthropic live state. A shared system/tools prefix
   alone is not reuse and therefore cannot beat an empty slot. The adaptation
   deliberately gates PR #765's GLM rewind tier through the existing
   `DS4_KV_REWIND_REUSE` kill switch, so production value 0 remains disabled.

8. `ds4.c`, `tests/ds4_test.c` (`51c14f5`, upstream `639d4eb`) — fixes
   GLM-5.3 continued prefill. Two-or-more-token checkpoint extensions now use
   the batched prefill graph, including a chunk that crosses the dense/sparse
   attention boundary; a one-token extension retains the lower-latency decode
   path. Image spans still force the embedding-capable prefill path. Upstream's
   model-backed progress, agreement, and throughput regression is included.

9. `ds4.c`, `ds4_gpu.h`, `ds4_metal.m`, `metal/glm53_bf16.metal`
   (`9bc9a65`, upstream `6cf658a`) — M3 Ultra-specific ordinary-decode
   optimization. It fuses the three BF16 KDA Q/K/V matrix-vector dispatches
   and uses four simdgroups for the relevant BF16 kernels. This does not change
   model weights, quantization, sampling, MTP, or launcher settings. The old
   paths remain selectable with upstream's `DS4_METAL_DISABLE_M3_ULTRA_GLM53_*`
   diagnostic environment switches.

10. `ds4.[ch]`, `ds4_server.c` (`366a0e7`) — fixes Pi threads that replay
    historical image-bearing tool results. The previous server invalidated
    every multimodal live checkpoint before reuse, and the batched multimodal
    scheduler independently restarted at token zero. Exact image identity is
    now part of slot routing and execution, and a matching batched continuation
    resumes at the live frontier. Image-conditioned checkpoints are barred from
    the text-keyed disk writer; mismatched images remain cold. Multimodal tool
    canonicalization also refuses unsafe text-only/disk reconstruction.

11. `ds4.[ch]`, `ds4_server.c` — fixes text-only disk-cache restores into a
    slot previously used by an image-bearing request. Payload restore already
    replaced the slot's tokens and KV tensors, but stale image fingerprints
    survived and made the next text sync invalidate the valid restored state,
    silently cold-prefilling the full prompt. A successful payload restore now
    clears the superseded image identity. The same disk-hit handoff now also
    seeds the resident slot's independent continued-checkpoint frontier; without
    that assignment, a 33,196-token hit observed in production immediately
    rewrote a 927 MiB checkpoint after only 1,024 new tokens instead of waiting
    for the next 16,384-token frontier. These changes do not enable rewind
    reuse, change cache keys, reduce checkpoint coverage, or alter
    image-conditioned live reuse.

12. `ds4_server.c` — interrupted suffix prefills no longer discard a validated
    disk checkpoint. Client disconnect and server shutdown are not evidence of
    cache corruption. Cache progress also normalizes the suffix-relative GLM TP
    callback shape; if an absolute backend ever reports a position below the
    claimed cached frontier again, the server emits one explicit `cache frontier
    lost` warning and displays honest cold progress instead of repeating a
    misleading `0/N` counter.

13. `ds4_server.c` — a new batched prefill now registers with the round-robin
    scheduler before reading its initial live/cache frontier. Previously that
    read waited directly on the raw inference mutex, so the currently running
    prefill could reacquire the mutex every slice while the newcomer remained
    invisible to round-robin arbitration. A production request with an 8,669-
    token disk hit waited about 250 seconds behind an 88,091-token cold prefill
    before receiving its first slice. The frontier read and first slice now
    occur in the same scheduled turn; model math, quantum sizes, and cache
    semantics are unchanged.

14. `ds4_server.c` (upstream PR #927) — a tool result that appends a new image
    after an otherwise byte-for-byte/token-for-token live prompt extension now
    reuses the existing KV frontier instead of discarding the full conversation.
    All old image spans, counts, and fingerprints must match, and the first new
    image must start at or beyond the live frontier. Protocol/text reconstruction
    and rewinds remain exact-image-only; earlier token edits, removed/moved/
    replaced images, and images inserted inside computed tokens still rebuild.
    The upstream post-rewind verification guard is also retained locally.

15. `ds4_server.c`, `ds4_help.c`, `README.md` (upstream PR #930) — separates
    resident KV capacity from active compute concurrency. The new
    `--max-active-requests N` cap counts a slot as active from assignment through
    prefill, decode, streaming, cancellation, and completion. Omitting the flag
    preserves upstream behavior by defaulting the cap to the resident-session
    count. DeepSeek production uses ten resident sessions with a cap of one so
    inactive conversations remain warm while complete requests run serially.
    A measured cap-of-two run was rejected because mixed prefill/decode
    contention reduced both decode speed and aggregate progress.

16. `ds4_server.c` (upstream PR #934) — OpenAI-compatible `tool` and legacy
    `function` messages may carry inline images. `assistant` and `system`
    images remain rejected. This fixes image-returning tool calls without
    widening URL/path access or changing the existing exact-image cache rules.

17. `ds4.[ch]`, `ds4_server.c` (upstream PR #827, reconciled with the newer
    GLM mixed-prefill floor) — an uncontended prefill now follows the engine's
    real cap. Vision-Exp Flash therefore uses 4096-token scheduler slices rather
    than splitting every 4096-token engine chunk into two 2048-token turns.
    While decoding is active, the production mixed quantum remains 64. The
    launcher, context, active-request cap, and resident-session count are
    unchanged. An 8192-token Flash cap was deliberately not enabled: the M3
    Ultra measurements show it favors large one-shot cold prefills but slightly
    regresses incremental chat and doubles raw-KV staging capacity.

18. `metal/dense.metal`, `metal/dsv4_kv.metal`, `metal/dsv4_rope.metal`,
    `metal/norm.metal` — three measured M3 Ultra decode optimizations extracted
    from upstream PR #874: branch-free but bit-exact E4M3FN rounding, a single
    final matvec reduction instead of one per simdgroup, and two-simdgroup FP8
    KV amax reduction. The broad experimental PR was not imported. A local
    guard makes the generic fused FP8 entry point fall back for threadgroups
    narrower than the reduction requires; the Vision-Exp fast path is unchanged.
    Model weights, quantization, sampling, and cache bytes are unchanged.

19. `ds4.[ch]`, `ds4_kvstore.[ch]`, `ds4_server.c`, `ds4_agent.c` (upstream
    PR #882, with atomic lazy publication) — new disk checkpoints store a
    compact model-weight fingerprint in three formerly reserved header bytes.
    A same-quant checkpoint from different weights is rejected even when the
    model shape is identical. Legacy headers with zero in those bytes remain
    loadable, so the existing Vision-Exp cache survives this update. The
    model-specific KV directory remains the primary isolation boundary.

20. Upstream main commit `110afdd` replaces sequential completion IDs with
    random response IDs and uses system randomness for the default sampling RNG
    seed. Explicit request seeds retain their existing behavior.

21. `ds4.[ch]`, `ds4_server.c`, `tests/ds4_test.c` (`6ec6bc7`, Metal allocator
    correction `7d61f2b`) — a client
    cancellation now restores the same DeepSeek session to the exact prompt
    frontier captured before generation. The rollback preserves prompt tokens,
    image identity, logits, the logical raw-KV window, and the mutable
    compressor/indexer state; appended compressed rows become unreachable when
    their saved counters are restored. A checkpoint is bound to one session and
    cannot be applied to another. If capture or validation fails, the existing
    conservative invalidation remains the fallback. This does not enable live
    rewind reuse, change disk-cache formats, or alter normal completed requests.
    The model-backed regression deliberately wraps the raw-KV ring before
    restore and then requires 300 regenerated steps to reproduce every full
    logit vector exactly.

Initial isolated validation for item 21 (`6ec6bc7`, 2026-09-01) covered
optimized Metal server/test builds, CPU portability objects, server and agent
tests, ASan+UBSan server tests, `git diff --check`, exact cancellation-exit
coverage, and repeated full-diff inspection. The 300-step model-backed rollback
test was present but could not run while the production model remained loaded.
The first live cancellation then exposed a Metal-only allocator error: Metal
tensors report no CUDA/ROCm tier (`-1`), but the checkpoint code fed that value
to the tiered allocator, so capture always failed and multimodal fallback
invalidated a 289,203-token live frontier. `7d61f2b` uses the ordinary
single-device allocator when no logical tier exists. After the owner-authorized
stop, the real Vision-Exp regression passed: 300 generated steps wrapped the
raw KV ring, restore returned to the exact prompt frontier, and all 300
regenerated full-logit vectors matched byte for byte. A live abort/retry after
the next start remains the production acceptance check.

22. `ds4_server.c` (`c6a8d6f`) — disk-cache lookup now retries a raw rendered-
    prompt miss with the decoded text of the already-tokenized prompt. Continued
    checkpoints are written with that token-text representation; tokenizer
    canonicalization can therefore make the original request bytes differ even
    when the entire saved token prefix is identical. The raw lookup remains the
    fast first path, and the existing loader still validates the checkpoint.
    This does not change cache files, cache admission, image-conditioned disk
    policy, or live rewind reuse.

23. `ds-stop.sh`, `ds-ds4-startup.sh`, and `ds-startup.sh` — a launchd-managed
    server now receives exactly one graceful stop request, both through the
    named stop aliases and when a start command replaces its own prior instance.
    `launchctl remove` already sends `SIGTERM`; the old scripts immediately sent
    a second `SIGTERM`, and DS4 intentionally treats a second stop signal as an
    emergency exit. That could terminate the process after `shutdown requested`
    but before resident slots were written with `reason=shutdown`. Unmanaged
    lock-file fallback processes still receive one explicit `SIGTERM`, and a
    failed launchd removal retains the same fallback. This is a local launcher
    correction, not an upstream server patch.

24. `ds4.c`, `ds4.h`, `ds4_kvstore.[ch]`, and `ds4_server.c` (`552f6b8`) —
    completed image-conditioned checkpoints may now survive resident-slot
    eviction and graceful process restart. The disk key prepends an exact image
    count plus every token span and 32-byte encoder fingerprint to canonical
    rendered token text. The loader reattaches image metadata only after that
    key matches and only when every image ends within the restored frontier.
    Text-only requests and changed, moved, missing, or additional images cannot
    select the checkpoint. Existing text-only cache files and payload ABI remain
    unchanged. Appended-image disk recovery is intentionally excluded; live
    appended-image reuse remains the separate #927 behavior.

Isolated live validation for items 21–23 on 2026-09-02 used the production
Vision-Exp model on port 8001 with model-specific scratch KV directories. Text
and image-stream cancellations restored their exact prompt frontiers; a
token-equivalent raw-text alias restored 34,816 tokens across a real restart;
an interrupted 31,614-token suffix retained at least the validated disk
frontier and subsequently wrote continued checkpoints at 49,152 and 65,536;
ten completed no-thinking conversations retained independent live slots with
the first resuming at token 830; Pi-style tool history resumed at token 1,198;
two unrelated conversations with a 1,450-plus-token shared prefix occupied
separate slots and the first resumed at token 1,459 with rewind reuse disabled;
an inline image returned by an OpenAI `tool` message replayed from exact live
image-conditioned KV;
an appended second image reused the exact first-image frontier while changing
the original image intentionally rebuilt; and a text disk restore into an
image-used slot cleared stale image identity and reused token 34,816 on retry.
For the stop-script test, cold and continued writes were disabled in an empty
scratch cache: the directory remained empty after an 816-token request, the
single graceful stop wrote exactly one `reason=shutdown` checkpoint, and an
actual restart restored all 816 tokens. The same empty-cache experiment also
passed when the second `start-ds-ds4` invocation replaced its own launchd
instance: self-replacement created the sole 816-token checkpoint and the new
server restored it. The reusable harness is
`local-performance/ds4_cache_acceptance.py`; it never starts, stops, or
reconfigures a server itself.

Re-verified after items 21–22 and the Metal allocator correction (`7d61f2b`,
2026-09-02): optimized Metal server/test/agent builds, server and agent tests,
CPU portability build, ASan+UBSan server tests, launcher syntax, and
`git diff --check` passed. The focused real-model cancellation checkpoint test
passed on Apple M3 Ultra with the Vision-Exp MXFP4 model. The next-start binary
SHA-256 is
`0b19999ed74d64cde759a1f0621fe4d87c742e5764e6d83dd60a175beb93f049`;
the immediate binary rollback is `ds4-server.bak-20260902T033458Z` with
SHA-256 `6d91f5bbae4ced66c9273805ca489d83df0c0f0862abc73d6c44b4cb1f58eef4`.
The service was owner-authorized to stop during the failed cold prefill and was
left stopped for the focused model test and handoff.

Re-verified after item 24 (`552f6b8`, 2026-09-02): clean optimized Metal
server/test/agent builds, focused server and agent suites, the CPU portability
build, ASan+UBSan server tests, and `git diff --check` passed. Two independent
real-model runs used Vision-Exp MXFP4 on Apple M3 Ultra, one from the clean
upstream PR worktree and one from the combined production candidate. With cold
and continued writes disabled, graceful shutdown wrote a 1,044-token
`key=vision-token-text` checkpoint; restart restored it in 10.7–11.0 ms and
resumed at token 1,044. Replacing the red image with blue rebuilt at token 0,
and replaying the same words without an image also rebuilt at token 0. The
next-start binary SHA-256 is
`64ab494635d9d62c834c6f2156d4333702a233fea5a57792d551906392d1670b`;
the immediate binary rollback is `ds4-server.bak-20260902T050000Z` with
SHA-256 `0b19999ed74d64cde759a1f0621fe4d87c742e5764e6d83dd60a175beb93f049`.
The live production PID 97796 started at 00:44:02 before this binary was built;
it was not stopped, restarted, signalled, or reconfigured, and still runs the
prior executable image until the owner chooses to restart.

Re-verified after items 16–20 and the FP8 width guard (`2975454`, 2026-09-01)
in an isolated worktree: clean optimized Metal builds of the server and test
binaries; server, agent, and DeepSeek Vision image tests; CPU build; ASan+UBSan
server tests; `git diff --check`; and a second complete diff inspection passed.
The model-free Metal suite passed on the Apple M3 Ultra, including 65,536
E4M3FN oracle inputs with zero mismatches. Every FP8 amax call site was audited
for its launch width. No model was loaded and the running service was not
stopped or signalled. The installed next-start binary SHA-256 is
`3997c853b16960726a38f724c35c7445e49eb024ee7934fb720717302ec12ac1`;
the immediate binary rollback is `ds4-server.bak-20260901T193036Z` with
SHA-256 `78371b696c93c68321bc41b0dacdb3a7fba01fa5a3f36cb6b9e9c575a6a81ae3`.
After the owner restarts, the startup line must report
`prefill_quantum=4096 mixed_prefill_quantum=64`; live throughput and cache
behavior still require observation before calling the performance change a
production win.

Re-verified after the audited reconciliation (`1d6e38a`, 2026-09-01) in an
isolated worktree: forced Metal builds of `ds4_test`, `ds4-server`,
`ds4_agent_test`, and the DeepSeek Vision image test; server, agent, and image
regression runs; CPU-only builds; ASan+UBSan server tests; launcher syntax/help;
and `git diff --check` all passed. The new model-independent regressions cover
exact GLM one/two-newline replay, empty tool content, forward/backward/zero KV
frontiers, integer overflow, and the narrow speculative-tail eligibility rule.
No model was loaded for this reconciliation; the earlier focused Vision-Exp
model checks remain recorded above. The installed next-start binary SHA-256 is
`78371b696c93c68321bc41b0dacdb3a7fba01fa5a3f36cb6b9e9c575a6a81ae3`;
the immediate binary rollback is `ds4-server.bak-20260901T170627Z` with
SHA-256
`538efe67a6d5673a4bb5e046867b0f08d30f9e6761be860f540ff99cf5d3be9e`.
The source rollback is branch
`codex/backup-main-vision-pre-pr-reconcile-20260901T170627Z` at `45e722a`.
Live PID 15543 remained running and listening throughout; it was not restarted
or signalled, and no model or cache data was loaded, unloaded, or modified.

Re-verified twice after patch 14 (2026-09-01) in the isolated main/Vision
candidate worktree: forced clean-source builds of `ds4_test`, `ds4-server`,
`ds4_agent_test`, and `tests/test_deepseek4_vision_image` passed;
`./ds4_test --server`, `./ds4_agent_test`, the DeepSeek Vision image test, and
`git diff --check` all passed. The regression directly proves an appended image
at the exact live frontier reuses that frontier, while an earlier token edit,
old-image removal/movement/fingerprint change, or new image inserted before the
frontier rejects reuse. The tested binary (SHA-256
`d706b63a25b9f49aeee8c7b61c1a00bdc1be7fd9a5c7acdaa5254625eb796939`)
was atomically installed for the next user-initiated restart; the previous
binary is `ds4-server.bak-20260901T121500Z` (SHA-256
`be5d87467a167e1d19c4f6914c166dae7a0af15ae326279290c74a530acbbb93`).
The running PID was not restarted or signaled during preparation.

Dropped: the `DS4_GLM53_PER_RANK_CAP_GIB` per-rank cap override — upstream
removed the fixed 110 GiB ceiling in the rewritten branch.

Re-verified after patch 6 (2026-08-29, CPU-safe tests only — no service restart
was performed): the production binaries rebuilt without warnings;
`./ds4_test --server` OK (includes GLM/Pi replay, MTP-tail rollback, and the
9,703 + 2,048-token continued-checkpoint regression);
`ds4-eval --self-test-extractors`; `ds4_agent_test`;
`tests/test_layer_pack` 97/97; `tests/test_engine_mgpu_placement` 108/108;
`tests/test_gpu_args`; `tests/test_gpu_args_cli.sh` PASS=83 FAIL=0; and
`tests/test_sampling` OK. `git diff --check` and launcher shell syntax checks
also passed. A read-only envelope audit of `/tmp/ds4-kv-batched` found 46/46
valid GLM-5.3 Q4 384K files (valid header/ABI, declared size, and rendered-text
SHA-1); the old files contained zero `continued` entries, independently
confirming the fixed scheduling failure. Requires a service restart and a real
cold-to-warm Pi replay before the production fix can be called proven live.

Re-verified after patch 7 (2026-08-29; no service launch):
`./ds4_test --server` OK, including PR #765's alien-subthread-to-empty-slot,
reuse-tier, dispatch, and staleness regressions; `ds4_agent_test` and extractor
self-tests passed; layer placement 97/97 and multi-GPU placement 108/108;
GPU argument CLI PASS=83 FAIL=0; sampling OK; GLM-5.3 KDA Metal and Q4/MXFP4
Metal suites passed. The model-backed four-session Q4 oracle passed mixed
decode/prefill with identical selected tokens, maximum full-logit delta
`3.39746e-05` under the documented `0.001` GLM tolerance, and a small-run
batch/serial speedup of 1.46x. The macOS 27 SDK emitted 27 pre-existing
`didModifyRange:` deprecation warnings from untouched Metal code; the same
warnings occur on clean upstream-based PR worktrees and were not introduced by
this server-only integration. A real cold-to-warm Pi replay still requires a
user-authorized server start before production cache behavior can be called
proven live.

Re-verified after patches 8–10 (2026-08-30; service remained stopped): the
evaluation and production binaries compiled successfully; `./ds4_test
--server` passed with exact-image hit, changed/missing-image miss,
memory-text/BPE replay, batched live-frontier resume, appended-image rejection,
and disk-write refusal coverage. `git diff --check` passed. Running the full
model suite without an explicit model path stopped immediately because its
default `ds4flash.gguf` is absent; this was not a test failure and no model was
loaded. Model-backed continued-prefill and M3 Ultra throughput validation, plus
the required cold-then-warm Pi image replay, remain first-start acceptance
checks; no live claim is made before those measurements.

Production launcher delta prepared 2026-08-29 and updated 2026-08-31: normal
`start-ds` defaults `DS4_MTP=0` and now starts the one-session batched
ordinary-decode configuration directly. The former `start-ds-1` MTP
evaluation alias was removed; single-session MTP tests require an explicit
command.

Previous state (upstream `a60a2a0` + both patches) preserved as branch
`codex/ds-glm53` (patches committed at `99fe1dc`).

Verified before handoff (2026-08-29, CPU-safe tests only — the production
server was left running): clean `make -j8`; `ds4-eval --self-test-extractors`;
`ds4_agent_test`; `tests/test_layer_pack` 97/97;
`tests/test_engine_mgpu_placement` 101/101; `tests/test_gpu_args`;
`tests/test_gpu_args_cli.sh` PASS=83 FAIL=0. Launcher flags re-verified
against the new binary (`--ctx`, `--kv-disk-dir`, `--mtp`, `--mtp-timing`).
KV store code (`ds4_kvstore.[ch]`) is unchanged upstream, so disk checkpoint
headers remain structurally compatible — but see the first-boot KV note below.

## Rollback

For this 2026-08-30 update, the pre-update source is preserved as
`codex/backup-glm53-pre-upstream-20260830T201426Z` at `edd92d5`, and the exact
pre-update executable is `ds4-server.bak-20260830T215541Z` (SHA-256
`8a90d2efd921320bed9e7f9d0f77498ff00a7ee1fd1ce65e4874ba11f9034811`).
Only roll back while the service is stopped. The production KV directory and
launcher need no rollback because neither was changed.

Stop GLM with `stop-ds-glm53f` (or `stop-ds`). The old branch
`codex/ds4-six-session-candidate` remains available. The retired DeepSeek 0731
MXFP4 file is preserved only on `/Volumes/Jordi's Stuff/ModelWeightsBup`;
restoring and loading it requires Jordi's explicit approval.
Q2 GLM-5.3 (`download_model.sh glm53-q2`, ~90 GiB) is the in-envelope
fallback if the raised cap ever misbehaves.

---

# RETIRED: DeepSeek-V4-Flash production (history, pre-2026-08-28)

## Normal operation

The expected shell aliases are:

```sh
alias start-ds4="/Users/jordiposthumus/ds4/ds4-startup.sh"
alias stop-ds4="/Users/jordiposthumus/ds4/ds4-stop.sh"
```

Use `start-ds4` with no extra options for normal production. It replaces the
existing launchd-owned instance, waits for readiness, and otherwise preserves
the familiar UX. Do not restart a busy service merely to apply a prepared code
or configuration change; let the user choose the restart time.

## Authoritative defaults

| Setting | Production value | Reason |
| --- | ---: | --- |
| Hardware | Mac Studio, M3 Ultra, 512 GB unified memory | Target machine |
| Checkout | `/Users/jordiposthumus/ds4` | Canonical source, alias target, production binary, and `gguf` directory |
| Branch | `codex/ds4-six-session-candidate` | Local integration branch |
| Model | `DeepSeek-V4-Flash-MXFP4Experts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-mxfp4-0731.gguf` | Validated 0731 MXFP4 model |
| Endpoint | `127.0.0.1:8000` | Local OpenAI-compatible service |
| Context | 384000 tokens | Long Pi sessions with headroom below 393216 Think Max threshold |
| Token limit | 384000 | Matches configured context ceiling |
| Resident sessions | 6 | Desired concurrency; capacity, not a promise of higher single-request speed |
| Thinking | enabled (`--think` default) | Preserve the established response behavior |
| Prefill chunk | 4096 tokens | Backend prefill work size |
| Uncontended scheduler quantum | 2048 tokens | Official server scheduler default |
| Mixed prefill quantum | 64 tokens | Keep decode latency responsive while another session prefills |
| Warm weights | enabled | Avoid first-request weight warmup |
| KV directory | `/tmp/ds4-kv-batched` | Persistent local checkpoint pool across restarts |
| KV budget | 349525 MiB (about 341.3 GiB) | One-third increase over the former 256 GiB ceiling |
| Continued checkpoint interval | 16384 tokens | Restart/fallback coverage without excessive checkpoint I/O |
| Cold-anchor prompt ceiling | 384000 tokens | Enable stable anchors for every prompt that fits this server context |
| Live rewind reuse | disabled | A production incident on 2026-08-25 demonstrated cross-session state bleed after rewinding an unrelated resident slot |
| Rewind minimum | 256 shared tokens | Avoid rewinding for trivial prefixes |
| Prompt timing logs | enabled | Diagnose cold, sync, and tail prefill time |
| Main log | `/tmp/ds4-start.log` | Startup, cache, prefill, and generation diagnostics |
| launchd label | `com.vonbling.ds4-0731` | Durable ownership after the terminal exits |

## Cache policy: do not casually change these

`DS4_KV_REWIND_REUSE=0` is the production setting. On 2026-08-25 a fresh Pi
session about deglycation was assigned a resident slot containing an unrelated
ResourceManager conversation. The server logged a rewind from 150381 tokens to
their shared 8546-token system-prompt prefix, after which the new session
generated reasoning from the ResourceManager prompt. This is the demonstrated
correctness failure for which the rollback exists. Do not enable rewind reuse
again until the backend passes an explicit concurrent cross-session isolation
regression. Disabling it can make divergent long prompts prefill more slowly;
that performance cost is accepted in favor of correctness.

`DS4_COLD_MAX_TOKENS=384000` deliberately covers the full server context. In
DS4, zero means **disable cold checkpoints**; it does not mean unlimited. Cold
checkpoints retain the stable system/tool prefix before a task-specific user
message and are especially valuable for Pi. PR #814 makes these cold anchors
outlive less reusable evict/shutdown dumps when the cache reaches its budget.

The cache reaching approximately 341 GiB is expected: that is its configured
ceiling, after which scoring and eviction choose what survives. Do not clear the
directory merely because it is full. Never reuse this directory with alternate
weights; give another model a separate `DS4_KV_DIR` to avoid unsafe or wasteful
cross-model checkpoint reuse.

The 64-token mixed quantum is a latency/fairness choice. While any slot is
actively decoding, another slot's prefill may progress in 64-token increments
and therefore show lower aggregate prefill throughput. When no generation is
active, the scheduler uses 2048-token quanta. This tradeoff supports six useful
interactive sessions rather than maximizing one prefill at everyone else's
expense.

## Local code provenance

The branch is based on the locally validated official production line and
contains these important local/integrated changes:

- `1e6e3df`: batched prefill, cancellation, and KV checkpoint performance and
  safety fixes.
- `47824da` (upstream PR #814 commit `a80811e`): prefer reusable cold anchors
  over live eviction/shutdown dumps.
- `3744873` plus `3ed37af` (upstream PR #818 through `c5942f6`): live-KV rewind
  reuse and corrected prompt-window/prefill timing.
- `76b5de9`: make six resident sessions the normal no-argument UX.
- `afccc5a`: raise the disk KV budget by one third.

The PR #818 integration had a conflict in the prompt-sync block. The resolution
kept the local interrupt-aware sync and disk-pin cleanup while adding the
upstream timing/rewind path. The upstream PR head was checked again on
2026-08-24 and remained `c5942f6`.

## Verification after a user-initiated restart

The startup summary should include:

```text
Context:       384000
Mixed q:       64 tokens (while decoding)
KV budget:     349525 MiB
Checkpoints:   every 16384 tokens
Cold anchors:  prompts up to 384000 tokens
KV rewind:     0
Thinking:      --think
Sessions:      6 resident batched sessions
```

Confirm launchd received the intended settings:

```sh
launchctl print "gui/$(id -u)/com.vonbling.ds4-0731"
```

Normal production logs must not contain `live kv cache rewind-hit` while
`KV rewind: 0` is active. A cold first request should be able to log a
`reason=cold` checkpoint, and later related requests may hit it from disk.
Rewind-hit behavior belongs only in a dedicated isolation test using a separate
KV directory, never in the production cache.

Before handing off a launcher or integration change, run:

```sh
bash -n ds4-startup.sh ds4-runner.sh ds4-stop.sh
make ds4-server
make ds4_test
./ds4_test --server
git diff --check
```

These checks do not replace a real long-context rewind test after restart, but
they must pass before asking the user to switch.

## Updating from upstream

Do not run a blind pull in the live checkout. Use this sequence:

1. Record `git status`, the current branch/head, launcher defaults, and the
   active launchd arguments.
2. Fetch upstream and prepare the update in a separate evaluation branch or
   checkout. Keep the current service running.
3. Reapply the local commits and launcher files deliberately; resolve prompt
   sync or KV-cache conflicts rather than accepting either side wholesale.
4. Build and run the server tests. Compare upstream defaults against this file,
   particularly sessions, thinking, mixed quantum, cold anchors, disk budget,
   and live rewind.
5. Report the exact diff and let the user choose when to restart.
6. After restart, verify launchd arguments and exercise continuation, tool-call,
   abort/retry, disk-hit, and concurrent cross-session isolation behavior.

The rollback code line is branch `codex/official-main-production` at `74595ff`
in this repository. Branch `codex/legacy-ds4-main` preserves the former
standalone `~/ds4` checkout and its unique `c46d614` commit; it is archival, not
the production line. The configuration-level rewind rollback,
`DS4_KV_REWIND_REUSE=0`, is the persistent production default following the
2026-08-25 isolation failure.

## 2026-09-03 V6 cancellation integration — staged, not restarted

The cancellation amendment is integrated into the existing production source
and the tested Metal binary is installed for the next ordinary start. This did
not restart, signal, load or unload the running service (PID 68701 remained the
listener). That process still runs the pre-integration binary.

The isolated integration is `codex/production-cancel-v6-20260903` at
`6ae213e635ddcae2c7602e0519dcfa4280c44adf`. Its parent freezes the prior production
working source, including the pre-existing uncommitted server edits. Only
`ds4.c`, `ds4.h`, `ds4_server.c` and `tests/ds4_test.c` changed for this integration.
It adds the audited exact cancelled-request binding, untouched-prompt and
terminal-write handling, backend/layout guards, and a cancellation tier in the
existing reuse-aware slot probe. The probe regression verifies a three-token
client replay reuses the four-token hidden frontier, unique-owner routing,
ambiguous/edit rejection, and invalidation. Existing speculative-tail guards,
OpenAI continuation, prefill alignment, scheduler and kernel changes remain.

No launcher, model, sampling, context/output ceiling, concurrency, disk-cache
directory/budget/format, or rewind setting changed. In particular the existing
262144 ceilings, ten resident / one active policy and disabled rewind remain.
The new upstream vision conditioning-hash key is NOT installed here: migrating
the older local image-key scheme requires separate approval because existing
image checkpoint hits can be lost. Text cache identity is unchanged.

Installed binary SHA256:
`0de63acfb6fa1178e4d87fef4f7c1be7609a7b7158c87a639db3d445bbcc364f`.
Installed server source SHA256:
`4cbb557acc487359f54dbab991fb29a37090e3cdcfe9dfcac98eb1e501a5935f`.

Validation: isolated Metal server/test build, model-free server/agent tests,
CPU server compile/link, ASan+UBSan server tests (normal Metal object, leaks
disabled), launcher syntax and diff checks passed. Installed sources were
byte-compared against the tested tree. No model was loaded for this integration;
the exact production adapter still needs a real abort/retry acceptance run after
an authorized restart. Earlier V6 candidate real-model evidence is separate.

Rollback inputs and logs: `local-performance/integration-20260903T1055Z/`.
It contains the prior source, header, test, launcher, document and binary.
Restore the source/binary together only after explicit rollback approval; never
overwrite an executable in place while a process may use it. No KV deletion or
format conversion is necessary for this cancellation-only rollback.

## 2026-09-03 cancellation save-counter amendment — tested and installed

This supersedes the staged binary above. During the authorized drained-M3
window, production was gracefully stopped after its work and queue reached
zero; all ten occupied resident slots were saved before exit. The exact local
candidate `cccafb4561ff4b4fde9a127e1d28ec25988d814d` was tested on Metal with the
existing Vision-Exp model, then installed for the normal production restart.

The amendment changes only `ds4_server.c`: after successful cancellation
rollback/preservation, a continued-save counter beyond the restored prompt is
clamped to that prompt. Lower/equal counters and failure invalidation remain
unchanged. This prevents saves made by a discarded generation tail from
suppressing checkpoint opportunities for a new tail. Runtime behavior is four
added lines plus owning-slot argument plumbing; the remainder is regression
coverage. The source byte-matches the tested local candidate; all other engine,
header and engine-test sources match that same candidate without further edits.

Installed server SHA256:
`31c83e2c986848c90667e46aece65c49cadbf650d69728eccbe02f5794730f17`.
Installed server source SHA256:
`6d6370a195af454c8ac9dbd794c411405af9cda0c3a4d261623763c180cff60d`.

No launcher, model, sampling, context/output ceiling, concurrency, prefill
quantum, disk-cache path/budget/format, image-key scheme or rewind setting was
changed. Normal settings remain 262144 context/output ceilings, ten resident
sessions, one active request, 4096 prefill / 64 mixed quantum, cold anchors
enabled, 16384 continued interval and rewind disabled. Scratch test settings
were process-local and were not copied into the production launcher.

Real-model validation passed for the exact local candidate: 607 replayed
full-logit vectors were identical after a cancellation checkpoint restored an
overwritten raw KV ring; text/image abort retries reused 4010/2107 tokens;
image/tool cancellation restored and reused all 1272 tokens; an omitted-reasoning
tool continuation reused 1112 tokens; the first of ten resident conversations
remained reusable. Model-free tests prove the continued-save counter red-to-green
at save boundaries, repeated cancellation, lower counters and restore failures.
The real-model runs complement those tests; they do not generate a tail across
a 16384-token continued-save interval. No claim of universal cache correctness
or long-context throughput follows from these bounded checks.

Timestamped rollback copies, commands, manifests and results are in
`local-performance/validation-20260903T1134Z/`. The prior installed source and
binary are `production-ds4_server.c.before` and `production-ds4-server.before`;
the pre-window log and shutdown saves are preserved there too. As before,
rollback requires explicit approval and source/binary must move together while
the service is stopped. No cache deletion or format conversion is needed.
This local installation is not a push of the separate #960 upstream amendment.

## 2026-09-03 Metal indexer stack — tested and installed

Upstream PRs #830, #831 and #832 are integrated into the existing production
source. They change only the pre-M5 Metal DeepSeek indexer prefill scorer and
top-512 selector plus focused tests and Makefile targets. No launcher, model,
vision encoder, sampling, context/output ceiling, concurrency, prefill quantum,
KV directory/budget/format, cache policy or rewind setting changed. In
particular production remains 262144 context/output, ten resident sessions,
one active request, 4096/64 prefill quanta and rewind disabled.

The stack uses the tiled5 register-resident scorer, a canonical
`(score descending, index ascending)` order for exact score ties, and an exact
streaming top-512 selector for prefills of at least 32 tokens. Both new paths
remain independently rollbackable per call with
`DS4_METAL_DISABLE_ARGSORT_CANON=1` and
`DS4_METAL_DISABLE_TOPK_STREAM512=1`; neither rollback is set in the normal
launcher. The streaming selector is exact relative to the canonical order.
The canonical tie rule intentionally differs from legacy DS4 only when indexer
scores compare exactly equal, so the complete stack is deterministic but not a
claim of bit-identical behavior to legacy tie selection.

The PR #832 test originally used obsolete opt-in variables after the final
commit made both paths default-on. That allowed its two nominal arms to select
the same streaming implementation. Local commit `e06f342` corrects the test to
exercise the final default and rollback flags, adds dispatch-boundary, odd-row,
dense-tie, 64K-frontier and non-512 cases, compares both GPU paths to an
independent CPU total-order reference, poisons outputs and releases every
allocation. This is test hardening for Adrian Galilea's PR, not a competing
implementation.

On the drained Apple M3 Ultra with the production Vision-Exp MXFP4 model, an
alternating ABBA benchmark isolated streaming against canonical full argsort.
Every one of 1,551,360 compared final logits was bit-identical:

| Prefix | Streaming | Full argsort | Streaming gain |
| ---: | ---: | ---: | ---: |
| 32768 | 540.1569 t/s | 534.0709 t/s | +1.1395% |
| 65536 | 508.5590 t/s | 498.3680 t/s | +2.0449% |
| 131072 | 438.2469 t/s | 404.0194 t/s | +8.4717% |

The canonical comparator changes long-context logits relative to legacy tie
selection, so quality was checked separately. The repository's official
100-case Vision-Exp continuation scorer was byte-identical at 4096 context
(`avg_nll=0.167972379` in both arms), but that raw-window test does not exercise
the compressed indexer. A held-out next-token slice of *I promessi sposi* was
therefore scored after real compressed frontiers with streaming disabled in
both arms. At 32768, canonical improved average NLL from `1.029397156880` to
`1.021238518828` (-0.7926%) and greedy matches from 363/512 to 367/512. At
65536, NLL moved from `1.212505775262` to `1.212609296449` (+0.00854%) while
greedy matches improved from 340/512 to 342/512. Combined NLL improved 0.3593%.
These two corpus slices are evidence of no meaningful observed regression, not
a universal quality proof.

The installed production-shaped build also passed 2,134,134 exact scorer cells,
135,136 canonical/default/CPU top-k entries, the model-free server suite,
launcher syntax and `git diff --check`. A clean exact-head worktree passed the
CPU portability build. The only compiler diagnostics were 27 existing macOS 27
`didModifyRange:` deprecation warnings from untouched code.

Installed `ds4-server` SHA256:
`265671a75997bf1d6fb3bd252e95f076d16fdae05f4eac9e68dccb4b1048bee6`.

Post-install production validation passed. Launchd started PID 86306 with that
binary, Vision-Exp model and encoder, 262144 context/output/cold ceilings, ten
resident sessions, one active request, 4096/64 prefill quanta, the unchanged
KV directory and `DS4_KV_REWIND_REUSE=0`. `/v1/models` reported the same
262144 limits. A correctly shaped no-thinking continuation reused 20 cached
tokens and evaluated only its 10-token suffix. Repeating only the shorter
prompt did not rewind, as required by the disabled-rewind safety policy. DSG
then resumed only `m3-studio` and verified `drained=false`, `is_healthy=true`,
`quarantine=null`, load 0 and queue 0.

The previous binary and every replaced source are retained with timestamp
suffix `20260903T235728Z`; rollback requires explicit approval and no KV cache
deletion or conversion. Test sources, commands and result TSVs are preserved in
`local-performance/pr832-eval-20260903T225737Z/`.

## 2026-09-04 PR #959 pruned argsort merges — tested and installed

Upstream PR #959 at exact head
`ea16db6f7f800b1311a199bf6debbc143878b1bb` is installed. The runtime change
prunes intermediate Metal argsort merges to the requested `top_k` instead of
carrying candidates that later rounds must discard. The comparator, final
selection and sampling behavior are unchanged. Local commits `a541198` and
`e4a6195` contain the upstream runtime change and focused Metal regression test;
`5ab05e6` supplies the test's missing `ds4_image.o` link dependency. That last
commit is test plumbing only and does not alter the server binary.

No launcher, model, vision encoder, sampling, context/output ceiling,
concurrency, prefill quantum, KV path/budget/format, cache policy or rewind
setting changed. Production remains 262144 context/output, ten resident
sessions, one active request, 4096/64 prefill quanta, the existing
Vision-Exp-specific KV directory, continued saves every 16384 tokens, cold
anchors enabled and rewind disabled.

Correctness was checked at three levels. The focused Metal suites passed odd
run counts, maximal pruning, non-power-of-two `top_k`, dense ties, the 31/32
streaming gate, a 64K compressed frontier and non-512 fallback. Real-model
frontier logits at 32768, 65536 and 131072 tokens were byte-identical between
baseline and candidate. A separate 64-step teacher-forced trace after a 32768
token real-model prefill compared all 8,273,920 float logits (33,095,680 bytes)
and was byte-identical; both files have SHA256
`fdef848d3bcb50ddb75d069842b0e9be42678543ac2e700b1e0fc4581441c871`.

Whole-model ABBA timing varied by several percent between runs, so it was not
used to claim a small net speedup. An evaluation-only same-process switch then
alternated legacy and pruned merges on the same resident buffers and GPU state.
Across 20 blocks per shape, median affected-kernel speedups were 0.1290% at
8192 candidates (319.3220 to 318.9105 microseconds), 3.4121% at 32768
candidates (355.2300 to 343.5090 microseconds), and 11.7051% at 65536
candidates (388.5700 to 347.8533 microseconds). Every block produced the same
selected-index checksum. The switch exists only in the disposable evaluation
worktree; it is not present in production or proposed upstream.

The production-shaped build passed `tests/test_argsort_metal`,
`tests/test_topk_ab`, `./ds4_test --server`, launcher syntax and
`git diff --check`. The clean staging head also passed the CPU portability
build. The only compile diagnostics were the existing macOS 27
`didModifyRange:` deprecation warnings from unrelated code.

Installed `ds4-server` SHA256:
`68c29f9e4f4a87605578988cac309e58d97aeef02972f2d6a55c717a514ee477`.
The previous binary SHA256 was
`265671a75997bf1d6fb3bd252e95f076d16fdae05f4eac9e68dccb4b1048bee6`.

Post-install validation started launchd PID 49195 with the unchanged effective
arguments and confirmed `/v1/models` still advertises 262144 context and output
limits. A real 1879-token request was cold and wrote a checkpoint; its identical
repeat reported 1879 cached tokens, zero cache-write tokens, loaded the disk
checkpoint in 16.4 ms and performed zero prefill. Because the disk cache was
already at its configured budget, storing that validation checkpoint evicted
one zero-hit 147456-token checkpoint; no cache directory, format or policy was
changed. DSG resumed only `m3-studio` and verified it healthy, undrained,
unquarantined and able to accept work.

Exact rollback copies, hashes, CSVs, full-logit traces, benchmark harnesses and
commands are retained in
`local-performance/pr959-production-20260904T121730Z/`. Rollback requires
explicit approval and the server must be stopped before restoring the matching
source and binary; the KV cache needs no deletion or conversion.
