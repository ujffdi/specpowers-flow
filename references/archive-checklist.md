# Archive Checklist

This reference defines the complete set of readiness conditions that must hold before a change can
be archived into the living specs, the conservative fallback procedure used when the real
`openspec archive` command is absent, and the required summary that every completed archive must
produce.

The `specpowers-archive` skill reads this file at the start of the archive stage and does not
advance past any gate listed here until it is explicitly satisfied.

---

## 1. Archive prerequisites checklist

All seven prior gates must have passed and their recorded evidence must still match the files on
disk at the moment archive is requested. Work through every item below in order. A single
unresolved item blocks archive — do not proceed, route back to the first failing gate.

### 1a. Gate-evidence freshness — all seven prior gates

For each of the seven stages that precede archive, locate the gate evidence record at
`openspec/changes/<change>/.specpowers/gates/<stage>.yaml`. For each record:

1. Confirm the record file exists and its `result` field is `passed`.
2. For every entry in the record's `artifacts` list, recompute `sha256sum <path>` and compare
   against the stored hex digest. If any digest differs, the gate is stale — invalidate it and
   all downstream gates, surface the changed path, and route back.

The seven stages are, in order:

- [ ] `brainstorm` — evidence record exists and all artifact digests still match.
- [ ] `generate-spec` — evidence record exists and all artifact digests still match.
- [ ] `harden-spec` — evidence record exists and all artifact digests still match.
- [ ] `plan-from-spec` — evidence record exists and all artifact digests still match.
- [ ] `check-coverage` — evidence record exists and all artifact digests still match.
- [ ] `execute-plan` — evidence record exists and all artifact digests still match.
- [ ] `verify-compliance` — evidence record exists, all artifact digests still match, and the
  implementation evidence set (§1b) is recomputed and validated before proceeding.

If any record is missing or stale: do not archive. Report exactly which gate failed and which file
changed, then stop.

### 1b. Compliance implementation evidence — recompute before passing

The `verify-compliance` gate binds its verdict to a precise snapshot of the implementation. Before
accepting that gate as valid for archive, recompute the entire implementation evidence set using
the **same `base_ref` that was recorded when compliance ran** — do not re-resolve the base ref,
and do not substitute a different one.

Recompute all of the following and compare each against the values stored in
`verify-compliance.yaml`:

**Coverage-area file digests.** For each path listed in `implementation.coverage_file_digests`,
run `sha256sum <path>`. If any digest differs from the stored value, the implementation changed
after compliance ran. Block archive and route back to `verify-compliance`.

**Commit range.** Using the stored `base_ref`, re-derive `merge_base_oid`:

```bash
merge_base_oid=$(git merge-base "$base_ref" HEAD)
head_sha=$(git rev-parse HEAD)
```

Compare `${merge_base_oid}..${head_sha}` against the stored `commit_range`. If the range differs,
commits have been added or HEAD has moved. Block archive and route back to `verify-compliance`.

**HEAD tree OID.**

```bash
head_tree=$(git rev-parse HEAD^{tree})
```

Compare against the stored `head_tree`. If different, the working tree changed. Block archive.

**Dirty-worktree diff hash.**

```bash
dirty_diff_sha256=$(git diff HEAD | sha256sum | awk '{print $1}')
```

If this hash is anything other than the stored value, uncommitted edits are present. Block archive
and ask the user to commit or discard the changes before proceeding.

**Untracked-relevant files.**

```bash
git ls-files --others --exclude-standard -- <each Implementation-Area path>
```

If any files are returned that were not in the stored `untracked_relevant` list (or if the list
was empty and now files appear), block archive. These files must be committed or explicitly ignored
before proceeding.

**Empty change-set block.** If the recomputed change set is empty — the commit range covers no
commits, the dirty-diff hash is the sha256 of empty output
(`e3b0c44298fc1c149afbf4c8996fb924`… compare to the well-known empty-string sha256), and
`untracked_relevant` is empty — while implementation tasks in `tasks.md` are marked complete,
block archive. An empty change set against a complete task list means the evidence was gathered
against the wrong base, or the implementation was never committed. Surface an explicit error and
require the user to diagnose before proceeding.

- [ ] Compliance implementation evidence recomputed and all values match stored record.
- [ ] Change set is non-empty (or a recorded exemption for genuinely non-behavioral-only changes
  has been verified — see §1c).
- [ ] No new relevant untracked files have appeared since compliance ran.

### 1c. Behavioral-change spec-delta assertion

For any change that alters observable behavior — including new features, modified business rules,
changed error handling, altered API contracts, or modified side effects — a real spec delta must
exist in the change's `openspec/changes/<change>/specs/` directory before archive can proceed.

There is no `no-spec-delta` escape for behavioral changes. The `no-spec-delta` exemption is
reserved strictly for independently-reviewed, genuinely non-behavioral changes (pure
documentation rewrites, comment edits, code formatting, or whitespace-only changes that carry
zero behavioral effect). An exemption taken for a behavioral change is a violation of this gate,
not a bypass of it.

