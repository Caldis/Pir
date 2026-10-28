# Rename the existing maintenance App

The owner requests the existing GitHub App be named `pir-maintainer` and have a recognizable avatar. Reuse Pir's existing 256px application icon. Preserve App ID 5512939, installation 176235800, bot user 349413745, repository scope and credentials; do not create another App or add permissions.

Prepare the authentication helper, config example and identity references for the new slug before changing GitHub. Verify the resulting actual App slug and bot login through API readback, then update only the private config's slug locally. Preserve and reuse comments belonging to the same immutable bot ID after a login rename; owner comments stay untouched and input fingerprints must remain stable.

Acceptance: unchanged immutable identities/scope; GitHub name/avatar saved and read back; the new runner authenticates successfully; regression tests cover renamed bot ownership/fingerprints; independent review and current-head CI pass before merge. This is tooling-only and requires no application release. Main retains the sole lease and all GitHub/settings writes. A worker implements locally in this isolated worktree and a separate worker reviews.

The owner's multi-agent question is discussion: recommend one external bot with bounded implementation/review workers, coordinated external writes and truthful role headings. Do not create more Apps or automated role-comment streams. The prior issue-only question did not authorize silently removing Project workflow requirements in this rename change.


## Implementation and verification

The runner now expects slug `pir-maintainer`, resolves the actual login using `GET /user/349413745`, and validates that immutable ID and Bot type before accepting a token. Comment reuse and marked-comment fingerprint exclusion use that bot ID, preserving historical bot comments across a login rename. Legacy owner comments retain their existing fingerprint exclusion and are never edited by the bot upsert helper. No Project workflow, permissions, release flow or application behavior changed.

- Original-head offline reproduction fails both rename invariants: the historical bot marker changes the fingerprint and comment upsert creates another comment. The regression fixtures pass with the implementation; matching logins with a different or missing ID do not grant ownership.
- `python3 -B -m unittest discover -s Tests/ReleaseTools`: 92 tests passed.
- `scripts/check.sh`: passed, including 130 Swift tests, localization checks, website build/static checks, 92 release-tool tests and shell syntax checks. The first fresh-worktree attempt stopped at missing Vite; `npm ci --prefix website` installed the existing locked dependencies and the complete rerun passed.
- Skill validation passed using the existing PyYAML-enabled Python runtime: `/Users/caldis/.local/share/uv/tools/kimi-cli/bin/python -B /Users/caldis/.codex/skills/.system/skill-creator/scripts/quick_validate.py .agents/skills/pir-maintainer`.
- Coordinator readback in `dist/maintenance/de8d76554914426d82b0978d5b2b4212/rename-verification.json` confirms App ID 5512939, slug/name `pir-maintainer`, installation 176235800, bot login `pir-maintainer[bot]` with ID 349413745, and historical comment 6473892825 still owned by that bot ID. The coordinator saved the existing Pir icon as the avatar and updated only the private config slug.

Evidence logs are local under `dist/maintenance/de8d76554914426d82b0978d5b2b4212/`. The implementation worker performed no GitHub/settings mutations, credential reads or lease operations. Independent review, new-runner live authentication and current-head CI/merge remain the coordinator's closeout gates. No application release is required for this tooling-only change.
