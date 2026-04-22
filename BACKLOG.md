# Scout — Backlog

A running list of improvements to tackle in future versions of Scout.app and
the surrounding Scout system. Items at the top are next-up; items below are
nice-to-haves.

---

## Shipped

### 2026-04-22
- **Launch Claude — split menu with Ghostty/tmux, Claude Desktop Chat, and
  Claude Desktop Cowork.** The old single "Launch Claude" button drove an
  AppleScript that pressed ⌘T and typed into Ghostty, which quietly failed
  whenever Accessibility permission wasn't granted to the current bundle
  ID. Rewritten as a Menu with three targets. The Ghostty path detects a
  running tmux server (via `tmux list-sessions` against `/tmp/tmux-$UID/
  default`, since macOS GUI apps get a different TMPDIR) and spawns a new
  tmux window with `claude` in the Scout directory — the only reliable way
  to get a fresh terminal surface when Ghostty's macOS config sets
  `command = tmux new-session -A`. Claude Desktop paths open
  `claude://claude.ai/new?q=…` or `claude://cowork/new?q=…`. The full
  action-item context (subject + body + prior comments + deep-link URLs)
  is copied to the clipboard on every launch as a reliable ⌘V fallback.
- **Schedules tab.** Full CRUD on `com.scout.*.plist` files from within
  Scout.app — edit times, add new schedules (including the long-missing
  research cadence), delete unwanted ones. Saving writes both the live copy
  in `~/Library/LaunchAgents/` and the repo copy in `~/Scout/launchd/`,
  reloads via `launchctl bootout`/`bootstrap`, and makes a path-scoped git
  commit. Also refactored `LaunchdScheduleService` to use the shared
  `PlistIO` helper, which fixed a latent off-by-one weekday-convention bug.

---

## Action Items view (Scout.app)

### Soon
- **Delete / archive comments from a card.** Comments can only be added right
  now. Want an inline delete affordance per comment that removes the line
  from the markdown (git history is the archive). Probably needs a
  ``--delete-comment`` mode on ``add_comment.py`` or a new
  ``delete_comment.py`` that finds the comment by subject + index or text.
- **Edit a comment in-place.** Same shape as delete — kill and re-insert via
  the CLI.
- **Custom date option on Snooze.** Current popover is preset-only
  (Tomorrow / +3d / +1w / +2w / +1mo). Add an "Other date…" row that opens
  a nested picker. Previous attempt tripped a macOS 26 ``State(initialValue:)``
  bug inside ``.popover`` (the wrapper read as the reference-date epoch
  2001-01-01 UTC → ``--until 2000-12-31``); whichever pattern we pick needs
  to avoid that.
- **Preserve original section kind when snoozing.** A snoozed urgent task
  currently lands under ``## 🛌 Snoozed`` (kind = ``.neutral``, gray accent)
  on the target day. Would be nicer if an urgent task stays visually urgent
  when it carries in.

