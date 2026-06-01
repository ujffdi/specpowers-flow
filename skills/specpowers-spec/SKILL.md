---
name: specpowers-spec
description: Use as stages 2-3 of specpowers-flow — generate OpenSpec artifacts from the approved proposal, then harden them via validation and independent adversarial review.
---

## Stage 2: Generate Spec

Starting from the approved `proposal.md` in `openspec/changes/<change>/`, produce the full artifact set for the change:

- Fill in `proposal.md` with any sections left as stubs during brainstorm (Why, What Changes, Impact).
- Write `design.md` covering the technical approach, key decisions, and explicit tradeoffs.
- Write `tasks.md` as a checkbox task list that will drive planning and execution.
- For each capability being changed, add a spec delta under `specs/<capability>/spec.md` using `ADDED`/`MODIFIED`/`REMOVED` markers with testable `SHALL` statements and at least one concrete scenario per statement.

Consult `references/openspec-artifact-format.md` for the required directory layout and section contracts for each artifact type.

**Completion gate:** the change directory exists at `openspec/changes/<change>/` and all four artifact types — `proposal.md`, `design.md`, `tasks.md`, and at least one spec delta — are present and structurally complete (no missing required sections).

---

## Stage 3: Harden Spec

With the artifacts from stage 2 in place, run two hardening passes before any planning begins:

**Validation pass:** if the `openspec` CLI is available, run `openspec validate` on the change directory and resolve every reported issue. Without the CLI, apply the format checks defined in `references/openspec-artifact-format.md` — verify required sections exist, every `SHALL` statement has at least one scenario, and no `ADDED`/`MODIFIED`/`REMOVED` marker is missing its requirement body.

**Adversarial review pass:** dispatch an independent reviewer per `references/independent-review.md` with the instruction to refute the spec. The reviewer applies the full checklist in `references/adversarial-spec-review.md`, probing for ambiguity, missing failure paths, lifecycle gaps, rollback omissions, and security surfaces. Collect the returned findings (verdict, severity, location, recommendation). For each finding at blocker severity, update the relevant artifact to address it; for accepted non-blocker findings, incorporate them or record a reasoned disposition. Re-run the validation pass after syncing findings to confirm the updated artifacts are still structurally sound.

**Gate evidence:** once both passes succeed, record a gate evidence file at `openspec/changes/<change>/.specpowers/gates/harden-spec.yaml` per `references/stage-protocol.md`. The record must contain the stage name, timestamp, and a `sha256` digest for each artifact verified (`proposal.md`, `design.md`, `tasks.md`, every spec delta). On any future resume, the orchestrator recomputes these digests; if an artifact has changed, this gate is invalidated along with all downstream gates.

**Completion gate:** validation passes with no errors, no finding of blocker severity remains unresolved, and all accepted findings have been synced back into the spec artifacts. Advance to specpowers-plan.
