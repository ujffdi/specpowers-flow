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
