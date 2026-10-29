# GitHub App maintenance identity

Use `pir-maintainer[bot]` for Codex-authored issue replies, especially when Caldis opened the issue. The owner introduced the App to distinguish agent responses from their own messages, not to prohibit owner-account operations. Use the existing Caldis or App authentication as appropriate for other authorized work, including Project, Pages/domain setup, repository configuration, Git, PR and release operations. App permission gaps alone do not require another approval when the task is already authorized. Record the actual actor and read back mutations. Git author strings and comment signatures do not change the API actor.

## Local configuration and runner

The approved private App is `pir-maintainer` (5512939), installation 176235800, immutable bot user ID 349413745, selected repository `Caldis/Pir`. The current runner requests Issues/Pull requests/Contents write and Actions/Checks/Metadata read. These describe the installed App, not a restriction on authorized tasks; use the existing owner authentication when appropriate instead of expanding App permissions unnecessarily.

Use `scripts/maintenance/github_app.example.json` as the schema for private `~/.config/pir/maintenance/github-app.json`. The configuration and PEM must be regular user-owned files with mode 0600; their containing directories must be user-owned mode 0700. Keep the PEM outside every repository. Never commit configuration, keys, JWTs or installation tokens. Do not print them, use command arguments for tokens, or change the owner's global `gh` authentication.

```bash
python3 scripts/maintenance/github_app.py check
python3 scripts/maintenance/github_app.py run -- gh api repos/Caldis/Pir
python3 scripts/maintenance/github_app.py run -- gh pr view 36 --repo Caldis/Pir
python3 scripts/maintenance/github_app.py run -- git push origin HEAD
```

After renaming the existing App, read back its actual slug and bot login, then change only `app_slug` in the private configuration to `pir-maintainer`; keep App ID, installation ID, key and repository scope unchanged. Old-slug configuration fails closed.

The runner validates App ID/slug, installation owner/repository selection, token repository scope, effective permissions and expiry. It signs a short-lived JWT through OpenSSL and mints an installation token only in memory. It refreshes before expiry and replaces inherited GitHub token variables. `check` prints nonsecret identity/permissions/expiry; there is no token export command. `cycle.py` acquires this identity internally. `projects.py` uses the owner Project identity below. Use the App runner for issue replies. For other operations, it remains available when suitable; owner-authenticated `gh` or Git is also allowed within the authorized task. For owner commands, remove inherited token overrides and verify the actual login is Caldis without printing credentials. Keep global gh authentication unchanged when command-local routing suffices. Lease `guard` and external-write authorization still apply immediately before mutation; the runner does not grant a lease or review approval.

Installation tokens cannot rely on `GET /user`. The runner resolves the bot login through `GET /user/349413745` and verifies its immutable ID and Bot type; an App slug rename does not establish the bot's actual login. Comment upserts match immutable bot user ID 349413745, reusing that bot's marked comments even when their historical login differs. Marked bot comments stay excluded from issue input fingerprints across the rename; legacy marked `Caldis` comments retain their existing fingerprint exclusion. Preserve legacy owner-authored marked comments and checkpoints; read them as prior evidence and create/reuse a bot-owned status comment when needed. Never edit another actor's comments. Re-read remote state after an unknown write outcome before retrying. Bot activity is not independent review and never bypasses current-head CI/release gates.

## Personal Project #7 and owner authentication

The owner authorizes the existing **Caldis** main account to read and synchronize personal Project #7. The App cannot access this board; do not migrate it or create another account. `projects.py` uses the dedicated owner runner; use `python3 scripts/maintenance/projects.py --owner-run -- gh project ...` for guarded Project writes. The runner accepts only supported Project commands, pins owner/number and validates IDs against Project #7; it rejects repository/issue/PR/API commands. Verify actual actor Caldis before access, ignore inherited token variables, retain credentials only in memory and never change global gh authentication. Missing/wrong owner authentication fails closed. This Project helper is intentionally limited to Project commands; use ordinary owner-authenticated tools for other authorized operations rather than weakening its command validation.

Continue recording exact Project/item/field identities, stage markers, intent and readback. Owner attribution on Project changes is intentional; Codex-authored issue replies use the bot. A Project access/sync failure leaves pending local synchronization and does not stop independently actionable issue/release work. If remote stage creation is unavailable, record the bounded stage locally and backfill once access returns; never create repository tracking issues. Completion of an actual issue and verified release can be reported and closed while board-only synchronization remains pending; preserve release facts and retry only synchronization.

Offline validation: `python3 -B -m unittest discover -s Tests/ReleaseTools`. Validate identity routing, wrong/missing credentials, fixed Project scope and error sanitization. Do not upload private security audit reports to Project, issues, PRs or Telegram.

Official sources:
- [Installation authentication and attribution](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation)
- [Generating a JWT](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app)
- [Generating installation tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [Projects authentication guidance](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/automating-projects-using-actions)
