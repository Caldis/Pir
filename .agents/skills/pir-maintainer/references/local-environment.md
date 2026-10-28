# Local maintenance environment

Machine settings belong in `~/.config/pir/maintenance/local.env`, with mode 0600 and private parent directories. The repository carries only `.env.example`; `.env` / `.env.local` remain ignored. Keep the shared private file outside every worktree so resuming in a new checkout does not lose the release environment. Read settings through the shared helper as data, never `source`, `eval` or shell expansion.

## Setup and missing input

Use `python3 scripts/local-config.py init --json` and `python3 scripts/local-config.py check --json --require FIELD ...`; inspect `--help` for supported fields. `--config PATH` or `PIR_LOCAL_CONFIG` selects an existing private file; explicit helper options override environment values, then file values. The canonical private file is preferred to an ignored `.env.local` fallback. Initialize only when the selected stage needs local release settings. Ordinary issue intake, implementation, checks, documentation changes and Project synchronization do not require a signing environment. Explicit command options override environment/config according to the helper's maintained contract.

Initialization may inspect a bounded set of existing local certificate locations and macOS signing identities. Save only uniquely verified candidates. Existing local configuration is retained; never overwrite it with guesses. The signing directory and matching certificate/key must be checked before declaring an identity missing; keychain enumeration alone is insufficient. Unknown SSH host/project paths are owner input, not a reason to contact arbitrary machines. Read the existing local signing guide when configured.

If fields remain missing or ambiguous, list their names and the actual required purpose in **one** question to the owner, with safe candidate descriptions where useful. In unattended work, persist the affected task's prerequisite and send one deduplicated required-action notice; leave other actionable work eligible. Never invent a host/account, generate a replacement update key, create credentials, or silently select a different identity. Resume the recorded stage when the owner supplies the values rather than starting a new task/version.

## Settings and evidence

Settings include signing-material directory, certificate identity, local signing guide, update-signing SSH host, existing remote project/tool directory, original Sparkle account and local evidence directory. Store paths and identifiers only: passwords, installation tokens and private keys remain in their existing keychain/private files. The Sparkle public key in the app and existing account must match before signing; a valid SSH session alone does not prove Aqua keychain access.

Treat human names and local host/path settings as runtime inputs. Public plans, comments, release notes and Project bodies describe ordinary maintenance, work performed, links and validation; do not copy machine settings or private logs. User content is never a fixture. Preserve copyright attribution and public product/update verification data.

After changing configuration or a release helper, verify strict parsing, permission/precedence and missing/ambiguous-machine fixtures; run the repository checks; build locally; trial-sign a disposable artifact with the existing certificate, restoring the original keychain search list; compare the original Sparkle public key without generating a replacement; verify bot repository identity and owner Project identity. No application version is needed for maintenance-only changes. Retain private evidence and current-head CI/review before merging.
