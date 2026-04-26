# Scout Event Architecture (v0.5+)

**Date:** 2026-04-25
**Status:** Vision document — not bound to v0.4 implementation. Companion to [`2026-04-24-scout-unification-design.md`](./2026-04-24-scout-unification-design.md).
**Author:** Jordan Burger (drafted with Claude)
**Audience:** Anyone considering using or extending Scout. Read the v0.4 unification spec first for product context — this document picks up where that one ends.

## TL;DR

Scout today is a personal autonomous-knowledge tool: a Claude-powered engine plus a Mac menu-bar app that reads/writes a `~/Scout` data directory. The v0.4 unification spec consolidates engine + plugin + app distribution. This document is the next step.

In v0.5+, **Scout becomes a personal event bus with pluggable connectors.** Many sources push events in (Slack messages, Linear status changes, GitHub PR events, Telegram messages, calendar events). Many handlers consume them (action-item updates, KB writes, ad-hoc Claude sessions, projection caches). Action items, the KB, the Mac app, the TUI — all become *projections* over the event log rather than the canonical store.

A defining property: **Scout itself can author new connectors on the fly.** When the user describes a new source-and-trigger pairing in chat, Scout fills out a connector manifest YAML; the engine validates and starts a worker process. No commit, no PR. The pattern is the same one Home Assistant, Beeper, and Zapier use, with a Claude-shaped front door.

This is a one-year evolution split into versions v0.5 → v0.9. Each step is independently shippable; you can stop at any point and still have a coherent system.

## Why this exists

The v0.4 spec consolidates a working personal tool. It does not address three things that became visible during v0.4 brainstorming:

1. **External event ingestion.** Linear status changes, Slack messages, GitHub events, Telegram messages from the user. Today, none of them flow into Scout. Scout discovers them by polling later, if at all.
2. **Multi-source identity.** Substring matching (`mark_done --subject "lever"`) makes external sync structurally impossible. If Linear says *"ENG-1234 changed state to Done,"* there's no join key from that event to a markdown line in `action-items-2026-04-25.md`.
3. **Self-extensibility.** A growing fraction of the user's actual desire is *"write me a small daemon that does X with my Slack/Linear/calendar/Telegram."* Doing this case by case as new shell scripts is exactly the unmaintainable pattern v0.4 is unwinding.

Without an architectural answer, every new "Scout watches X" feature lands as another bespoke shell script with its own concurrency model, its own credentials handling, its own retry logic, and its own coupling to action-item markdown. v0.4 was the last reasonable iteration of "more scripts;" v0.5 is the architectural shift.

## The reframe

| Before (v0.4 and earlier) | After (v0.5+) |
|---|---|
| Scout is a personal knowledge log | Scout is a personal event bus with attached projections |
| Markdown is the canonical store | Markdown is one projection (the human/LLM-readable one) |
| Scripts are mutators | Scripts are *event sources* and *event handlers* |
| New features = new scripts | New features = new connectors and new subscribers |
| Concurrency = hope and atomic rename | Concurrency = append-only log + idempotent handlers |
| Multi-source sync = manual reconciliation | Multi-source sync = each source is just another connector |

## Architecture

```
                    External world (sources)
   ┌─────────┬─────────┬─────────┬──────────┬───────────┐
   │ Linear  │  Slack  │ GitHub  │ Telegram │ Calendar  │
   │webhooks │ events  │ webhooks│  bot     │   ICS     │
   └────┬────┴────┬────┴────┬────┴─────┬────┴──────┬────┘
        │         │         │          │           │
   ╔════▼═════════▼═════════▼══════════▼═══════════▼════╗
   ║                  CONNECTORS                        ║
   ║  Each: auth + transform + emit canonical events    ║
   ║  Declared via YAML manifest; isolated process      ║
   ╚════════════════════════╤═══════════════════════════╝
                            │
   ╔════════════════════════▼═══════════════════════════╗
   ║              EVENT LOG  (canonical)                ║
   ║   $SCOUT_DATA_DIR/.scout-logs/events.jsonl         ║
   ║   Append-only. Every event: id, ts, source,        ║
   ║   kind, payload, dedup_key                         ║
   ╚════════════════════════╤═══════════════════════════╝
                            │
   ╔════════════════════════▼═══════════════════════════╗
   ║                  DISPATCHER                        ║
   ║  Routes events → handlers. Idempotency, retry,     ║
   ║  backpressure, dead-letter queue.                  ║
   ╚═╦══════════╦═════════╦════════╦═══════════╦═══════╝
     │          │         │        │           │
     ▼          ▼         ▼        ▼           ▼
 Action     KB        Session   Watch       Custom
 Items      Updater   Spawner   Diff       (user-
 Projection                     Stream     authored)
     │          │
     ▼          ▼
 Markdown    KB markdown +
 files       schema files
```

