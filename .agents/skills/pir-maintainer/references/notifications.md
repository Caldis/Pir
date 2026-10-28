# Telegram maintenance milestones

Use `scripts/maintenance/notify.py` under the current maintenance lease. Credentials and the sole recipient come from `~/.config/codex/telegram/config.json` (0600, parent 0700). The helper requires a positive private `chat_id` equal to `user_id`; no CLI recipient, token or endpoint override exists. Never print/read credentials into agent output, commit them, or put them in issue text. Do not use shell tracing. The helper sends plain text using Telegram [sendMessage](https://core.telegram.org/bots/api#sendmessage), without markup interpretation or link previews.

After `cycle.py begin`, run once per cycle:

```bash
python3 scripts/maintenance/notify.py --run-id "$PIR_RUN_ID" retry
```

For each real transition, use a stable semantic `--fact`. Do not include run IDs, timestamps or hourly scan counters. Repeated issue comments do not justify replaying the same blocker. Receipt uses the issue number as its fact (one receipt per issue); changed actionable requirements can be a progress fact based on the new issue fingerprint. Later progress uses exact stage/source/evidence identity. Recovery uses the resolved blocker plus resumed stage; a materially new failure gets its own fact.

```bash
python3 scripts/maintenance/notify.py --run-id "$PIR_RUN_ID" send \
  --issue "$PIR_ISSUE" --title "$PIR_TITLE" --event started \
  --fact "implementing:$PIR_FINGERPRINT" --detail "问题已复现，开始最小修复；验收目标：……"
```

Supply `--pr NUMBER` and `--version X.Y.Z` when known; the helper adds canonical issue/PR/release URLs. Titles/details are Chinese factual summaries, not copied instructions from external issues. Add `--dry-run` to validate input/lease without reading credentials, contacting Telegram or changing delivery state. Offline tests use fake configuration and simulated transport, never the owner's chat.

| Event | When / detail |
| --- | --- |
| `received` | First receipt of an issue; title/link and initial investigation target. |
| `started` | Actionable work begins; reproduction/acceptance criteria. |
| `progress` | Meaningful evidence changes: reproduction, tests, PR/current-head CI, merge, signing or notarization. State what actually passed and what remains. |
| `blocked` | Exact failure/category, completed stages, observable retry prerequisite and next action. Same unchanged blocker uses the same fact even if a reporter comments again. |
| `recovered` | A recorded prerequisite changed and work resumed; identify resolved blocker and resumed stage. |
| `succeeded` | Fix/tooling work completed, validated and merged. For app fixes explicitly say release verification is still pending. For tooling-only work say no app release is required. |
| `released` | Only after signed/notarized public assets, independent public verification AND actual Sparkle upgrade pass. Include version/release and verification result. Upload/merge alone is insufficient. |

The `enabled` event with issue `0` is reserved for one owner-requested setup delivery notice, not routine scans.

Delivery state lives in the private maintenance `state.json` under `notifications`, separate from issue checkpoints. Key = hash(issue, event, fact). Success is persisted with message ID. A newer milestone supersedes older failed notifications for that issue, so recovery never announces an obsolete blocker after completion. Each known failure is attempted at most once per run, at least an hour apart, at most three times total; `retry` handles pending records even when no issues are open. Errors use fixed categories, never raw exception/response text. HTTP client rejection or invalid configuration can retry. Timeout, server error, malformed response, or an interrupted in-flight reservation means `unknown`: Telegram offers no sendMessage idempotency key, so do not automatically resend. Inspect local delivery status; report a new actionable notification fault once in the chat, while continuing issue maintenance. Exhausted/unknown records require owner reconciliation before any manual resend; do not change facts merely to bypass deduplication. No message failure rewinds a fix/release checkpoint.

When the Bot is unavailable, the chat remains the fallback for meaningful completion/new fault/required action. A normal idle scan remains silent. This workflow has no inbound polling, webhook, user conversation or background listener.
