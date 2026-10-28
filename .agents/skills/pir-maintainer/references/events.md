# Verified event intake and cycle acknowledgement

Read this when a private event configuration already exists or when maintaining the receiver. Ordinary scans and release recovery work without it. `scripts/maintenance/events.py` stores intake hints; the existing maintenance lease and dual-source issue/Project workflow still govern work. Event payload text never expands owner authorization.

## Current operating boundary

The receiver can verify and queue deliveries independently of model wakeups. The current deployment uses `control_socket: null`: delivery intake does not start a model turn, and the existing heartbeat remains the fallback. Preserve scheduler configuration; event state contains no cadence expectations or drift checks.

A temporary App Server reading the same persisted thread does not prove ownership of the desktop conversation. Independent-server observations can report `notLoaded` or stale turn state while the desktop is active. Wakeups require an explicitly configured, existing private app-owned control socket, `app-server proxy --sock`, and target membership in that same server's bounded `thread/loaded/list`. Missing socket or ownership proof leaves deliveries pending before any bridge-dispatch claim; explicit fallback-cycle claims do not require model transport. Never create another server/daemon to bypass this prerequisite. `probe` reports unavailable transport without launching one; explicit `probe --temporary-readonly` may inspect persisted data but always reports `wakeReady: false` and cannot wake.

Real signed GitHub delivery proves receiver operation only. A native wakeup additionally requires observed acceptance in the existing desktop conversation and matching processed-cycle evidence. Keep these verification claims separate; neither offline tests nor an independent server read establish a native wakeup.

## Private intake and filtering

Use `scripts/maintenance/events.example.json` as the field reference. Actual configuration, webhook secret, SQLite queue and maintenance state stay outside repositories/worktrees. Files use mode 0600 and parent directories mode 0700; symlink configuration/secret/database targets are rejected. A webhook secret is read from its private file, never a command argument or log. Keep public ingress addresses and credentials out of repository documents and public progress reports. Receiver/ingress changes belong to the coordinating owner-authorized deployment.

The receiver binds only `127.0.0.1`, accepts the exact `/github/events` path and limits raw bodies to 1 MiB. It verifies the raw-body SHA-256 HMAC with constant-time comparison before interpreting JSON. Valid signed App `ping` is acknowledged without queueing; actionable events must match the fixed repository and installation. Accepted deliveries commit to SQLite before HTTP 202, UUID delivery IDs deduplicate, and only identifiers are retained. Errors are sanitized and raw payloads are not logged.

Issue opened/reopened/edited and issue-comment created/edited events exclude PRs and bot feedback. Completed workflow runs qualify only when an unfinished checkpoint's `externalJob` matches that exact run. Project changes still come from the normal Project scan. Batches become eligible after 300 seconds of quiet or 900 seconds from their first arrival. New deliveries during a claimed batch remain separate. Do not wait for debounce during a fallback activation: continue normal maintenance if no batch is due.

## Optional fallback-cycle integration

When event configuration already exists, inspect `cycle.py status` first. An active lease still means skip quietly; never claim a new event batch for another run. If free, optionally collect a due batch **before acquiring the lease and before source scans**:

```bash
python3 scripts/maintenance/events.py --config "$PIR_EVENT_CONFIG" status
python3 scripts/maintenance/events.py --config "$PIR_EVENT_CONFIG" claim
```

Save the returned real batch ID as `PIR_EVENT_BATCH`; null means no batch. Run the usual read-only issue and Project scans, then acquire the normal lease before taking action, following cycle-lifecycle.md. Read current evidence for all batch identifiers, triage them within existing scope and retain actual checkpoints/evidence. A batch acknowledges intake processing, not completion of every issue or release. If the lease becomes busy or processing cannot be established, leave the batch unresolved and continue recovery next activation.

After actual processing, finish the normal cycle with its real outcome, evidence and this exact marker as a complete note line:

```bash
python3 scripts/maintenance/cycle.py finish --run-id "$PIR_RUN_ID" \
  --outcome "$PIR_OUTCOME" \
  --note "Pir maintenance event batch $PIR_EVENT_BATCH processed" \
  --evidence "$PIR_EVIDENCE"
python3 scripts/maintenance/events.py --config "$PIR_EVENT_CONFIG" \
  acknowledge --batch "$PIR_EVENT_BATCH"
```

Acknowledgement requires no current lease, a matching `lastRun` started after the claim, the exact marker line and nonempty cycle evidence. Allowed outcomes are `completed`, `idle`, `waiting` and `blocked`, provided every batch identifier was actually checked/triaged and its remaining work recorded. `failed` cannot acknowledge; waiting/blocked acknowledges intake only, not issue or release completion. The queue records that cycle ID and evidence references. A completed model turn alone is insufficient. The receiver may acknowledge a matching finished cycle on its next dispatch check even when model transport remains unavailable.

## Interrupted or unknown outcomes

An unresolved batch suppresses further bridge dispatch but does not own the repository lease or block ordinary fallback issue/release work. Preserve delivery/batch IDs and any accepted turn ID across restarts. Inspect local status, run journals and bounded conversation readback for the exact batch marker. A coordinator may reconcile autonomously within existing authorization; human confirmation is not inherently required.

To recover an existing unresolved batch, use `events.py status` and select its actual `batches` entry with `status: unknown`; retain its `id` as `PIR_EVENT_BATCH` and inspect its `turn` when present. Do not call `claim` again for that batch. Confirm a prior accepted turn has ended or was safely stopped before taking over its processing. If that cannot be established, preserve it and continue independent normal issue/release recovery. Otherwise, run the normal scans and leased cycle for those identifiers, finish with that same marker and real evidence, then `acknowledge --batch "$PIR_EVENT_BATCH"`.

If processing is already proven, acknowledge using actual matching cycle evidence. If readback affirmatively proves no accepted turn/work began, use `reconcile --batch ID --outcome retry --evidence REFERENCE`. A truncated search finding no marker is not proof of absence. Never automatically replay an accepted turn with an unknown outcome. Only an affirmative busy/ownership response before any `turn/start` permits automatic requeueing. If an accepted turn skipped due to lease contention, retain unknown until readback establishes what happened; a later fallback cycle can actually process that batch and provide its own matching evidence.

Offline recovery regression coverage: `python3 -B -m unittest discover -s Tests/ReleaseTools -p test_maintenance_events.py`. It covers HMAC/filtering, delivery persistence/deduplication, debounce/restart/in-flight arrivals, unavailable ownership, mocked proxy protocol/approval/timeouts and cycle-evidence acknowledgement. Run `scripts/check.sh` for repository validation. Deployment requires separate real-delivery and native-conversation evidence.
