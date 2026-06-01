# SpecPowers Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `specpowers-flow`, a self-contained, cross-platform skill **plugin** (orchestrator + 5 phase skills + 10 reference templates) that fuses Superpowers process discipline with OpenSpec's spec-driven artifact lifecycle, publishable to GitHub.

**Architecture:** A multi-skill plugin. One orchestrator skill (`specpowers-flow`) drives an 8-stage state machine, infers stage from on-disk OpenSpec artifacts, enforces gates, selects a tier (quick/standard/full), and routes failures. Five phase skills carry the per-stage logic. Ten platform-agnostic reference templates in `references/` hold the heavy protocols and are shared by all skills. The deliverable is pure markdown + a JSON manifest — no runtime code — verified by a structure-validation shell script that acts as the test harness.

**Tech Stack:** Markdown (SKILL.md + references), JSON (`plugin.json`), Bash + `jq` (validation script). Targets Claude Code plugin format and Codex skill format.

**Spec:** `docs/superpowers/specs/2026-06-01-specpowers-flow-design.md` (read it before starting).

**Branch:** Work continues on `design/specpowers-flow`.

---

## File Structure (decomposition lock-in)

| File | Responsibility |
|---|---|
| `scripts/validate-plugin.sh` | Test harness: validates manifest, skill frontmatter, cross-refs, placeholders |
| `.claude-plugin/plugin.json` | Claude Code plugin manifest (name, version, description) |
| `LICENSE` | MIT license for the repo |
| `NOTICE` | Attribution to Superpowers + OpenSpec (inspiration, their licenses) |
| `references/stage-protocol.md` | Master table: 8 stages × input/output/gate/next/failure |
| `references/openspec-artifact-format.md` | Adopted OpenSpec dir + file format |
| `references/tiering-rules.md` | quick/standard/full selection + non-overridable escalation |
| `references/independent-review.md` | Adversarial-subagent dispatch pattern (CC + Codex) |
| `references/subagent-execution.md` | Per-task subagent execution protocol (fresh subagent + two-stage review, tier-scaled) |
| `references/test-driven-development.md` | RED→GREEN→REFACTOR test-first discipline + per-task test-first sub-gate |
| `references/adversarial-spec-review.md` | Spec-review checklist (harden-spec) |
| `references/plan-coverage-matrix.md` | Requirement→plan→test coverage table + rules |
| `references/compliance-verification.md` | Implementation-vs-spec verification |
| `references/archive-checklist.md` | Archive readiness checklist + summary + conservative-fallback rules |
| `skills/specpowers-flow/SKILL.md` | Orchestrator: state machine, tiering, gates, routing, resume |
| `skills/specpowers-brainstorm/SKILL.md` | Stage 1: idea → proposal draft |
| `skills/specpowers-spec/SKILL.md` | Stage 2-3: generate artifacts + harden |
| `skills/specpowers-plan/SKILL.md` | Stage 4-5: plan into tasks.md + coverage gate |
| `skills/specpowers-build/SKILL.md` | Stage 6-7: subagent-driven TDD execution + compliance verify |
| `skills/specpowers-archive/SKILL.md` | Stage 8: archive gate + living-spec update |
| `examples/generic-feature-flow.md` | One full closed-loop walkthrough |
| `README.md` | What / when / install (Claude Code + Codex) |

**Build order rationale:** validator first (gives every later task a test), then repo shell, then references (the contract everything aligns to), then the orchestrator (binds the contract), then phase skills, then example + README (which exercise/describe the finished whole).

**Shared content conventions (apply to every SKILL.md):**
- Frontmatter is exactly two keys: `name` (must equal the parent directory name) and `description` (one line, includes trigger phrases).
- Body references templates by relative path `references/<file>.md` and says *when* to read each.
- No verbatim copying from Superpowers/OpenSpec; rewrite all content.
- No placeholder tokens (`TBD`, `TODO`, `FIXME`, `XXX`, `fill in`).

---

## Task 1: Validation harness + repo shell

**Files:**
- Create: `scripts/validate-plugin.sh`
- Create: `.claude-plugin/plugin.json`
- Create: `LICENSE`
- Create: `NOTICE`

- [ ] **Step 1: Write the validator (the failing test)**

Create `scripts/validate-plugin.sh`. It must exit non-zero on any failure and print one `OK:`/`FAIL:` line per check:

