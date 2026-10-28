# Bounded execution and durable closeout

The scheduler decides when to wake this chat. Do not put cadence expectations, scheduler drift checks or frequency fields in maintenance state. TTL and notification backoff are safety controls independent of scheduling.

## Startup and execution

1. Read required repository instructions, then `cycle.py status` (compact by default), `scan` and `projects.py` (all pages). Follow [projects.md](projects.md) to reconcile item/issue aliases and exclude generated stage children. Project access failure is a source blocker, not an empty backlog. Use `status --full` only to investigate a specific missing detail. Save large logs under `dist/maintenance/<run-id>/`; return factual summaries and paths instead of full build logs or old notification bodies.
2. Acquire the lease. An active lease means skip quietly; an expired lease still needs process/PR/release reconciliation before recovery. Run `notify.py retry` once. Do not re-register schedules.
3. Resume prior work first. Persist `--worktree`, `--branch`, `--next-action` and `--external-job` on the issue or local task checkpoint as those facts become known. Pending tasks are listed separately in `scan` and `status`; they never become synthetic GitHub issue requests. A job ID includes its service/type; resuming always reads the actual external result first.
4. Before substantive delegation, create/reuse a Project draft stage item linked to the root item (never a new repository issue) under the selected root item, then sync actual status through the coordinator. Explicitly spawn a fresh bounded worker with current acceptance criteria, safe workspace and evidence paths. Give it no external-write or lease ownership. The coordinator serializes merge, signing and release; signing search-list changes are shared macOS user state even across worktrees. A worker's success summary requires actual diff/test/evidence review before advancing.
5. Worker handoff: root project/item IDs, stage draft item/content IDs, actual phase and sync request, issue/task ID; worktree/branch/head SHA; reproduction; files changed; commands/results and evidence paths; app interaction actually observed; remaining limits; exact next action. Do not copy raw transcripts or credentials. Reviewers are independent and read-only. Do not spawn workers for idle scans.

When waiting a long time for CI/notarization, persist the job and next action and yield only at a safe boundary. Do not release the lease while a worker or signing command can still mutate the repository/keychain; stop or finish that owned work first. Next activation reacquires and reads back the job result. Short bounded waits can finish in the same activation.

## Mandatory closeout

Before yielding, even on caught failure:

- Save the real issue checkpoint or proactive-task plan/PR evidence. Release stages never reset merely because an activation ends. Record a blocker and observable retry prerequisite when needed.
- Confirm owned workers/processes ended or were safely stopped. Keep unfinished branches, signed assets, public verification downloads and unknown delivery records. Copy needed worker evidence to a durable location outside any worktree before archiving it with the app's managed-worktree tool. Never delete the main checkout or user pin contents.
- Send only real milestone/novel-fault notifications via the deduplicated helper. Notification failure does not replay the business action. Idle scans have no commentary or routine completion message.
- Run the following with the actual result; wrap scripted stages in `try/finally` or a trap where appropriate. A hard crash cannot be guaranteed to clean up: TTL/recovery and signing recovery records remain required.

```bash
python3 scripts/maintenance/cycle.py finish --run-id "$PIR_RUN_ID" \
  --outcome waiting --note "Current-head CI pending; no local writer remains" \
  --next-action "Read PR head and stored Check run before merge" \
  --evidence "$PIR_EVIDENCE"
```

Outcomes: `idle` (no unfinished checkpoints and no work), `completed` (selected work finished for this activation), `waiting` (external job/unchanged prerequisite), `blocked` (new actionable prerequisite failure), `failed` (unexpected failure). These describe the activation, not proof that the issue/release is verified. Always pass an explicit outcome. Backward-compatible omitted outcome is `completed`.

`finish` atomically writes a private `runs/<run-id>.json` before releasing the lease and records `lastRun` with `finishedAt`, outcome, next action and evidence. An invalid result or journal I/O failure retains ownership. Repeating finish after an unknown local result returns the recorded result if no new lease intervened. Default status includes pending issue/task checkpoints and their completion counts, last-run result and notification counts, not old message bodies or verified history. Full state and run journals remain available for incident analysis.

## Improvement evidence

Choose a proactive task only when owner issue/release work cannot advance. Record the observed bottleneck, before measurement/reproduction, smallest proposed change and acceptance in a repository plan. For Project-origin or newly delegated issue work, use the stable item taskSlug and draft parent/stage items from projects.md. Keep behavior and product scope; use a normal reviewed PR and app release only for application changes. A tooling-only improvement needs no empty app release. Before delegating, create a local checkpoint using a stable slug and repository plan; persist its branch/worktree/head and subsequent PR/CI facts with `--task` throughout the same lifecycle. A new task requires `--plan`; later checkpoints inherit it. Finished tasks require the same evidence and no-app-release reason as issue checkpoints. Never fabricate a bug report or route task notifications through a fake issue number. Real selected Project work may use its existing linked owner issue for progress and Telegram events. Report meaningful proactive completion/new blockers in this chat; Telegram events require the real linked issue; drafts without one use the chat fallback. Project notifications use the real existing linked owner issue; include the Project item link in detail.

Fresh worktree preflight: ignored dependencies and build outputs are not copied. For this repo, install locked website dependencies with `npm ci --prefix website` if `website/node_modules` is absent before full `scripts/check.sh`. Never copy user configuration or credentials into a worker worktree. Keep the setup result in the worker handoff.

Example local task (use real plan/evidence and current lease):

```bash
python3 scripts/maintenance/cycle.py checkpoint --run-id "$PIR_RUN_ID" \
  --task "$PIR_TASK" --plan "$PIR_PLAN" --phase implementing \
  --worktree "$PIR_WORKTREE" --branch "$PIR_BRANCH" \
  --next-action "Collect worker commit and validate reproduction evidence"
```

Tasks have separate `resume`/`blocked` entries in `scan`, not remote issue fingerprints. Recheck a task blocker once per activation; read its real PR/head/CI before continuing. Verified tasks leave the pending list. `finish --outcome idle` rejects unfinished tasks as well as unfinished issues; use waiting/blocked when preserving a pending task. Owner issues and release recovery remain higher priority than starting another proactive task.
