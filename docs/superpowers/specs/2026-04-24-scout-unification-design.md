# Scout Unification Design

**Date:** 2026-04-24
**Status:** Design approved, ready for implementation planning
**Author:** Jordan Burger (brainstormed with Claude)
**Repos affected:** `scout-plugin`, `scout-app`, `~/Scout` (personal data dir)

## 1. Problem statement

Scout today consists of three tightly-coupled pieces with inconsistent distribution:

- **`~/Scout`** — Jordan's private, actively-evolving engine instance. Contains a mix of (a) shippable engine code (shell scripts, Python files, hooks, runners, skills) and (b) personal data (knowledge-base, action-items, drafts, session logs). Local-only, no git remote.
- **`~/scout-plugin`** — a Claude Code plugin published at `github.com/jordanrburger/scout-plugin`. Intended to be the shareable engine, but lags `~/Scout` substantially. Many engine pieces exist only as templates; several are missing entirely.
- **`~/scout-app`** — a SwiftUI Mac menu-bar app published at `github.com/jordanrburger/Scout`. Hardcodes `~/Scout` as the engine root; invokes scripts and reads JSONL artifacts from there.

### Observable symptoms

1. **Colleague installs break silently.** Features in scout-app (connector health, session tokens, action-item CLI) depend on engine artifacts produced only by scripts that live in `~/Scout` but have no template or package equivalent in `~/scout-plugin`. A colleague who installs scout-plugin + scout-app hits empty cards and unresponsive buttons with no diagnostic surface.
2. **Improvements flow the wrong way.** Jordan edits engine code in `~/Scout` (edit-and-go). Porting changes to `~/scout-plugin` is manual and rarely done, so the published plugin perpetually trails.
3. **Personal data is tangled with skill definitions.** `SKILL.md`, `DREAMING.md`, `RESEARCH.md` contain family names, phone numbers, colleague rosters, and internal project codes inlined as context. They cannot be shipped as-is.
4. **`scout-app` hardcodes paths.** `AppState.swift:34-36` resolves `scoutDir` from `~/Scout` with no override. Even if a colleague had a complete plugin install at a different path, the app wouldn't find it.
5. **No contract between app and engine.** If the engine is missing a feature the app needs, the app silently renders an empty view instead of telling the user the engine is out of date.

### Root cause

`~/Scout` is simultaneously the canonical location of engine code and of Jordan's personal data. No boundary. Every improvement becomes a choice between "ship it" (port to plugin) and "keep hacking" (edit in place) — and "keep hacking" wins because it preserves edit-and-go.

## 2. Goals and non-goals

### Goals

1. Make `scout-plugin` the single canonical home for all engine code.
2. Demote `~/Scout` to a pure data directory — user state only, never shipped, never git-tracked.
3. Preserve Jordan's edit-and-go workflow — no rebuild/publish step between editing a file and having it take effect.
4. Give `scout-app` a configurable engine path and a capability contract with the engine, so mismatches are diagnosable rather than silent.
5. Make the engine UI-independent — usable via CLI, TUI, Mac app, or a future web UI — and cross-platform-capable (Python, not Swift).
6. Give a colleague a five-command install that yields a working Scout.

### Non-goals