```bash
#!/usr/bin/env bash
# Structure validator for the specpowers-flow plugin. Acts as the test harness.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
fail=0
ok(){ echo "OK: $1"; }
bad(){ echo "FAIL: $1"; fail=1; }

# Mode: `--final` enforces the full required-file manifest (use in Tasks 17-18).
# Without it, missing-file manifest checks are warnings so earlier tasks can run incrementally.
FINAL=0; [ "${1:-}" = "--final" ] && FINAL=1

# 0. required-file manifest — a partial/empty repo must NOT report all-passed
REQUIRED=(
  .claude-plugin/plugin.json README.md LICENSE NOTICE examples/generic-feature-flow.md
  skills/specpowers-flow/SKILL.md skills/specpowers-brainstorm/SKILL.md
  skills/specpowers-spec/SKILL.md skills/specpowers-plan/SKILL.md
  skills/specpowers-build/SKILL.md skills/specpowers-archive/SKILL.md
  references/stage-protocol.md references/openspec-artifact-format.md
  references/tiering-rules.md references/independent-review.md
  references/subagent-execution.md references/test-driven-development.md
  references/adversarial-spec-review.md references/plan-coverage-matrix.md
  references/compliance-verification.md references/archive-checklist.md
)
missing=0
for p in "${REQUIRED[@]}"; do
  if [ -f "$p" ]; then :; else missing=$((missing+1)); [ "$FINAL" -eq 1 ] && bad "required file missing: $p" || echo "PENDING: $p"; fi
done
[ "$missing" -eq 0 ] && ok "all ${#REQUIRED[@]} required files present"
# fail on zero skills regardless of mode
skill_count=$(find skills -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
[ "${skill_count:-0}" -ge 1 ] && ok "skills present ($skill_count)" || bad "zero skills found"

# 1. plugin.json valid JSON with required keys
if [ -f .claude-plugin/plugin.json ]; then
  if jq -e '.name and .version and .description' .claude-plugin/plugin.json >/dev/null 2>&1; then
    ok "plugin.json valid (name/version/description present)"
  else bad "plugin.json missing name/version/description or invalid JSON"; fi
else bad "plugin.json missing"; fi

# 2. every skills/*/SKILL.md has frontmatter with name==dir and a description
for d in skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"; f="${d}SKILL.md"
  if [ ! -f "$f" ]; then bad "missing $f"; continue; fi
  fm="$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f{print}' "$f")"
  if echo "$fm" | grep -Eq "^name:[[:space:]]*${name}[[:space:]]*$"; then ok "skill $name: name matches dir";
  else bad "skill $name: frontmatter name missing or != dir"; fi
  if echo "$fm" | grep -Eq "^description:[[:space:]]*\S"; then ok "skill $name: has description";
  else bad "skill $name: missing description"; fi
done

# 3. cross-reference integrity: every references/<x>.md mentioned in a skill exists
for ref in $(grep -rhoE 'references/[a-z0-9-]+\.md' skills/ 2>/dev/null | sort -u); do
  if [ -f "$ref" ]; then ok "ref exists: $ref"; else bad "referenced file missing: $ref"; fi
done

# 4. no placeholder tokens in shipped files
if grep -rIlnE '\b(TBD|TODO|FIXME|XXX|fill in)\b' skills/ references/ examples/ README.md 2>/dev/null | grep -q .; then
  bad "placeholder tokens found in shipped files"; grep -rInE '\b(TBD|TODO|FIXME|XXX|fill in)\b' skills/ references/ examples/ README.md 2>/dev/null
else ok "no placeholder tokens"; fi

[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "VALIDATION FAILED"
exit "$fail"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `chmod +x scripts/validate-plugin.sh && bash scripts/validate-plugin.sh`
Expected: FAIL — `PENDING:` lines for each not-yet-created file, `FAIL: plugin.json missing`, `FAIL: zero skills found`, and `VALIDATION FAILED`, exit 1.

- [ ] **Step 3: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "specpowers-flow",
  "version": "0.1.0",
  "description": "End-to-end spec-driven change workflow: fuses Superpowers process discipline with OpenSpec's spec-driven artifact lifecycle, from idea to archived living spec.",
  "author": { "name": "suka" },
  "homepage": "https://github.com/suka/specpowers-flow",
  "license": "MIT"
}
```

- [ ] **Step 4: Create `LICENSE`**

Standard MIT license text, copyright `2026 suka`. (Use the canonical MIT template verbatim.)

- [ ] **Step 5: Create `NOTICE`**

```
specpowers-flow
Copyright 2026 suka — MIT License.

This project is an independent work, inspired by but not derived from:
  - Superpowers (process-discipline skills) — see its repository for its license.
  - OpenSpec (spec-driven artifact lifecycle) — see its repository for its license.

No source text was copied from either project; all content here is original.
The OpenSpec directory/file conventions (openspec/changes, openspec/specs,
archive/) are adopted as an interoperable format.
```

- [ ] **Step 6: Run validator — plugin.json check passes**

Run: `bash scripts/validate-plugin.sh`
Expected: `OK: plugin.json valid (name/version/description present)` present, plus `PENDING:` lines for skills/references/README/example not yet created. Still `VALIDATION FAILED` overall (zero skills) — that is expected this early; later tasks clear it.

