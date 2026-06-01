---
name: specpowers-archive
description: Use as stage 8 of specpowers-flow — verify all prior gates passed, then archive the completed change into the living specs (real openspec archive if present, else conservative guided merge).
---

## When to invoke

Invoke `specpowers-archive` after `specpowers-build` reports that both `execute-plan` and
`verify-compliance` have passed. The orchestrator hands off here; do not invoke this skill
directly unless resuming a workflow that has already passed all seven prior gates.

---

## Step 1 — Enforce archive prerequisites

Read `references/archive-checklist.md` before doing anything else. Work through every item in
§1 of that file in order:

**Gate-evidence freshness (all seven prior stages).** For each stage from `brainstorm` through
`verify-compliance`, locate the evidence record at
`openspec/changes/<change>/.specpowers/gates/<stage>.yaml`. Confirm the record exists, its
`result` is `passed`, and every artifact digest stored in it still matches its file on disk
(recompute `sha256sum` for each path). If any record is absent, stale, or shows a changed
digest, that gate is invalidated — along with all gates that follow it. Stop, name the failing
gate and the changed file, and route back to that stage. Do not proceed to any later step.

**Compliance implementation evidence — recompute before accepting the gate.** Using the
`base_ref` recorded in `verify-compliance.yaml` (never re-resolve; use the stored value), derive
`merge_base_oid = git merge-base "$base_ref" HEAD` and recompute: every coverage-area file
digest, the commit range (`merge_base_oid..HEAD`), the HEAD tree OID
(`git rev-parse HEAD^{tree}`), the dirty-worktree diff hash
(`git diff HEAD | sha256sum | awk '{print $1}'`), and the untracked-relevant file list
(`git ls-files --others --exclude-standard` scoped to each Implementation-Area path). Compare
each computed value against the stored `implementation` block. Any divergence means the
implementation changed after compliance ran — block archive and route back to
`verify-compliance`. See `references/stage-protocol.md` §"Gate-evidence binding" for the
evidence record shape and the full base-ref resolution rules.

Block archive and surface an explicit error if either of these conditions holds:
- The computed change set is empty (no commits in the range, empty dirty diff, empty untracked
  list) while at least one implementation task in `tasks.md` is marked complete. An empty change
  set against a complete task list signals that compliance was gathered against the wrong base or
  the work was never committed.
- `untracked_relevant` lists any file not present in the stored record. Untracked files under an
  Implementation-Area path represent uncommitted work; require the user to commit or explicitly
  ignore them before proceeding.

**Behavioral-change spec-delta assertion.** For any change that alters observable behavior —
new features, changed business rules, modified error handling, altered API contracts, or modified
side effects — at least one spec delta file must exist under
`openspec/changes/<change>/specs/` and the `harden-spec` gate must have validated it. There is
no `no-spec-delta` escape for behavioral changes; that exemption is only valid for independently
reviewed, genuinely non-behavioral changes (documentation, comments, formatting, whitespace).
If the delta is missing for a behavioral change, block archive and route back to `generate-spec`.

**User confirmation when required.** Present the archive summary (Step 3 below) before
modifying any file when: the tier is `full`, the change touched any non-overridable escalation
surface (authentication/authorization, data migration, schema changes, destructive/irreversible
state transitions, tenant/security boundaries, billing), or any compliance finding was accepted
with a `minor` verdict rather than a clean `approve`. Wait for explicit approval before
continuing.

If any prerequisite is unmet, stop. Do not proceed to Step 2. Identify the first failing item
and route back.

---

## Step 2 — Archive

**Real `openspec archive` (preferred).** Check with `command -v openspec`. If present, run
`openspec archive` according to the project's configuration and capture the full output. Record
the command invoked, its exit code, and its output in the archive summary.

**Conservative fallback (when `openspec` is absent).** Apply the full fallback procedure
defined in §2 of `references/archive-checklist.md`. The steps in order:

1. *Preflight diff* — for every spec delta in `openspec/changes/<change>/specs/`, produce a
   unified diff against the corresponding living spec in `openspec/specs/`. Display each diff
   with a clear header showing the capability name and file paths. Identify and explicitly mark
   any conflict (a line in the living spec whose context diverged since the delta was written).
   Do not touch any file until all diffs are displayed.

2. *Timestamped backup* — before writing to any `openspec/specs/` file, write a backup to
   `openspec/specs/<capability>/.archive-backup/<YYYY-MM-DDTHH-MM-SS>-spec.md` using atomic
   write-and-rename (write to a `.tmp` file, then rename). Abort if the backup write fails.

3. *Per-capability confirmation* — for each capability whose living spec will change, show the
   diff and wait for explicit confirmation for that specific capability. A blanket "proceed" does
   not satisfy this requirement. Require the user to resolve any conflicts in the delta file
   before the merge is applied; do not auto-resolve.

4. *Atomic write with conflict detection* — write each confirmed merge to a temp file
   (`spec.md.archive-tmp-<timestamp>`), verify it was written completely, check that the living
   spec still matches the backup (abort if it changed concurrently), then rename atomically.
   Immediately verify by reading back and comparing the sha256 against the expected merged content.
   Restore from backup and stop on any verification failure.

5. *Idempotency marker* — after each successful capability merge, write a marker at
   `openspec/changes/<change>/.specpowers/archive-applied/<capability>` containing the sha256 of
   the merged content. On any re-run, check this marker first and skip already-applied merges.

6. *Move the change directory* — once all merges are confirmed and verified, move
   `openspec/changes/<change>/` to `openspec/changes/archive/<YYYY-MM-DD>-<change>/` atomically.
   If the destination already exists, check idempotency marker state before deciding whether to
   retry or report an inconsistency requiring human resolution.

Never emit any success message or mark the workflow complete unless every sub-step above
succeeded and was verified.

---

## Step 3 — Emit the archive summary

Write the summary to
`openspec/changes/archive/<YYYY-MM-DD>-<change>/archive-summary.md` and present it to the user.
The summary must contain all five elements below. No element may be omitted or deferred:

1. **Change name and identifier** — the canonical change directory name, the archive date, and
   the commit range (`merge_base_oid..HEAD`) from the compliance evidence record.

2. **Final implementation summary** — a coherent description of what was built: which files were
   created or modified, what behavior was introduced or changed, and which spec capabilities are
   now reflected in the living specs. Write this as a delivery summary, not a commit log.

3. **Verification summary** — how the implementation was verified: the compliance gate verdict
   (passed, adversarial reviewer verdict, tier), which tests ran and their pass/fail counts, any
   compliance findings and how they were resolved, and any `minor` findings accepted with
   rationale.

4. **Archive path and command result** — the final location of the archived change directory. If
   the real CLI was used, include the command invoked, its exit code, and its output. If the
   conservative fallback was used, list each capability merged, the backup path written, and the
   post-merge verification result for each.

5. **Residual risks** — an honest, specific assessment of anything unresolved after archive:
   `minor` findings accepted with rationale, capabilities that required manual conflict resolution,
   implementation files closely coupled to the changed behavior but outside the spec delta's scope,
   known test-coverage gaps, and any explicit TODOs in the committed code. If there are no
   residual risks, state "No residual risks identified." explicitly. Do not leave this field
   blank.
