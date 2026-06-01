# Stage Protocol — Master Contract

This file defines the canonical 8-stage state machine that governs every change flowing through
`specpowers-flow`. All skills, orchestrator logic, and gate-evidence records align to this document.

## Stage inference

**Stage is inferred by scanning `openspec/changes/<change>/`** — specifically: which artifact files
are present, whether validation markers are recorded, and whether the coverage table exists and is
complete. The orchestrator reads the directory structure and artifact content on every resume; it
does not rely on a persisted stage variable.

A `.specpowers-state.yaml` file may be written alongside the change directory to cache hints
(current stage, last-run timestamp, tier selection). It is a performance hint only and is
**never authoritative**. If any artifact digest recorded in gate evidence no longer matches its
on-disk file, the cached stage is discarded and stage is re-derived from first principles. On-disk
artifacts are the single source of truth.

---

## Stage table

| Stage | Input | Output artifact(s) | Completion gate | Next action | Failure handling |
|---|---|---|---|---|---|
| `brainstorm` | Raw idea or feature request | `proposal.md` draft (problem, scope, success criteria, non-goals, risks, open questions) | Direction approved and requirement specific enough to drive spec generation | Proceed to `generate-spec` | Refine scope; re-run brainstorm until requirement is concrete and bounded |
| `generate-spec` | Approved `proposal.md` draft | `proposal.md` (final), `design.md`, `tasks.md`, spec deltas under `openspec/changes/<change>/specs/` | Change directory exists under `openspec/changes/<change>/`; all required artifacts are present and non-empty | Proceed to `harden-spec` | Identify which artifact is absent or malformed; regenerate; re-check gate |
| `harden-spec` | Artifacts from `generate-spec` | Validated artifacts with any findings recorded; independent adversarial review result committed alongside | Validation passes with no schema or structural errors; no unresolved blocker surfaced by adversarial review; all review findings synced back into the artifacts | Proceed to `plan-from-spec` | Route back to `harden-spec`: resolve each blocker, update artifacts, re-run validation and adversarial review |
| `plan-from-spec` | Hardened and validated spec artifacts | `tasks.md` updated with an explicit task plan that names the spec and design version it is based on | A plan exists in `tasks.md`; the plan is explicitly anchored to the hardened spec (references the validated design artifact) | Proceed to `check-coverage` | Revise `tasks.md` to add missing plan steps or explicit spec anchoring; re-check gate |
| `check-coverage` | `tasks.md` plan, `design.md`, spec deltas | Coverage matrix (requirement × plan step × verification path) | Every requirement in the spec has at least one plan step and at least one verification path (test or observable check) | Proceed to `execute-plan` | Extend `tasks.md` with steps or verification paths for uncovered requirements; rebuild and re-check matrix |
| `execute-plan` | `tasks.md` with coverage-checked plan, spec artifacts | Committed implementation code, passing tests, per-task test evidence (RED-before / GREEN-after probes) | Implementation is complete for all plan tasks; tests run and pass; test evidence is preserved and shows each task's RED→GREEN transition | Proceed to `verify-compliance` | Identify which task's tests are failing or missing evidence; fix implementation or restore missing test; re-run affected task |
| `verify-compliance` | Implemented code, spec artifacts, coverage matrix, test evidence | Compliance pass record including implementation evidence set | Compliance check passes (implementation matches spec); all tests pass; no unresolved blocker found by independent adversarial compliance review | Proceed to `archive` | Route to `execute-plan` if tests fail or implementation is incomplete; route to `harden-spec` then re-plan if implementation diverged from spec |
| `archive` | All prior gates passed; living specs under `openspec/specs/` | Updated living specs, archived change directory, final summary | All 7 prior gates passed; change set is non-empty relative to the recorded base ref; no relevant untracked files; user confirmation obtained when required (standard/full tier) | Workflow complete (DONE) | Route to the first failing gate; block if change set is empty while implementation tasks are complete; require untracked files to be committed or explicitly ignored |

---

## Gate-evidence binding

### Purpose

Each gate, when it passes, writes an evidence record. This record is **not** a trusted or
tamper-proof token — it is a cache that is always re-validated, never believed on its own. On any
subsequent resume the orchestrator recomputes artifact digests and compares them against the stored
record. If a verified artifact has changed, that gate and every downstream gate are invalidated and
the flow routes back to the appropriate stage. A pass marker is honored only when every recorded
digest still matches its corresponding on-disk file.

Because the record is plain editable YAML, it carries no authority by itself: a hand-edited or
forged `result: passed` cannot smuggle an unverified change through, because the digests it claims
must still match disk **and** the substantive checks a gate depends on (tests actually run,
adversarial review actually returned a verdict, user confirmation actually obtained) are re-derived
or re-run rather than inferred from the record. Treat the evidence record as a resume hint and an
audit breadcrumb, not as proof of work.

### Evidence record location and shape

Each gate writes one YAML evidence record at:

```
openspec/changes/<change>/.specpowers/gates/<stage>.yaml
```

The record has the following fields:

```yaml
stage: <stage-name>
passed_at: <ISO-8601 timestamp>
artifacts:
  - path: <repo-relative path>
    sha256: <hex digest>
  - path: ...
    sha256: ...
result: passed
```

`stage` is one of the eight stage names. `passed_at` is the wall-clock time the gate was marked
passed. `artifacts` lists every file the gate verified, with its sha256 content digest at the
moment of passing. `result` is always `passed` in a stored record (failed gates are not persisted).

### Stale-evidence guard

