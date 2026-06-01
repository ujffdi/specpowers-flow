---
name: specpowers-build
description: Use as stages 6-7 of specpowers-flow — execute the approved plan with subagent-driven TDD (fresh subagent per task) and no silent scope expansion, then verify the implementation complies with the hardened spec via independent adversarial review.
---

## Execute-plan (stage 6)

Run the subagent-driven execution protocol in `references/subagent-execution.md`. Each task in `tasks.md` gets its own fresh subagent carrying only the task text, the relevant spec delta, and its coverage-matrix row — keeping context focused and preventing scope from silently drifting across the full change.

Within each task subagent, apply the test-first discipline from `references/test-driven-development.md`: write a failing test that pins the spec requirement (RED), confirm it fails for the stated reason, then write the minimal implementation to make it pass (GREEN), then commit. No implementation is written before a failing test exists. The task subagent returns its diff plus the RED run and GREEN run as evidence.

Between tasks the orchestrator runs a two-stage review: first, a functional check (does the diff satisfy the task and its coverage-matrix row, was the test RED-before and GREEN-after, do all tests pass); second, an independent adversarial check via `references/independent-review.md` for any risky or code-changing task.

If the implementation must deviate from the spec or plan, the task subagent stops immediately. The affected artifact (`tasks.md` or the spec delta) is updated first, which invalidates downstream gates per `references/stage-protocol.md`. Work resumes only after the artifact is reconciled.

Tier scaling: `quick` may execute all tasks inline in a single context, requiring at least one real test per behavioral change. `standard` and `full` use one dedicated subagent per task with strict per-task RED→GREEN ordering; `full` adds the independent adversarial check on every code-changing task, `standard` on risky tasks only.

Every task's diff and RED/GREEN test evidence is preserved as the implementation evidence set, feeding the next stage.

Gate = implementation complete & tests run with the test-first sub-gate satisfied (RED-before evidence + GREEN-after evidence present for each task) & evidence preserved.

## Verify-compliance (stage 7)

Apply `references/compliance-verification.md` to check whether the completed implementation actually satisfies the hardened spec. Use the independent-review pattern from `references/independent-review.md` — a separate reviewer instructed to refute, not confirm, with a default toward rejection when uncertain.

The reviewer checks for literal-but-incomplete compliance (wording matches but business closure is missing), missing failure paths, missing or post-hoc tests, and behavior that falls outside the approved spec scope. Any unresolved blocker prevents the gate from passing.

Record gate evidence digests per `references/stage-protocol.md`. The evidence record for this stage includes the implementation evidence set: the content digests of every file named in the coverage matrix's Implementation Area, plus the precisely-defined change set against the resolved base ref (coverage-area file digests and the change-set hash as specified in `references/compliance-verification.md`). If any implementation file or the git tree changes after this gate is recorded, the gate is invalidated and must re-run.

Gate = compliance passes & tests pass & no unresolved blocker. Next → specpowers-archive.
