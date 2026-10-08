# ALESIS Team Protocol — the info highway

Standardizes how the team communicates and shares state. Companion to
`.claude/TEAM_MEMORY_PROTOCOL.md` (the memory format, authored by Ark).

## Roster
| Member | Role | Kind | Writes code? |
|---|---|---|---|
| **Dylon** | human — intent, final say | — | decides |
| **Claude1** | computational partner / orchestrator / router | persistent session | yes |
| **Cairn** | builder, in the ALESIS repo (session_01WY5Kc8…) | persistent session | yes (the app) |
| **Vector** | relational analyst (outward + adversarial) | subagent | no (read-only) |
| **Myea** | creative analyst (inward, deeper want) | subagent | no (read-only) |
| **Ark** | cartographer / team memory | subagent | map only |

## Routing (honest topology: hub-and-spoke, Claude1 is the hub)
- Subagents (Vector/Myea/Ark) are spawned by Claude1 and report back to Claude1.
  They are ephemeral per call; their persistence lives in this repo (agent files
  + the map), not in a running process.
- Cairn ↔ Claude1 is cross-session messaging. **Cairn cannot initiate** — it has
  no outbound tool to reach Claude1 — so Claude1 polls Cairn's transcript and
  relays both directions, verbatim. This is a platform limit, not a choice.
- Dylon ↔ Claude1 is the chat. Everyone's words are relayed to Dylon verbatim.

## File transfer (the only cross-container channel)
Containers are isolated. Files cross **only through the shared GitHub repo**.
Research/staging lives in `research/belief-state/` on branch
`ccr-20b2707c-nz8fa6`. Nothing enters `lib/` until its gate passes.

## Shared memory
Canonical memory lives in `docs/memory/`: `ark_map.json` (machine), `ARK_MAP.md`
(human view), `ARK_CHANGELOG.md` (immutable append-only log). Format:
`.claude/TEAM_MEMORY_PROTOCOL.md`. Reasoning agents read the map at the start of a
call; only Ark writes; Claude1 commits. (A v4 snapshot also sits in
`research/belief-state/` from the belief-state work; `docs/memory/` is canonical
going forward.)

## Discipline (non-negotiable)
- No fabrication. Mark measured vs estimated. Confidence floors where recall can
  be wrong (a confident wrong answer is a fabrication).
- Gate before build: a proposed component isn't built until its experiment passes.
- Never claim an architecture produces feeling. Build what it *does*.
- Verdicts are honest even when they deflate the exciting option.
