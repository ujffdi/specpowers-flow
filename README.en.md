[中文](README.md) | **English**

# specpowers-flow

## What it is

`specpowers-flow` is a self-contained, cross-platform skill plugin that delivers an
end-to-end, spec-driven engineering workflow — from raw idea to archived living spec.
It fuses *process discipline* (explicit stages, mandatory gates, adversarial review,
subagent-driven TDD) with *spec-driven artifact management* (the OpenSpec
`proposal/design/tasks/spec-delta` lifecycle and the active-change → archive pattern)
into one auditable, right-sized loop. The plugin runs as pure markdown skills — no
runtime code — and works on both Claude Code and Codex without any external dependency.

```
brainstorm → generate-spec → harden-spec → plan-from-spec → check-coverage → execute-plan → verify-compliance → archive
```

Each arrow is a mandatory gate. Stage is inferred from on-disk artifacts; no hidden
state is authoritative. Gate evidence records the content digests of every verified
artifact so that editing anything after a gate passed invalidates that gate and all
downstream gates on resume.

---

## Why

Disciplined spec-driven development requires remembering a lot: write a proposal before
designing, harden the spec adversarially before planning, build a coverage matrix before
writing code, test-first inside every task, run an independent compliance review before
archiving, and merge the spec delta into the living specs atomically. Left to memory,
each of these disciplines is skipped under time pressure or forgotten mid-change. The
result is undocumented behavior, coverage gaps, stale living specs, and changes that
were "done" but never verified against a written contract.

`specpowers-flow` encodes every discipline as an explicit stage with a gate that cannot
be bypassed: the next stage does not start until the current gate passes, and a resumed
flow revalidates all prior evidence before proceeding. The right stage, the right gate,
and the required artifact are always explicit — the workflow is not something the user
has to remember.

---

## Skills and references

### 6 skills

| Skill | Role |
|---|---|
| `specpowers-flow` | Orchestrator — tier selection, stage detection, gate enforcement, routing, resume |
| `specpowers-brainstorm` | Stage 1 — raw idea to approved direction and `proposal.md` draft |
| `specpowers-spec` | Stages 2–3 — generate OpenSpec artifacts, then harden via adversarial spec review |
| `specpowers-plan` | Stages 4–5 — write the plan into `tasks.md`, then build the requirement coverage matrix |
| `specpowers-build` | Stages 6–7 — subagent-driven TDD execution (fresh subagent per task) + compliance verification |
| `specpowers-archive` | Stage 8 — archive-readiness gate, living-spec update, final summary |

### 10 reference templates

| Reference | Purpose |
|---|---|
| `references/stage-protocol.md` | Master table: 8 stages × input / output / gate / next / failure routing |
| `references/openspec-artifact-format.md` | Adopted directory and file format for all change artifacts |
| `references/tiering-rules.md` | quick / standard / full selection rules and non-overridable escalation |
| `references/independent-review.md` | Adversarial subagent dispatch pattern for Claude Code and Codex |
| `references/subagent-execution.md` | Per-task subagent execution protocol with two-stage review |
| `references/test-driven-development.md` | RED → GREEN → REFACTOR discipline and the test-first sub-gate |
| `references/adversarial-spec-review.md` | Spec-review checklist applied during harden-spec |
| `references/plan-coverage-matrix.md` | Requirement → plan step → test coverage table and pass/fail rules |
| `references/compliance-verification.md` | Implementation-vs-spec verification with change-set evidence binding |
| `references/archive-checklist.md` | Archive readiness checklist, conservative fallback, and required summary |

---

## Tiering

The orchestrator estimates change size (files touched, reversibility, blast radius) and
selects a tier; the user may override downward within the limits below.

| Stage | quick (small / bugfix) | standard (most features) | full (high-risk / large) |
|---|---|---|---|
| brainstorm | skip, inline one-liner | light | full |
| generate-spec | proposal + tasks; spec delta required for any behavioral change | full artifacts | full |
| harden-spec | self-check | 1 independent adversarial subagent | parallel adversarial subagents |
| plan | inline in tasks.md | tasks.md | separate plan + tasks |
| check-coverage | quick checklist | coverage matrix | matrix + re-check |
| execute (TDD) | required | required | required |
| verify-compliance | light self-check | 1 independent adversarial subagent | parallel adversarial subagents |
| archive | gates | gates | gates + user confirmation |

### Non-overridable escalation

