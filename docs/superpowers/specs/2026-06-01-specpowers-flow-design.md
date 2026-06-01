# SpecPowers Flow — Design Spec

- **Date:** 2026-06-01
- **Status:** Approved (brainstorming phase)
- **Working name:** `specpowers-flow`
- **Source PRD:** `/Users/suka/Documents/Tongsr/PRD-specpowers-flow.md` (Codex-generated; superseded where noted)

## 1. One-line description

A self-contained, cross-platform skill **plugin** that fuses the *process discipline* of
Superpowers with the *spec-driven artifact lifecycle* of OpenSpec into one auditable,
right-sized engineering workflow — from idea to archived living spec.

## 2. Goal

Provide an end-to-end (A+B+C) closed loop: `idea → change proposal → TDD implementation →
archive into living specs → review`, where:

- **Process discipline (from Superpowers):** skill-based stages, mandatory gates, brainstorm →
  plan → TDD → adversarial review methodology, "announce the skill and follow it exactly" rigor.
- **Spec-driven artifacts (from OpenSpec):** the `proposal/design/tasks/spec-delta` artifact set,
  the `active change → archive` lifecycle, living specs as the single source of truth, validation.

The library is **inspired by** both projects and **reimplements** the essential logic itself.
It does **not** require Superpowers or OpenSpec to be installed (but uses them when present —
see §8 Progressive Enhancement).

## 3. Non-goals (MVP)

1. Not a replacement for OpenSpec/opsx or Superpowers — a standalone library inspired by them.
2. No full CLI (markdown skills only; an optional CLI is a future enhancement).
3. No automatic business-code changes without an approved plan.
4. No language/framework/repo-layout assumptions beyond the OpenSpec directory convention.
5. No GitHub API / CI / external SaaS integration.
6. Does not copy text verbatim from either source project — all content is rewritten; see §10.

## 4. Key design decisions (resolved in brainstorming)

| Dimension | Decision |
|---|---|
| Nature | Self-contained library, **inspired by** Superpowers + OpenSpec, not a thin wrapper that delegates to them |
| Form | Multi-skill **plugin** (orchestrator + phase skills) |
| Platform | Cross-platform: Claude Code + Codex, pure markdown skills |
| Artifact format | **Adopt** OpenSpec's directory/file convention (`openspec/changes`, `openspec/specs`, `archive/`) |
| Flow | PRD's 8-stage state machine, **right-sized into tiers** |
| Reviews | Adversarial gates run via **independent subagents** |
| State | **Inferred from on-disk artifacts**; state file is cache-only |
| Redundancy | brainstorm writes the proposal draft directly; the plan lives in `tasks.md` |
| Robustness | Self-contained + **progressive enhancement** (use real tools if detected) |

These five adjustments (tiering, independent review, artifact-inferred state, de-duplication,
progressive enhancement) refine the original PRD, which assumed a single always-full-weight skill
that delegated to installed tools.

## 5. Architecture — skill decomposition

A multi-skill plugin: **1 orchestrator + 5 phase skills = 6 skills.**

| Skill | Stage(s) | Responsibility |
|---|---|---|
| `specpowers-flow` | — | Orchestrator: tier selection, stage detection (from artifacts), gate enforcement, routing, resume, failure fallback |
| `specpowers-brainstorm` | 1 | Idea → problem / scope / success criteria / non-goals / risks / open questions; writes the `proposal.md` draft directly |
| `specpowers-spec` | 2–3 | Generate OpenSpec artifacts + **harden** (validate + adversarial spec review via independent subagent + sync findings back) |
| `specpowers-plan` | 4–5 | Plan from the hardened spec (into `tasks.md`) + **requirement coverage matrix** gate |
| `specpowers-build` | 6–7 | TDD execution (no silent scope expansion; diverge → update artifact first) + **compliance verification** via independent subagent |
| `specpowers-archive` | 8 | Archive-readiness gate checklist + update living specs + final summary |

