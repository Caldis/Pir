# Native-move regression waits for its completion callback

Task: `native-move-callback-wait`. Scope: test harness only; no app source/version/scheduler change or application release.

Evidence: PR #28 Check run 40646345612 attempt 1 (head 4a79a3d) failed `testNativeMoveWithoutMouseUpClearsAfterButtonRelease`: captured callbacks were empty after a fixed 100ms Task.sleep. Local targeted recheck and one same-head rerun passed. Evidence is retained in `dist/maintenance/c28159951ca148aebde6ebe42fbe383f/ci-failure.log` and `ci-incident.txt`. Application uses a 50ms main run-loop timer; elapsed sleep does not guarantee that the completion callback has been delivered under CI scheduling load.

Acceptance: replace the arbitrary sleep with bounded asynchronous waiting for the real frame-change callback. Preserve exact captured-frame equality and the assertion that later programmatic moves do not add a second callback. Missing or duplicate callbacks must still fail; no skip, assertion weakening or production change. Do not sweep unrelated sleeps or timers.

Execution: stable coordinator owns repository lease; bounded worker in isolated managed worktree investigates existing asynchronous XCTest patterns, demonstrates the fixed-sleep limitation, implements the minimal event wait and runs targeted plus full project checks. Worker returns local commit/evidence without external writes. Independent read-only review checks semantics and timeout/actor safety. Coordinator opens a normal PR, requires current-head Check, merges matching head, saves verified task with release=not-required, copies evidence and archives worktree before explicit closeout.