Any change touching authentication / authorization / permissions, data migration or
schema changes, destructive or irreversible state changes, tenant / security boundaries,
or money / billing is **forced to `standard` or `full`** regardless of size estimate or
user-requested tier. The orchestrator detects these from the brainstorm scope. This
escalation cannot be bypassed by tier selection or override.

High-risk surfaces additionally require a real spec delta before coverage or compliance
can pass. A `no-spec-delta` exemption is allowed only for independently-reviewed,
genuinely non-behavioral changes (pure docs or formatting); it must be narrow and logged.

### Behavioral-change delta rule

Any change that alters behavior requires a real spec delta in every tier, including
`quick`. Without a living-spec contract the coverage and compliance gates have nothing to
verify against. `quick`'s "spec delta optional" applies only to genuinely non-behavioral
changes (docs / formatting / comments).

---

## Install

### Claude Code

1. Clone the repository into your Claude Code plugins directory:

   ```bash
   git clone https://github.com/suka/specpowers-flow \
     ~/.claude/plugins/specpowers-flow
   ```

   Alternatively, install via the Claude Code plugin marketplace if it is listed there.

2. The plugin manifest is at `.claude-plugin/plugin.json`. Claude Code reads this to
   register the plugin name, version, and description.

3. Skills are under `skills/<name>/SKILL.md` — for example,
   `skills/specpowers-flow/SKILL.md` is the orchestrator.

4. Reference templates are at `references/<name>.md` at the repo root — they are shared
   by all skills and do not need separate installation.

### Codex

The skill bodies load their protocols with relative paths like `references/<file>.md`,
resolved **relative to the plugin root**. So `skills/` and `references/` MUST stay
colocated under one common root — do **not** scatter skills into a flat
`~/.codex/skills/` while moving `references/` elsewhere, or the mandatory stage,
compliance, and archive protocols will fail to resolve.

1. Install the plugin as a single directory, keeping its layout intact:

   ```bash
   git clone https://github.com/suka/specpowers-flow \
     ~/.codex/plugins/specpowers-flow
   ```

   This keeps `~/.codex/plugins/specpowers-flow/skills/` and
   `~/.codex/plugins/specpowers-flow/references/` under the same root, so every
   `references/<file>.md` referenced from a `SKILL.md` resolves correctly.

2. Point your Codex skills configuration at
   `~/.codex/plugins/specpowers-flow/skills/` (use a symlink into your Codex skills
   directory if it must live elsewhere — symlink the whole plugin dir, not individual
   skills, so the `references/` sibling travels with it).

3. Codex reads each `skills/<name>/SKILL.md` directly. The frontmatter `name` field
   matches the directory name; `description` contains the trigger phrases Codex uses to
   select the skill. When a skill says "read `references/<file>.md`", resolve it from the
   plugin root above.

---

## Usage

### Trigger phrases

Invoke the orchestrator skill with any of:

- `"run the full specpowers flow"`
- `"start a complete spec-driven change"`
- `"go from brainstorm to archive"`
- `"use specpowers for this feature"`

The individual phase skills can also be invoked directly when resuming at a specific
stage — for example, `"use specpowers-build"` to resume at the execute-plan stage.

### New change vs resume

**New change:** when no `openspec/changes/<change-name>/` directory exists yet, or when
the user requests a fresh start. The orchestrator begins at stage 1 (brainstorm) and
walks through all 8 stages in order, enforcing each gate before advancing.

**Resume:** when an `openspec/changes/<change-name>/` directory already exists, the
orchestrator scans the on-disk artifacts and the `.specpowers/gates/` sidecar records to
infer the current stage. It recomputes content digests for every previously-passed gate;
if any verified artifact changed since the gate passed, that gate and all downstream
gates are invalidated and the flow routes back to the correct stage. The user is shown
the current stage and the next required action.

---

## Relationship to Superpowers and OpenSpec

`specpowers-flow` is **inspired by** Superpowers (process-discipline skills) and OpenSpec
(spec-driven artifact lifecycle). It is **not** a thin wrapper around either — it
reimplements the essential logic self-contained and does **not** require either project
to be installed.

When Superpowers skills or the `openspec` CLI are detected in the environment, the plugin
uses them: the orchestrator may hand off brainstorm, execute-plan, and test-driven stages
to real Superpowers skills, and `specpowers-archive` prefers `openspec archive` over the
built-in conservative fallback. This is **progressive enhancement** — the plugin works
everywhere and is more capable where the real tools are present.

No source text was copied from either project; all content here is original. See `NOTICE`
for the full attribution statement and license references.
