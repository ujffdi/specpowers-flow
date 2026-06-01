# Independent Adversarial Review

## Why a separate reviewer is required

When the same agent that produced an artifact is also the one asked to validate it, the review
tends to confirm the author's reasoning rather than challenge it. Blind spots are shared;
assumptions go unquestioned; a technically passing checklist run hides the gaps the author did not
think to probe. This is not a failure of effort — it is a structural property of self-review.

Adversarial gates in this workflow therefore require a **reviewer that is isolated from the author
context**. The reviewer is launched as a fresh, independent context with no exposure to the design
rationale that shaped the artifact under review. Its sole mandate is to find flaws. It defaults
toward rejection: if a claim is uncertain, it flags it as a blocker rather than giving benefit of
the doubt. The author agent never reviews its own output for the `harden-spec` or
`verify-compliance` gates.

---

## Cross-platform dispatch pattern

### Claude Code — `Agent` / `Task` tool

Use the built-in `Agent` tool (also surfaced as the `Task` tool in some interfaces) to launch a
general-purpose or Explore subagent in a fresh context.

**System framing for the reviewer:**

> Your only job is to REFUTE this \<spec|implementation\>. Default to rejecting if uncertain.
> List every concrete blocker with file:line (or section reference). Do not explain why it might
> be acceptable — only enumerate what is wrong or unverifiable.

Pass the reviewer the artifact text (or a path to it) and the relevant checklist
(`references/adversarial-spec-review.md` for spec review; `references/compliance-verification.md`
for implementation review). Do not pass design rationale or author commentary — the reviewer
must evaluate the artifact on its own terms.

### Codex — subagent dispatch

In Codex, launch a subagent task (via `codex challenge` or the equivalent subagent entrypoint)
with the same adversarial framing. The prompt structure is identical: frame the subagent's role as
a refuter, provide only the artifact and the checklist, withhold the author's reasoning.

If the Codex environment supports named roles or system prompts per task, set the role to
"adversarial reviewer" explicitly. The subagent should return a structured verdict; see the output
contract below.

### No-subagent fallback (quick tier only)

When a fresh independent context cannot be dispatched — for example, when operating in quick tier
where the entire change runs inline — the author agent performs a **structured self-review pass**
using the same checklist, but the result must be **explicitly labeled as a self-review, not an
independent review**. This pass still applies every checklist item and records its findings. It is
considered a weaker gate: any blocker still blocks the stage, but the absence of findings carries
less weight than it would from a genuinely independent reviewer. Standard and full tier must use
the actual dispatch patterns above; the fallback is not eligible for those tiers.

---

## Reviewer output contract

The reviewer must return a structured response with the following fields:

```
verdict: approve | needs-attention
findings:
  - severity: blocker | major | minor
    location: <file:line or section reference>
    description: <what is wrong or unverifiable>
    recommendation: <what change would resolve this>
```

**Verdict semantics:**

- `approve` — no blockers found; minor findings are advisory only.
- `needs-attention` — one or more blockers or majors are present; the gate cannot pass.

**What the calling skill does with the output:**

1. If `verdict: needs-attention`, the calling skill syncs accepted findings back into the artifact
   (updating the spec delta, design, or implementation file as appropriate).
2. After syncing, the stage re-runs its validation step and dispatches a new review pass against
   the updated artifact.
3. Only when the reviewer returns `verdict: approve` (or all remaining findings are `minor` and
   explicitly accepted by the author with a recorded rationale) does the gate pass.
4. The final verdict and the finding list are stored alongside the gate-evidence record
   (`.specpowers/gates/<stage>.yaml`) so the review outcome is traceable on resume.

---

## Tier scaling for parallel vs single reviewer

**Full tier — parallel reviewers.**
Dispatch multiple independent reviewers simultaneously, each assigned a different lens:

- Correctness reviewer: does the artifact satisfy every stated requirement?
- Security reviewer: are there authentication, authorization, permission, or data-integrity gaps?
- Lifecycle reviewer: are create/update/delete/expire paths complete; is rollback covered?

All three run concurrently. The gate does not pass until all three return `approve` (or all blockers
are resolved and re-reviewed). This catches classes of flaw that a single reviewer might not
prioritize.

**Standard tier — one reviewer.**
A single independent reviewer applies the full checklist. One pass, one verdict. The gate resolves
on that reviewer's output.

Quick tier uses the no-subagent fallback described above and does not dispatch an independent
reviewer.
