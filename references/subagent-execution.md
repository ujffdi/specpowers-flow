# Per-Task Subagent Execution Protocol

This reference defines the self-contained execution protocol used by `execute-plan` (stage 6).
It governs how the orchestrator dispatches, reviews, and sequences individual `tasks.md` tasks
during the build phase of any specpowers-flow change.

> The subagent-driven path described here is the **recommended default but is not forced**.
> `execute-plan` may also run inline in a single context in any tier — see section 4. Test-first
> and every gate apply identically regardless of which mode is used.

---

## 1. Why a fresh subagent per task

When a single large context implements every task in sequence, two problems compound quietly:
scope creep and context pollution. Earlier decisions, tangential code, and accumulated assumptions
bleed into later work; a task that should be narrow touches unintended files because the agent
"remembers" that a similar file was already edited. Gate evidence becomes unreliable because the
boundary between task N and task N+1 dissolves.

Running each `tasks.md` task in its own fresh subagent solves both problems. The subagent receives
exactly three inputs: the task description, the relevant spec delta for that task, and its row from
the coverage matrix. It has no knowledge of other tasks' implementations. Scope cannot drift
silently across the whole change because there is no shared working memory spanning tasks. This
reimplements Superpowers' subagent-driven discipline as a self-contained protocol — no Superpowers
installation required.

---

## 2. Per-task loop

For each unchecked task in `tasks.md`, the orchestrator runs the following sequence:

**Step 1 — Dispatch.** Launch a fresh subagent (Claude Code: `Agent`/`Task` tool; Codex: subagent
dispatch) with the three-piece context: task text, relevant spec delta, coverage-matrix row for
this task.

**Step 2 — Test-first implementation.** The subagent implements the task following the full
RED→GREEN→REFACTOR discipline in `references/test-driven-development.md`. It writes a failing test
that pins the spec requirement first, confirms it fails for the right reason (RED run), writes the
minimal code to make it pass, confirms it is green (GREEN run), refactors if needed, and commits.
The subagent returns its diff and the RED/GREEN test evidence as output.

**Step 3 — Two-stage review.** Before the next task starts, the orchestrator runs two review
passes on the returned output:

- *Stage 1 — Correctness check:* Did the implementation satisfy the task description? Does it
  address the coverage-matrix row it was assigned? Is there a RED run recorded before the code
  and a GREEN run recorded after? Do all tests pass? This review is done by the orchestrator
  itself, using the returned evidence.

- *Stage 2 — Adversarial check (risky tasks):* For tasks the orchestrator classifies as risky
  (touching auth/permissions, data mutation, security boundaries, external APIs, or any surface
  flagged by `references/tiering-rules.md` non-overridable escalation), dispatch an independent
  adversarial reviewer per `references/independent-review.md`. The adversarial reviewer receives
  the diff and task context and is instructed to find holes, not approve.

**Step 4 — Gate or block.** If both review stages pass, the task is marked complete, the diff and
evidence are appended to the execution evidence set, and the next task is dispatched. If either
review stage fails, the subagent is asked to resolve the finding before advancing.

---

## 3. Divergence rule

A task subagent sometimes discovers during implementation that the correct solution requires
something the spec or plan did not anticipate — a different function signature, an added data
field, a changed interaction boundary. When that happens:

The subagent **stops immediately** rather than implementing the deviation. It surfaces the
divergence to the orchestrator with a precise description: what the plan says, what the code
actually requires, and why they differ.

The orchestrator then updates the affected artifact — the spec delta in
`openspec/changes/<change>/specs/` or the plan in `tasks.md` — before resuming the task. Updating
any artifact that has already been verified by a gate invalidates that gate and all gates
downstream of it, per the digest-matching rules in `references/stage-protocol.md`. Work resumes
only after the artifact update is complete and any invalidated gates have been re-run.

This rule exists to prevent silent scope expansion: an undocumented deviation accepted quietly
during execution breaks the compliance gate's ability to verify what was actually agreed to.

---

## 4. Two execution modes: subagent-driven (recommended) or inline