Verify:

- [ ] If the change is behavioral: at least one spec delta file exists under
  `openspec/changes/<change>/specs/`, and `harden-spec` validated it (confirmed by gate evidence).
  If absent, block archive and route back to `generate-spec`.
- [ ] If a `no-spec-delta` exemption was recorded: confirm the change is genuinely non-behavioral
  by reviewing the commit range diff. If any behavioral change is present, revoke the exemption,
  block archive, and route back to `generate-spec` to produce the missing delta.

### 1d. User confirmation when required by tier or escalation

In some configurations, the archive gate requires explicit user confirmation before any files are
modified:

- **Full-tier changes:** the `full` tier always requires a user confirmation step at archive,
  even when all gates pass cleanly. Present the archive summary (§3) and wait for explicit
  approval.
- **Non-overridable escalation surfaces:** any change that touched authentication/authorization,
  data migration, schema changes, destructive or irreversible state transitions, tenant/security
  boundaries, or billing requires explicit user confirmation regardless of tier.
- **Any compliance finding that was resolved by accepted-`minor` rationale (not `approve`):**
  surface those findings alongside the summary and require the user to acknowledge them before
  archiving.

- [ ] If full tier or escalation surface: user confirmation received.
- [ ] If any `minor` findings were accepted: user has acknowledged them.

---

## 2. Conservative fallback archive

When the real `openspec archive` command is present in the environment, prefer it. Run it
according to the project's OpenSpec configuration and record the command's output in the archive
summary (§3). The remainder of this section applies only when `openspec archive` is not available.

### 2a. When to use the fallback

The fallback is active when `command -v openspec` (or equivalent) returns no result. Do not
simulate the real CLI by name or by partially replicating its behavior — use this defined fallback
procedure in full, or use the real CLI. There is no middle path.

### 2b. Preflight diff — inspect before touching

Before modifying any file in `openspec/specs/`, produce a full preflight diff for every spec delta
in `openspec/changes/<change>/specs/`. For each delta file at path
`openspec/changes/<change>/specs/<capability>/spec.md`:

1. Locate the corresponding living spec at `openspec/specs/<capability>/spec.md` (it may not exist
   yet if this is a new capability).
2. Run a unified diff: `diff -u openspec/specs/<capability>/spec.md
   openspec/changes/<change>/specs/<capability>/spec.md` (or `diff -u /dev/null <delta>` for new
   files).
3. Display the diff to the user with a clear header identifying the capability and the source paths.
4. Identify conflicts: lines present in the living spec that are not in the delta's context (meaning
   the living spec has diverged since the delta was written). Mark each conflict explicitly.
5. Do not proceed to any write step until all diffs have been displayed and conflicts surfaced.

- [ ] Preflight diffs produced and displayed for all affected capabilities.
- [ ] Conflicts (if any) identified and listed.

### 2c. Timestamped backup of affected living specs

Before writing any change to `openspec/specs/`, create a timestamped backup of every file that
will be modified. The backup path must encode the timestamp to the second so that multiple fallback
archive runs do not overwrite each other's backups:

```
openspec/specs/<capability>/.archive-backup/<YYYY-MM-DDTHH-MM-SS>-spec.md
```

Create the `.archive-backup/` subdirectory if it does not exist. Write the backup using an atomic
write-and-rename pattern (write to a `.tmp` file first, then rename) so that a crash during the
write leaves the backup directory in a consistent state.

If the backup write fails, do not proceed. Report the failure and stop.

- [ ] Timestamped backups written for all affected living-spec files.

### 2d. Explicit confirmation per merge

For each capability whose living spec will be modified, present the diff (from §2b) and require
the user to confirm that specific merge before applying it. Confirmation must be per-capability —
a single blanket "proceed" does not satisfy this requirement. The user must see and acknowledge
each individual diff.

If conflicts were identified in §2b, require the user to resolve each conflict in the delta file
before the merge is applied. Do not auto-resolve conflicts by preferring either side silently.

- [ ] Per-capability confirmation received for each merge.
- [ ] All conflicts resolved by the user before application.

### 2e. Atomic write-and-rename with conflict detection

Apply each confirmed merge using the following atomic procedure:

1. Write the merged content to a temporary file in the same directory:
   `openspec/specs/<capability>/spec.md.archive-tmp-<timestamp>`.
2. Verify the temp file was written completely (check file size against expected content length or
   re-read and compare).
3. Detect conflicts: before renaming, re-read the living spec and verify it still matches the
   backup taken in §2c. If it has changed between backup and rename (another write landed
   concurrently), abort this capability's merge, report the conflict, and return to §2d.
4. Rename the temp file to `spec.md` atomically: `mv spec.md.archive-tmp-<timestamp> spec.md`.
   On POSIX systems this rename is atomic within the same filesystem.
