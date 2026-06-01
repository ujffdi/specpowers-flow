# Plan Coverage Matrix

The coverage matrix is the single artifact that proves every requirement extracted from the hardened spec is accounted for in the implementation plan and has a way to be verified. It is produced during the `check-coverage` stage and its contents feed the `verify-compliance` gate.

---

## Matrix Format

Each row represents exactly one requirement. The five columns are:

| Requirement | Plan Step | Implementation Area | Test/Verification | Status |
|---|---|---|---|---|

Column definitions:

- **Requirement** — a short identifier (e.g. `REQ-001`) plus a concise statement of what must be true. Each row comes from one `SHALL` statement or one scenario extracted from the spec deltas (see "Extracting Requirements" below).
- **Plan Step** — the checkbox task in `tasks.md` that implements this requirement. Reference by task number or heading. A requirement may reference more than one step if the work is split; list all that apply.
- **Implementation Area** — the file(s), module(s), or configuration section(s) that will contain the implementation. These paths feed the compliance implementation evidence set: `references/compliance-verification.md` digests every file listed here and records them in the gate evidence record so the compliance reviewer knows exactly what to inspect.
- **Test/Verification** — the specific test, assertion, or structural check that will confirm the requirement is satisfied. This must be something that was RED before implementation and GREEN after (per `references/test-driven-development.md`). For non-code requirements, a validator check or schema check qualifies.
- **Status** — one of `Covered`, `Missing`, or `Blocked`. `Covered` means a plan step and a verification path both exist. `Missing` means no plan step addresses the requirement yet. `Blocked` means a plan step exists but the verification path is absent, or an external dependency prevents verification.

### Worked Example

The following illustrates a complete coverage matrix for a small feature — "add a per-user rate limit to the `/search` API endpoint."

| Requirement | Plan Step | Implementation Area | Test/Verification | Status |
|---|---|---|---|---|
| REQ-001: The `/search` endpoint SHALL reject requests that exceed 60 calls per minute per authenticated user with HTTP 429. | Task 3: implement rate-limit middleware | `src/middleware/rate_limit.py`, `src/routes/search.py` | `tests/test_rate_limit.py::test_search_rejects_at_61_calls` — asserts HTTP 429 on the 61st call within a 60-second window; was RED before Task 3 and GREEN after | Covered |
| REQ-003: The rate-limit counter SHALL reset at the start of each 60-second window, not on a rolling basis. | (no task addresses window semantics) | — | — | Missing |

The `REQ-001` row is **Covered**: it names the plan task, identifies the files that will hold the implementation, and points to a deterministic test that fails before the code exists. The Implementation Area paths (`src/middleware/rate_limit.py`, `src/routes/search.py`) are the exact paths that `references/compliance-verification.md` will digest when recording the gate evidence.

The `REQ-003` row is **Missing**: the spec delta includes a scenario for fixed-window reset behavior but the current `tasks.md` has no task that implements it. This row blocks the `check-coverage` gate and routes the workflow back to `plan-from-spec` so the missing task can be added before any implementation begins.

---

## Extracting Requirements from Spec Deltas

Requirements are drawn from the spec deltas under `openspec/changes/<change>/specs/<capability>/spec.md`. The extraction rule is mechanical:

1. Every `SHALL` statement becomes one requirement row. Copy the `SHALL` statement verbatim as the row's description and assign a sequential `REQ-NNN` identifier.
2. Every named scenario attached to a `SHALL` statement also becomes its own requirement row if the scenario describes a distinct behavioral outcome that could be tested independently. The scenario's "given/when/then" or "if/then" logic becomes the description.
3. `ADDED`, `MODIFIED`, and `REMOVED` markers in the delta are all in scope. A `REMOVED` marker requires a row confirming the removed behavior is no longer reachable (negative test or structural assertion).
4. Ambiguous prose that does not contain `SHALL` and is not a named scenario is not extracted as a requirement row. Flag it during harden-spec (`references/adversarial-spec-review.md`) to be converted into a testable `SHALL` before plan-from-spec runs.

If the spec delta is empty or contains no `SHALL` statements and the change is behavioral, stop. A behavioral change without a spec delta cannot produce a coverage matrix; the `check-coverage` gate must fail and route back to `generate-spec` per `references/tiering-rules.md`.

---

## Pass/Fail Rule and Gate Behavior

The `check-coverage` gate passes only when all three conditions hold simultaneously:

**Condition 1 — Full plan coverage.** Every requirement row has Status `Covered`. That means each row names at least one plan step in `tasks.md` that directly addresses the requirement, and at least one verification path (test or structural check) that will confirm it.

**Condition 2 — No surplus scope without justification.** Every plan step in `tasks.md` maps to at least one requirement row. If a task implements something not represented in any requirement row, that task either needs a new row (meaning the spec delta is incomplete and must be updated first) or it must be removed from the plan. Silent scope expansion is not permitted.

**Condition 3 — No Missing or Blocked rows.** A single `Missing` row means a requirement exists in the spec but no plan task implements it. A single `Blocked` row means the implementation path exists but no verification path does. Either condition means implementation cannot start safely.

When any condition fails, the `check-coverage` gate fails and the orchestrator routes back to `plan-from-spec`. The practitioner updates `tasks.md` to add the missing tasks, resolves the blocked verifications, or removes unjustified scope, then reruns the gate. The gate does not partially pass.

Once all rows are `Covered` and all plan steps are accounted for, the gate records its evidence (spec delta digests, `tasks.md` digest, coverage matrix digest) per the gate-evidence binding in `references/stage-protocol.md`, and the workflow advances to `execute-plan`.

The Implementation Area column values from every `Covered` row are collected into the compliance evidence set. `references/compliance-verification.md` digests those files when recording the `verify-compliance` gate evidence, binding the compliance verdict to the exact implementation files the coverage matrix identified.