This protocol describes the **subagent-driven** path, which is the recommended default because of
the isolation benefits in section 1. It is **not mandatory in any tier**. Mirroring Superpowers —
which lets you pick `subagent-driven-development` or inline `executing-plans` — `execute-plan` may
instead run **inline in a single agent context** whenever the implementer or user prefers it,
including in `standard` and `full`.

Whichever mode is chosen, the **gates do not change**: test-first (RED→GREEN) per
`references/test-driven-development.md`, the no-silent-scope-expansion rule, the divergence rule
(section 3), evidence capture (section 6), and downstream compliance verification all apply
identically. The only difference is whether each task runs in its own fresh subagent (isolated
context, parallel-safe, two-stage review between tasks) or sequentially in one context.

### Tier scaling (recommended rigor, not a mandate)

Tier sets the *recommended* level of rigor; it never forces the subagent path.

**quick** — Inline single-context execution is typical. Per-task subagents and the full two-stage
review are not expected. The quick tier still mandates at least one real test per behavioral change
and the RED-before/GREEN-after probe policy from `references/test-driven-development.md` for each
behavioral task. The divergence rule applies in every tier.

**standard** — Subagent-driven (one fresh subagent per task) is recommended, with stage 1
(correctness) review on every task and stage 2 (adversarial check via
`references/independent-review.md`) on risky tasks only. Inline execution is permitted; if chosen,
the implementer still satisfies strict per-task RED→GREEN ordering and runs the same two reviews
on the same tasks. Strict per-task RED→GREEN ordering is enforced either way.

**full** — Subagent-driven is strongly recommended, one fresh subagent per task, with both review
stages on every code-changing task and parallel adversarial reviewers in stage 2 (multiple lenses:
correctness, security, lifecycle) per `references/independent-review.md`. Inline execution is
permitted but must still meet every gate above. Strict per-task RED→GREEN ordering is enforced.

---

## 5. Progressive enhancement

When the orchestrator detects real Superpowers skills in the environment, it hands off the
`execute-plan` stage to Superpowers' `subagent-driven-development` or `executing-plans` skills
rather than running this protocol directly. Those skills provide a richer implementation and are
the preferred path when available.

Detection: probe for the `subagent-driven-development` and `executing-plans` skill names in the
active skill registry. If either is found, use it; otherwise execute this protocol as the
self-contained fallback.

The evidence requirements described in section 6 below apply regardless of which path is taken.
When handing off to Superpowers, the orchestrator is still responsible for collecting and
recording the per-task diff and test evidence before advancing past `execute-plan`.

---

## 6. Evidence and gate binding

Each completed task contributes two artifacts to the execution evidence set:

1. **Diff** — the complete set of file changes made by the task subagent (or by the inline
   execution for quick tier), sufficient to reconstruct exactly what was implemented.
2. **Test evidence** — the RED run output showing the failing test before implementation and the
   GREEN run output showing it passing after.

The orchestrator accumulates these across all tasks. The full execution evidence set feeds two
downstream gates:

- **`execute-plan` gate** (stage 6): implementation is considered complete and the gate passes
  only when every `tasks.md` task has a corresponding diff and RED/GREEN test evidence in the
  execution evidence set. Gaps in evidence — missing RED runs, missing GREEN runs, tasks with no
  recorded diff — block the gate and route back. The test-first sub-gate in
  `references/test-driven-development.md` defines the exact evidence a single task must provide.

- **`verify-compliance` gate** (stage 7): the compliance reviewer in
  `references/compliance-verification.md` incorporates the implementation evidence set —
  coverage-matrix file digests and the precisely-defined change-set hash — alongside the
  accumulated task diffs. This binds the compliance verdict to the code that was actually reviewed,
  and ensures that per-task commits made during the TDD loop are captured (a plain `git diff` after
  commits is empty; the change-set hash against the resolved base ref is the correct probe). If any
  implementation file changes after the compliance gate passes, the gate-evidence digest mismatch
  in `references/stage-protocol.md` invalidates it and forces a re-run.
