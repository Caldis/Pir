# Issue 42: custom website domain

Goal: Serve the existing Pir GitHub Pages site at https://pir.caldis.me/ and update the application's official website destination. Owner explicitly requires official Cloudflare CLI installation and user-approved CLI login; all Cloudflare reads/writes use that CLI, never browser automation or ad hoc API clients.

Scope and sequence:
1. Install official cf and compatible isolated Node runtime; begin CLI login and wait for owner authorization. Retain credentials outside checkout, prefer OS keychain.
2. Read existing Pages and exact DNS record state. Bind the custom domain on Pages before creating the exact CNAME pir.caldis.me -> caldis.github.io, initially DNS-only; preserve unrelated records. Use existing authorized identity; report a real missing capability rather than silently using another identity.
3. Change active application/README website links to the new HTTPS domain. Keep source, feedback and Sparkle release/feed endpoints at their existing GitHub destinations. No history edits or unrelated UI changes.
4. Independently review, run scripts/check.sh and build, require exact-head CI, merge then verify Pages deployment, public authoritative DNS, HTTPS certificate and source assets.
5. Application change requires normal version/signing/notarization/public download/actual Sparkle-upgrade gates. Close issue and mark Project root Done only when domain and application delivery are verified; otherwise preserve completed stages and explicit retry condition.

Acceptance: CLI identity/zone and readback, exact CNAME, public HTTPS site/assets, working application About website action, no unrelated DNS change, current-head CI, normal application release and actual update evidence. Coordinator retains sole lease/external write/signing ownership. Project root PVTI_lAHOADXbEs4BpJKyzhERD80 aliases issue42.
