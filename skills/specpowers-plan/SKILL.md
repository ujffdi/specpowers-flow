---
name: specpowers-plan
description: Use as stages 4-5 of specpowers-flow — write the implementation plan into tasks.md from the hardened spec, then build and check the requirement coverage matrix before any code is written.
---

## Stage 4: Plan from Spec

With a hardened spec in place (stages 2-3 complete, gate evidence digests still matching disk), write the implementation plan directly into `openspec/changes/<change>/tasks.md`. This file already exists from stage 2 — add the plan by filling in or replacing the task list in place rather than creating a parallel document, so the change directory always has a single source of truth for tasks.

Each task entry must include:

- **Steps:** a concrete, ordered sequence of actions that fully implements the requirement it covers.
- **Target files/modules:** the specific files, directories, or modules the task will create or modify.
- **Test strategy:** what kind of test (unit, integration, contract, structural check) demonstrates the task is done and links to a requirement row.
- **Verification commands:** the exact commands to run to confirm the implementation is correct (build commands, test runners, validators, lint checks).
- **Rollback/failure handling:** how to undo this task's changes if it fails mid-execution, or how to detect a partial-apply so the next attempt is safe.
- **Dependency assumptions:** any other tasks, artifacts, or runtime conditions this task depends on, stated explicitly, so nothing is silently assumed.

Derive each task entry directly from the hardened spec deltas — every `SHALL` statement and every scenario in `openspec/changes/<change>/specs/<capability>/spec.md` must be traceable to at least one task. Do not add tasks for behavior not present in the hardened spec; if a needed step has no backing requirement, stop and update the spec first.

**Completion gate:** `tasks.md` contains a plan with at least one task per requirement in the hardened spec, every task entry carries the required fields listed above, and the plan is explicitly grounded in the hardened spec (not an independent scope expansion). Record a gate evidence file at `openspec/changes/<change>/.specpowers/gates/plan-from-spec.yaml` per `references/stage-protocol.md` with the stage name, timestamp, and `sha256` digest of `tasks.md` and each spec delta reviewed.

---

## Stage 5: Check Coverage

Build the requirement coverage matrix before any implementation begins. Follow the format and rules in `references/plan-coverage-matrix.md`.

Extract every requirement from the spec deltas: each `SHALL` statement and each scenario becomes one row in the matrix. For each row, record the plan step from `tasks.md` that addresses it, the target implementation area (file or module), and the verification command or test that will confirm it. Assign a status: `Covered` when both a plan step and a verification path are present, `Missing` when no plan step addresses the requirement, or `Blocked` when a plan step exists but no concrete verification path can be defined.

Once the initial matrix is assembled, apply the pass rule: every requirement row must have status `Covered`. Any row with status `Missing` or `Blocked` means the plan is incomplete — route back to stage 4 (plan-from-spec) to add or repair the relevant tasks before proceeding. Do not advance on a partial matrix.

When every row is `Covered`, record a gate evidence file at `openspec/changes/<change>/.specpowers/gates/check-coverage.yaml` per `references/stage-protocol.md` with the stage name, timestamp, and `sha256` digest of `tasks.md` and the coverage matrix artifact.

**Completion gate:** the coverage matrix is complete, every requirement has at least one plan step and at least one verification path, and no row is in `Missing` or `Blocked` status. Advance to specpowers-build.