On resume, the orchestrator reads each gate record in order from `brainstorm` to the last stored
`passed` record. For each record it recomputes `sha256` for every path listed under `artifacts`.
If any digest diverges from the stored value, that gate is invalidated together with all gates that
follow it in the sequence. The orchestrator then resumes from the earliest invalidated stage,
surfacing which artifact changed and which gates were dropped. This ensures that editing `design.md`
after `harden-spec` passed, or editing implementation files after `verify-compliance` passed,
re-triggers the appropriate review rather than being silently carried through to archive.

### verify-compliance evidence extension

The `verify-compliance` gate record carries all standard fields plus an `implementation` block:

```yaml
stage: verify-compliance
passed_at: <ISO-8601 timestamp>
artifacts:
  - path: openspec/changes/<change>/design.md
    sha256: <hex>
  - path: openspec/changes/<change>/specs/<capability>/spec.md
    sha256: <hex>
  - ...
implementation:
  coverage_file_digests:
    - path: <Implementation-Area file from coverage matrix>
      sha256: <hex>
    - ...
  base_ref: <human-readable ref name used for base resolution>
  base_oid: <full SHA of the resolved base commit>
  merge_base_oid: <full SHA of git merge-base between base and HEAD>
  commit_range: "<merge_base_oid>..<HEAD SHA>"
  head_tree: <OID of HEAD's tree>
  dirty_diff_sha256: <sha256 of staged+unstaged diff at time of compliance run>
  untracked_relevant: []
result: passed
```

`coverage_file_digests` contains the sha256 of every source file named in the coverage matrix's
Implementation Area column, capturing the exact implementation state that compliance verified.

#### Base-ref resolution order

The `base_ref` / `base_oid` / `merge_base_oid` trio is resolved exactly once at `verify-compliance`
time and recorded. Archive recomputes the change-set fields against the same `base_ref`. Resolution
proceeds in this order and stops at the first successful result:

1. **Configured review base** — a base ref recorded in project config or the project's CLAUDE.md
   (e.g. `review_base: origin/release-2.x`).
2. **Well-known trunk refs** — the first of `origin/main`, `main`, `origin/master`, `master`,
   `trunk` that resolves to an existing ref in the repository.
3. **Upstream ref** — `@{upstream}` of the current branch, **only if** it is not the current
   branch's own remote-tracking ref. A feature branch's upstream is typically itself (its own
   tracking ref on the remote); using it as the base would produce an empty `merge_base..HEAD`
   range after the branch is pushed. The resolver checks whether `@{upstream}` names the same
   branch and skips it if so.

The resolver must never pick the current feature branch, or any ref that is the remote-tracking
counterpart of the current branch, as the base. If none of the three steps resolves to a real,
unambiguous merge target, the orchestrator stops with an explicit setup prompt asking the user to
configure a review base — it never falls back to a hard-coded guess.

#### Change-set fields

Against the resolved base, the `implementation` block records:

- `commit_range` — `merge_base_oid..HEAD` (captures all commits introduced by this change
  relative to the shared ancestor, regardless of whether the branch has been pushed).
- `head_tree` — the OID of HEAD's tree object (a content-stable identifier for the current
  working tree state at commit time).
- `dirty_diff_sha256` — sha256 of the combined staged-and-unstaged diff at the moment compliance
  ran. An empty diff (clean tree) produces the sha256 of the empty string.
- `untracked_relevant` — list of untracked file paths that fall under any Implementation-Area
  directory named in the coverage matrix.

#### Archive recomputation and blocking conditions

Archive recomputes `commit_range`, `head_tree`, `dirty_diff_sha256`, and `untracked_relevant`
using the same `base_ref` stored in the compliance record. Archive is blocked and surfaces an
explicit error in either of these conditions:

- The computed change set is empty (no commits in `merge_base_oid..HEAD`, empty dirty diff,
  empty untracked list) while at least one implementation task is marked complete. An empty
  change set against a complete plan indicates the compliance evidence was gathered against the
  wrong base or the work was never committed, and archiving would record no actual change.
- `untracked_relevant` is non-empty. Untracked files under an Implementation-Area path are not
  captured by the commit range and could represent uncommitted work product. They must be
  committed, explicitly ignored, or confirmed out-of-scope before archive proceeds.

---

## Failure routing

When a gate is not satisfied or a stage is interrupted, the orchestrator routes to the earliest
stage that can correct the problem. The eight interrupted states and their routing targets are:

| Condition | Routes back to |
|---|---|
| (a) No change directory exists under `openspec/changes/`; idea has not been captured yet | `brainstorm` (idea not yet developed) or `generate-spec` (if a proposal draft exists but no change dir was created) |
| (b) Artifacts exist in the change directory but structural validation fails | `harden-spec` — fix artifact structure or content, re-validate |
| (c) Adversarial review during `harden-spec` surfaces unresolved blockers | `harden-spec` — address each blocker, update artifacts, re-run adversarial review |
| (d) Plan in `tasks.md` does not cover all requirements (coverage matrix has gaps) | `plan-from-spec` — extend the plan to cover missing requirements or add missing verification paths |
| (e) Implementation diverges from the spec during `execute-plan` (code does something the spec does not permit, or omits something the spec requires) | `harden-spec` to update the spec to the intended behavior, then back through `plan-from-spec` and `check-coverage` before resuming execution |
| (f) Tests fail during or after `execute-plan` | `execute-plan` — fix the failing implementation; evidence must show a fresh RED→GREEN transition for affected tasks |
| (g) `verify-compliance` adversarial review finds the implementation non-compliant or finds unresolved blockers | `execute-plan` if the gap is in the implementation; `verify-compliance` re-run once fixed — if the gap requires a spec update, route to `harden-spec` first |
| (h) Archive is requested before all prior gates have passed | The first gate in the sequence that has not yet passed (or whose evidence has been invalidated) — the orchestrator names it explicitly rather than silently skipping to archive |
