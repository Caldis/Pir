# Maintenance pilot: issue 26 and durable cycle closeout

Goal: apply the approved stable-coordinator / bounded-worker strategy to issue 26, learn from concrete failures and make future runs recoverable without depending on a transcript.

Scope: trim only newly pasted text, preserve internal layout and clipboard bytes; retain edited/restored pins. Add compact local status and terminal run records; persist worktree/branch/next-action handoffs. The scheduler alone controls cadence: maintenance records never inspect, validate or reset it. Retain notification rate-limit backoff as an independent delivery policy.

Sequence:
1. Coordinator acquires the repository lease, reads all issue comments and sends receipt/start milestones. Isolated worker reproduces and minimally fixes the paste boundary with failing regression tests, then provides a commit and factual handoff; no external writes from worker.
2. Coordinator adds failing Python regressions for finish result/time, invalid closeout preservation, compact summary and pending handoff fields. Implement minimal atomic state changes and append-only private per-run evidence, keeping old state readable.
3. Update canonical skill, scheduled prompt and discoverable metadata via skill-creator workflow: conditional delegation, evidence-based proactive improvements when no issue is actionable, concise output and safe resource closeout. No frequency tracking or correction. Keep permission/release gates.
4. Integrate worker, inspect final diff, prepare next unused patch/build in PR, run targeted + full checks and app interaction in isolated fixtures. Independent review, exact-head CI, guarded merge, recorded source.
5. Existing signing/notary/Sparkle helpers only. Public readback + real upgrade precede completion/closure. Reconcile failures with checkpoints, never replay a completed release. Update existing heartbeat prompt preserving scheduler-owned recurrence. Close out with outcome/next action and archive completed worker worktree after evidence is copied.

Acceptance: a cold next activation can identify outcome and unfinished work without reading old logs; idle status hides old notification bodies; invalid closeout cannot lose lease; no schedule field exists in new maintenance records; user clipboard and user pin data remain intact.
