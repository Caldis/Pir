# Local Development and Release Smoke Test Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify development, Universal compilation, application launch, Git push, and a signed Pir 0.1.9 release from ~/Code/Pir.

**Architecture:** Keep application behavior unchanged. Add a small user instruction, bump version metadata, and use the existing Apple signing, notarization, and Sparkle release scripts. Preserve the existing Sparkle public key and user data.

**Tech Stack:** Swift 6.3, AppKit, SwiftPM, Node.js, local Developer ID signing, notarytool, Sparkle, GitHub CLI.

### Task 1: Establish local development

- Install website dependencies: `npm ci --prefix website`.
- Run `scripts/check.sh`; require all Swift, Python, website, localization, and shell checks to pass.
- Run `scripts/dev.sh`; inspect the running application.

### Task 2: Prepare the minimal release change

- Modify `README.md`: document the update preferences page.
- Modify `Resources/Info.plist`: set version 0.1.9 and build 20261028.1.
- Run `git diff --check` and `scripts/check.sh`.

### Task 3: Build and publish

- Run `PIR_SIGN_IDENTITY="Developer ID Application: BIAO CHEN (N7Z52F27XK)" PIR_VERSION=0.1.9 PIR_BUILD=20261028.1 scripts/release.sh`.
- Require Developer ID signing, Apple Accepted for app and DMG, stapler, Gatekeeper, and Universal architecture verification.
- Prepare Sparkle assets with `scripts/release/prepare-update.sh`; require the existing Keychain private key to match the configured public key.
- Commit the reviewed change and push main; create tag 0.1.9 and a GitHub release with DMG, ZIP, and SHA256SUMS.
- Publish the signed appcast to the existing update-feed release after uploading version assets.

### Task 4: Verify delivery

- Download the published assets, compare SHA256, inspect the mounted DMG, and verify the signed appcast.
- Read back GitHub release metadata, main and tag revisions, and CI outcomes.
- Record observed results and any actual credential blockers in `docs/maintenance.md`.
