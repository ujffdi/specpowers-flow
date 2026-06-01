# Compliance Verification

This reference defines the `verify-compliance` gate: how to confirm that the finished
implementation faithfully satisfies the hardened spec before the change can proceed to archive.
It is the last substantive check before living specs are updated, so it must bind the verdict
to the actual code that was built, not to a cached or approximate snapshot.

---

## 1. Inputs

Before the compliance gate can run, three input sets must be available and complete:

**Hardened spec deltas.** The `design.md` and each `openspec/specs/<capability>/spec.md` delta
that `harden-spec` validated and signed off. These define the behavioral contract the
implementation is measured against. If any of these files has changed since `harden-spec` passed,
that gate is invalidated and must re-run before compliance can proceed.

**Coverage matrix.** The requirement-coverage table produced by `check-coverage`, listing every
`SHALL`-level requirement alongside its plan step, Implementation Area (the specific source files
or modules where the behavior lives), and its verification path. This table drives both the
file-digest collection and the scope of the behavioral checks below.

**Test and verification evidence.** The per-task RED-before/GREEN-after probes collected during
`execute-plan`: the test output showing each task's failing run before implementation and its
passing run after. Any task that lacks this evidence is treated as incomplete regardless of whether
code is present.

If any of these three inputs is missing, the gate cannot run. Surface the gap explicitly and route
back to the appropriate prior stage.

---

## 2. Implementation evidence set

The compliance verdict must be tied to the exact state of the code that was reviewed. Because the
TDD loop commits after every task, a plain `git diff` is empty by the time compliance runs — it
reveals nothing about the work done. The implementation evidence set is designed to survive this.

### 2a. Coverage-area file digests

For every file path listed in the coverage matrix's Implementation Area column, record:

```
sha256sum <path>
```

Store each path and its hex digest. These digests capture the exact content of every file the
compliance verdict covers. If any of these files changes after the gate passes, the stale-evidence
guard in `references/stage-protocol.md` will invalidate this gate on the next resume.

### 2b. Change set against a resolved, recorded base ref

The change set answers: "What did this branch actually add to the codebase, relative to the trunk
it will eventually merge into?" It must be computed against a stable external reference — not
against the current branch itself.

#### Step 1: Resolve the base ref

Work through the following priority order and stop at the first step that yields a real, reachable
ref that is not the current branch or its own remote-tracking counterpart:

**Priority 1 — Configured review base.** Check the project's CLAUDE.md or a project-level config
file for an explicit `review_base` entry (e.g. `review_base: origin/release-3.x`). If present,
use it. This covers monorepos and projects that integrate to a non-default branch.

**Priority 2 — Well-known trunk refs.** Try each of the following in order; use the first one
that resolves:

```bash
git rev-parse --verify origin/main 2>/dev/null
git rev-parse --verify main        2>/dev/null
git rev-parse --verify origin/master 2>/dev/null
git rev-parse --verify master      2>/dev/null
git rev-parse --verify trunk       2>/dev/null
```

**Priority 3 — Upstream ref, with identity check.** Attempt `@{upstream}` only after confirming
it is not the current branch's own tracking ref:

```bash
# Determine the current branch
current=$(git symbolic-ref --short HEAD)

# Attempt to resolve the upstream
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || upstream=""

# Accept upstream only if it does not track this branch back to itself
if [ -n "$upstream" ] && ! echo "$upstream" | grep -qF "$current"; then
  base_ref="$upstream"
fi
```

A feature branch's upstream is typically its own remote-tracking ref (e.g.
`origin/my-feature-branch`). Using that as the base would produce an empty
`merge_base..HEAD` range after the branch is pushed, which is wrong. The identity check
prevents this silently bad case.

**If no step resolves:** Do not guess and do not hard-code `main`. Stop with an explicit setup
prompt:

```
COMPLIANCE BLOCKED — base ref could not be resolved.
No configured review_base was found in CLAUDE.md or project config.
No well-known trunk refs (origin/main, main, origin/master, master, trunk) exist in this repo.
No eligible @{upstream} was found (or it points back to the current branch).

Action required: add a review_base entry to this project's CLAUDE.md, e.g.:
  review_base: origin/main
Then re-run the compliance gate.
```

