# Recoverable proactive maintenance tasks

## Evidence and scope

The first activation after the issue-26 pilot found no open issues, pending issue checkpoints or open PRs. The owner authorized bounded evidence-backed architecture/maintenance improvements. `cycle.py checkpoint --help` still requires a numeric issue; default status and scan discover only issue records. A proactive plan can be written, but another activation cannot discover its PR/worktree/stage through the existing recovery contract. Fabricating an issue would violate that contract.

Task identity: `maintenance-task-recovery`. This change affects maintenance tools/skill only, so no application release or version change is needed. Evidence lives in `dist/maintenance/c28159951ca148aebde6ebe42fbe383f/`.

## Design and acceptance

Add a local `tasks` namespace to the existing private schema-1 state. `checkpoint` accepts exactly one of `--issue NUMBER` and `--task SLUG`; a new task requires a plan, and later phases inherit it. Slugs are bounded lowercase identifiers in a separate task namespace; they are never resolved as GitHub issue resources. Task records share the repository lease, phase/evidence/release gates and blocked resume context. History identifies whether an entry belongs to a task or issue. No fabricated issue/comment/notification or scheduler changes.

`status` compactly includes pending task handoffs and a verified-task count. `scan` returns pending tasks separately from remote issues: resume/blocked only, with plan/PR/head/worktree/next action. The coordinator reads actual PR/CI state before advancing. A pending task prevents an idle closeout. Older state without tasks remains readable.

Acceptance tests: real CLI cross-run resume; new task plan/slug validation and issue/task CLI exclusivity; blocked task retains release/PR context; invalid lease cannot mutate; verified task requires evidence/no-app-release reason; verified task is omitted from pending scan; unchanged issue tests remain green.

## Execution

1. Stable coordinator owns production lease; fresh worker with a clean context implements/tests in managed worktree `maintenance-task-recovery` and returns factual handoff.
2. Worker writes red regressions, implements the minimal compatible state/CLI extension, runs ReleaseTools tests and commits locally without external writes.
3. Coordinator updates the canonical skill/lifecycle to use task checkpoints before independent work, integrates worker, simulates cold cross-run recovery, runs full checks and independent read-only review.
4. Create one PR, require current-head Check success, merge matching head and read back. Checkpoint this actual task verified with `release=not-required`, record result/evidence, archive completed worker after copying evidence, finish activation with explicit outcome.

## Validation evidence

- Worker RED reproduced the original CLI requiring `--issue` and Store lacking a task keyword; logs copied to the durable run evidence directory before worktree cleanup.
- Worker `scripts/check.sh` exit 0: 130 Swift tests, 50 ReleaseTools tests, localizations, website and shell checks. Integrated ReleaseTools rerun: 50 tests pass. Skill validator and `git diff --check` pass.
- Independent read-only reviewer ran 35 maintenance tests and an extra temporary-state crash/recovery scenario. With zero open issues, the scanner discovers the same pr_open task/PR/head without issue API lookups; expired lease requires explicit recovery, old writer is rejected, blocked context and unchanged issue state survive, idle/verification gates remain enforced. Review passed at integrated code head 3c691bf.
- This activation itself now has a private `maintenance-task-recovery` checkpoint with its plan/workspace/next action; no synthetic issue or task Telegram event was created. No app UI or release is needed because product code is unchanged.
