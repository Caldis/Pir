# Local maintenance configuration and task recovery

Use an external private local.env for machine-specific maintenance settings and a tracked placeholder-only .env.example. Existing explicit command options take precedence; strict parsing treats values as data. Initialization discovers only safe, verifiable candidates, writes known settings with private permissions, reports unresolved field names, and requires owner input for unresolved/multiple candidates. Never regenerate or export signing/update keys. Keep ordinary app builds/tests independent of release settings.

Migrate signing and Sparkle helpers to shared configuration. Keep existing certificate/key pairing, notarization, original Sparkle public key and real update checks. Use local private evidence for machine values; public maintenance messages describe work and validation without copying them. No Git history rewrite or published asset replacement.

Document field/schema, initialization/recovery and explicit owner-input behavior in the maintainer skill. Project uses authorized owner identity; repo/issue/PR/release use App bot. Project/notification faults retain pending sync and must not block independent issue/release work or a genuinely verified issue closing. Missing release settings only block affected app release, never unrelated docs/tooling work. Preserve exact-head CI, independent review and real app release gates.

Acceptance: parser/precedence/no-config/new-machine/missing/multiple/invalid candidate tests; complete scripts/check.sh; local build and controlled real signing with restored keychain search list; original Sparkle public-key check; real GitHub identity/Project reads; independent review, current-head CI and merge. Tooling/docs changes require no app version.
