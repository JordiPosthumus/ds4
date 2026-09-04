# Local production instructions

This checkout is the source used by Jordi's normal `start-ds4` and `stop-ds4`
aliases. Before changing the launcher, cache behavior, concurrency, model, or
update procedure, read `LOCAL-PRODUCTION-CONFIG.md` in full.

- Do not stop, restart, or signal the running DS4 service unless the user
  explicitly asks. Preparing and testing code does not authorize a restart.
- Preserve the simple UX: ordinary `start-ds4` starts the documented production
  configuration without extra flags.
- Keep cold-anchor checkpoints enabled by default. Keep live-KV rewind reuse
  disabled: a 2026-08-25 production incident demonstrated cross-session state
  bleed in that path. Do not enable it outside an explicit concurrent-isolation
  evaluation. For both settings, zero means disabled.
- Do not delete or replace `/tmp/ds4-kv-batched` without explicit approval.
- Do not point different model weights at the production KV directory. Use a
  model-specific `DS4_KV_DIR` for evaluations or alternate models.
- Treat upstream updates as evaluations first. Build and test before switching
  the aliases or restarting the service.
- Any intentional default change must update `LOCAL-PRODUCTION-CONFIG.md`, pass
  launcher syntax and server tests, and state the performance/correctness
  rationale.

## Standard for Antirez / upstream DS4 pull requests

Use the following process and shape for PRs to `antirez/ds4`:

1. Read `CONTRIBUTING.md` in full. Fetch the current upstream target branch and
   prepare the PR in a clean isolated worktree based directly on that head.
   Never submit local production history, launchers, aliases, cache paths,
   hardware-specific defaults, or dependencies on unmerged local patches.
2. Submit one coherent, generally useful idea per PR, preferably as one clean
   commit. Separate unrelated cache, scheduler, kernel, model, and documentation
   changes. The production mechanism should be the smallest direct change that
   fixes the abstraction or invariant; reuse existing state, locks, queues, and
   conventions instead of adding a parallel subsystem.
3. Preserve existing behavior by default unless the upstream bug itself makes
   that impossible. Validate new option combinations early, keep rollback
   obvious, and do not silently change model math, sampling, cache formats, or
   established server behavior.
4. Write the PR for a technically literate adult. Include a direct ELI20 that
   names what was coupled or broken, the concrete consequence, and exactly how
   the patch changes it. Avoid cute metaphors, sales language, vague claims, and
   unexplained local lore.
5. Test the realistic failure boundaries, not only the happy path. For
   scheduler/cache work this includes queued, assigned, worker-claimed,
   running, cancelled, completed, and reuse/eviction transitions where
   applicable. Tests may be longer than the runtime patch when they protect
   genuinely dangerous handoffs; do not remove valuable tests merely to make
   the diff look smaller.
6. Follow the project regression matrix proportionately: clean default build,
   focused unit/regression tests, CPU build for portability, sanitizers for
   server/state changes, and focused real-model checks when they add evidence.
   Do not load a local model or disturb the production server without explicit
   authorization. Record the exact machine, backend, model/quant, commands, and
   results. Distinguish an environmental prerequisite or absent optional
   fixture from a code failure, and disclose both precisely.
7. Keep the body compact and evidence-led: `Summary`, `Why`, the relevant
   behavioral/invariant explanation, and `Validation`. State backward
   compatibility explicitly. Do not claim the full aggregate suite passed when
   only focused tests ran; equally, do not describe a deliberately inapplicable
   optional-fixture test as though the patch failed.
8. Before submission, run `git diff --check`, inspect the complete diff twice,
   verify there are no accidental files or local paths, and compare against the
   current upstream head. After submission, re-read the published GitHub body,
   verify the head SHA and changed files, and confirm that the PR is open and
   mergeable. Add live production evidence only after an authorized real run.

PRs #927 and #930 are the reference pattern: generic fixes extracted from local
incidents, clean upstream branches, backward-compatible mechanisms, explicit
invariants, adversarial regression coverage, and honest real-machine evidence.
