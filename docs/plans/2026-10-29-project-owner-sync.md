# Project owner synchronization

Owner explicitly authorizes existing Caldis main-account credentials for personal Project #7 reads and updates. Repository, issue, PR and release writes continue as pir-maintainer[bot]. No global authentication changes, new account, Project migration or repository stage issues.

Implement an isolated owner-authenticated Project runner, verify actual actor and target, update skill routing, and preserve lease/readback/idempotent stage recovery. Project-only failures must not prevent independent issue/release completion; store pending board synchronization.

Acceptance: offline wrong/missing identity and command-boundary tests, complete real Project scan and readback of substantive field updates, skill validation, independent review and current-head CI before merge. No application release required.