5. Immediately verify the written file by reading it back and comparing its sha256 against the
   sha256 of the expected merged content. If verification fails, restore from the backup (§2c),
   report the failure, and stop.

- [ ] Each living-spec file written atomically and verified.
- [ ] No merge was applied without a successful verification step.

### 2f. Retry-safe idempotency marker

To make a re-run safe — for example, if the process was interrupted partway through — write an
idempotency marker after each capability's merge succeeds:

```
openspec/changes/<change>/.specpowers/archive-applied/<capability>
```

Before applying any merge in a re-run, check whether this marker exists for the capability. If
it does, the merge for that capability was already applied successfully in a prior run. Skip it
and record it as already-complete in the summary. Do not re-apply a merge that was already
committed — doing so could introduce duplicate content.

The marker file should contain the sha256 of the merged content that was written, so a re-run can
also verify that the file on disk still matches the successfully-applied merge.

- [ ] Idempotency markers written after each successful capability merge.
- [ ] Any re-run checked existing markers before re-applying merges.

### 2g. Move the change directory to the archive location

After all living-spec merges are confirmed and verified, move the completed change:

```
openspec/changes/<change>/  →  openspec/changes/archive/<YYYY-MM-DD>-<change>/
```

This is also an atomic rename within the same filesystem. If the destination already exists (a
prior partial run), check the idempotency marker state — if all merges were already applied, the
rename may have been interrupted and can be retried. If the destination exists and some merges are
incomplete, report the inconsistency and require human resolution before proceeding.

- [ ] Change directory moved to archive path.

### 2h. Never report "archived/complete" prematurely

The fallback archive must not emit any success message, mark the workflow complete, or write a
final archive summary (§3) unless every one of the following is true:

1. All applicable diffs were generated and shown (§2b).
2. All backups were written and verified (§2c).
3. All per-capability confirmations were received (§2d).
4. Every merge was written atomically and verified by read-back comparison (§2e).
5. All idempotency markers are written (§2f).
6. The change directory was successfully moved to the archive path (§2g).

If any step failed or was skipped, emit a clear partial-failure report naming exactly which
capabilities succeeded and which did not, and leave the workflow in a diagnosable state that a
re-run can safely resume from.

---

## 3. Required archive summary

Every completed archive — whether via the real `openspec archive` CLI or the conservative fallback
— must produce a structured summary that is persisted alongside the archived change and presented
to the user. Write this summary to:

```
openspec/changes/archive/<YYYY-MM-DD>-<change>/archive-summary.md
```

The summary must include all five elements below. Do not omit any element, and do not substitute
"see the spec" or similar deferrals — the summary must be self-contained and stand alone.

### 3a. Change name and identifier

The canonical name of the change (the directory name used throughout the workflow), the date of
archive, and the commit range that constitutes the change's implementation
(`merge_base_oid..HEAD` as recorded in the compliance evidence).

Example:

```
Change: add-rate-limit-api-endpoint
Archived: 2026-06-01T14:32:00Z
Commit range: 3a7f91c..d84be02
```

### 3b. Final implementation summary

A concise description of what was built. Cover: which files were created or modified, what behavior
was introduced or changed, and which capabilities from the spec deltas are now reflected in the
living specs. This is not a commit log — it should read as a coherent summary of the delivered
work from the perspective of what the system can now do that it could not do before.

### 3c. Verification summary

A summary of how the implementation was verified, covering:

- The compliance gate result (passed, with adversarial reviewer verdict and tier).
- Which tests were run and their pass/fail counts.
- Any compliance findings that were resolved (with their severity and how they were addressed).
- Any `minor` findings accepted with rationale.

This section provides the evidentiary basis for the archive: someone reading the summary later
must be able to understand what was checked and why the implementation was considered complete.

### 3d. Archive path and command result

The final location of the archived change directory:

```
openspec/changes/archive/<YYYY-MM-DD>-<change>/
```

If the real `openspec archive` CLI was used: include the full command invoked and its exit code
and output (or a reference to a captured log file if the output is long).

If the conservative fallback was used: list each capability that was merged, the backup paths
written, and the result of the post-merge verification for each.

### 3e. Residual risks

An honest assessment of anything that remains uncertain or unresolved after archive. Examples of
what belongs here:

- Spec delta sections that were marked accepted with `minor` findings rather than a clean
  `approve` verdict.
- Any capability that required manual conflict resolution, noting what was resolved and how.
- Implementation-area files that are closely coupled to the changed behavior but fell outside the
  spec delta's scope (potential drift surfaces for future changes).
- Known test gaps: requirements that have only integration-level coverage and no unit-level
  coverage, or vice versa.
- Explicit TODOs in the committed code that represent deferred work (if any — ideally zero).

If there are no residual risks, state that explicitly: "No residual risks identified." Do not leave
this section blank or omit it — a blank residual-risks section is indistinguishable from a
section that was forgotten.