#### Step 2: Record the base identifiers

Once a base ref is resolved, capture its identity:

```bash
base_oid=$(git rev-parse "$base_ref")
merge_base_oid=$(git merge-base "$base_ref" HEAD)
```

`base_oid` is the full SHA of the tip of the base ref at resolution time.
`merge_base_oid` is the SHA of the common ancestor between the base and HEAD — this is the point
from which the current change diverged. Using `merge_base_oid` rather than `base_oid` directly
means the range is unaffected by new commits landing on the trunk after the branch was created.

#### Step 3: Record the commit range

```bash
head_sha=$(git rev-parse HEAD)
commit_range="${merge_base_oid}..${head_sha}"
```

This range names every commit that the current branch introduced relative to the trunk ancestor,
regardless of how many per-task TDD commits were made during `execute-plan`.

#### Step 4: Record the HEAD tree OID

```bash
head_tree=$(git rev-parse HEAD^{tree})
```

The tree OID is a content-stable fingerprint of the entire working tree at HEAD. It changes
whenever any tracked file changes, making it a reliable sentinel for the stale-evidence guard.

#### Step 5: Hash the dirty worktree diff

```bash
dirty_diff_sha256=$(git diff HEAD | sha256sum | awk '{print $1}')
```

This captures any staged or unstaged modifications that have not yet been committed. On a clean
tree, `git diff HEAD` produces no output, so the hash is the sha256 of the empty string
(`e3b0c44298fc1c149afbf4c8996fb92427ae41e4bcb879b18ce2cf7ab7d43c12` for sha256). A non-empty
hash here means the working tree diverges from HEAD — unresolved edits that are not captured by
the commit range.

#### Step 6: List relevant untracked files

```bash
git ls-files --others --exclude-standard -- <each Implementation-Area path from coverage matrix>
```

Run this once per Implementation-Area directory or file root. Collect every path returned into
`untracked_relevant`. Untracked files under an Implementation-Area path are not captured by
the commit range and may represent uncommitted work product.

**Blocking conditions.** Compliance is blocked (and must surface an explicit error) if either of
the following is true when implementation tasks are marked complete:

- The computed change set is empty: `commit_range` resolves to no commits (`git log` of the
  range is empty), `dirty_diff_sha256` is the empty-string hash, and `untracked_relevant` is
  empty. An empty change set while tasks are complete means the evidence was gathered against the
  wrong base, or work was never committed.
- `untracked_relevant` is non-empty. Files present but untracked under an Implementation-Area
  path must be committed or explicitly ignored before compliance can pass.

---

## 3. Compliance checks

The reviewer applies four categories of checks against the hardened spec and the collected evidence.
These are behavioral questions, not documentation reviews — the goal is to confirm that the system
does what the spec requires in every situation it describes, including the ones that go wrong.

**Literal-but-incomplete compliance.** The code may satisfy the exact wording of a requirement
without satisfying its intent. Check: does the implementation close the business case the
requirement was written to address, or does it exploit a gap in the phrasing? A requirement that
says "the system SHALL validate the input" is not satisfied by validation that always passes.
Probe the boundary between what the words say and what they mean.

**Missing failure paths.** Every `SHALL` requirement that involves a state transition, an external
call, a data write, or a condition check has at least one failure mode. Verify that each such
requirement has a corresponding test or observable behavior for the failure case — not just the
happy path. Check: what happens when the external call times out? When the data write conflicts?
When the condition is false? If the spec defined failure behavior and the implementation silently
swallows it or produces undefined behavior, that is a blocker.

**Missing tests.** Cross-check the coverage matrix's Test/Verification column against the actual
test files. Every requirement row must have at least one test that would fail if the requirement
were removed. A test that always passes regardless of the implementation does not satisfy this
check. Also verify that the RED-before/GREEN-after evidence is present and plausible for each
task: if a task has no RED run or the GREEN run preceded code changes, the evidence is suspect.