- [ ] **Step 7: Commit**

```bash
git add scripts .claude-plugin LICENSE NOTICE
git commit -m "build(plugin): add validation harness, manifest, license, notice"
```

---

## Task 2: `references/stage-protocol.md` — the master contract

**Files:**
- Create: `references/stage-protocol.md`

This is the canonical definition every other file aligns to. Source of truth: spec §6 + §7.

- [ ] **Step 1: Write the file**

Required content (write as prose + tables, original wording):
1. Intro: this file defines the 8-stage machine; stage is **inferred from on-disk artifacts**, `.specpowers-state.yaml` is cache-only.
2. A table with one row per stage: `Stage | Input | Output artifact(s) | Completion gate | Next action | Failure handling`. The 8 stages and gates are exactly:
   - `brainstorm` — gate: direction approved & requirement specific enough → output `proposal.md` draft.
   - `generate-spec` — gate: change dir exists & required artifacts present → output `proposal.md`,`design.md`,`tasks.md`, spec deltas under `specs/`.
   - `harden-spec` — gate: validation passes & no unresolved blocker & findings synced back → output validated artifacts + recorded review.
   - `plan-from-spec` — gate: plan exists in `tasks.md` & explicitly based on hardened spec.
   - `check-coverage` — gate: every requirement ≥1 plan step & ≥1 verification path → output coverage matrix.
   - `execute-plan` — gate: implementation complete & tests run & evidence preserved.
   - `verify-compliance` — gate: compliance passes & tests pass & no unresolved blocker.
   - `archive` — gate: prior 7 gates passed (+ user confirm when required) → DONE.