Three properties to notice:

1. **The event log is the canonical store.** Markdown action items, KB files, and projection caches are all *materializations* of the log. They can be rebuilt from scratch by replay.
2. **Connectors are isolated.** Each connector is its own process. A crash in the Telegram listener doesn't take down the Slack bridge or the Linear receiver.
3. **Handlers subscribe to event kinds, not to sources.** The "Action Items Projection" handler subscribes to `action_item.*` events regardless of whether they came from CLI, Obsidian, Linear, or a hand-authored connector. This is the shape that makes new sources cheap.

## Core concepts

### Event

```jsonl
{
  "id": "01HXABC...",
  "ts": "2026-04-25T14:32:01Z",
  "source": "connector:linear",
  "kind": "linear.issue.updated",
  "dedup_key": "linear:ENG-1234:state:Done",
  "payload": {"issue_id": "ENG-1234", "state": "Done", "title": "..."}
}
```

ULID for `id` (sortable, no clock sync needed). `kind` follows a flat namespace: `<domain>.<entity>.<verb>`. `dedup_key` lets the dispatcher drop redeliveries that at-least-once delivery inevitably produces.

### Connector

A worker process that converts an external source into events. Declared via YAML manifest:

```yaml
# ~/Scout/connectors/linear-status-sync.yaml
name: linear-status-sync
version: 1
authored_by: scout-session-2026-04-25-1432  # or human@email
source:
  kind: webhook                    # or polling | bot | script | inbound-rest
  url_path: /webhooks/linear
  secret_env: LINEAR_WEBHOOK_SECRET
transform:
  jq: |
    {
      kind: "linear.issue.updated",
      payload: {issue_id: .data.id, state: .data.state.name},
      dedup_key: ("linear:" + .data.id + ":state:" + .data.state.name)
    }
emits:
  - linear.issue.updated
  - linear.issue.commented
permissions:
  - read:secret:LINEAR_WEBHOOK_SECRET
  - write:event_log
runtime:
  builtin: webhook-runner          # or "python-script" with connector.py
  resources: {cpu: "100m", mem: "64Mi"}
```

The engine ships **builtin runners** (`webhook-runner`, `polling-runner`, `bot-runner`, `script-runner`) that interpret manifests of common shapes. Power-user fallback: a connector can ship `connector.py` implementing the same `Connector` interface.

### Handler

A function that subscribes to event kinds and emits side effects (which may include further events). In v0.5 these live in the engine as Python; in v0.7+ they can be user-authored alongside connectors:

```python
@handler.subscribe("action_item.completed", "linear.issue.updated")
def update_action_items_projection(events: list[Event]) -> list[Event]:
    """Materialize event batch into the action-items markdown.
    Idempotent: re-runnable on the same events."""
```

### Projection

A derived view rebuilt from events. The action-items markdown projection is one. The Mac app's in-memory cache is another. The KB summary cache (Plan 5 of v0.4) is a third. Projections may lag the log; the dispatcher tracks "projection X is current through event Y" and exposes that to UIs.

## Architectural principles

