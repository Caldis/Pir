# Telegram maintenance notifications

Goal: deliver Chinese milestone notifications for the owner's authorized Pir maintenance assignment to the existing fixed private Telegram chat.

Design: a standard-library helper shares the maintenance Store transaction/lease, but keeps delivery records separate from issue checkpoints. Deduplicate by issue, event and semantic fact (not run ID or wall clock). Persist an in-flight reservation before HTTP; unknown results are never automatically resent. Known failures retry once per later cycle, up to three attempts, without replaying fixes or releases. Credentials stay in the existing private local configuration; diagnostics contain fixed error categories only.

Implementation sequence:
1. Add offline regression tests for fixed recipient/plain text, dedupe across cycles, distinct milestones, bounded retry, unknown outcomes/crash reservation, lease exclusion and credential-safe errors/dry run; run them before implementation.
2. Implement scripts/maintenance/notify.py using cycle.Store, bounded HTTPS and no recipient/endpoint CLI override. Add retry and dry-run commands.
3. Update canonical skill and hourly prompt with event mapping, release gates, failure recovery and helper usage. The discovery entry is a symlink to canonical skill.
4. Run ReleaseTools, scripts/check.sh and skill validation. Independently review, open PR, require current-head Check success, merge with matching head. Update the existing heartbeat preserving all other configuration and send one real delivery notice.

No application behavior or application release is involved. Offline tests must not read real credentials or contact Telegram.

Validation evidence:
- Initial notification regression run failed because the helper did not exist (7 tests), then passed after implementation.
- Expanded offline notification suite: 9 tests pass; all 37 ReleaseTools tests pass. Simulated HTTP only, no real credentials loaded.
- `scripts/check.sh`: exit 0, 128 Swift tests, localization, website build/path checks and ReleaseTools pass. Website retains its existing Vite chunk-size advisory.
- `uv run --with pyyaml python /Users/caldis/.codex/skills/.system/skill-creator/scripts/quick_validate.py .agents/skills/pir-maintainer`: Skill is valid. System Python lacked PyYAML; the validator used an isolated uv dependency.
- `git diff --check`: pass. App interaction is not applicable: maintenance tooling/skill only; no application release required.
