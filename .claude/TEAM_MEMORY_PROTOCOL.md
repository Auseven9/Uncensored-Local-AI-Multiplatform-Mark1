# TEAM MEMORY PROTOCOL (v1, owner: Ark)

Principle: an immutable ground-truth log plus a rebuildable current view (the same idea as the project's Archive).

## 1. Schema (one node per entry in ark_map.json)
```
id, name, path, kind, purpose, uses[], used_by[], status, notes,
decided    ISO date the node's current definition was confirmed
confidence confirmed | likely | guess
source     file, commit, test, or agent that proves it
```
`status`: `working` | `planned` | `deprecated`.
Numbers in `notes` are tagged `(measured)` or `(estimated)`.

## 2. Append-only CHANGELOG (ARK_CHANGELOG.md)
Never edited, never regenerated, only appended. Entry format:
```
## vN | YYYY-MM-DD | trigger: <agent/event>
- what changed (node ids affected)
- why (rationale, one line)
```
Removals and renames are logged as entries. Nothing is deleted from the log.
The map (json and md) is a current view and may be rebuilt at any time from the log plus the repo.
Every map version must have a matching log entry.

## 3. Read/Write conventions
| Agent | Reads | Writes |
|---|---|---|
| Vector, Myea (reasoning) | ARK_MAP.md at the start of every call | nothing |
| Ark | map, log, repo | map files and log entries (sole writer) |
| Claude1 | Ark's output | commits it to the repo, verbatim |

Canonical files, all in `docs/memory/` at the repo root:
`ark_map.json` (machine), `ARK_MAP.md` (human view), `ARK_CHANGELOG.md` (immutable log).
If an agent finds an error, it reports to Ark and does not patch the file.

## 4. Integrity rules
1. Record only confirmed truth. Put guesses in `notes` with `confidence: guess`.
2. Always mark planned vs working. Never present a plan as built.
3. "(none recorded)" means unknown, not absent.
4. Never edit another agent's definition. Quote it, cite it in `source`, and flag any conflict in the log.
5. Mark every number as measured or estimated.
6. If rationale conflicts with the new state, keep the old rationale in the log.

## 5. Status header (top of ARK_MAP.md, 3-5 lines)
```
> MAP vN | updated YYYY-MM-DD | by Ark | commit <sha or pending>
> Nodes: X total (W working, P planned, D deprecated)
> Lowest confidence: <ids or "none">
> Last change: <one line, see CHANGELOG vN>
> Open unknowns: <count and top item>
```
