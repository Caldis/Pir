# Release gates and commands

Read `.agents/docs/release.md` and `docs/updates.md` for the maintained contract. The helpers below codify the tested local-keychain and 更新签名主机 Aqua paths; they do not replace an agent's investigation or actual application verification.

## Preflight and source

Read [local-environment.md](local-environment.md) for machine setup. Use `python3 scripts/local-config.py init --json` when settings are absent, then `check --json --require FIELD ...` for only the selected stage’s required fields. The initializer never invents unresolved settings; ask once for missing/ambiguous owner input and continue unrelated issue work. Do not load the file with shell source.

Run from the intended clean checkout, with a current maintenance lease. Capture commands/results under `dist/maintenance/<run-id>/`. Check `git status`, remote `Caldis/Pir`, GitHub authentication, current main/PR/checks, existing tags/releases and the signed appcast before allocating a version. Require the current head's `Check` workflow success, with its head SHA matching the PR after the final push. If current-head CI is missing, await or explicitly rerun the appropriate workflow for that exact head; if it failed, fix it on the PR before merging. For an already merged PR, validate the selected exact release source and its Check run instead of creating a duplicate fix. Merge with `--match-head-commit` and read back its merge SHA.

Use one next patch version (`X.Y.Z`) and a build newer than **all** entries in `release/appcast.xml` and any already published build. Build date is Asia/Shanghai, sequence is `YYYYMMDD.N`. Put version changes in the fix PR or a small release-preparation PR before building; do not mutate signed application metadata afterward. Persist version/build once allocated, so retrying the same release does not allocate another version. Never overwrite a published version with different bytes.

Record the merge/build SHA. If main advanced, inspect every new commit before selecting the release revision; include only reviewed/tested changes. Build from a clean checkout of that recorded revision. Repository/worktree paths can vary; do not assume an agent runs on a machine with either key loaded.

## Sign and notarize on the configured build host

```bash
PIR_VERSION="$PIR_VERSION" PIR_BUILD="$PIR_BUILD" \
  python3 scripts/release/with-local-signing.py
```

This invokes existing `scripts/release.sh`: checks, Universal build, Developer ID signing, app notarization/stapling/Gatekeeper, signed DMG notarization/stapling and checksum. The identity and paired-file directory are resolved through `scripts/local-config.py` and the existing private local.env; it loads the configured Developer ID files into a disposable keychain and restores the original search list on exit. Keep the known backup in place. A missing identity in `security find-identity` is not proof that these files or their private key are absent.

Require **Accepted** in both `dist/notarization.json` and `dist/dmg-notarization.json`; codesign, stapler and Gatekeeper must pass. A submitted notarization request is unfinished. Do not start multiple releases concurrently: the keychain search list is shared per macOS user. Catchable failures clean up automatically; after a machine crash inspect `signing/pir-signing-*.json` under the configured `PIR_EVIDENCE_DIR` (also check the legacy `~/.config/pir/maintenance/signing/` location when recovering a pre-configuration run): it records the original search list, created keychain path, PID and timestamp, without passwords or key material. Confirm the old process is no longer active, restore exactly `originalKeychains`, then delete only its recorded temporary keychain before resuming. Never delete unrelated keychains.

## Prepare Sparkle with the original key

Write user-facing bilingual notes to an HTML file (escape issue text as content, never evaluate it). Then:

```bash
python3 scripts/release/prepare-on-macbook.py --check-key --timeout 90
python3 scripts/release/prepare-on-macbook.py \
  --app dist/Pir.app --notes "$PIR_NOTES_HTML" --timeout 300
```

The first command compares the **public** key; the second signs only in a private temporary staging directory on the configured update-signing SSH host. Existing official tools are read from `${PIR_SPARKLE_PROJECT_DIR}/.build`. One-shot Aqua launchd jobs use `RunAtLoad=true`, `KeepAlive=false`; don't substitute `launchctl submit`, which may rerun a completed task. No original remote project file or private key is exported/modified. Returned ZIP/feed are independently verified before local `release/appcast.xml` is updated.

If normal SSH reports Keychain access blocked, diagnose execution session/access. Do not regenerate keys, change `SUPublicEDKey` or reuse Mos keys. If the configured update-signing host is offline, checkpoint `blocked` with this prerequisite and retain already notarized assets for resumption; don't publish an unsigned or incomplete substitute. A completed one-shot task can be retried safely only after reading its result and local returned artifacts.

Combine the two fixed release-asset hashes into `dist/SHA256SUMS`, with the **bare** DMG and ZIP names (no `updates/` path). Compare app version/build and signer with the planned values, and save the `prepared` checkpoint.

## Publish without duplicating or replacing a release

Before each external write: `cycle.py guard --run-id "$PIR_RUN_ID"`. Re-read an existing tag/release/asset before retrying a timed-out write.

1. Commit the signed `release/appcast.xml` and relevant release evidence, then push. Pure signed-feed/release-record metadata can be pushed directly if repository rules allow; source or version changes require a PR. If protected, use a metadata PR with the same CI gate.
2. Record tag SHA. It may differ from build SHA **only** by reviewed feed/documentation metadata; require no differences in `Sources/`, `Resources/`, `Vendor/`, `Package.swift`, `Package.resolved` or build/package/sign scripts. Otherwise rebuild and revalidate the changed source.
3. If the version tag exists, require its SHA to match. Otherwise create/push it at the recorded full SHA. A mismatched existing tag is a blocker, never force-move it. Record expected/actual SHAs and stop that version. If it is already a legitimate different published version, allocate the next unused patch version through a preparation PR; an unexplained or inconsistent tag needs owner resolution rather than overwriting.
4. Create one **draft** GitHub release with the signed DMG, update ZIP and combined SHA256SUMS using `gh release create "$PIR_VERSION" ... --verify-tag --draft --notes-file "$PIR_NOTES_MD"`. If it already exists, inspect it. Retry only missing assets on a draft; compare existing hashes before reuse. Do not clobber a published version's assets.
5. Read back all three asset names/sizes/hashes and tag target; publish with `gh release edit "$PIR_VERSION" --draft=false --latest`. Then update the **existing** `update-feed` prerelease asset using `gh release upload update-feed dist/updates/appcast.xml --clobber`. Verify its prerelease flag remains true. ZIP must be public before feed publication. Save `published` immediately; feed-upload failure resumes here.
6. Run:

```bash
python3 scripts/release/verify-public.py \
  --version "$PIR_VERSION" --build "$PIR_BUILD" --compare-feed
```

The verifier resolves an explicit OpenSSL 3 executable rather than relying on macOS system OpenSSL; `PIR_OPENSSL` can select an installed OpenSSL 3 binary. This downloads public assets, compares SHA256, independently verifies Ed25519, checks metadata and macOS trust on extracted ZIP and readonly-mounted DMG, and detaches. Require exit 0. Existing downloaded evidence can be rechecked with `--local DIRECTORY`.
7. In a separate application directory, open the previous public version, trigger **Check for Updates**, install and restart through Sparkle. Read back new version/build, check it reports latest, verify installed files against the signed ZIP, and verify representative isolated pin persistence if the fix touches sessions. Do not use or overwrite the user's real pin contents for fixtures. Use the available desktop tool; if interaction evidence is unavailable, record the exact remaining gap and keep the issue unverified rather than inventing it.
8. Complete the issue comment/closure and `verified` checkpoint only after actual evidence above. Preserve a small release verification record in `.agents/docs/release.md` with SHAs, notarization IDs, links, commands, results and manual limits. Update skill/helper regressions only for demonstrated workflow problems.