### Nice-to-have
- **Launch Claude — broader terminal + shell support.** Today the Ghostty
  path requires the exact setup it was written against: Ghostty.app, tmux
  running at `/tmp/tmux-$UID/default`, and a session to attach to (the
  launcher falls back to `open -na Ghostty.app --args --command=…` for
  users without tmux, but the tmux path is what's actually been tested).
  Expand to: (a) iTerm2 (has a mature AppleScript dictionary — `tell app
  "iTerm" to create window with default profile`); (b) Terminal.app via a
  `.command` file drop (most reliable baseline for users with nothing
  else); (c) kitty (`kitty --single-instance --title=… holdtty=yes`); (d)
  non-tmux Ghostty users on macOS (verify the `--command=` fallback
  actually renders a fresh window when the primary Ghostty instance
  hasn't set a `command = tmux …` override). Probably wants a
  preferences dropdown: *"Launch Claude Code in: Ghostty+tmux / Ghostty /
  iTerm2 / Terminal"* rather than auto-detection.
- **Task-relevant cwd for Launch Claude.** Currently every Ghostty launch
  opens in `~/Scout`. If the task's deep links include a GitHub PR URL
  (e.g. `github.com/acme/mcp-server/pull/42`), we could try common clone
  locations (`~/<repo>`, `~/code/<repo>`, `~/src/<repo>`) and cd there
  instead. Falls back to `~/Scout` when nothing matches.
- **Keyboard navigation.** Arrow keys to move focus between cards; Enter to
  open the composer on the focused card.
- **Bulk actions.** Multi-select cards → mark done / snooze all together.
- **Drag-and-drop reorder** within a section, writing a stable ordering
  marker back to the markdown.
- **Pinned filter presets.** Save a filter combination (e.g. "Urgent +
  Watching, Open only") and restore it with one click.
- **In-card deep-link inline preview.** Hover a Linear chip → preview the
  issue title / status without leaving the app.

## Control Center view (Scout.app)

### Soon
- **"Run now" should refresh the heartbeat schedule.** Clicking *Run now*
  from the heartbeat table fires the job, but the scheduled row sits there
  unchanged — the next-fire timestamp doesn't shift and the row isn't
  removed. Expected: either drop the row until the next cron tick recomputes
  it, or have `LaunchdScheduleService.recompute()` fire immediately after
  `RunnerService.runNow` completes so the same item doesn't keep looking
  "queued" at the past time.
- **Budget panel shows $0 even when real spend is non-trivial.** `BudgetRailCard`
  sums `Run.cost` from session logs, but those values are mostly `nil` — so
  today's budget reads $0 while actual Claude usage is much higher. This
  also makes the heartbeat dispatcher's "budget permits" gate meaningless.
  Claude Code's `/usage` slash command has the real numbers; figure out how
  to feed that into Scout (sidecar JSON dropped by a hook? periodic poll of
  a local usage file? manual paste into `.scout-config.yaml`?) so both the
  rail card and the dispatcher see ground truth. Today's tracker (`.scout-logs/usage-tracker.jsonl`)
  only captures what sessions self-report, which isn't everything.

### Nice-to-have
- **Activity heatmap should adapt to available history.** Hardcoded 52-week
  grid is overkill when Scout only has ~10 days of data — 99% of cells are
  empty and the real activity crowds into one column on the right. Should
  auto-scale: show from the first-recorded run (minimum 4 weeks, max 12
  months) through today so cells fill the width proportionally. Header
  label ("Activity — last 12 months") should reflect the actual range
  being rendered.
- **`SessionLogService.reconcile()` orphan-sweep end-to-end test.** Task 5
  of the session-status-parser refactor (shipped 2026-04-21) wired the
  orphan sweep into both `loadInitial()` and `reconcile()`, but only
  `loadInitial()` has end-to-end test coverage. A regression in the
  reconcile path would land silently. Needs a controllable `FileSystemEventSource`
  test double (possibly `AsyncStream.Continuation`-backed) since `NoopFS`
  doesn't emit events.

### Bigger initiatives (each needs its own spec/brainstorm)

Decomposed from the broader "make Control Center as good as possible" ask
on 2026-04-21. Recommended build order below. Each lands on the Run detail
pane, so the first one (stats) improves the surface that the next two
render onto.

- **Per-run stats pane (v1).** `RunDetailView` today shows cost / errors /
  log-size. Add: duration (from startedAt + endedAt), diffstats for the
  commits in the run's time window (files touched, lines +/-), tool-use
  counts parsed from the log, and tokens in/out if they can be pulled from
  `.scout-logs/usage-tracker.jsonl`. No new surface — reuses the existing
  pane. Should ship **before** the two items below so they land on a
  cleaner detail pane. *Adjacent:* the existing "Budget panel shows $0"
  item is about the source-of-truth for cost, which feeds this pane.

- **Per-run feedback loop (app → dreaming).** Compose feedback from the
  Run detail pane → persist to a per-run file under `.scout-feedback/`
  (or similar) → teach `DREAMING.md` Phase 1 to read it alongside the
  two feedback channels that already exist (Slack DM reactions/replies,
  inline `//==<< ... >>==//` KB comments). Open questions for the spec:
  file format (YAML vs. markdown), whether the feedback dir is
  git-tracked, whether dreaming acknowledges what it processed (so the
  same feedback isn't re-ingested), and whether the composer supports
  ratings/tags or is pure prose. Prior art: the two existing channels
  are documented in `~/Scout/DREAMING.md` Phase 1.

- **Knowledge-graph-touched visualization.** Show every file and KB node
  a run touched, rendered as a graph overlay on the Run detail pane. Two
  phases, ship them separately:
  - **v1 (derived — ships first).** Parse commits-in-window → modified
    files → `[[wikilink]]` edges from each modified `.md` → force-directed
    SpriteKit / Canvas / WebView view. **Uses data we already have**; no
    changes to `run-*.sh` or skills required. Most of the design work is
    layout engine choice, interaction (click node → open file), and how
    the view is anchored in the pane (tab? overlay? modal?).
  - **v2 (explicit emit).** Each SCOUT session drops a sidecar JSON
    listing files *read / written / mentioned* during the run. Requires
    hooking `run-*.sh` to capture tool-use events from Claude Code and
    discipline across every skill to not skip emit. Weeks, not days —
    only worth building once v1 is proven to be worth looking at.

## Scout system (sessions, CLIs, pipelines)

### Soon
- **Scout-session awareness of snoozes.** Consolidation / dreaming sessions
  should read the target-day ``_(carried in from YYYY-MM-DD)_`` annotations
  so a task's snooze lineage is visible to the briefing prompt. Right now
  a snooze removes the source line and future sessions see a gap in the
  thread unless they ``git log`` it.
- **Comment-deletion helper CLI.** Paired with the app-side delete (above).

### Nice-to-have
- **Telemetry for writer errors.** ``ActionItemsWriter`` classifies failures
  (``.noMatch`` / ``.ambiguous`` / ``.environment`` / ``.other``); counting
  those per day in a sidecar log would make divergence between Scout.app
  and the Obsidian workflow easier to spot.

## Known paper cuts
- **Env banner copy drift.** The "missing: …" banner line lists scripts by
  filename; if the set of required CLIs changes, we need to keep the banner
  and ``ActionItemsEnvironmentCheck.requiredScripts`` in sync manually.
- **FilterChipsView's dual "all" representation.** ``filter.kinds == []``
  and ``filter.kinds == {every known kind}`` are treated as equivalent in
  the filter pipeline. Currently normalised to ``[]`` after every toggle
  but worth simplifying the data model so only one representation is valid.
