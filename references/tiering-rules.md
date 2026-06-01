# Tiering Rules

This reference defines how the orchestrator selects a workflow tier — `quick`, `standard`, or
`full` — for any change, the heuristic for default selection, the non-overridable escalation rules
for high-risk surfaces, and the behavioral-change delta rule that applies in every tier.

---

## 1. Tier Table

Each row is one of the eight pipeline stages. Cells describe what that stage does at each tier.

| Stage | quick (small / bugfix) | standard (most features) | full (high-risk / large) |
|---|---|---|---|
| brainstorm | Skip; inline one-liner captures the intent | Light discussion — problem, scope, success criteria | Full brainstorm — all six outputs (problem / scope / criteria / non-goals / risks / open questions) |
| generate-spec | `proposal.md` + `tasks.md`; spec delta **required for any behavioral change** (optional only for non-behavioral changes) | Full artifact set: `proposal.md`, `design.md`, `tasks.md`, plus spec deltas under `specs/` | Full artifact set with additional design depth; separate capability-level spec deltas |
| harden-spec | Self-check against the adversarial review checklist | One independent adversarial subagent instructed to refute the spec | Parallel adversarial subagents covering distinct lenses (correctness, security, lifecycle) |
| plan | Inline plan captured directly in `tasks.md` | Structured `tasks.md` plan with target files, test strategy, and rollback notes | Separate plan document plus a detailed `tasks.md`; explicit dependency ordering |
| check-coverage | Quick checklist: every requirement maps to at least one task | Full coverage matrix per `references/plan-coverage-matrix.md` | Coverage matrix plus a re-check pass after any plan revision |
| execute (TDD) | Test-first required; at least one real test per behavioral change; strict per-task RED→GREEN ordering may be relaxed | Test-first, strict per-task RED→GREEN; one fresh subagent per task with two-stage review | Test-first, strict per-task RED→GREEN; one fresh subagent per task; independent adversarial check on every code-changing task |
| verify-compliance | Light self-check against the spec delta and tests | One independent adversarial subagent verifying implementation against the hardened spec | Parallel adversarial subagents (correctness, security, business closure) |
| archive | All gates passed | All gates passed | All gates passed, plus explicit user confirmation before archiving |

---

## 2. Default Selection Heuristic

The orchestrator estimates change size and risk from three signals derived from the
brainstorm/proposal scope:

1. **Files touched** — how many source files, config files, or schema files are expected to
   change. A single localized fix (one or two files, no interface changes) points toward `quick`.
   A moderate feature touching several modules or an API boundary points toward `standard`. A
   large refactor, cross-cutting change, or anything touching more than one service or subsystem
   points toward `full`.

2. **Reversibility** — whether the change can be cleanly reverted in production. Pure additive
   logic that leaves existing behavior intact is reversible. A schema migration, a data
   transformation, or any write to persistent state that cannot be cleanly undone is not.
   Non-reversible changes raise the floor to `standard`.

3. **Blast radius** — how many callers, consumers, tenants, or users are affected if the change
   misbehaves. A change confined to an internal utility has a small blast radius. A change to a
   shared API, a platform-wide config, or any multi-tenant surface has a large blast radius and
   points toward `full`.

The orchestrator combines these signals into an initial estimate:

- All signals small and reversible → `quick` candidate (subject to escalation below).
- Any signal medium, or non-reversible → `standard`.
- Multiple medium signals, or any large signal → `full`.

The user may **override the orchestrator's estimate downward** (e.g. request `quick` when the
orchestrator estimated `standard`) within the limits of the non-overridable escalation rules below.
A user-requested tier that conflicts with those rules is silently upgraded to the required minimum;
the orchestrator records the upgrade and the reason.

---

## 3. Non-Overridable Escalation

Certain change surfaces carry an elevated inherent risk that no tier selection or user override
can reduce. When the brainstorm or proposal scope indicates that a change touches **any** of the
following high-risk surfaces, the change is **forced to `standard` or `full`** regardless of
estimated size:

