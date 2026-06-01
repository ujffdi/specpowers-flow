---
name: specpowers-flow
description: Use when running an end-to-end spec-driven change from idea to archive — orchestrates the full OpenSpec + Superpowers-style workflow with explicit stages and gates. Triggers - "run the full specpowers flow", "start a complete spec-driven change", "go from brainstorm to archive", "use specpowers for this feature".
---

## 1. Trigger conditions and new vs resume

Invoke this skill when the user wants to drive a change through the full 8-stage lifecycle. Determine whether this is a **new change** or a **resume**:

- **New:** no `openspec/changes/<change>/` directory exists yet, or the user explicitly requests a fresh start. Proceed from stage 1 (brainstorm).
- **Resume:** the change directory exists. Run stage detection (see §2) to identify the current stage and any invalidated gates, then continue from the earliest unresolved stage.

If the change name is ambiguous or multiple active changes exist, ask the user to confirm before proceeding.

## 2. Resume and stage detection

To determine current stage:

1. Scan `openspec/changes/<change>/` for artifacts: presence of `proposal.md`, `design.md`, `tasks.md`, `specs/`, and coverage/compliance markers.
2. Scan `.specpowers/gates/` inside the change directory for per-stage gate evidence files (see `references/stage-protocol.md` for the evidence record shape: `stage`, `passed_at`, `artifacts[{path, sha256}]`, `result`).
3. Recompute content digests for every artifact referenced in each gate evidence file. If a digest no longer matches disk, **invalidate that gate and all downstream gates** and route back to the earliest invalidated stage.
4. `.specpowers-state.yaml` is a hint cache only — never treat it as authoritative. Always derive stage from on-disk artifacts and gate evidence.

Full stage definitions, evidence record format, and invalidation rules are in `references/stage-protocol.md`. Read that file when resuming a change or debugging a stale gate.

## 3. Tier selection

Before advancing past brainstorm, select a tier — `quick`, `standard`, or `full` — using the rules in `references/tiering-rules.md`. The orchestrator estimates size (files likely touched, reversibility, blast radius) and suggests a default; the user may override **downward only within the limits defined there**.

**Non-overridable escalation:** any change touching authentication/authorization/permissions, data migration or schema changes, destructive or irreversible state, tenant/security boundaries, or money/billing is **forced to `standard` or `full`** regardless of size or user preference. This cannot be bypassed. Such changes also require a real spec delta before coverage/compliance can pass.

**Behavioral-change delta rule:** any change that alters system behavior requires a real spec delta in every tier, including `quick`. Without a delta the coverage and compliance gates have no contract to verify against. The `no-spec-delta` exception applies only to genuinely non-behavioral changes (docs/formatting/comments). Read `references/tiering-rules.md` at tier selection time and again when coverage or compliance gates are evaluated.

## 4. The 8-stage state machine

Each stage has a mandatory completion gate. **No stage may be marked complete until its gate passes.** The phase skill responsible for each stage is listed below; route to it and hand back control to the orchestrator when it completes or fails.

| Stage | Gate (summary) | Phase skill |
|---|---|---|
| 1. `brainstorm` | Direction approved; requirement specific enough to generate a change | `specpowers-brainstorm` |
| 2. `generate-spec` | Change dir exists; `proposal.md`, `design.md`, `tasks.md`, and spec deltas present | `specpowers-spec` |
| 3. `harden-spec` | Validation passes; no unresolved blocker; findings synced back into artifacts | `specpowers-spec` |
| 4. `plan-from-spec` | Plan exists in `tasks.md`; explicitly based on the hardened spec | `specpowers-plan` |
| 5. `check-coverage` | Every requirement has ≥1 plan step and ≥1 verification path; coverage matrix complete | `specpowers-plan` |
| 6. `execute-plan` | Implementation complete; tests run (test-first sub-gate satisfied); evidence preserved | `specpowers-build` |
| 7. `verify-compliance` | Compliance passes; tests pass; no unresolved blocker | `specpowers-build` |
| 8. `archive` | All 7 prior gates passed (evidence digests still match disk); user confirmation when required by tier | `specpowers-archive` |

Full input/output/failure-handling details for every stage are in `references/stage-protocol.md`.

## 5. Gate enforcement and failure routing

Never advance past a stage whose gate has not passed. When a gate fails, route back to the stage indicated by the failure-routing table in `references/stage-protocol.md`. Common cases:

- Validation or artifact check fails → route to `generate-spec`
- Adversarial spec review finds blockers → sync findings, re-run `harden-spec`
- Coverage gap → route to `plan-from-spec`
- Task implementation diverges from spec → update artifact first (which invalidates downstream gates), then resume from the updated stage
- Tests fail or compliance fails → route to `execute-plan` or `verify-compliance` as appropriate
- Archive requested before prior gates pass → block; route back to the first failing gate

Do not proceed to the next stage until the user has been informed of the failure and the affected stage is resolved.

## 6. When to read each reference file

| Reference | Read when |
|---|---|
| `references/stage-protocol.md` | On every invoke: stage detection, gate evaluation, failure routing, evidence record format |
| `references/tiering-rules.md` | At tier selection; again when evaluating coverage or compliance gates |
| `references/openspec-artifact-format.md` | When creating or validating the change directory and its artifacts |
| `references/adversarial-spec-review.md` | When running the `harden-spec` adversarial review |
| `references/independent-review.md` | When dispatching any adversarial subagent (harden-spec, verify-compliance) |
| `references/subagent-execution.md` | Before executing the plan in `execute-plan` |
| `references/test-driven-development.md` | Before each `execute-plan` task and when evaluating the test-first sub-gate |
| `references/plan-coverage-matrix.md` | At `check-coverage` and when verifying the compliance inputs |
| `references/compliance-verification.md` | At `verify-compliance` stage |
| `references/archive-checklist.md` | At `archive` stage; includes conservative fallback archive procedure |

## 7. Progressive enhancement

At startup, probe for the presence of real tools:

- **`openspec` CLI present** (`openspec --version` succeeds): use `openspec validate` for artifact validation and `openspec archive` for the archive merge. The format contract remains `references/openspec-artifact-format.md`.
- **Superpowers skills present**: when executing the plan, hand off to Superpowers `subagent-driven-development` or `executing-plans` rather than the self-contained protocol in `references/subagent-execution.md`. Similarly, hand off brainstorm to Superpowers `brainstorming` and test-first execution to Superpowers `test-driven-development` when present.
- **Neither present**: use the built-in markdown procedures defined in the reference files. This is the default fallback path and is fully functional.

The skill runs correctly in all three configurations. The self-contained fallback paths in `references/subagent-execution.md`, `references/test-driven-development.md`, and `references/archive-checklist.md` are authoritative when real tools are absent.