Each skill = "one self-contained process segment + its gate." `brainstorm` is standalone because
it is a complete, independently-triggerable discipline.

## 6. Stage state machine and gates

The orchestrator drives an explicit 8-stage machine. **Stage is inferred by scanning
`openspec/changes/<change>/`** (which files exist, validation markers, presence of the coverage
table, etc.). A `.specpowers-state.yaml` may cache hints but is **never authoritative** — disk
artifacts are the single source of truth.

```
[brainstorm]        gate: direction approved & requirement specific enough
[generate-spec]     gate: change dir exists & required artifacts present
[harden-spec]       gate: validation passes & no unresolved blocker & findings synced back
[plan-from-spec]    gate: plan exists & explicitly based on hardened spec
[check-coverage]    gate: every requirement ≥1 plan step & ≥1 verification path
[execute-plan]      gate: implementation complete & tests run & evidence preserved
[verify-compliance] gate: compliance passes & tests pass & no unresolved blocker
[archive]           gate: prior 7 gates passed (+ user confirmation when required) → DONE
```

Each stage defines: **input, output, completion gate, next action, failure handling.**

**Failure routing (PRD §12).** Any failed gate routes back to the correct prior stage rather than
continuing. Eight interrupted states are handled: no change exists; artifacts exist but validation
fails; adversarial review finds blockers; plan does not cover all requirements; implementation
diverges from spec; tests fail; compliance verification fails; archive requested before gates pass.

## 7. Tiering (right-sizing)

The orchestrator selects a tier from change size; the user can override. The spine
`spec → coverage → compliance` is mandatory in `standard`/`full`; `quick` compresses but never
removes it.

| Stage | quick (small / bugfix) | standard (most features) | full (high-risk / large) |
|---|---|---|---|
| brainstorm | skip, inline one-liner | light | full |
| generate-spec | proposal + tasks only, delta optional | full artifacts | full |
| harden-spec | self-check | **1 independent adversarial subagent** | **parallel adversarial subagents** |
| plan | inline in tasks.md | tasks.md | separate plan + tasks |
| check-coverage | quick checklist | coverage matrix | matrix + re-check |
| execute (TDD) | ✓ | ✓ | ✓ |
| verify-compliance | light self-check | **1 independent adversarial subagent** | **parallel adversarial subagents** |
| archive | gates | gates | gates + user confirmation |

## 8. Cross-cutting mechanisms

**Independent adversarial review.** `harden-spec` and `verify-compliance` dispatch a subagent
instructed to *refute / find holes*, so the author agent never rubber-stamps its own work.
Platform mapping (Claude Code `Agent`/`Task`; Codex subagent) lives in
`references/independent-review.md`.

**Artifact-inferred state.** See §6. Detection logic lives in the orchestrator skill.

**De-duplication.** Brainstorm output *is* the `proposal.md` draft; the plan *is* `tasks.md`. No
"copy the same content into another file" steps.

**Progressive enhancement.** The orchestrator probes for an `openspec` CLI and Superpowers skills.
If present, it uses the real `openspec validate` / `openspec archive` (true schema validation and
spec-merge) and may hand off brainstorm/plan/execute to Superpowers. If absent, it falls back to
the built-in markdown procedures. Runs everywhere; more robust where real tools exist.

## 9. Repository structure

