# GitHub App maintenance identity

The owner explicitly selected a native GitHub App bot for every maintenance issue/PR/Project mutation. No machine account and no fallback to the owner's credential.

## Scope and acceptance

- Private App `caldis-pir-maintainer`, ID 5512939, installed on Caldis/Pir only (installation 176235800).
- Issues, pull requests and contents write; actions/checks/metadata read. No webhook or user OAuth.
- Store the private key and local configuration outside the checkout with restricted modes. Mint expiring installation tokens without logging secrets or changing the owner's global gh login.
- Verify App ID/slug, installation owner/repository and effective permissions before operations. Resolve the bot actor without `/user`, which installation tokens do not support.
- Route maintainer scripts and documented gh/git operations through the App credential; fail closed on unavailable credentials or unsupported Project access. Preserve prior marked owner comments without editing them.
- Offline tests cover credential validation, expiry/refresh, actor resolution and lack of owner-token fallback. Real acceptance requires a meaningful authorized bot write and readback of its actor; Project #7 needs a separate capability check with the same token.
- Current-head CI and independent review remain mandatory. Tooling changes need no app release.

## Current external facts

App registration and Pir-only installation were read back in GitHub UI. An accessibility-button activation generated the first public key without downloading its private PEM. One bounded recovery using a coordinate click generated a second key and downloaded its PEM; its fingerprint was matched before moving it to a private directory outside the checkout (0600 file, 0700 directory). No more keys should be generated. The first unused public key remains recorded on GitHub.

JWT and installation-token verification succeeded: correct App, installation owner, selected repository, exact token repository scope and required permissions. Bot actor is `caldis-pir-maintainer[bot]`, GitHub user ID 349413745. PR36's exact-head Check and independent review passed; it was merged using the App installation token, and readback confirms `merged_by=caldis-pir-maintainer[bot]`, merge `a3a7991e28283e30b53a1751b2ad4ee131d2b47c`.

Personal Project #7 remains inaccessible: the App's GraphQL query returns HTTP200 with `projectV2=null` and `NOT_FOUND`, while the same read-only query using the owner's existing credential resolves `PVT_kwHOADXbEs4BpJKy`. No Project write was attempted and no personal-token maintenance write is permitted. Project workflow root final sync and pilot37 remain pending. Durable nonsecret evidence is in main checkout `dist/maintenance/9c7eed0d10dc4b73bf0153bcf9ab273c/`.

## Steps

1. Recover the downloaded key or resolve the bounded download failure; keep credentials private.
2. Implement the local token runner and script integration, with offline tests.
3. Verify bot identity and personal Project capability; report unsupported access rather than changing identity or moving the Project.
4. Independent review, checks, PR/CI/merge using verified App credentials; reconcile pending PR36 and Project checkpoints.
