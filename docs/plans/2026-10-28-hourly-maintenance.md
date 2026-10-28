# Pir Hourly Maintenance Implementation Plan

**Goal:** Give a new Pir chat one consistent hourly issue-to-release workflow, with resumable evidence and reusable local signing tools.

**Scope:** One project skill with issue/PR/release templates; a small lease/checkpoint/comment helper; local Developer ID signing and isolated 更新签名主机 Sparkle preparation; public-release verification. Reuse existing checks/build/release scripts. No product changes or extra version release for this workflow-only change.

1. Capture an offline baseline for crash recovery, stale CI and missing-key misdiagnosis.
2. Add the canonical skill under `.agents/skills/pir-maintainer`, route it from AGENTS.md, and expose it to the local skill catalog.
3. Add a JSON state/lease helper with paginated issue scan, atomic checkpoints and upserted marked comments. Test locking, resumability, unchanged-input handling and duplicate-comment prevention offline.
4. Turn the proven temporary-keychain signer and isolated Aqua signing method into reusable release helpers. Preserve original keychains and projects, bound execution time, require matching public key, and use one-shot jobs.
5. Add templates and strict evidence gates for current-head PR CI, merge recovery, version increments, signed assets, idempotent publish, public readback and real update validation.
6. Run validators, script tests and existing project checks; offline forward-test the skill; review and merge the workflow PR after CI.
7. Provide a bootstrap prompt for the user's new Pir chat. That chat creates one hourly heartbeat, with a matching-automation lookup first and quiet unchanged runs. Do not bind it to this agentic chat.

## Validation record

- Offline baseline understood recovery/source/signing invariants; it did not require a behavioral correction. Forward evaluation and code review nevertheless exposed three concrete helper defects: blocked-state context loss, missing closed blocked issues, and comment lease expiry during reads. Added failing regression cases, fixed each, then re-reviewed successfully.
- State/lease/fingerprint/comment behavior has isolated tests, including preserved merged-release context and authoritative comment ownership.
- Release helpers tested real disposable-keychain loading and one-shot Aqua public-key lookup without creating a release. Existing 0.1.9 public fixtures passed independent hash/signature and ZIP/DMG trust verification.
- Keychain cleanup failure retains a private, non-secret recovery snapshot; successful cleanup removes it. Signal cleanup terminates the entire child process group.
- Skill schema validator passed. Hourly scheduling is intentionally registered only when the user's new Pir chat starts the skill; this agentic chat has no maintenance heartbeat.
- Isolated full helper smoke also passed: existing notarized 0.1.9 app plus previous source feed produced signed/independently verified temporary update assets via the one-shot Aqua helper; original local and remote tracked files and remote job inventory were unchanged.
- First PR CI exposed runner system OpenSSL lacking `-rawin`; the helpers and crypto fixtures now resolve a verified OpenSSL 3 executable instead of depending on PATH.
