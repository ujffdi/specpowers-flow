# OpenSpec Artifact Format

This reference defines the directory layout and per-file content requirements that
specpowers-flow adopts from OpenSpec's spec-driven artifact lifecycle. All phase skills
read and write artifacts according to this format. When the real `openspec` CLI is
present, prefer its `validate` and `archive` commands; the layout described here is the
fallback definition that governs behavior when the CLI is absent.

---

## Directory Layout

```
openspec/
├── changes/
│   ├── <change-name>/              ← active change
│   │   ├── proposal.md
│   │   ├── design.md
│   │   ├── tasks.md
│   │   ├── specs/
│   │   │   └── <capability>/
│   │   │       └── spec.md         ← spec delta for that capability
│   │   ├── reference/              ← optional supporting material
│   │   ├── review/                 ← optional review records
│   │   └── .specpowers/            ← gate-evidence sidecar (see below)
│   └── archive/
│       └── <YYYY-MM-DD>-<change-name>/   ← archived change (read-only)
└── specs/
    └── <capability>/
        └── spec.md                 ← living spec for that capability
```

### Naming Conventions

- `<change-name>`: lowercase kebab-case description of the change
  (e.g. `add-rate-limiting`, `redesign-checkout-flow`).
- Archive directory name: ISO date prefix of the archive date followed by the original
  change name (e.g. `2026-06-01-add-rate-limiting`).
- `<capability>`: a logical product area or domain boundary, also lowercase kebab-case
  (e.g. `auth`, `order-processing`, `notification-delivery`).

---

## Active Change Directory

An active change lives at `openspec/changes/<change-name>/` until it is archived.
The required files are `proposal.md`, `design.md`, `tasks.md`, and at least one spec
delta under `specs/<capability>/spec.md`. The `reference/` and `review/` subdirectories
are optional but conventionally used for supporting context and adversarial review
records respectively.

---

## Artifact Contents

### `proposal.md` — the change proposal

Written first, by `specpowers-brainstorm`. Contains three sections:

- **Why** — the problem or opportunity that motivates this change: current pain, user
  impact, or technical debt. Answers "why now?" and "why does this matter?".
- **What Changes** — the concrete scope: which capabilities, behaviors, and surfaces are
  affected. Explicit enough that someone who hasn't been in the discussion can read it
  cold and know what is in and out of scope. Also declares any capabilities that are
  intentionally excluded.
- **Impact** — files and modules expected to change, dependencies, risks, and known
  constraints. Does not need to be exhaustive at proposal time but should be honest
  about blast radius.

### `design.md` — technical design

Written by `specpowers-spec`. Contains the full technical design for the change:

- **Goals and Non-Goals** — refined from the proposal; makes the scope boundary
  precise.
- **Decisions** — key design choices with rationale and rejected alternatives. Each
  decision is explicit so later reviewers can challenge the reasoning rather than
  reverse-engineering it from the implementation.
- **Risks and Trade-offs** — identified risks with mitigations; quantified where possible.
- **Migration Plan** (if applicable) — how to roll out, roll back, or migrate data.
- **Open Questions** — unresolved items that must be decided before implementation
  can proceed; each should be assigned an owner.

### `tasks.md` — the implementation plan

Written by `specpowers-plan` into this file directly. This is where the plan lives;
there is no separate plan document. Contains a checkbox task list:

```markdown
- [ ] Task N: Short description
  - Target: file/module
  - Test strategy: how to verify
  - Verification command: the command to run
  - Rollback: how to undo if needed
  - Assumptions: what must be true before starting
```

Each task must trace to at least one requirement in the spec delta and have a
corresponding row in the coverage matrix. The checkbox is checked only after the
task's implementation is complete, tests pass, and evidence is preserved.

### `specs/<capability>/spec.md` — spec delta

Written by `specpowers-spec`; amended by `specpowers-plan` and `specpowers-build` when
divergence is detected. A spec delta describes only what this change adds or modifies
relative to the living spec; it does not repeat unchanged requirements.

#### Markers

Every requirement block is introduced with one of three markers:

- `## ADDED Requirements` — new requirements that did not exist before this change.
- `## MODIFIED Requirements` — requirements that existed and are being changed; include
  the original wording (or a reference to it) so the delta is traceable.
- `## REMOVED Requirements` — requirements being intentionally retired; explain why.

#### Requirement format

Each requirement uses a `SHALL` statement that is precise enough to be verified, not
just evaluated by reading. Vague words like "should be fast" or "handle errors well"
are not acceptable; the requirement must name a measurable outcome or a specific
behavior boundary.

Every `SHALL` statement must be accompanied by at least one scenario:

```markdown
### Requirement: <short name>

The system SHALL <precise, testable behavior statement>.

#### Scenario: <name>

- **WHEN** <specific precondition or action>
- **THEN** <observable outcome that can be checked>
- **AND** <additional assertion if needed>
```

Multiple scenarios per requirement are expected for non-trivial behaviors. Each
scenario should cover a distinct condition: happy path, failure path, boundary case, or
edge case that the `SHALL` statement implies.

---

## `.specpowers/` Sidecar Directory

The `.specpowers/` directory lives inside the active change directory at
`openspec/changes/<change-name>/.specpowers/` and is managed exclusively by
specpowers-flow. It is not part of the OpenSpec spec content and is not validated or
touched by the `openspec` CLI.

Its sole purpose is to hold gate-evidence records. Each passed gate writes a YAML
file to `.specpowers/gates/<stage>.yaml` containing the content digests and timestamps
of the artifacts it verified. The structure and semantics of these records are defined
in `references/stage-protocol.md`.

The sidecar is treated as a cache: if a gate-evidence file is present but its recorded
digests no longer match the current artifact content on disk, the orchestrator
invalidates that gate (and all downstream gates) and routes back to the appropriate
stage. The sidecar should be committed alongside the change artifacts so resuming from
a different machine or agent session works correctly.

---

## Living Specs

Living specs accumulate requirements across all changes. They live at
`openspec/specs/<capability>/spec.md` and are updated by the `archive` stage by merging
the accepted spec deltas from the change into the living document.

Living specs use the same `SHALL` + scenario format as spec deltas. After archive, the
change's spec delta is no longer the authoritative source; the living spec is.

---

## CLI Integration

When `openspec` is present on the path, its commands take precedence:

- `openspec validate` — validates artifact structure, requirement format, and scenario
  completeness. Use this in preference to manual format checks.
- `openspec archive` — performs the spec-delta merge into living specs, moves the
  change directory to the archive path, and writes the archive manifest. Use this in
  preference to the conservative fallback merge.

When the CLI is absent, specpowers-flow falls back to the procedures defined in
`references/archive-checklist.md` (conservative guided merge) and performs its own
format checks.