- **Hexagonal architecture (Cockburn).** Core domain (action items, KB, sessions) is at the center. *Ports* are interfaces (`EventSource`, `EventStore`, `Projection`, `SessionLauncher`). *Adapters* are swappable implementations. New external sources plug into existing ports without touching the core.
- **CQRS / event sourcing.** Writes go to the event log; reads come from projections. Current state is `fold(events)`. Replay rebuilds any projection.
- **Idempotency by construction.** Every external source delivers at-least-once. Every handler must be re-runnable. `dedup_key` plus stable IDs make this tractable.
- **Capability-based security.** Each connector manifest declares required secrets and event kinds. The engine grants exactly those — never more. A user-authored connector cannot quietly read other connectors' API keys. New permission grants prompt the user.
- **Backpressure and coalescing.** Slack busy-day = 100 events/min. The dispatcher coalesces: *"5 messages in thread X within 30s → one `slack.thread.active` event."* Per-handler rate limits prevent runaway Claude session spawning.
- **Choreography over orchestration.** Handlers react to events independently. One event can have many subscribers; new subscribers don't require coordinator changes. Orchestration (a central state machine) is reserved for true multi-step sagas.
- **Eventual consistency, made visible.** Projections may lag. The Mac app shows a small indicator when its view is more than ~2s behind the log. Honest UX beats the illusion of synchronous truth.
- **Fail open, retry forever.** A handler crash logs to a dead-letter queue and retries with exponential backoff. The event is never lost. The user sees a banner; nothing wedges silently.

## Self-extensibility: Scout authors its own connectors

The motivating scenario:

> *"When my colleague comments 'ship it' on a GitHub PR I authored, send me a Telegram message and append a 🟢 action item to today's list."*

The flow:

1. User invokes a `scout-build-connector` skill in chat.
2. Scout (the agent) elicits the source shape, the trigger condition, the action.
3. Scout fills out a connector manifest YAML (or, for shapes the manifest can't express, a small `connector.py` against the documented interface).
4. Scout writes it to `~/Scout/connectors/<name>.yaml` and asks the user to confirm.
5. User runs `scoutctl connector enable <name>`. The engine validates the manifest, prompts for any required secrets it doesn't already hold, and starts a worker process.
6. Events start flowing. A Scout-authored handler (`~/Scout/handlers/<name>.py`) subscribes and produces side effects — sending Telegram via the existing outbound Telegram connector, appending an `action_item.created` event consumed by the action-items projection.

The pattern is **declarative-first, escape hatch to code**. Scout doesn't write daemons from scratch — that's a debuggability and security catastrophe. Scout fills in templates the engine knows how to run, and writes small handlers against a stable subscription API.

This is the same shape as MCP servers, Home Assistant integrations, and Zapier triggers — all of which thrive precisely because the boundary is well-defined.

### Safety rails on self-authoring

- **Manifest validation** — schema check before enable; rejects unknown fields, unsupported runtime types, malformed jq.
- **Secret prompts are user-mediated** — engine never ingests a secret from the agent's chat-message context. User pastes into a separate prompt or keychain entry.
- **Dry-run mode** — `scoutctl connector enable --dry-run` runs the worker against a sample event without producing side effects.
- **Per-connector kill switch** — `scoutctl connector disable <name>` stops the worker; events queued for it drain to dead-letter.
- **Audit log** — every connector enable/disable, every secret grant, every authored manifest is appended to the event log itself (`scout.connector.authored`, `scout.connector.enabled`, `scout.permission.granted`). Self-monitoring.

## Roadmap

| Version | Adds | Carries forward from v0.4 |
|---|---|---|
| **v0.4** (current spec) | Stable IDs everywhere, mutations function-shaped as events, `watch` reframed as projection consumer | All of unification |
| **v0.5** | Event log JSONL writer; mutations *also* append to log (markdown still authoritative); first projection rebuilder runs offline | Markdown stays canonical for action items; no external connectors yet |
| **v0.6** | Dispatcher with idempotency + retries; first connector (**Linear** — easiest: stable IDs, signed webhooks, REST API); event log becomes co-canonical with markdown | Plan 6's scout-app reads from the projection cache, not directly from markdown |
| **v0.7** | Connector manifest schema v1 + generic runners; second connector (**Slack**); third (**Telegram bot**); migrate v0.4's `connector-log` and `session-tokens` hooks to emit events | Markdown remains the editable surface |
| **v0.8** | `scoutctl connector build` skill: agent fills out manifest in chat, engine validates and starts. Capability-grant prompts for new permissions. | First user-authored connectors land |
| **v0.9** | Saga support for multi-step orchestration; outbound connectors (Telegram→user, Slack→channel); session-spawning handler with policy gates | — |

Roughly a year of evolution. Each step independently shippable. **You can stop at any version and still have a coherent system.**

## What v0.4 must commit to (the small price of admission)

The full architecture lands in v0.5+. v0.4 makes three commitments that keep the door open without expanding scope:

1. **Stable IDs on every mutable entity.** Action items, KB entries, connector log lines, sessions. ULID. Per-entity comment marker for markdown items: `- [ ] task title <!-- id:01HX... -->`.
2. **Mutations modeled as events at the function level.** `mark_done` returns an event-shaped object even though nothing yet logs it. This is a 5-line discipline change per script, not a re-architecture.
3. **`watch` and `kb_summary` are documented as projection consumers**, not file-watchers. v0.4 implements them as file-watchers (because no event log exists yet), but their public contract is the right shape for substitution in v0.5.

That's the entire v0.4 commitment. Everything else in this document is v0.5+.

## What this is *not*

- **A real-time collaboration system.** Scout is single-user. Multi-user / true CRDT editing is out of scope.
- **A general workflow engine.** It's specialized to "events trigger LLM sessions and projections." If you need branching workflows with manual approval gates, use n8n or Inngest.
- **A replacement for Linear/Slack/GitHub.** Scout aggregates and reacts; it does not become the source of truth for any external system.
- **A hosted service.** Single-machine, single-user, file-based. The dispatcher and connectors are local processes. (A future hosted variant is conceivable but explicitly out of scope.)
- **Open-ended code generation.** Scout authors connectors against a constrained manifest schema. It does not write arbitrary daemons.

## Open questions

1. **Where do outbound connectors live?** When Scout sends a Telegram message in response to an event, is "send Telegram message" a connector (symmetric — connectors are bidirectional) or a handler operation (asymmetric)? Probably symmetric — connectors are bidirectional in Beeper, n8n, and Home Assistant.
2. **Secret storage.** macOS Keychain is the obvious answer for v0.4-era. For colleague portability (Linux, headless), we may need an opt-in encrypted file fallback (e.g., `age`-encrypted secrets file). Defer to v0.5 design.
3. **Event log retention.** Append-only forever isn't viable beyond a few months. Periodic compaction into projection snapshots is needed. v0.7 problem.
4. **Cross-process coordination.** Multiple connectors and multiple handler processes all writing to the same JSONL. Atomic-append with `O_APPEND` is sufficient for line writes ≤ 4KB (POSIX guarantee — already specced in unification §6). Larger payloads need `flock`. Worth re-confirming under load.
5. **Schema evolution.** Event payloads will change. Need a migration story (event versioning via a `v` field on each event; projection rebuild on schema bump). v0.6 problem.
6. **Backfill semantics.** When a new Linear connector is enabled, does it backfill historical events, or only stream from "now"? Probably user-configurable, default "now"; backfill is a separate `scoutctl connector backfill` command.

## Prior art

| System | Pattern stolen |
|---|---|
| **Home Assistant** | Connector manifest YAML; integration registry; capability declaration; user-mediated permission grants |
| **Beeper / Matrix bridges** | One bridge process per source; isolation; common event vocabulary |
| **Inngest / Trigger.dev** | Durable event-driven LLM workflows; idempotency primitives; dead-letter retry |
| **n8n / Activepieces** | User-authored connector SDK; declarative-first; visual flow as optional layer |
| **Apache Camel / Spring Integration** | Enterprise integration patterns vocabulary (Hohpe & Woolf 2003) |
| **MCP (Model Context Protocol)** | Cleanest existing model for "agent authors a new external interface" |
| **TaskWarrior** | CLI-first task management with sync server (`taskd`) |
| **Logseq, org-roam** | Markdown-canonical with derived index — the pattern v0.4 keeps and v0.5 extends |

## References

- v0.4 unification spec: [`./2026-04-24-scout-unification-design.md`](./2026-04-24-scout-unification-design.md)
- Hohpe & Woolf, *Enterprise Integration Patterns* (2003) — the vocabulary
- Cockburn, *Hexagonal Architecture* (2005) — the boundary model
- Home Assistant developer docs on integrations and the event bus
- MCP specification: `modelcontextprotocol.io`
- Inngest concepts: durable functions, event-driven workflows, idempotency keys

## Status notes

This is a *vision document*, not a binding spec. Implementation details (file formats, exact CLI surface, exact handler API) will be finalized in version-specific specs (`2026-MM-DD-scout-event-architecture-v0.5-design.md` etc.) when each version is brainstormed in turn. The purpose of this document is to establish the destination, so v0.4 does not paint into a corner and so colleagues can evaluate whether this trajectory matches their needs.