```
specpowers-flow/
├── .claude-plugin/
│   └── plugin.json                  # Claude Code plugin manifest
├── skills/
│   ├── specpowers-flow/SKILL.md
│   ├── specpowers-brainstorm/SKILL.md
│   ├── specpowers-spec/SKILL.md
│   ├── specpowers-plan/SKILL.md
│   ├── specpowers-build/SKILL.md
│   └── specpowers-archive/SKILL.md
├── references/                      # platform-agnostic portable core, shared by all skills
│   ├── stage-protocol.md            # 8 stages: input/output/gate/failure-handling master table
│   ├── openspec-artifact-format.md  # the adopted OpenSpec artifact format spec
│   ├── tiering-rules.md             # quick/standard/full selection rules
│   ├── independent-review.md        # subagent adversarial-review pattern (cross-platform)
│   ├── adversarial-spec-review.md   # ⭐ used by harden-spec
│   ├── plan-coverage-matrix.md      # ⭐ requirement→plan→test coverage table + pass/fail rules
│   ├── compliance-verification.md   # ⭐ implementation-vs-spec verification
│   └── archive-checklist.md         # ⭐ archive readiness checklist + required summary
├── examples/
│   └── generic-feature-flow.md      # one complete closed-loop walkthrough
├── README.md                        # what / when / how to install (Claude Code + Codex)
├── LICENSE
└── NOTICE                           # attribution + inspiration notes for Superpowers & OpenSpec
```

`references/` lives at repo top level (not nested in one skill) because multiple skills reference
the same templates. Codex form may add `agents/openai.yaml`; handled in the cross-platform section.

## 10. Skill design rules

`SKILL.md` files stay concise. The orchestrator `SKILL.md` contains only: frontmatter
(`name`/`description`), trigger conditions, the stage state machine, tier selection, mandatory
gates, when to read each reference file, resume rules, and failed-gate routing rules. Detailed
prompts and templates live in `references/`.

**Attribution & licensing.** All content is **rewritten** — no verbatim copying from Superpowers or
OpenSpec. `NOTICE` and `README` credit both projects as inspiration and note their respective
licenses, so the repo can be published cleanly under its own LICENSE.

## 11. Reference templates (MVP must include)

1. `stage-protocol.md` — every stage's input/output/gate/failure-handling.
2. `openspec-artifact-format.md` — the adopted artifact format (proposal/design/tasks/spec-delta + living specs + archive).
3. `tiering-rules.md` — how to pick quick/standard/full and what each runs.
4. `independent-review.md` — how to dispatch an adversarial subagent on each platform.
5. `adversarial-spec-review.md` — checklist: ambiguity, loopholes, missing failure paths, concurrency, lifecycle, rollback, data migration, unverifiable promises.
6. `plan-coverage-matrix.md` — `Requirement | Plan Step | Implementation Area | Test/Verification | Status` table + pass/fail rules.
7. `compliance-verification.md` — verify implementation against spec/tests/plan; catch literal-but-incomplete compliance, missing failure paths, missing tests, out-of-scope behavior.
8. `archive-checklist.md` — readiness checklist + required archive summary (change name, implementation summary, verification summary, archive path/result, residual risks).

## 12. Acceptance criteria

MVP is ready for GitHub release when:

1. Orchestrator + 5 phase skills exist and can guide the full workflow.
2. All 8 reference templates exist.
3. Tiering works: a small change can take the `quick` path; a large change takes `full`.
4. Adversarial gates (harden-spec, verify-compliance) dispatch independent subagents.
5. Stage is correctly inferred from on-disk artifacts (resume works from a cold start).
6. The skill explicitly blocks archive before validation, plan coverage, tests, and compliance pass.
7. Progressive enhancement: detects and uses real `openspec`/Superpowers when present, falls back otherwise.
8. README explains what/when/how-to-install for both Claude Code and Codex.
9. At least one complete example flow is included.
10. No verbatim content copied from the source projects; NOTICE present.

## 13. Success metric

A user starts from a feature idea and reliably reaches an archived OpenSpec change through
`brainstorm → generate-spec → harden-spec → plan-from-spec → check-coverage → execute-plan →
verify-compliance → archive` — right-sized to the change — without having to remember the workflow
informally. The next required stage, gate, and artifact are explicit at every step.

## 14. Future enhancements

CLI wrapper for stage detection; generated `change-state.yaml`; automated requirement-coverage
extraction; GitHub Action validating skill structure; platform-specific example integrations;
command aliases (`specpowers new/status/verify`).