**Behavior outside the approved spec.** The implementation must not introduce observable behavior
that the hardened spec neither requires nor permits. Scan the committed diff (the `commit_range`)
for changes that add endpoints, side effects, data mutations, security-sensitive paths, or external
calls that are not described in the spec deltas or explicitly declared as scaffolding. Any such
addition is out-of-scope scope expansion and blocks compliance. The reviewer is not looking for
intent — undocumented behavior is a blocker regardless of whether it seems harmless.

---

## 4. Adversarial implementation review

Compliance uses the independent-review pattern defined in `references/independent-review.md`.

The author agent must not be the reviewer. Dispatch a fresh, independent reviewer and provide it
only the artifact (the committed diff and the implementation files) and this checklist. Do not pass
design rationale, task history, or the author's explanation of intent — the reviewer must evaluate
the code on its own terms against the spec.

The reviewer's system framing:

> Your only job is to REFUTE this implementation. Default to rejecting if uncertain.
> List every concrete blocker with file:line. Do not explain why the code might be acceptable —
> only enumerate what is wrong, missing, or unverifiable against the spec.

The reviewer returns a structured verdict per the output contract in
`references/independent-review.md`. If the verdict is `needs-attention`, the author syncs
accepted findings into the implementation, re-runs the affected tests, and dispatches a new review
pass against the updated code. The gate does not pass until the reviewer returns `approve` or all
remaining findings are `minor` with recorded acceptance rationale.

Tier scaling follows `references/independent-review.md`: full tier dispatches parallel reviewers
(correctness, security, lifecycle lenses running concurrently); standard tier uses one reviewer;
quick tier uses the structured self-review fallback, explicitly labeled as such.

---

## 5. Pass rule, recording, and invalidation

### Pass rule

The compliance gate passes when all three conditions hold simultaneously:

1. Every compliance check in §3 is satisfied — no unresolved blocker, no missing failure path,
   no missing test, no out-of-scope behavior.
2. All tests pass. The full test suite runs clean; no test is skipped without a recorded exemption.
3. The independent adversarial reviewer has returned `approve` (or all findings are `minor` with
   accepted rationale), and no finding is left unaddressed or silently dropped.

The change set must not be empty while implementation tasks are complete (§2b blocking condition).
Relevant untracked files must not be present (§2b blocking condition). Both are checked as part of
the pass evaluation, not as a separate preflight.

### Recording

When the gate passes, write the compliance evidence record at:

```
openspec/changes/<change>/.specpowers/gates/verify-compliance.yaml
```

The record follows the standard gate-evidence shape from `references/stage-protocol.md`, extended
with the `implementation` block:

```yaml
stage: verify-compliance
passed_at: <ISO-8601 timestamp>
artifacts:
  - path: openspec/changes/<change>/design.md
    sha256: <hex>
  - path: openspec/specs/<capability>/spec.md
    sha256: <hex>
  - ...
implementation:
  coverage_file_digests:
    - path: <Implementation-Area file>
      sha256: <hex>
    - ...
  base_ref: <resolved ref name>
  base_oid: <full SHA of resolved base ref tip>
  merge_base_oid: <full SHA of git merge-base result>
  commit_range: "<merge_base_oid>..<HEAD SHA>"
  head_tree: <HEAD tree OID>
  dirty_diff_sha256: <sha256 of git diff HEAD output>
  untracked_relevant: []
result: passed
```

The `artifacts` list records the spec files that the compliance reviewer read; the
`implementation.coverage_file_digests` list records the source files that the compliance verdict
covers. Both sets are independently checked by the stale-evidence guard on resume.

### Invalidation

If any implementation file in `coverage_file_digests` changes after this record is written, the
`verify-compliance` gate is invalidated on the next resume. The orchestrator detects this during
the stale-evidence check (recomputing each sha256 against disk) and routes the flow back to
`verify-compliance`. This holds even for single-line edits, formatting changes, or test-only
changes — any content change to a covered file requires the gate to re-run with fresh evidence.

Similarly, if the HEAD tree OID recorded in `head_tree` no longer matches `git rev-parse
HEAD^{tree}`, the gate is invalidated. This catches the case where new commits land on the branch
after compliance ran.

Archive recomputes `commit_range`, `head_tree`, `dirty_diff_sha256`, and `untracked_relevant`
against the same `base_ref` recorded here, and applies the same blocking conditions (§2b) before
allowing the archive gate to open.
