# Website hotkey and focused Hero implementation plan

**Goal:** Resolve owner issues48/49 without changing the application version.

**Design:** Display literal [hotkey] in step02 in both locales and initialHTML, with no fixed ⇧⌘V in current website instructions. Rebuild the Hero product visual as a focused, user-controlled content example: image/text/files selectors, one large actual native screenshot at a time and short localized context. Keep the new MeshGradient background, existing real screenshots/downloads and page copy. Initial/no-JS presentation remains useful. No autoplay, generated imagery, dependency/framework upgrade or fake application controls.

**Alternatives:** Repeating the three-card grid does not materially answer the new Hero request. Layered collage still compromises screenshot legibility. Selected single-focus examples make each type readable and distinguish the redesign.

**Implementation:** Edit website/index.html/style.css/locales/en.json/locales/zh.json and minimal JS only if needed for accessible selection. Native controls or correctly keyboard-operated buttons; visible focus, image alt text, no inert controls. Keep ambient lifecycle/telemetry-off/pause/reduced-motion and responsive layout. Update current design notes. Two Project roots remain separate with shared branch/PR/evidence and separate stage records.

**Acceptance:** Literal[hotkey]in bothlanguages/initialHTML; all3examples selectable, onlyselectedimage displayed, selectedstateandkeyboardnavigation valid; clear screenshot scales at1280/920/390/320 and nooverflow, bilingual labels; realGPU/pause unaffected. Lockeddeps, websiteproduction/static/localization/fullcheck pass; independent review/current-headCI, Pages matchingmerge and publicasset/visual verification before bothbot completion andProjectDone. Noapplicationrelease.


## Execution details

- Replace the three-image grid in `website/index.html` with a fieldset and three native radio inputs. CSS selects the matching screenshot and local context; no new JavaScript or framework is needed. Native controls provide checked state, Tab entry, arrow navigation and no-JS operation.
- Give the single screenshot a stable stage, preserve intrinsic aspect ratio, and cap it at the natural asset dimensions (397/387/376 px wide). Keep titles, two-line context, real-window credit and independent motion control outside the screenshots.
- Update both locale dictionaries and initial HTML for literal `[hotkey]`; describe the user's configured shortcut in Preferences. No application source changes.
- Update `docs/design.md` and `website/README.md` to reflect actual selection, keyboard behavior and MeshGradient implementation.
- Run locked `npm ci --ignore-scripts`, syntax checks, localization/path checks, production build and full `scripts/check.sh`. Native CSS state needs browser interaction evidence rather than implementation-mirroring tests. Coordinator performs independent browser checks at 320/390/920/1280 px, both languages, keyboard, no-JS and background lifecycle.
- Parent retains independent review, current-head CI, merge, Pages/public visual verification and both separate Project acceptance records. This is website-only; no application release.


## Worker verification — 2026-10-29

- `npm ci --ignore-scripts` passed using the unchanged lockfile. Log: `/tmp/pir-issues48-49-npm-ci.log`.
- `node --check website/main.js`, `node --check website/artwork.js`, `node --check website/i18n.js`, `python3 scripts/check-localizations.py`, `npm run build --prefix website` and `python3 scripts/check-website.py` passed. Log: `/tmp/pir-issues48-49-website-checks.log`.
- `scripts/check.sh` passed (exit 0): 130 Swift XCTest cases, 143 ReleaseTools tests, 113 native and 46 website matching localization keys, production build, static resource/release paths and shell syntax. Log: `/tmp/pir-issues48-49-check.log`.
- `git diff --check` passed. Website source contains no fixed ⇧⌘V instruction. Application and artwork lifecycle source are unchanged.
- Existing limitations: the locked Vite 7.2.2 development dependency reports one high-severity audit finding (details: `/tmp/pir-issues48-49-audit.json`); the deferred shader engine retains its 726.21 kB gzip build-size warning. Dependency upgrades are outside this task.
- Browser visual/interaction evidence, independent review, current-head CI and public Pages verification remain coordinator-owned acceptance gates. The local server is available at `http://127.0.0.1:4178/` for those checks. No app release is required.
