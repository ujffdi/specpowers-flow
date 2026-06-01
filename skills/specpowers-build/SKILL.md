---
name: specpowers-build
description: Use as stages 6-7 of specpowers-flow — execute the approved plan test-first (subagent-driven per task recommended, inline single-context supported) with no silent scope expansion, then verify the implementation complies with the hardened spec via independent adversarial review.
---

## Execute-plan (stage 6)

Execute the plan following `references/subagent-execution.md`. Two execution modes are supported, and **subagent-driven is the recommended default but is not forced** (mirroring Superpowers' choice between `subagent-driven-development` and inline `executing-plans`):

- **Subagent-driven (recommended):** each task in `tasks.md` gets its own fresh subagent carrying only the task text, the relevant spec delta, and its coverage-matrix row — keeping context focused and preventing scope from silently drifting across the full change.
- **Inline:** run the tasks sequentially in a single context. Permitted in any tier, including `standard`/`full`, when the implementer or user prefers it.

The execution mode does not change the gates — test-first, no-silent-scope-expansion, divergence handling, evidence, and compliance all apply identically either way.

Apply the test-first discipline from `references/test-driven-development.md` to every task (in whichever mode): write a failing test that pins the spec requirement (RED), confirm it fails for the stated reason, then write the minimal implementation to make it pass (GREEN), then commit. No implementation is written before a failing test exists. Each task produces its diff plus the RED run and GREEN run as evidence.

Between tasks the orchestrator runs a two-stage review: first, a functional check (does the diff satisfy the task and its coverage-matrix row, was the test RED-before and GREEN-after, do all tests pass); second, an independent adversarial check via `references/independent-review.md` for any risky or code-changing task. These reviews are required in both modes.

If the implementation must deviate from the spec or plan, work stops immediately. The affected artifact (`tasks.md` or the spec delta) is updated first, which invalidates downstream gates per `references/stage-protocol.md`. Work resumes only after the artifact is reconciled.

Tier scaling (recommended rigor, never a mandate to use subagents): `quick` is typically inline, requiring at least one real test per behavioral change. `standard` and `full` recommend one dedicated subagent per task with strict per-task RED→GREEN ordering — `full` adds the independent adversarial check on every code-changing task, `standard` on risky tasks only — but inline execution is permitted in any tier provided it still meets every gate above.

Every task's diff and RED/GREEN test evidence is preserved as the implementation evidence set, feeding the next stage.

Gate = implementation complete & tests run with the test-first sub-gate satisfied (RED-before evidence + GREEN-after evidence present for each task) & evidence preserved.

## Verify-compliance (stage 7)

Apply `references/compliance-verification.md` to check whether the completed implementation actually satisfies the hardened spec. Use the independent-review pattern from `references/independent-review.md` — a separate reviewer instructed to refute, not confirm, with a default toward rejection when uncertain.

The reviewer checks for literal-but-incomplete compliance (wording matches but business closure is missing), missing failure paths, missing or post-hoc tests, and behavior that falls outside the approved spec scope. Any unresolved blocker prevents the gate from passing.

Record gate evidence digests per `references/stage-protocol.md`. The evidence record for this stage includes the implementation evidence set: the content digests of every file named in the coverage matrix's Implementation Area, plus the precisely-defined change set against the resolved base ref (coverage-area file digests and the change-set hash as specified in `references/compliance-verification.md`). If any implementation file or the git tree changes after this gate is recorded, the gate is invalidated and must re-run.

Gate = compliance passes & tests pass & no unresolved blocker. Next → specpowers-archive.
