# Issue event intake and same-thread wakeups

The owner requests event-driven issue intake with a five-minute batching window, reuse of the existing Pir conversation and a low-frequency scheduler fallback after native wakeups are proven. Keep issue/Project maintenance and release recovery within their existing authorization. This is maintenance tooling; no app version is required.

## Implemented scope

A loopback-only GitHub receiver verifies raw-body HMAC, repository/installation and event filters, limits request size/concurrency, deduplicates delivery UUIDs and durably stores identifiers before acknowledging actionable deliveries. Signed App pings are ignored safely. Issue/comment bot feedback and PRs are excluded; workflow completion is accepted only for matching unfinished external jobs. No raw issue bodies enter the queue or model prompt.

SQLite batches use a 300-second quiet window and 900-second maximum eligibility wait, preserve restart state and separate arrivals during processing. Dispatch respects the existing maintenance lease. Unknown accepted-turn outcomes are preserved without automatic replay. Actual processed-cycle acknowledgement requires a matching finished run, exact batch marker and evidence; model turn completion alone is insufficient. Fallback cycles can claim due batches and acknowledge after actual scans/triage.

The native adapter accepts only an explicitly configured existing private app-owned socket through `app-server proxy --sock` and verifies loaded-thread ownership before claiming a batch. It cannot start an independent server for a wake. Explicit temporary read-only probing never reports wake readiness. Configuration, secrets and queue remain outside the repository; the repository contains examples only.

## Current operating limit and remaining goal

The desktop app-owned shared control socket is currently unavailable. Independent App Server reads can show `notLoaded` and stale completed/interrupted turn records while the desktop conversation is active; reading the same stored thread ID does not prove ownership. Current deployment configuration uses `control_socket: null`, so this implementation operates as receiver/queue only and starts no model turns. Existing heartbeat configuration remains unchanged and continues ordinary issue/Project scanning and release recovery. An unknown bridge outcome does not block that independent work.

Receiver-only deployment still needs coordinator-recorded proof of an actual signed GitHub delivery reaching the queue and duplicate readback. Do not infer live delivery from offline tests. The remaining native-wakeup prerequisite is an observable app-owned shared transport with target-thread ownership, followed by accepted work in the existing desktop conversation and matching finished-cycle evidence. Only after that end-to-end proof should the coordinator consider the owner's requested fallback adjustment through the supported automation tool. Never store cadence expectations or validate scheduler frequency from maintenance state.

## Validation and recovery

Acceptance covers HMAC/scope/bot filtering, signed ping, invalid/oversized requests, durable deduplication, debounce/restart/new arrivals, active-lease suppression, ownership failure before claim, mocked proxy identity/approval/timeout handling, unknown outcomes and actual cycle evidence including evidence-list persistence. Require repository checks, independent review and current-head CI before merge. Receiver delivery and native wakeup each require their own live evidence; workers perform neither deployment nor external mutations.

Operational startup, acknowledgement and offline recovery are documented in `.agents/skills/pir-maintainer/references/events.md`. Preserve batches and run journals during interruptions; reconcile exact markers with affirmative readback evidence instead of replaying uncertain accepted turns. Public records describe ordinary maintenance and verification without local identities, credentials or ingress addresses.

Local verification: `scripts/check.sh` passed with 130 Swift tests and 143 Python tests; the targeted event suite passed 25 tests, including actual `cycle.Store.finish` evidence-list acknowledgement across queue restart. The skill creator's `quick_validate.py` passed for `pir-maintainer`; an independent read-only scenario review verified absent configuration, queue-only fallback, unknown completed turns and active-lease handling. These results establish local behavior only; signed receiver-delivery and native-wakeup evidence remain separate coordinator work.
