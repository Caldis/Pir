# Project item maintenance

Owner request: include https://github.com/users/Caldis/projects/7 alongside all Pir issues. Project item is the work unit. **Owner clarified: draft stage items linked to their parent in Project; no new repository issues, no draft-to-issue conversion.** Maintain actual fields and associations to source, PR, release and evidence.

Implementation: read-only fully paginated snapshot, stable case-sensitive ID hash, reuse cycle task checkpoints and lease, dedup issue aliases and verified stage linkage, pending release/sync recovery; draft workers report phase/evidence to sole coordinator writer.

Acceptance: offline error/pagination/identity/stage/field-value recovery tests, real Project read and draft/field writes, independent skill forward-test, full checks and current-head CI. Tooling/docs only, no app version. No scheduler changes or bot provisioning.

## Live trial and correction

- Project `PVT_kwHOADXbEs4BpJKy`, Status `PVTSSF_lAHOADXbEs4BpJKyzhnmF6c`: Todo f75ad846, In progress 47fc9ee4, Done98236657. Re-read before writes.
- Root draft item `PVTI_lAHOADXbEs4BpJKyzhEOjsQ`, full database ID286166724, link https://github.com/users/Caldis/projects/7?pane=issue&itemId=286166724 . Legacy local task project-maintenance is the recovery coordinator for this same work.
- Project text fields Parent item `PVTF_lAHOADXbEs4BpJKyzhnmXpk`, Work links `PVTF_lAHOADXbEs4BpJKyzhnmXsc` associate drafts; no fake native issue fields.
- Initial unwanted tracking issues33/34/35 were closed **not planned**, associated Project items archived after owner correction. They do not represent completion and must not be resumed as root work. Keep evidence locally; never repeat this creation strategy.
- Live OAuth project scope granted. Existing owner README issue30/PR32 recovered: merged154b60874cd34d41d1f7bdd7c56f934db9165dee, original Project item Done read back, no app release.
- Independent first pass found stage classification flaws; fixed native legacy validation and added draft-stage linkage validation, field-value coverage according to clarified requirements.

- Draft root taskSlug `project-8c232a3405c75f130a6ae2c473f5ada753e63bbf3c99ba2b527b8846`; review draft `PVTI_lAHOADXbEs4BpJKyzhEOmS8`. Both In progress, Start date2026-10-28; review Parent item and both Work links populated. Unknown estimates/deadline/sprint left empty.
- Earlier local project-9474... checkpoint is an alias for withdrawn issue-based trial, never a second work item. Completion of this same change retires those aliases with correction evidence.
- Installed gh2.86 draft body-only edit failed Title cannot be blank without changing title; read back then retry with existing title+updated body succeeded. Skill preserves both fields on edits.