- **Authentication / authorization / permissions** — any change that alters who can do what,
  how credentials are issued or validated, how roles or scopes are checked, or how access control
  decisions are made.
- **Data migration or schema change** — any modification to a persistent data schema, a
  migration script, or a data-transformation pipeline that changes the shape or semantics of
  stored records.
- **Destructive or irreversible state changes** — any operation that deletes, purges, or
  permanently transforms data or state in a way that cannot be rolled back.
- **Tenant or security boundaries** — any change that affects isolation between tenants, security
  domains, or trust boundaries within a multi-tenant or multi-principal system.
- **Money or billing** — any change to pricing logic, billing calculations, payment flows,
  subscription state, or financial ledger entries.

When escalation fires, three additional constraints apply unconditionally:

1. **Tier minimum** — the change runs at `standard` or `full`. The orchestrator selects the
   higher of the estimated tier and `standard`. The user cannot override this downward.
2. **Independent compliance review** — the `verify-compliance` stage must use at least one
   independent adversarial subagent (no self-check shortcut), regardless of the user's tier
   preference.
3. **Mandatory real spec delta** — a genuine spec delta (one or more `SHALL` statements with
   scenarios, marked `ADDED`/`MODIFIED`/`REMOVED`) must exist before coverage or compliance can
   pass. There is no "justification instead of a delta" escape for high-risk surfaces. Coverage
   and compliance gates have no living-spec contract to verify against without a real delta, so
   they must fail until one exists.

A recorded `no-spec-delta` exception is **not available** for high-risk surfaces. That exception
exists only for independently-reviewed, genuinely non-behavioral changes (pure documentation or
formatting), must be narrow in scope, and must be logged with a rationale. It cannot be used to
bypass the mandatory delta on any change that touches a high-risk surface, even if the author
characterizes the change as minor.

---

## 4. The Spine Rule

The `spec → coverage → compliance` spine is the backbone of the workflow's correctness guarantee:

- **`standard` and `full`** run the full spine without compression: a real spec delta is generated,
  the coverage matrix maps every requirement to a plan step and a verification path, and the
  compliance gate independently verifies the implementation against the spec before archive.
- **`quick`** compresses the spine but does not remove it: it uses a lighter spec artifact
  (proposal + tasks rather than the full set), a quick checklist instead of the full matrix, and a
  self-check compliance pass. The spine is still present; the gates still must pass.

`quick` is eligible **only** for changes that are simultaneously small in scope, reversible, and
not security-sensitive. If any of those conditions is not met — including when non-overridable
escalation fires — the change is upgraded to `standard` or `full`.

---

## 5. Behavioral-Change Delta Rule

This rule applies in **every tier**, including `quick`.

Any change that alters the observable behavior of the system — its outputs, its state transitions,
its error conditions, its API contracts, or any user-visible result — **requires a real spec
delta** before coverage or compliance can pass. Without a delta, the coverage and compliance gates
have no living-spec contract to verify against; they would be checking implementation against
nothing, making them self-referential and meaningless.

The `no-spec-delta` exception is available **only** for genuinely non-behavioral changes:
reformatting a document, fixing a typo, updating a comment, reorganizing a README section. These
changes produce no observable behavioral difference and have no spec requirement to record. When an
author claims a `no-spec-delta` exemption, the exemption must be:

- **Narrow** — scoped to the specific files changed, with no behavioral effect asserted.
- **Recorded** — logged in the gate evidence so reviewers can verify the claim.
- **Independently reviewed** — when running at `standard` or `full`, a reviewer must confirm the
  change is genuinely non-behavioral before the exemption is accepted.

The `quick` tier's "spec delta optional" language refers only to this non-behavioral case. It does
not mean behavioral changes may skip the delta in `quick`; it means that a `quick`-tier change that
is genuinely non-behavioral may use the exemption instead of producing an artifact the system has
no use for.

**Coverage and compliance gates must fail** for any behavioral change that lacks a real spec delta,
regardless of tier. The orchestrator must not advance past these gates on the basis of a
`no-spec-delta` exception when the change is behavioral.