- Windows port (Python leaves the door open; not in scope).
- TUI rewrite (moves in as-is).
- Plugin auto-update (`git pull` is sufficient).
- Web UI.
- Migration tooling beyond schema-version scaffolding (v1 is the starting state; no older versions to migrate from).
- Re-signing `scoutctl` (it's Python; no binary signing required).
- Rewriting the engine in Go/Rust/Swift (explicitly considered and rejected — kills edit-and-go, doesn't fix the real jankiness which is structural, not linguistic).

## 3. Architecture

Three locations with clear, non-overlapping roles.

```
┌─────────────────────────────────────┐   ┌─────────────────────────────────┐
│  ENGINE  (shippable, git-tracked)   │   │  DATA DIR  (personal, never     │
│  ~/scout-plugin (dev clone)         │   │  in git, never bundled)         │
│  = Claude Code plugin               │   │  ~/Scout  (default)             │
│                                     │   │                                 │
│  engine/                            │   │  knowledge-base/                │
│    scout/ (Python package)          │   │  action-items/ (markdown only)  │
│    bin/scoutctl (entry shim)        │   │  drafts/                        │
│    tests/                           │   │  .scout-logs/                   │
│    manifest.json                    │   │  .scout-cache/                  │
│    launchd_templates/               │   │  .scout-state/                  │
│  commands/  skills/  phases/        │   │  .obsidian/                     │
│  plugin.json                        │   │  .scout-config.yaml             │
│                                     │   │  .mcp.json                      │
└─────────────────┬───────────────────┘   └────────────────┬────────────────┘
                  │                                         │
                  │  SCOUT_ENGINE_DIR                       │  SCOUT_DATA_DIR
                  │  (env var or NSUserDefaults)            │  (env var or NSUserDefaults)
                  ▼                                         ▼
         ┌────────────────────────────────────────────────────────┐
         │              scout-app  (SwiftUI, Mac)                 │
         │  - Resolves both dirs at launch                        │
         │  - Reads engine/manifest.json for capability check     │
         │  - Invokes engine via EngineClient → scoutctl          │
         │  - Reads data_dir/.scout-logs/*, action-items/*, etc.  │
         │  - First-run wizard if either dir unresolved           │
         └────────────────────────────────────────────────────────┘
```

### Three anchors

1. **Engine = clone of `scout-plugin`.** Contains every shell script (now Python), Python file, hook, command, skill, TUI, ontology parser, launchd template. Git-tracked. Pushed to GitHub. Jordan edits here. Colleagues pull here.
2. **Data dir = `~/Scout`** (default; overrideable). Pure user state. Never in git. Never bundled. Created by `scoutctl setup` if absent.
3. **App = `scout-app`.** Resolves engine + data paths via env vars → NSUserDefaults → first-run wizard. Reads the engine's `manifest.json` at launch; degrades individual features gracefully if missing.

### Key design moves

- **Templates shrink dramatically.** Today's `scout-plugin/templates/` exists because the install model is "render and scatter." Under this design, most files live directly in the package and are invoked from there. Only launchd plists (which embed absolute paths) and the default `.scout-config.yaml` remain as templates.
- **Hooks declared by the plugin, not by the user.** `plugin.json` includes a `hooks` array; installing the plugin wires them up. No per-user `.claude/settings.json` surgery.
- **Single CLI surface.** Engine exposes one entry point (`scoutctl`) with subcommands. Scout-app invokes `scoutctl <subcommand>` for every engine interaction — one path to test, one version to check.

## 4. Engine package design

### Directory layout

```
scout-plugin/
├── plugin.json                 (Claude Code plugin manifest)
├── commands/                   (slash commands)
├── skills/                     (skill markdown — scrubbed, generic)
├── phases/                     (phase docs)
├── engine/
│   ├── pyproject.toml
│   ├── README.md
│   ├── manifest.json           (built by scoutctl manifest build)
│   ├── bin/scoutctl            (shell launcher shim)
│   ├── defaults/
│   │   ├── scout-config.yaml   (baseline config; user overrides in data dir)
│   │   └── mcp.json.tmpl       (MCP schema; secrets in data dir)
│   ├── launchd_templates/
│   │   └── *.plist.tmpl
│   ├── scout/                  (THE Python package)
│   │   ├── __init__.py
│   │   ├── __main__.py         (enables `python -m scout`)
│   │   ├── cli.py              (Typer app — scoutctl entry point)
│   │   ├── config.py           (resolves SCOUT_DATA_DIR, layers config)
│   │   ├── paths.py            (single source of truth for path resolution)
│   │   ├── manifest.py         (builds capability manifest)
│   │   ├── errors.py           (exception classes mapped to exit codes)
│   │   ├── hooks/
│   │   │   ├── connector_log.py
│   │   │   ├── kb_pre_filter.py
│   │   │   └── session_tokens.py
│   │   ├── scripts/
│   │   │   ├── budget_check.py
│   │   │   ├── heartbeat.py
│   │   │   ├── rate_limit_detect.py
│   │   │   ├── collect_events.py
│   │   │   ├── connector_health_report.py
│   │   │   ├── pre_session_data.py
│   │   │   ├── write_session_cost.py
│   │   │   └── cc_session_cache.py
│   │   ├── runners/
│   │   │   ├── scout.py
│   │   │   ├── dreaming.py
│   │   │   └── research.py
│   │   ├── action_items/
│   │   │   ├── cli.py
│   │   │   ├── parser.py       (shared with TUI)
│   │   │   ├── writer.py       (shared with TUI)
│   │   │   ├── mark_done.py
│   │   │   ├── snooze.py
│   │   │   ├── add_comment.py
│   │   │   ├── render.py
│   │   │   └── watch.py
│   │   ├── kb/
│   │   │   ├── ontology.py
│   │   │   ├── schema.yaml     (package data; user may override in data dir)
│   │   │   └── query.py
│   │   ├── tui/                (Textual app; shares parser/writer with action_items)
│   │   │   ├── app.py
│   │   │   ├── config.py
│   │   │   └── screens/
│   │   └── setup/
│   │       ├── init_data_dir.py
│   │       ├── register_hooks.py
│   │       ├── install_launchd.py
│   │       └── migrations/     (schema-version migrations)
│   └── tests/
│       ├── unit/
│       ├── integration/
│       ├── contract/           (snapshots the Swift side decodes)
│       └── fixtures/
└── .github/workflows/
    ├── test.yml
    ├── lint.yml
    └── release.yml
```

### `scoutctl` CLI surface

| Command | Purpose |
|---|---|
| `scoutctl run {scout\|dreaming\|research}` | Launch a Claude session (replaces `run-*.sh`) |
| `scoutctl hook {connector-log\|session-tokens\|kb-pre-filter}` | Claude Code hook entry (stdin = event JSON) |
| `scoutctl action-items {mark-done\|snooze\|add-comment\|render\|watch\|list}` | Action-item operations |
| `scoutctl kb query [--type X --status Y --name-match "..."]` | KB graph query |
| `scoutctl report {connector-health\|heartbeat\|budget-check\|rate-limit\|session-cost}` | Reporting/monitoring |
| `scoutctl manifest {build\|show}` | Capability manifest emit |
| `scoutctl setup {data-dir\|hooks\|launchd\|mcp\|verify}` | First-run and maintenance |
| `scoutctl migrate data-dir --from N --to M` | Data dir schema migrations |
| `scoutctl tui` | Launch Textual TUI |
| `scoutctl version` | Engine version (app uses this for manifest check) |
| `scoutctl diagnose` | Full diagnostic dump (redacted) for bug reports |

### `engine/bin/scoutctl` shim

A small bash wrapper that resolves the venv Python deterministically, so hooks invoked from LaunchAgents (which don't inherit user PATH) still find the right interpreter:

```bash
#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ENGINE_DIR="${DIR%/bin}"
VENV_PY="${ENGINE_DIR}/.venv/bin/python"

if [ -x "$VENV_PY" ]; then
    exec "$VENV_PY" -m scout.cli "$@"
else
    exec python3 -m scout.cli "$@"
fi
```

### `pyproject.toml`

```toml
[project]
name = "scout-engine"
version = "0.4.0"
requires-python = ">=3.11"
dependencies = ["typer", "pyyaml", "textual", "rich", "watchdog", "jinja2"]

[project.scripts]
scoutctl = "scout.cli:main"

[project.optional-dependencies]
dev = ["pytest", "pytest-cov", "mypy", "ruff"]
```

### File migration map (source → destination)

Moves to plugin:

| Current location | New location |
|---|---|
| `~/Scout/run-scout.sh` | `engine/scout/runners/scout.py` |
| `~/Scout/run-dreaming.sh` | `engine/scout/runners/dreaming.py` |
| `~/Scout/run-research.sh` | `engine/scout/runners/research.py` |
| `~/Scout/hooks/connector-log.sh` | `engine/scout/hooks/connector_log.py` |
| `~/Scout/hooks/kb-pre-filter.sh` | `engine/scout/hooks/kb_pre_filter.py` |
| `~/Scout/scripts/sum-session-tokens.sh` | `engine/scout/hooks/session_tokens.py` |
| `~/Scout/scripts/{budget-check,heartbeat,rate-limit-detect,collect-events,connector-health-report,pre-session-data,write-session-cost,cc-session-cache}.sh` | `engine/scout/scripts/*.py` |
| `~/Scout/action-items/{mark_done,snooze,add_comment,render}.py` | `engine/scout/action_items/*.py` |
| `~/Scout/action-items/watch.sh` | `engine/scout/action_items/watch.py` (using `watchdog`) |
| `~/Scout/knowledge-base/ontology/parser.py` | `engine/scout/kb/ontology.py` |
| `~/Scout/knowledge-base/ontology/schema.yaml` | copied to `engine/scout/kb/schema.yaml` (shipped default); a copy stays in data dir as optional user override (see below) |
| `~/Scout/tui/*` | `engine/scout/tui/*` |
| `~/Scout/launchd/*.plist` | `engine/launchd_templates/*.plist.tmpl` |
| `~/Scout/.claude/commands/scout-meta-review.md` | `scout-plugin/commands/scout-meta-review.md` |
| `~/Scout/.claude/commands/scout-work.md` (live) | overwrites `scout-plugin/commands/scout-work.md` |
| `~/Scout/SKILL.md`, `DREAMING.md`, `RESEARCH.md` (scrubbed) | `scout-plugin/skills/*.md` |
| `~/Scout/.scout-config.yaml` (de-personalized defaults) | `engine/defaults/scout-config.yaml` |
| `~/Scout/.mcp.json` (schema only, no secrets) | `engine/defaults/mcp.json.tmpl` |

Stays in `~/Scout` (data dir):

| Path | Reason |
|---|---|
| `knowledge-base/` (minus `ontology/parser.py`; `ontology/schema.yaml` optional) | User's personal KB content. `ontology/schema.yaml` is optional here — engine falls back to the packaged default when absent. |
| `action-items/*.md` | Daily markdown files user authors |
| `drafts/` | Personal message drafts |
| `.scout-logs/`, `.scout-cache/` | Runtime logs and cache |
| `.obsidian/` | Editor workspace |
| `.scout-config.yaml` (user values) | Per-user overrides layered on defaults |
| `.mcp.json` (secrets) | User-specific secrets |

Deleted after migration:

- `~/Scout/app/` (dead Xcode stub, last touched 2026-04-22).

## 5. Claude Code plugin integration

### `plugin.json`

```json
{
  "name": "scout",
  "version": "0.4.0",
  "description": "Autonomous knowledge management and daily briefing system.",
  "commands": [
    "commands/scout-setup.md",
    "commands/scout-status.md",
    "commands/scout-work.md",
    "commands/scout-meta-review.md"
  ],
  "skills": [
    "skills/scout-briefing.md",
    "skills/scout-consolidation.md",
    "skills/scout-dream.md",
    "skills/scout-research.md",
    "skills/SKILL.md",
    "skills/DREAMING.md",
    "skills/RESEARCH.md"
  ],
  "hooks": [
    {
      "event": "PostToolUse",
      "matcher": ".*",
      "command": "${CLAUDE_PLUGIN_ROOT}/engine/bin/scoutctl hook connector-log",
      "timeout": 5
    },
    {
      "event": "Stop",
      "command": "${CLAUDE_PLUGIN_ROOT}/engine/bin/scoutctl hook session-tokens",
      "timeout": 10
    },
    {
      "event": "UserPromptSubmit",
      "matcher": ".*",
      "command": "${CLAUDE_PLUGIN_ROOT}/engine/bin/scoutctl hook kb-pre-filter",
      "timeout": 5
    }
  ]
}
```

### Command and skill engine invocation

Skills and commands that need engine data invoke `scoutctl` directly:

```markdown
---
name: scout-status
description: Show current Scout health
---

Run the health report:

!`${CLAUDE_PLUGIN_ROOT}/engine/bin/scoutctl report connector-health --json`

Then summarize any alerts above threshold.
```

### MCP server handling

- **Plugin ships:** `engine/defaults/mcp.json.tmpl` — schema with `${LANGSMITH_API_KEY}` style placeholders.
- **Data dir holds:** `~/Scout/.mcp.json` — user secrets, rendered by `scoutctl setup mcp`.
- **Setup flow:** `scoutctl setup mcp` prompts for each required env var (or reads from shell env / keychain), writes resolved config to data dir, registers with Claude Code.

### Env var contract

| Variable | Default | Set by |
|---|---|---|
| `SCOUT_DATA_DIR` | `~/Scout` | User shell profile, or app first-run wizard |
| `SCOUT_ENGINE_DIR` | Resolved from `${CLAUDE_PLUGIN_ROOT}` | Plugin install; app may override |

## 6. Data directory contract

### Layout

```
$SCOUT_DATA_DIR/
├── .scout-config.yaml          (user-owned; scalars + thresholds)
├── .mcp.json                   (user-owned; secrets)
├── .scout-logs/                (runtime JSONL/log; engine-writable)
│   ├── connector-calls-*.jsonl
│   ├── session-tokens.jsonl
│   ├── usage-tracker.jsonl
│   ├── connector-alerts.log
│   ├── heartbeat.jsonl
│   └── sessions/
├── .scout-cache/               (regenerable; engine-writable)
│   ├── connector-alerts-acked.json
│   └── session-context/
├── .scout-state/               (persistent state; engine-writable)
│   └── schema-version
├── knowledge-base/             (user-owned; relational context source)
│   ├── ontology/schema.yaml    (optional user override)
│   ├── people/
│   ├── projects/
│   ├── channels/
│   └── ...
├── action-items/               (user-owned; engine reads/writes)
│   └── action-items-YYYY-MM-DD.md
├── drafts/                     (user-owned)
├── .obsidian/                  (user-owned editor state)
└── exports/                    (engine-written snapshots)
```

### `.scout-config.yaml` — three-layer merge

Precedence (low → high): engine defaults → user overrides → env vars.

```yaml
schema_version: 1

user:
  email: jordan.burger@keboola.com
  github_username: jordanrburger
  slack_user_id: U02T4ADKB38
  timezone: America/New_York
  company: Keboola
  display_name: Jordan

budgets:
  daily_budget_estimate_usd: 150
  max_per_session_usd: 20

thresholds:
  rate_limit_warn_pct: 80
  rate_limit_block_pct: 95
  connector_staleness_hours: 24

features:
  tui: true
  connector_health: true
  dreaming: true
```

The `user:` block consolidates the "Jordan's Details" footer found duplicated across all three skill files. Skills reference `{{ user.email }}`, `{{ user.timezone }}`, etc., via Jinja at session start.

### KB as canonical relational context

The `~/Scout/knowledge-base/` directory is the source of truth for people, projects, channels, and any other entities with relationships. Skills query via `scoutctl kb query --type person --name-match "${name}"` instead of inlining names.

Per-entity entries use frontmatter:

```yaml
---
type: person
name: Example Person
team: Example Team
works_on: [ProjectA, ProjectB]
slack: "@example"
---
```

### `scoutctl setup data-dir` contract

**Does:**
- Creates missing top-level directories.
- Writes starter `.scout-config.yaml` from defaults if missing.
- Writes `$SCOUT_DATA_DIR/.scout-state/schema-version`.
- Writes starter `knowledge-base/ontology/schema.yaml` if missing.
- Creates a data-dir `README.md` explaining user-owned vs engine-written paths.
- Reports per-item success/failure.

**Does not:**
- Touch existing files.
- Populate KB content.
- Write secrets (`scoutctl setup mcp` does that).
- Run silent migrations — schema mismatches fail fast with a `scoutctl migrate` instruction.

### Data dir schema versioning

Plain-text `$SCOUT_DATA_DIR/.scout-state/schema-version` holds the integer version. Migrations are numbered Python scripts in `engine/scout/setup/migrations/00N_description.py`. Only forward migrations; no downgrade path (backup before migrating).

| Version | Change |
|---|---|
| 1 | Initial — matches current `~/Scout` layout |

## 7. Scout-app integration

### Resolution order (per path, independent)

```
Env var (SCOUT_DATA_DIR / SCOUT_ENGINE_DIR)
    ↓ (if unset)
NSUserDefaults (scout.dataDir / scout.engineDir)
    ↓ (if unset)
Legacy default (~/Scout for data; ${CLAUDE_PLUGIN_ROOT}/engine if discoverable)
    ↓ (if unresolved)
First-run wizard
```

### `ScoutEnvironment` value

Injected at `AppState.init`, passed to every service:

```swift
struct ScoutEnvironment {
    let engineDir: URL
    let dataDir: URL
    let source: ResolutionSource  // env | defaults | legacy | wizard
}
```

Services receive `ScoutEnvironment` via constructor injection. No service calls `FileManager.homeDirectoryForCurrentUser` directly — that becomes a lint/review red flag.

### `EngineClient`

Consolidates every engine invocation behind a single type:

```swift
struct EngineClient {
    let engineDir: URL

    func run(_ args: [String], input: Data?) async throws -> ProcessResult
    func runJSON<T: Decodable>(_ args: [String], as: T.Type) async throws -> T
    func loadManifest() throws -> EngineManifest
}

extension EngineClient {
    func markActionItemDone(_ taskID: String) async throws
    func snoozeActionItem(_ taskID: String, until: Date) async throws
    func connectorHealthReport() async throws -> ConnectorHealthReport
    func runSession(mode: SessionMode) async throws -> SessionResult
    // ... one method per engine operation the app uses
}
```

All subprocess invocation goes through `EngineClient`. Failure modes (nonzero exit, missing subcommand, stale manifest) handled in one place.

### Capability manifest check

At `AppState.init`, after resolving env:

```swift
let manifest = try EngineClient(engineDir: env.engineDir).loadManifest()
try CapabilityChecker.require(manifest, features: [
    .sessionTokensV1,
    .connectorHealthV1,
    .actionItemsCLIv1,
    .kbOntologyV1,
])
```

On failure: app launches normally, a non-dismissable banner appears:

> "This app needs scout-plugin ≥ 0.5 for connector health. You have 0.3.
> Run `scoutctl upgrade` or `cd ~/scout-plugin && git pull`."

Feature-specific cards degrade to "Requires plugin update" stubs. Rest of app works.

### First-run wizard

Three-step sheet, triggered when either dir is unresolved:

1. **Engine location.** Auto-detects `~/.claude/plugins/scout-plugin` and `${CLAUDE_PLUGIN_ROOT}`; allows browse.
2. **Data dir location.** Default `~/Scout`; offers "Create for me" (invokes `scoutctl setup data-dir`).
3. **Verify.** Runs `scoutctl manifest show`; shows green checklist; persists paths to NSUserDefaults.

Re-accessible from Preferences → Paths.

### Degradation matrix

| Condition | Behavior |
|---|---|
| Neither env nor persisted, defaults missing | First-run wizard |
| Data dir exists but no `.scout-config.yaml` | Prompt to run `scoutctl setup data-dir`; affected views show "Data dir not initialized" |
| Engine dir resolved but `manifest.json` missing | Banner: "Scout engine not installed. Run `scoutctl setup verify`"; engine features disabled |
| Engine present but required feature missing | Feature-specific "Requires plugin update" stub |
| `scoutctl` invocation fails | Toast: subcommand + exit code; "Copy diagnostic" button |
| JSONL file malformed | Log, skip bad lines, show "partial data" indicator on affected card |

### Removed or slimmed

- Hardcoded `scoutDir` constant in `AppState.swift`.
- Direct `~/Scout/run-scout.sh` invocation in `RunnerService.swift` → `engineClient.runSession(mode: .scout)`.
- Direct Python invocation in `ActionItemsWriter.swift` → `engineClient.markActionItemDone(...)`.
- `ActionItemsEnvironmentCheck.swift` (manifest subsumes "is python3 available, are scripts present").
- `GitService` remains but points at `$SCOUT_DATA_DIR` instead of `~/Scout`.

## 8. Distribution and update flows

### Jordan's one-time migration

Ordered, gated, reversible. Run from dedicated branches (`migrate/v0.4.0` in scout-plugin, `migrate/scout-env-resolution` in scout-app). Full `~/Scout` backup before starting.

1. Scaffold `engine/` package with `pyproject.toml`, empty `scout/`, CI workflows. Verify `uv pip install -e .` succeeds.
2. Port Python files as-is (action_items, ontology, TUI). Adjust imports. Per-subsystem commits.
3. Port shell scripts to Python one at a time. Each port paired with a pytest asserting observable I/O parity. Shell originals retained until parity confirmed, then deleted.
4. Wire `scoutctl` CLI (Typer). `scoutctl --help` enumerates everything.
5. **Personal-data scrub and split** (see §11).
6. Plugin-level hook registration via `plugin.json`. Remove per-user hook registrations from `~/Scout/.claude/settings.json`. Restart Claude Code. Verify hooks fire.
7. Scout-app refactor in a single PR: `ScoutEnvironment`, `EngineClient`, first-run wizard, capability check, service migrations.
8. Launchd re-registration via `scoutctl setup launchd`: unload old plists, render and load new.
9. Delete dead files from `~/Scout` (runners, hooks, scripts, action-items Python, TUI, old Xcode stub, launchd, `.claude/settings.json` hooks block, SKILL/DREAMING/RESEARCH originals). Keep all user data.
10. Publish: tag scout-plugin v0.4.0 and push; merge scout-app PR.

Rollback: revert migration branch; restore `~/Scout` from backup; reload old launchd plists.

### Jordan's day-to-day (after migration)

One-time:
```bash
cd ~/scout-plugin/engine
uv venv
uv pip install -e ".[dev]"
claude plugin add --dev ~/scout-plugin  # or symlink to ~/.claude/plugins/
```

Daily:
```bash
$EDITOR ~/scout-plugin/engine/scout/hooks/connector_log.py  # edit-and-go
# ... iterate locally ...
cd ~/scout-plugin && git commit -am "fix: ..." && git push
```

Cross-repo contract changes bump manifest version AND scout-app required floor in the same linked-PR pair.

### Colleague first-time install

```bash
# 1. Plugin
claude plugin install github:jordanrburger/scout-plugin

# 2. Dev clone (optional, for modification)
git clone https://github.com/jordanrburger/scout-plugin.git ~/scout-plugin
cd ~/scout-plugin/engine && uv pip install -e ".[dev]"

# 3. Setup
scoutctl setup
# - creates ~/Scout data dir
# - prompts for user scalars
# - prompts for MCP secrets
# - renders + loads launchd plists
# - runs verify

# 4. App
curl -L https://github.com/jordanrburger/Scout/releases/latest/download/Scout.app.dmg -o Scout.dmg
open Scout.dmg
# First-run wizard discovers plugin + data dir, verifies manifest.
```

Five commands + one app install. Every step idempotent.

### Update flow

Fix ships:
```bash
cd ~/scout-plugin && git push                   # Jordan
cd ~/scout-plugin && git pull \
    && cd engine && uv pip install -e ".[dev]" --upgrade \
    && scoutctl setup verify                     # colleague
```

App update: download new DMG, drag-replace. (Sparkle auto-updater is a future consideration, not v0.4.)

### Versioning contract

| Artifact | Where | Bump rules |
|---|---|---|
| Plugin version | `plugin.json` + `pyproject.toml` (sync by pre-commit) | Semver; minor for additive, patch for fix, major for breaking contract |
| Manifest version | `engine/manifest.json` | Derived from plugin version + `features: {}` dict of capability flags |
| App required floor | `CapabilityChecker.swift` | Bumped deliberately when adding cross-repo features |
| Data dir schema | `~/Scout/.scout-state/schema-version` | Bumped only on directory contract changes |

## 9. Testing strategy

### Unit tests (pytest)

Targets `engine/scout/*.py`. Fast, no real I/O (uses `tmp_path` fixtures). Coverage target: **90%+ for `scout/` package.**

| Module | Focus |
|---|---|
| `hooks/*` | JSONL line shape, event parsing, categorization, dedup, token math |
| `scripts/*` | Happy path + empty-input path per report |
| `action_items/*` | Substring match, date parse, atomic write, exit-code contract |
| `kb/ontology`, `kb/query` | Graph build, filters, relationship validation |
| `config` | Three-layer merge, missing-file fallback, invalid YAML error |
| `paths` | Env → config → default resolution; schema-version gate |
| `manifest` | Feature flag detection, version compare, missing-feature signaling |

### Integration tests (pytest, fake data dir)

| Scenario | Covers |
|---|---|
| `test_setup_fresh_data_dir` | `scoutctl setup data-dir` on empty dir creates all expected subdirs + seed files |
| `test_setup_idempotent` | Second `scoutctl setup` run changes nothing |
| `test_setup_refuses_on_schema_mismatch` | v1 data dir, v2 engine → refuses with migrate instruction |
| `test_hook_end_to_end` | Pipe Claude Code event JSON to `scoutctl hook connector-log`; assert JSONL row appended |
| `test_manifest_round_trip` | `manifest build` → `manifest show` equality |
| `test_action_items_cli_contract` | Every action-items subcommand's stdout/stderr/exit-code shape scout-app depends on |

### Contract tests (both sides)

Snapshot files committed to `engine/tests/contract/snapshots/`. Python side asserts the engine produces matching output; Swift side decodes the same snapshots via the app's types. CI fails if either drifts.

Contract changes = update snapshots + bump manifest capability + bump app floor, all in a linked PR pair.

### Shell parity tests (migration-only)

For each of the 11 shell scripts being ported: bats test runs `bash old_script.sh < fixture` and `scoutctl <subcommand> < fixture`; diffs stdout + produced files. Must be green before old script deleted. Removed from CI after migration step 9.

### Swift tests (XCTest)

| Target | Focus |
|---|---|
| `ScoutEnvironmentResolverTests` | 4 resolution paths |
| `EngineClientTests` | Mock Process injection; argv, stdin, timeout, nonzero-exit |
| `CapabilityCheckerTests` | Manifest version + feature-flag matrix |
| `FirstRunWizardTests` | Screen validation, happy path persistence |
| `ContractTests` | Decode committed engine snapshots |

### CI

`scout-plugin/.github/workflows/test.yml`:

```yaml
on: [push, pull_request]
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        python: ["3.11", "3.12"]
    steps:
      - uv pip install -e "./engine[dev]"
      - ruff check engine/scout engine/tests
      - mypy engine/scout
      - pytest engine/tests --cov=scout --cov-fail-under=90
      - shellcheck engine/bin/scoutctl
```

`scout-app/.github/workflows/test.yml`:

```yaml
  - xcodebuild test
  - contract-tests against pinned scout-plugin version (submodule or fetched tarball)
```

`scout-plugin/.github/workflows/release.yml` on tags `v*`:

```yaml
  - build manifest.json
  - publish GitHub release
  - repository_dispatch → scout-app to refresh contract tests
```

## 10. Error handling

### Exit codes (`engine/scout/errors.py`)

Every `scoutctl` subcommand maps Python exceptions to an exit code + single-line stderr message + (optional) structured JSON stdout when `--json` is passed.

| Code | Class | Example |
|---|---|---|
| 0 | Success | — |
| 1 | Generic / unexpected | Uncaught exception |
| 10 | Config error | `.scout-config.yaml` missing or invalid |
| 11 | Data dir error | `$SCOUT_DATA_DIR` unset or not a directory |
| 12 | Schema version mismatch | Data dir v1, engine expects v2 |
| 20 | KB error | Entity not found, schema violation |
| 21 | Action-item error | `no-match` / `ambiguous` substring lookup |
| 30 | External process error | `git`, `claude`, `launchctl` failed |
| 40 | Contract violation | Manifest missing required feature |

### Swift side

`EngineClientError` enum maps engine exit codes to specific cases. `EngineClient.markActionItemDone` throws `ActionItemError.noMatch(taskID)` — not a generic process failure.

### User-visible error format

Every failure a user sees has three parts:

1. **What** — one sentence.
2. **Why** — the cause.
3. **Next step** — a specific command to try.

Example:

> Scout data directory is at schema v1 but engine expects v2.
> Run: `scoutctl migrate data-dir --from 1 --to 2`

### Observability

- `scoutctl --log-level debug <cmd>` — structured JSON-line logs to stderr.
- `scoutctl diagnose` — redacted dump of resolved paths, manifest, config (without `user.*` scalars or `.mcp.json` values), recent log tails, schema version.
- App's Help → Copy Diagnostic invokes `scoutctl diagnose` and puts output on the clipboard.

## 11. Personal-data scrub pass

The audit surfaced ~56 findings across SKILL.md (1074 lines, 35 findings), DREAMING.md (549 lines, 14 findings), and RESEARCH.md (196 lines, 7 findings) including family names, phone numbers, home city, pet name, colleague names, internal project codes (Geneea, NAH, P3, E2B, KAI), Slack channels, emails, and specific dates.

The design handles this via **split**, not **scrub-and-delete**:

- **Scalars** (email, GitHub username, Slack ID, timezone, phone) → `~/Scout/.scout-config.yaml` under `user:`. Jinja-rendered into skill templates at session start.
- **Relations** (people, projects, channels, companies) → `~/Scout/knowledge-base/` entries. Skills query via `scoutctl kb query --type person --name-match "${name}"` at runtime.

### Ordered task list (Step 5 of Jordan's migration)

**Phase A — Set up canonical user-context homes:**
1. Define `user:` block schema in `engine/defaults/scout-config.yaml` with placeholder values.
2. Write real `user:` values into `~/Scout/.scout-config.yaml`.
3. Audit `~/Scout/knowledge-base/people/` — ensure entries exist for every colleague and family member named in SKILL/DREAMING/RESEARCH (audit cited specific names).
4. Audit `~/Scout/knowledge-base/projects/` — ensure entries exist for every project code cited in audit.
5. Create `~/Scout/knowledge-base/channels/` with entries for every Slack channel cited.

**Phase B — Rewrite skills in ascending difficulty order (RESEARCH → DREAMING → SKILL):**
6. RESEARCH.md (7 findings) — scalar substitutions only. Pattern reference.
7. DREAMING.md (14 findings) — scalar substitutions; relational references rewritten as `scoutctl kb query` invocations.
8. SKILL.md (35 findings) — same pattern, more instances. Family phone numbers deleted from skill entirely; move to KB person entries with `phone:` frontmatter if retention is desired.

**Phase C — Verify:**
9. Re-run the audit prompt against the scrubbed copies in `scout-plugin/skills/` → must return zero findings.
10. Grep `scout-plugin/` for every specific name/email/phone the audit flagged → must be absent.
11. Commit scout-plugin with tag `scrub-complete`.

**Phase D — Wire runtime context injection:**
12. Engine adds a template rendering step before session start: Jinja over the skill markdown with `{user: {...}, kb_summary: {...}}` context.
13. Test with live data: run a session with the template-rendered skills; verify Claude's output quality is not degraded relative to pre-scrub inlined-context behavior. Degradation fix: more structured `kb_summary` injection, not re-inlining.

**Phase E — Delete originals:**
14. `rm ~/Scout/SKILL.md ~/Scout/DREAMING.md ~/Scout/RESEARCH.md`.

## 12. YAGNI list (explicit non-scope)

Out of scope for this design:

- Windows port.
- TUI rewrite (moves as-is).
- Plugin auto-update (git pull is fine).
- Web UI.
- Sparkle auto-updater in scout-app (future).
- Migration tooling beyond schema-version scaffolding.
- Touching `~/Scout/.obsidian/` or existing KB content beyond Phase A scrub gap-fill.
- Signing `scoutctl` (Python; no binary).
- Rewriting engine in Go/Rust/Swift.
- Any engine capability not currently present in `~/Scout` (this spec is consolidation, not feature work).

## 13. Open questions

None blocking implementation. Possible followups after v0.4.0 ships:

- Sparkle auto-updater for scout-app.
- A `scoutctl plugin sync` command that wraps `git pull && uv pip install -e .[dev] --upgrade && scoutctl setup verify` into one colleague-friendly update step.
- Auto-prompt in app when plugin has updates available (polls `git fetch` periodically).
- A public "example" KB seed dataset for colleagues' first-run bootstrap.

## 14. References

- Existing cross-repo feature example: `docs/superpowers/specs/2026-04-22-usage-and-connector-health-design.md`.
- scout-plugin repository: `github.com/jordanrburger/scout-plugin`.
- scout-app repository: `github.com/jordanrburger/Scout`.
- Audit of personal-info in SKILL.md, DREAMING.md, RESEARCH.md: performed 2026-04-24; ~56 findings across three files.