3. **Gate-evidence binding** subsection (spec §6): each passed gate records the content digest + timestamp of every artifact it verified; on resume recompute digests; if a verified artifact changed, invalidate that gate AND all downstream gates and route back. A marker is honored only when recorded digests still match disk. Specify a concrete evidence record shape, e.g. a fenced block stored at `openspec/changes/<change>/.specpowers/gates/<stage>.yaml` with fields `stage`, `passed_at`, `artifacts: [{path, sha256}]`, `result`. **The `verify-compliance` record additionally carries an `implementation: {files: [{path, sha256}], git_tree: <hash>}` block** (coverage-matrix Implementation-Area files + the change's git diff/tree hash); archive recomputes this before passing so code edited after compliance invalidates the gate.
4. **Failure routing** subsection: map the 8 interrupted states (spec §6) to the stage each routes back to.

- [ ] **Step 2: Run validator**

Run: `bash scripts/validate-plugin.sh`
Expected: no new FAIL lines; placeholder check still `OK: no placeholder tokens`.

- [ ] **Step 3: Commit**

```bash
git add references/stage-protocol.md
git commit -m "docs(ref): add stage-protocol master contract"
```

---

## Task 3: `references/openspec-artifact-format.md`

**Files:**
- Create: `references/openspec-artifact-format.md`

Source of truth: spec §4 (adopt OpenSpec format) + the real OpenSpec project layout observed at `/Users/suka/Documents/web/mini-catering-demo-catering-default-jsps/openspec/`.

- [ ] **Step 1: Write the file**

Required content:
1. Directory convention: `openspec/changes/<change-name>/` (active) holding `proposal.md`, `design.md`, `tasks.md`, `specs/<capability>/` deltas, optional `reference/`, optional `review/`; `openspec/specs/<capability>/` (living specs); `openspec/changes/archive/<YYYY-MM-DD>-<change-name>/` (archived).
2. For each artifact, the required sections:
   - `proposal.md`: Why / What changes / Impact (and that brainstorm writes the draft here).
   - `design.md`: technical design, decisions, tradeoffs.
   - `tasks.md`: checkbox task list (this is where the plan lives — spec §8 de-duplication).
   - `specs/<capability>/spec.md` delta: requirement entries using `ADDED`/`MODIFIED`/`REMOVED` markers and testable `SHALL` statements with at least one scenario each.
3. State the `.specpowers/` sidecar dir (gate evidence from Task 2) lives inside the change dir and is not part of the OpenSpec spec content.
4. Note: when the real `openspec` CLI is present, prefer its `validate`/`archive`; format here is the fallback definition.

- [ ] **Step 2: Run validator** → Expected: no new FAIL lines.
- [ ] **Step 3: Commit**

```bash
git add references/openspec-artifact-format.md
git commit -m "docs(ref): add adopted openspec artifact format"
```

---

## Task 4: `references/tiering-rules.md`

**Files:**
- Create: `references/tiering-rules.md`

Source of truth: spec §7 (incl. non-overridable escalation).

- [ ] **Step 1: Write the file**

Required content:
1. The tier table (spec §7): rows = the 8 stages, columns = quick/standard/full, cells as in the spec.
2. Default selection heuristic: how the orchestrator estimates size (files touched, reversibility, blast radius) and picks a tier; user may override **downward only within limits below**.
3. **Non-overridable escalation** (spec §7): list the high-risk surfaces — authn/authz/permissions, data migration/schema change, destructive/irreversible state changes, tenant/security boundaries, money/billing. Any match forces `standard`/`full`, independent compliance review, and a **mandatory real spec delta** before archive. There is **no** "justification instead of a delta" escape for high-risk surfaces; a recorded `no-spec-delta` exception is allowed **only** for independently-reviewed, genuinely non-behavioral changes (pure docs/formatting) and must be narrow and logged. Tier choice and user override **cannot** bypass this.
4. State the spine `spec → coverage → compliance` is mandatory in standard/full and only compressed (never removed) in quick; quick is eligible only for small, reversible, non-security-sensitive changes.

- [ ] **Step 2: Run validator** → Expected: no new FAIL lines.
- [ ] **Step 3: Commit**

```bash
git add references/tiering-rules.md
git commit -m "docs(ref): add tiering rules and non-overridable escalation"
```

---

## Task 5: `references/independent-review.md`

**Files:**
- Create: `references/independent-review.md`

Source of truth: spec §8 (independent adversarial review).

- [ ] **Step 1: Write the file**

Required content:
1. Why: an agent reviewing its own artifact rubber-stamps it; adversarial gates must use a **separate** reviewer instructed to refute/find holes.
2. Dispatch pattern, cross-platform:
   - Claude Code: dispatch via the `Agent`/`Task` tool (general-purpose or Explore), prompt = "Your only job is to REFUTE this <spec|implementation>. Default to rejecting if uncertain. List concrete blockers with file:line."
   - Codex: dispatch a subagent / `codex challenge` equivalent with the same adversarial prompt.
   - No-subagent fallback: a structured self-review pass that still applies the checklist, clearly labeled as weaker (used only in quick tier).
3. Output contract the reviewer must return: verdict (`approve`/`needs-attention`), findings list with severity + location + recommendation. The calling skill syncs accepted findings back into the artifact and re-runs the gate.
4. `full` tier runs parallel reviewers (multiple lenses: correctness, security, lifecycle); `standard` runs one.

- [ ] **Step 2: Run validator** → Expected: no new FAIL lines.
- [ ] **Step 3: Commit**

```bash
git add references/independent-review.md
git commit -m "docs(ref): add cross-platform independent adversarial review pattern"
```

---

## Task 5b: `references/subagent-execution.md`

**Files:**
- Create: `references/subagent-execution.md`

Source of truth: spec §5 (build row), §8 (Subagent-driven execution), §11 item 5.

- [ ] **Step 1: Write the file**

Required content (the self-contained per-task subagent execution protocol used by `execute-plan`):
1. Why: each `tasks.md` task runs in a **fresh subagent** with only the context it needs (the task text, the relevant spec delta, its coverage-matrix row) so each implementation step stays in a clean, focused context and scope cannot silently drift across the whole change. This reimplements Superpowers' subagent-driven discipline self-contained.
2. Per-task loop: dispatch task subagent → it implements **test-first per `references/test-driven-development.md`** (RED failing test → minimal code → GREEN) → returns its diff + RED/GREEN test evidence → orchestrator runs a **two-stage review** (stage 1: does it satisfy the task + its coverage row, was the test RED-before/GREEN-after, do tests pass; stage 2: independent adversarial check via `references/independent-review.md` for risky tasks) → only then dispatch the next task.
3. Divergence rule: if a task needs to deviate from spec/plan, the subagent **stops** and the artifact (spec delta / `tasks.md`) is updated first (which invalidates downstream gates per `references/stage-protocol.md`), then work resumes.
4. Tier scaling: `quick` may execute inline in a single context (no per-task subagents); `standard`/`full` use one subagent per task; `full` adds the independent adversarial check on every code-changing task, `standard` on risky tasks only.
5. Progressive enhancement: when real Superpowers is detected, hand off to its `subagent-driven-development`/`executing-plans`; otherwise use this protocol.
6. Evidence: each task's returned diff + test output feeds the `execute-plan` gate (implementation complete & tests run & evidence preserved) and the implementation evidence set recorded by `verify-compliance`.

- [ ] **Step 2: Run validator** → Expected: no new FAIL lines.
- [ ] **Step 3: Commit**

```bash
git add references/subagent-execution.md
git commit -m "docs(ref): add per-task subagent execution protocol"
```

---

## Task 5c: `references/test-driven-development.md`

**Files:**
- Create: `references/test-driven-development.md`

Source of truth: spec §8 (Test-driven execution) + §11 item 10.

- [ ] **Step 1: Write the file**

Required content (the self-contained test-first discipline used inside each `execute-plan` task):
1. The loop: **write a failing test** that pins the task's spec requirement → **run it, confirm it fails for the right reason (RED)** → **write the minimal implementation** → **run it green (GREEN)** → **refactor** → **commit**. State plainly: **no implementation is written without a failing test first.**
2. **Test-first sub-gate of `execute-plan`:** a task is not "done" unless it introduced or extended a test that was RED before its code and GREEN after. The task subagent must show the RED run and the GREEN run as evidence.
3. What counts as a proper test: tests behavior/requirement (not implementation detail), fails for the stated reason, is deterministic, and maps to a coverage-matrix row. Anti-patterns to reject: tests written after the code to rubber-stamp it, tautological asserts, tests that never failed.
4. Tier scaling: `standard`/`full` enforce strict per-task RED→GREEN ordering; `quick` requires at least one real test per change but may relax strict per-task ordering.
5. Relationship to other refs: complements `references/plan-coverage-matrix.md` (every requirement has a verification path) and `references/compliance-verification.md` (catches missing tests); the RED/GREEN evidence feeds the `execute-plan` gate per `references/subagent-execution.md`.
6. Progressive enhancement: hand off to real Superpowers `test-driven-development` when present; otherwise use this protocol.

- [ ] **Step 2: Run validator** → Expected: no new FAIL lines.
- [ ] **Step 3: Commit**

```bash
git add references/test-driven-development.md
git commit -m "docs(ref): add test-first RED-GREEN discipline and test-first sub-gate"
```

---

## Task 6: `references/adversarial-spec-review.md`

**Files:**
- Create: `references/adversarial-spec-review.md`

Source of truth: spec §11 item 6.

- [ ] **Step 1: Write the file**

Required content: a review checklist the harden-spec reviewer applies, grouped and with concrete probing questions, covering: ambiguity, loopholes / literal-but-incomplete requirements, missing failure paths, concurrency / race conditions, lifecycle gaps (create/update/delete/expire), rollback & data migration, unverifiable promises, and security/permission surfaces. End with the pass rule: validation passes + no unresolved blocker + findings synced back into the spec artifacts.

- [ ] **Step 2: Run validator** → Expected: no new FAIL lines.
- [ ] **Step 3: Commit**

```bash
git add references/adversarial-spec-review.md
git commit -m "docs(ref): add adversarial spec-review checklist"
```

---

## Task 7: `references/plan-coverage-matrix.md`

**Files:**
- Create: `references/plan-coverage-matrix.md`

Source of truth: spec §11 item 7 + PRD FR-006.

- [ ] **Step 1: Write the file**

Required content:
1. The matrix format: `Requirement | Plan Step | Implementation Area | Test/Verification | Status` with a worked example (REQ-001 Covered, REQ-003 Blocked/Missing).
2. How to extract requirements from the spec deltas (each `SHALL` / scenario → one requirement row).
3. Pass/fail rule: every requirement covered by ≥1 plan step AND ≥1 verification path; any extra implementation scope must be justified or removed; any `Missing`/`Blocked` row blocks the gate and routes back to plan-from-spec.

- [ ] **Step 2: Run validator** → Expected: no new FAIL lines.
- [ ] **Step 3: Commit**

```bash
git add references/plan-coverage-matrix.md
git commit -m "docs(ref): add plan-coverage matrix format and rules"
```

---

## Task 8: `references/compliance-verification.md`

**Files:**
- Create: `references/compliance-verification.md`

Source of truth: spec §11 item 8 + PRD FR-008.

- [ ] **Step 1: Write the file**

Required content: how to verify the final implementation against the hardened spec before archive:
1. Inputs: hardened spec deltas, coverage matrix, test/verification evidence.
2. **Define the implementation evidence set explicitly:** the digests of every file named in the coverage matrix's Implementation Area, **plus the git diff/tree hash of the change**. This binds the compliance verdict to the actual code reviewed.
3. Checks: literal-but-incomplete compliance (business closure, not just wording), missing failure paths, missing tests, behavior outside approved spec.
4. Use the independent-review pattern (`references/independent-review.md`) for the adversarial implementation review.
5. Pass rule: compliance passes + tests pass + no unresolved blocker. Records the spec digests **and the implementation evidence set** per the gate-evidence binding in `references/stage-protocol.md`. If any implementation file or the git tree changes after this gate, the compliance gate is invalidated and must re-run.

- [ ] **Step 2: Run validator** → Expected: no new FAIL lines.
- [ ] **Step 3: Commit**

```bash
git add references/compliance-verification.md
git commit -m "docs(ref): add compliance-verification protocol"
```

---

## Task 9: `references/archive-checklist.md`

**Files:**
- Create: `references/archive-checklist.md`

Source of truth: spec §8 (conservative fallback archive) + §11 item 9 + PRD FR-009.

- [ ] **Step 1: Write the file**

Required content:
1. Archive prerequisites checklist (all 7 prior gates passed, with their evidence digests still matching disk; user confirmation when required by tier/escalation). **Before passing, recompute the compliance gate's implementation evidence set** (coverage-matrix files + git diff/tree hash) and block archive if any changed since verify-compliance ran — so code edited after compliance cannot be archived on stale evidence. For high-risk surfaces, also assert a real spec delta exists (no `no-spec-delta` escape).
2. **Conservative fallback archive** (spec §8): when real `openspec archive` is absent — produce a preflight diff of each spec delta vs the target living spec, write a timestamped backup of affected `openspec/specs/` files, surface conflicts, require explicit confirmation per merge; any auto-apply must use atomic write-and-rename + conflict detection + a retry-safe idempotency marker; never report "archived/complete" unless the merge succeeded and verified.
3. Required archive summary: change name, final implementation summary, verification summary, archive path/command result, residual risks.

- [ ] **Step 2: Run validator** → Expected: no new FAIL lines.
- [ ] **Step 3: Commit**

```bash
git add references/archive-checklist.md
git commit -m "docs(ref): add archive checklist with conservative fallback"
```

---

## Task 10: `skills/specpowers-flow/SKILL.md` — orchestrator

**Files:**
- Create: `skills/specpowers-flow/SKILL.md`

Source of truth: spec §5 (orchestrator row), §6, §7, §10.

- [ ] **Step 1: Write the file**

Frontmatter (exact):

```yaml
---
name: specpowers-flow
description: Use when running an end-to-end spec-driven change from idea to archive — orchestrates the full OpenSpec + Superpowers-style workflow with explicit stages and gates. Triggers - "run the full specpowers flow", "start a complete spec-driven change", "go from brainstorm to archive", "use specpowers for this feature".
---
```

Body must contain (concise; delegate detail to references):
1. Trigger conditions + how to tell new change vs resume.
2. **Resume / stage detection:** scan `openspec/changes/<change>/` and `.specpowers/gates/` to infer current stage; recompute gate-evidence digests and invalidate stale/downstream gates per `references/stage-protocol.md`. `.specpowers-state.yaml` is cache only.
3. **Tier selection:** apply `references/tiering-rules.md`, including non-overridable escalation.
4. The 8-stage state machine with the mandatory gate for each (point to `references/stage-protocol.md` for full detail), and which phase skill owns each stage: brainstorm→specpowers-brainstorm, generate+harden→specpowers-spec, plan+coverage→specpowers-plan, execute+verify→specpowers-build, archive→specpowers-archive.
5. **Gate enforcement:** never advance past a failed gate; route back per the failure-routing table.
6. When to read each reference file.
7. Progressive enhancement: probe for `openspec` CLI / Superpowers; use real tools if present else fallback (point to relevant references).

- [ ] **Step 2: Run validator — orchestrator skill must pass**

Run: `bash scripts/validate-plugin.sh`
Expected: `OK: skill specpowers-flow: name matches dir`, `OK: skill specpowers-flow: has description`, and `OK: ref exists: references/...` for each reference it mentions (all already created in Tasks 2-9).

- [ ] **Step 3: Commit**

```bash
git add skills/specpowers-flow/SKILL.md
git commit -m "feat(skill): add specpowers-flow orchestrator"
```

---

## Task 11: `skills/specpowers-brainstorm/SKILL.md`

**Files:**
- Create: `skills/specpowers-brainstorm/SKILL.md`

Source of truth: spec §5 (brainstorm row), PRD FR-002.

- [ ] **Step 1: Write the file**

Frontmatter:

```yaml
---
name: specpowers-brainstorm
description: Use as stage 1 of specpowers-flow — turn a raw idea into an approved direction and a proposal.md draft. Produces problem statement, scope boundary, success criteria, non-goals, risks, and open questions.
---
```

Body: the brainstorm discipline (one question at a time, explore approaches), required outputs (problem / scope / success criteria / non-goals / risks / open questions), and that it writes these **directly into `openspec/changes/<change>/proposal.md` draft** (spec §8 de-dup). Completion gate: direction approved & requirement specific enough to generate a change. Next: hand back to orchestrator → specpowers-spec. Point to `references/openspec-artifact-format.md` for the proposal shape.

- [ ] **Step 2: Run validator** → Expected: `OK: skill specpowers-brainstorm: ...` lines.
- [ ] **Step 3: Commit**

```bash
git add skills/specpowers-brainstorm/SKILL.md
git commit -m "feat(skill): add specpowers-brainstorm (stage 1)"
```

---

## Task 12: `skills/specpowers-spec/SKILL.md`

**Files:**
- Create: `skills/specpowers-spec/SKILL.md`

Source of truth: spec §5 (spec row), §6, PRD FR-003/FR-004.

- [ ] **Step 1: Write the file**

Frontmatter:

```yaml
---
name: specpowers-spec
description: Use as stages 2-3 of specpowers-flow — generate OpenSpec artifacts from the approved proposal, then harden them via validation and independent adversarial review.
---
```

Body:
1. Generate-spec: produce `proposal.md`, `design.md`, `tasks.md`, and spec deltas per `references/openspec-artifact-format.md`; gate = change dir + required artifacts present.
2. Harden-spec: run validation (real `openspec validate` if present, else format checks); run adversarial spec review via `references/independent-review.md` applying `references/adversarial-spec-review.md`; sync accepted findings back into artifacts; re-validate. Record gate evidence (digests) per `references/stage-protocol.md`.
3. Gate = validation passes & no unresolved blocker & findings synced. Next → specpowers-plan.

- [ ] **Step 2: Run validator** → Expected: `OK: skill specpowers-spec: ...` and refs resolve.
- [ ] **Step 3: Commit**

```bash
git add skills/specpowers-spec/SKILL.md
git commit -m "feat(skill): add specpowers-spec (stages 2-3)"
```

---

## Task 13: `skills/specpowers-plan/SKILL.md`

**Files:**
- Create: `skills/specpowers-plan/SKILL.md`

Source of truth: spec §5 (plan row), PRD FR-005/FR-006.

- [ ] **Step 1: Write the file**

Frontmatter:

```yaml
---
name: specpowers-plan
description: Use as stages 4-5 of specpowers-flow — write the implementation plan into tasks.md from the hardened spec, then build and check the requirement coverage matrix before any code is written.
---
```

Body:
1. Plan-from-spec: write the plan **into `tasks.md`** (spec §8 de-dup), explicitly based on the hardened spec; required contents: steps, target files/modules, test strategy, verification commands, rollback/failure handling, dependency assumptions. Gate = plan exists & based on hardened spec.
2. Check-coverage: build the matrix per `references/plan-coverage-matrix.md`; gate = every requirement ≥1 plan step & ≥1 verification path; any Missing/Blocked routes back to plan-from-spec. Next → specpowers-build.

- [ ] **Step 2: Run validator** → Expected: `OK: skill specpowers-plan: ...`.
- [ ] **Step 3: Commit**

```bash
git add skills/specpowers-plan/SKILL.md
git commit -m "feat(skill): add specpowers-plan (stages 4-5)"
```

---

## Task 14: `skills/specpowers-build/SKILL.md`

**Files:**
- Create: `skills/specpowers-build/SKILL.md`

Source of truth: spec §5 (build row), §8, PRD FR-007/FR-008.

- [ ] **Step 1: Write the file**

Frontmatter:

```yaml
---
name: specpowers-build
description: Use as stages 6-7 of specpowers-flow — execute the approved plan with subagent-driven TDD (fresh subagent per task) and no silent scope expansion, then verify the implementation complies with the hardened spec via independent adversarial review.
---
```

Body:
1. Execute-plan: run the **subagent-driven execution protocol** in `references/subagent-execution.md` — one fresh subagent per `tasks.md` task with a two-stage review between tasks, **test-first per `references/test-driven-development.md`** (RED→GREEN, no implementation without a failing test first), no silent scope expansion; if implementation must diverge from spec/plan, the task subagent stops and the artifact is updated first (invalidating downstream gates per `references/stage-protocol.md`); preserve each task's diff + RED/GREEN evidence. Tier-scaled (quick may run inline + ≥1 real test; standard/full use per-task subagents + strict per-task RED→GREEN). Gate = implementation complete & tests run (test-first sub-gate satisfied) & evidence preserved.
2. Verify-compliance: apply `references/compliance-verification.md` using the independent-review pattern (`references/independent-review.md`); check literal-but-incomplete compliance, missing failure paths/tests, out-of-scope behavior. Record gate evidence digests **including the implementation evidence set** (coverage-area file digests + git diff/tree hash). Gate = compliance passes & tests pass & no unresolved blocker. Next → specpowers-archive.

- [ ] **Step 2: Run validator** → Expected: `OK: skill specpowers-build: ...`.
- [ ] **Step 3: Commit**

```bash
git add skills/specpowers-build/SKILL.md
git commit -m "feat(skill): add specpowers-build (stages 6-7)"
```

---

## Task 15: `skills/specpowers-archive/SKILL.md`

**Files:**
- Create: `skills/specpowers-archive/SKILL.md`

Source of truth: spec §5 (archive row), §8, PRD FR-009.

- [ ] **Step 1: Write the file**

Frontmatter:

```yaml
---
name: specpowers-archive
description: Use as stage 8 of specpowers-flow — verify all prior gates passed, then archive the completed change into the living specs (real openspec archive if present, else conservative guided merge).
---
```

Body:
1. Enforce the archive prerequisites checklist from `references/archive-checklist.md`: all 7 prior gates passed with evidence digests still matching disk; user confirmation when tier/escalation requires it. Block archive otherwise (route back to the first failing gate).
2. Archive: real `openspec archive` if present; else the conservative fallback (preflight diff, backup, conflict detection, atomic+idempotent apply, never report complete unless merged & verified).
3. Emit the required archive summary.

- [ ] **Step 2: Run validator** → Expected: `OK: skill specpowers-archive: ...`.
- [ ] **Step 3: Commit**

```bash
git add skills/specpowers-archive/SKILL.md
git commit -m "feat(skill): add specpowers-archive (stage 8)"
```

---

## Task 16: `examples/generic-feature-flow.md`

**Files:**
- Create: `examples/generic-feature-flow.md`

Source of truth: spec §13 success metric.

- [ ] **Step 1: Write the file**

A complete narrated walkthrough of one small feature (e.g. "add a rate-limit to an API endpoint") going through all 8 stages at `standard` tier: show the proposal draft, the spec delta with a SHALL + scenario, the harden-spec adversarial finding and its fix, the tasks.md plan, the coverage matrix (all Covered), the TDD execution summary, the compliance verdict, and the archive summary with the living-spec update. Show the gate evidence concept once. Keep it realistic and concrete, not abstract.

- [ ] **Step 2: Run validator** → Expected: `OK: no placeholder tokens` still holds (no TBD/TODO in the example).
- [ ] **Step 3: Commit**

```bash
git add examples/generic-feature-flow.md
git commit -m "docs(example): add generic feature closed-loop walkthrough"
```

---

## Task 17: `README.md`

**Files:**
- Create: `README.md`

Source of truth: spec §12 acceptance criteria #11.

- [ ] **Step 1: Write the file**

Required sections:
1. What it is (one paragraph) + the 8-stage spine diagram.
2. Why (the manual-discipline problem it solves).
3. The 6 skills + 10 references, one line each.
4. Tiering (quick/standard/full) + the non-overridable escalation note.
5. Install — Claude Code (clone into the plugins dir / marketplace) and Codex (skills dir), with the exact paths.
6. Usage: the trigger phrases; new change vs resume.
7. Relationship to Superpowers & OpenSpec (inspired-by, not required; progressive enhancement) + link to NOTICE.

- [ ] **Step 2: Run full validator in final mode — everything passes**

Run: `bash scripts/validate-plugin.sh --final`
Expected: `OK: all 21 required files present`, ends with `ALL CHECKS PASSED`, exit 0. No FAIL/PENDING lines anywhere.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add README with install and usage for Claude Code + Codex"
```

---

## Task 18: Final integration check

**Files:** none created (verification + fixes only).

- [ ] **Step 1: Full structure validation (final mode)**

Run: `bash scripts/validate-plugin.sh --final`
Expected: `OK: all 21 required files present`, `ALL CHECKS PASSED`, exit 0. Any `FAIL:`/`PENDING:` line blocks completion.

- [ ] **Step 2: Cross-reference completeness — every reference is actually used**

Run: `for r in references/*.md; do b="references/$(basename "$r")"; grep -rqF "$b" skills/ || echo "UNUSED: $b"; done`
Expected: no `UNUSED:` lines. (If any reference is unused, either wire it into the owning skill or remove it.)

- [ ] **Step 3: Spec-coverage spot check**

Manually confirm each spec §12 acceptance criterion (1-13) maps to a created file/behavior. Fix gaps inline.

- [ ] **Step 4: Skill frontmatter sanity across platforms**

Run: `for f in skills/*/SKILL.md; do head -5 "$f"; echo "---"; done`
Expected: each shows a `name:`/`description:` frontmatter; descriptions contain trigger phrases.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "chore: final integration validation for specpowers-flow plugin" --allow-empty
```

---

## Self-Review notes (author)

- **Spec coverage:** Tasks map to spec §5 (skills: T10-15), §6 (stage-protocol + gate evidence: T2, T10), §7 (tiering + escalation: T4), §8 (independent review T5, subagent-driven execution T5b/T14, test-first TDD T5c/T14, fallback archive T9, progressive enhancement T10/T15, de-dup T11/T13), §9 (structure: all), §11 (10 references: T2-9b), §12 (acceptance: T18 step 3), §13 (example: T16). README → criterion 14 (T17). No spec section left without a task.
- **No placeholders:** validator Step 4 enforces this mechanically on every run.
- **Naming consistency:** skill dir names == frontmatter `name` (validator check 2); reference filenames match those used in skill bodies (validator check 3 + T18 step 2).
