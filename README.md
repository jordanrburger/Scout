# Scout.app

A macOS companion app for the [Scout](https://github.com/jordanrburger/scout-plugin) Claude Code plugin.

Scout is an autonomous knowledge-management and daily-briefing system that runs as scheduled Claude Code sessions. The plugin does the work; this app gives you a native interface on top of whatever Scout produces in `~/Scout/`:

- **Control Center** — sessions activity, upcoming schedule, recent runs with cost/status, usage heatmap.
- **Action Items** — today's to-do list rendered from the daily markdown file, with inline comments and deep links to Linear / GitHub PRs / Slack threads.
- **Schedules** — full CRUD on the `com.scout.*.plist` launchd agents: edit fire times, add a new schedule, pause or remove existing ones. Saves to both the live copy in `~/Library/LaunchAgents/` and the repo copy in `~/Scout/launchd/`, reloads via `launchctl`, and commits the repo change.

## Requirements

- macOS 13 (Ventura) or newer.
- Xcode 15 or newer (for build + codesign).
- An existing Scout instance at `~/Scout/` — install via `claude plugin add <scout-plugin-repo>` and run `/scout-setup` first.

## Build & run

```bash
open Scout.xcodeproj
# In Xcode: Product → Run (⌘R)
```

Or from the command line:

```bash
xcodebuild -scheme Scout -destination 'platform=macOS' build
xcodebuild -scheme Scout -destination 'platform=macOS' test
```

## First-run configuration

Cmd+, opens Settings. A few fields are worth filling in:

- **Launch Scout at login** — start the app automatically so it's watching your Scout instance all day.
- **Scout directory** — read-only display. The app assumes `~/Scout` (the scout-plugin default).
- **Linear workspace** — your Linear workspace slug (e.g. `acme-co`). Used to build Linear URLs when you click a `[[PROJ-123]]` wikilink or deep link in an action item. Leave blank to open `linear.app` without a workspace.
- **Your name** — shown next to comments you add to action items. Defaults to `user`.

## Repo layout

```
Scout/                 # main target source
  ActionItems/         # parser, writer, views for daily action-items markdown
  ControlCenter/       # sessions dashboard
  Models/              # shared types (Run, Schedule, CalendarFire, …)
  Schedules/           # list + detail views for launchd schedules
  Services/            # file watcher, git, launchctl, plist I/O, schedule editor
  Shell/               # AppState, sidebar, main window, settings
ScoutTests/            # unit + integration tests (~120 tests)
docs/                  # design specs
```

## Development

Tests run from the command line:

```bash
xcodebuild test -scheme Scout -destination 'platform=macOS'
```

Or a specific suite:

```bash
xcodebuild test -scheme Scout -destination 'platform=macOS' \
  -only-testing:ScoutTests/ScheduleEditorServiceSaveTests
```

The `ScoutTests/Fixtures/` directory holds synthetic plists, logs, and action-items files used by the suite. Nothing in them references a real person or incident.

## Relationship to the plugin

The plugin writes; the app reads (and occasionally writes back via CLI shims for action-item comments and schedule edits). The plugin owns:

- Session scheduling via `com.scout.*.plist` launchd agents.
- Daily action-items markdown at `~/Scout/action-items/action-items-YYYY-MM-DD.md`.
- Session logs at `~/Scout/.scout-logs/*.log`.
- Usage tracking at `~/Scout/.scout-logs/usage-tracker.jsonl`.
- Commit history in `~/Scout/.git`.

The app is a pure consumer of all of the above, plus:

- Saves comment edits via the plugin's `action-items/add_comment.py` CLI.
- Saves schedule edits by writing plists directly and running `launchctl bootout`/`bootstrap`.

If the plugin isn't installed, the app still builds and runs; it just shows empty views.
