# Test-Driven Development — RED→GREEN Discipline and Test-First Sub-Gate

This reference defines the test-first discipline used inside every `execute-plan` task. It is shared
by all skills and applies in every tier unless an explicit exemption is recorded.

---

## 1. The RED→GREEN→REFACTOR Loop

Each task follows a strict three-step loop before its work is considered complete:

1. **Write a failing test (RED).** Before touching any implementation, write a test that pins the
   task's requirement as derived from the hardened spec. Run it and confirm it fails — and that it
   fails *for the stated reason*, not because of an unrelated error. A test that cannot be run, or
   that fails for a different reason than the one the task addresses, is not a valid RED signal.

2. **Write the minimal implementation, then run green (GREEN).** Write only the code needed to make
   that test pass. Run the full test suite and confirm the new test is now green without breaking
   existing tests. Resist adding logic not demanded by the current failing test.

3. **Refactor, then commit.** With the suite green, clean up the implementation — no behavioural
   change, only clarity and structure. Commit once the suite is green and the code is clean.

**The rule is absolute: no implementation is written without a failing test first.** Writing code
and then adding a test to confirm it works is not TDD — it is post-hoc documentation dressed as
verification and provides none of the design or confidence benefits of genuine test-first work.

---

## 2. Test-First Sub-Gate of `execute-plan`

A task is not "done" for the purposes of the `execute-plan` gate unless the following is satisfied:

- The task **introduced or extended** a test that was **RED before its implementation code** and
  **GREEN after** it.
- The task subagent must provide **both the RED run and the GREEN run** as evidence (output log,
  exit code, or equivalent) when it returns its diff to the orchestrator.

The orchestrator's two-stage review (per `references/subagent-execution.md`) checks this evidence
as its first stage: if the RED run is missing, if the test never actually failed, or if the GREEN
run shows a broken suite, the task is sent back before the second (adversarial) review stage runs.
A task that ships code but shows no RED evidence fails this sub-gate unconditionally.

---

## 3. What Counts as a Proper Test

A test qualifies as proper when it meets all four of the following criteria:

- **Behaviour-focused:** it verifies a requirement or observable behaviour, not an internal
  implementation detail. Changing the internals without changing the behaviour should not break it.
- **Fails for the right reason:** on the RED run it fails specifically because the behaviour being
  added is absent — not because of a setup error, import problem, or unrelated regression.
- **Deterministic:** given the same inputs it produces the same pass/fail result every run; no
  reliance on timing, external network calls, or mutable shared state.
- **Mapped to a coverage row:** the test corresponds to at least one row in the
  `references/plan-coverage-matrix.md` coverage matrix, so every requirement has a traceable
  verification path.

**Anti-patterns that must be rejected:**

- *Post-hoc tests:* tests written after the implementation code is already complete, designed to
  pass the existing code rather than to define and fail against a missing behaviour. These can never
  provide a genuine RED run.
- *Tautological asserts:* assertions that cannot fail regardless of the implementation — for example,
  `assert True`, a trivial identity check, or a test that mocks the very function it is supposed to
  exercise so completely that nothing real is tested.
- *Tests that never failed:* any test for which no RED run exists or can be demonstrated. If a test
  was not observed failing, there is no evidence it is testing the right thing.

---

## 4. Non-Code Task Policy

Not every task ships executable code. Documentation updates, configuration files, schema migrations,
and reference files (such as those in this repository) are all valid task outputs that have no
runnable unit test. This policy extends the RED→GREEN discipline to those tasks without relaxing
the underlying principle.

**The "test" for a non-code task is a semantic or structural check** — a validator, linter, schema
checker, or any automated probe that:

- **Fails (RED) before the task is performed** because the file, section, or structure is absent
  or malformed.
- **Passes (GREEN) after the task is complete** because the file now exists and is well-formed.

A concrete illustration: the build plan for this plugin uses `scripts/validate-plugin.sh` in exactly
this role. Before a reference file is written, the script emits `PENDING: references/<file>.md`
(RED). Once the file is written and passes all structural checks the validator no longer emits that
PENDING line (GREEN). The task subagent must show the PENDING/FAIL output from the RED run and the
OK/no-PENDING output from the GREEN run as evidence — the same two-run evidence requirement as for
executable tests.

**Recorded-exemption escape.** When a task makes a genuinely non-behavioral change (for example,
fixing a typo, reformatting whitespace, or correcting a comment that does not affect any behavioral
contract) *and* there is no automated check that could meaningfully fail before the change and pass
after it, the task may record an exemption instead of providing RED→GREEN evidence. The exemption
must include:

- A precise description of the change and why it is non-behavioral.
- A statement that no automated check is applicable and why.
- A timestamp and the identifier of the task or subagent recording it.

Exemptions are logged alongside the task evidence in the `.specpowers/gates/execute-plan.yaml`
record for the change. They are reviewed at the verify-compliance stage; an exemption that a
reviewer finds to be covering a behavioral change is treated as a sub-gate failure and routes the
task back.

The test-first sub-gate verifies *this policy* — a RED-before/GREEN-after probe from either an
executable test or a structural check, or a recorded exemption — not a literal unit test. This
makes the discipline neither impossible for non-code tasks nor satisfiable by post-hoc validation
alone.

---

## 5. Tier Scaling

The discipline applies in every tier, but strictness scales with risk:

| Tier | Ordering requirement | Minimum test requirement |
|---|---|---|
| `quick` | Per-task RED→GREEN ordering may be relaxed; tests may be written in a small batch alongside the implementation for genuinely small, non-security-sensitive changes | At least one real test per behavioral change; post-hoc rubber-stamping is still rejected |
| `standard` | Strict per-task RED→GREEN ordering; the sub-gate is enforced before the orchestrator dispatches the next task | One test per task that covers the task's coverage-matrix row |
| `full` | Same as standard, plus the independent adversarial check on every code-changing task verifies the RED/GREEN evidence independently | Same as standard; adversarial reviewer may require additional test scenarios |

Quick-tier relaxation applies only to test ordering, not to the no-post-hoc principle. A behavioral
change at quick tier that has no test at all still fails the sub-gate.

---

## 6. Relationship to Other References

This discipline does not stand alone — it connects to three other references that form the
verification spine of the workflow:

- **`references/plan-coverage-matrix.md`:** the coverage matrix records, for every requirement, at
  least one verification path. Tests written under this discipline are the concrete form of those
  verification paths. A requirement with a coverage-matrix row but no test in the codebase is an
  open gap that compliance will surface.
- **`references/compliance-verification.md`:** compliance verification checks the final
  implementation against the hardened spec. Missing tests — requirements for which RED→GREEN
  evidence was never recorded — are a compliance failure. The sub-gate here and the compliance check
  are complementary: the sub-gate enforces the discipline task-by-task during execution; compliance
  verifies the net result before archive.
- **`references/subagent-execution.md`:** the per-task subagent execution protocol is the vehicle
  that carries RED/GREEN evidence back to the orchestrator. The two-stage review in that protocol
  treats sub-gate satisfaction as stage one of the review; RED/GREEN evidence feeds the
  `execute-plan` gate record and the implementation evidence set used by verify-compliance.

---

## 7. Progressive Enhancement

When real Superpowers is detected in the environment, hand off to its `test-driven-development`
skill rather than using this protocol. The Superpowers implementation provides the same RED→GREEN
discipline with any platform-specific integrations it supports.

When Superpowers is absent, this reference is the self-contained fallback. The sub-gate, evidence
requirements, non-code task policy, and tier scaling defined here are sufficient to drive the
`execute-plan` stage without any external dependency.
