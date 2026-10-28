# GitHub App maintenance identity

Every Pir maintenance issue, pull request, repository and Project write must use the native installation bot `pir-maintainer[bot]`. The owner explicitly selected this identity. A machine user, personal/OAuth token, App user token, owner connector, or inherited `gh` login is never a fallback. Git author strings and comment signatures do not change the API actor.

## Local configuration and runner

The approved private App is `pir-maintainer` (5512939), installation 176235800, immutable bot user ID 349413745, selected repository `Caldis/Pir`. Required permissions are Issues/Pull requests/Contents write and Actions/Checks/Metadata read. Do not add administration, secrets, bypass or unrelated repository access.

Use `scripts/maintenance/github_app.example.json` as the schema for private `~/.config/pir/maintenance/github-app.json`. The configuration and PEM must be regular user-owned files with mode 0600; their containing directories must be user-owned mode 0700. Keep the PEM outside every repository. Never commit configuration, keys, JWTs or installation tokens. Do not print them, use command arguments for tokens, or change the owner's global `gh` authentication.

```bash
python3 scripts/maintenance/github_app.py check
python3 scripts/maintenance/github_app.py run -- gh api repos/Caldis/Pir
python3 scripts/maintenance/github_app.py run -- gh pr view 36 --repo Caldis/Pir
python3 scripts/maintenance/github_app.py run -- git push origin HEAD
```

After renaming the existing App, read back its actual slug and bot login, then change only `app_slug` in the private configuration to `pir-maintainer`; keep App ID, installation ID, key and repository scope unchanged. Old-slug configuration fails closed.

The runner validates App ID/slug, installation owner/repository selection, token repository scope, effective permissions and expiry. It signs a short-lived JWT through OpenSSL and mints an installation token only in memory. It refreshes before expiry and replaces inherited GitHub token variables. `check` prints nonsecret identity/permissions/expiry; there is no token export command. `cycle.py` and `projects.py` acquire this identity internally. All other maintenance `gh` and authenticated Git operations in these references must use the runner, including PR creation, review, merge, releases and CI reads. Lease `guard` and external-write authorization still apply immediately before mutation; the runner does not grant a lease or review approval.

Installation tokens cannot rely on `GET /user`. The runner resolves the bot login through `GET /user/349413745` and verifies its immutable ID and Bot type; an App slug rename does not establish the bot's actual login. Comment upserts match immutable bot user ID 349413745, reusing that bot's marked comments even when their historical login differs. Marked bot comments stay excluded from issue input fingerprints across the rename; legacy marked `Caldis` comments retain their existing fingerprint exclusion. Preserve legacy owner-authored marked comments and checkpoints; read them as prior evidence and create/reuse a bot-owned status comment when needed. Never edit another actor's comments. Re-read remote state after an unknown write outcome before retrying. Bot activity is not independent review and never bypasses current-head CI/release gates.

## Personal Project #7 is blocked

Project #7 is user-owned. A repository installation does not establish Project access. During bootstrap on 2026-10-28, the validated installation token returned `projectV2: null` with GraphQL `NOT_FOUND` for the exact Caldis Project #7; an owner-authenticated read confirmed the Project exists. No App Project draft mutation was attempted. This is an explicit source/capability blocker, never an empty board.

Keep Project reads and writes on the same App identity. Do not route them to owner credentials, create a machine user, create repository tracking/stage issues, or move the Project to an organization. Migration or other changes require a separate owner decision. Until App read **and mutation** capability against the exact board are proven, checkpoint the stage locally with its task/plan/evidence and record pending Project synchronization; do not claim a remote draft exists or status was synchronized. The bootstrap stage may proceed under the owner's bounded assignment with this recorded blocker. After capability changes, reconcile existing local stages and Project drafts before creating anything, using an authorized substantive mutation and readback rather than test spam.

Offline validation: `python3 -B -m unittest discover -s Tests/ReleaseTools`. Missing/insecure configuration, key or access, expired/invalid tokens and Project failures stop the relevant operation without consulting personal credentials. Report the fixed diagnostic and retry prerequisite; preserve checkpoints for recovery.

Official sources:
- [Installation authentication and attribution](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation)
- [Generating a JWT](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app)
- [Generating installation tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [Projects authentication guidance](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/automating-projects-using-actions)
