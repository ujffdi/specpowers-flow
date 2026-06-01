# Adversarial Spec Review Checklist

This checklist drives the `harden-spec` stage review. The reviewer's job is to find holes in the spec
artifacts before any implementation begins — not to rubber-stamp them. Approach each section as an
adversary whose goal is to surface every ambiguity, gap, or unstated assumption that would let an
implementation satisfy the letter of the spec while silently failing the intent.

The checklist is applied by a separate, independent reviewer (see `references/independent-review.md`).
Any finding must be classified as a **blocker** (prevents gate passage), a **major** (must be resolved
before work reaches the affected stage), or a **minor** (should be resolved; may proceed with
documented rationale). All accepted findings must be synced back into the spec artifacts before the
gate can pass.

---

## 1. Ambiguity

Vague wording that two competent engineers would interpret differently is a blocker.

Probing questions:
- Does every `SHALL` statement have a single, unambiguous reading? If you can construct two different
  implementations that both satisfy the sentence, the sentence is ambiguous.
- Are all quantities qualified (e.g. "at most one", "within 5 seconds", "per request")? Bare
  comparatives like "low latency" or "fast enough" are not requirements.
- Do terms used across multiple sections mean the same thing in each? List domain-specific terms and
  check that each has exactly one definition, used consistently.
- Are optional behaviors distinguished from mandatory ones? Words like "should", "may", and "can"
  must not appear where "shall" is intended.
- Is every actor named? "The system" vs "the caller" vs "the background job" must be distinct
  whenever the behavior differs.

---

## 2. Loopholes and Literal-but-Incomplete Requirements

A requirement may be technically satisfiable by an implementation that fulfills no user value.

Probing questions:
- Can you write a minimal, obviously-wrong implementation that passes every stated requirement
  literally? If yes, the requirement is incomplete — what business closure is missing?
- Are success criteria defined in terms of observable outcomes, not internal mechanics? Requirements
  that describe what the code does internally rather than what users or callers observe are likely
  incomplete.
- Does the spec say what happens in the common case but leave the important boundary cases silent?
  Silence is not permission — state explicitly what is and is not permitted at each boundary.
- Are there any requirements that an implementation could satisfy by doing nothing (a no-op)? Those
  are always incomplete.
- Does each scenario exercise a distinct behavior? Scenarios that are paraphrases of one another add
  no coverage.

---

## 3. Missing Failure Paths

Every operation that can fail must specify what happens when it does.

Probing questions:
- For each operation in the spec, what are all the ways it can fail? List them. Does the spec
  address each one?
- What error is surfaced to the caller, and in what form? Is the error content specified, or just
  the fact that an error occurs?
- When a failure occurs mid-operation (e.g. after partial writes), what is the state of the system?
  Is partial state cleaned up, rolled back, or left intact? The spec must say.
- Are retry semantics defined? If a caller retries after a failure, will the operation be idempotent?
  What happens if it is not?
- Are timeout and deadline behaviors specified? What is visible to the caller when a timeout fires?
- Are cascading failures addressed? If component A fails, does the spec describe how component B
  should behave when it depends on A?

---

## 4. Concurrency and Race Conditions

Behavior under concurrent access is one of the most commonly omitted spec concerns.

Probing questions:
- If two actors execute the same operation simultaneously, which one wins? Is the winner
  deterministic? Does the spec describe the outcome for the loser?
- Are there any shared resources (queues, counters, files, records)? For each one, does the spec
  define the consistency guarantee: last-write-wins, first-write-wins, conflict error, merge, or
  something else?
- Are there any check-then-act sequences (read a value, then act on it) that could be invalidated
  between the check and the act? Does the spec acknowledge this window and define the expected
  behavior?
- If work is queued or batched, what happens when duplicate items arrive? Does the spec define
  deduplication or ordering semantics?
- Does the spec describe what happens when an operation is interrupted (process restart, network
  partition) while another concurrent operation is in flight?

---

## 5. Lifecycle Gaps (Create / Update / Delete / Expire)

Specs frequently describe the creation path in detail and leave update, delete, and expiry
underspecified.

Probing questions:
- Can every entity that can be created also be updated and deleted? If not, is the restriction
  explicit and justified?
- When an entity is updated, which fields are mutable? Does the spec list them, or does it leave
  mutability implicit?
- What triggers an entity's expiry or deactivation? Is the trigger time-based, event-based, or
  both? What is the exact behavior at the expiry boundary (inclusive vs. exclusive)?
- After deletion or expiry, what happens to references to the entity? Are they invalidated, left
  dangling, or redirected? Does the spec address stale references?
- Are there any entities that can exist in an intermediate state (e.g. "pending", "processing",
  "soft-deleted")? Does the spec define valid transitions between each state pair and what is
  observable in each state?
- Are there cascade effects? Deleting a parent entity: does the spec say whether children are
  deleted, orphaned, or blocked?

---

## 6. Rollback and Data Migration

Changes that touch persistent state carry rollback obligations that the spec must address.

Probing questions:
- If the feature is rolled back after deployment, what happens to data written in the new format?
  Is there a migration path back, or does rollback require a data transformation?
- If a schema change is involved, is the migration reversible? Does the spec describe the down
  migration, or only the up migration?
- During a migration, can old and new code versions operate on the same data simultaneously (e.g.
  during a rolling deploy)? If so, does the spec define the compatibility contract for the overlap
  window?
- Are there any data invariants that must hold before, during, and after the migration? Does the
  spec state how violations are detected and handled?
- Does the spec require a point-in-time backup or a dry-run validation step before the migration
  runs? If data corruption is possible, is there a recovery procedure?

---

## 7. Unverifiable Promises

Requirements that cannot be tested are not requirements — they are aspirations.

Probing questions:
- For each `SHALL` statement, write down the test you would run to verify it. If you cannot state
  a concrete, deterministic test, the requirement is not verifiable as written.
- Are non-functional requirements (performance, availability, throughput) given as concrete,
  measurable thresholds with defined measurement conditions? Statements like "shall be performant"
  or "shall be highly available" are not verifiable.
- Are behavioral guarantees tied to observable outputs, or only to internal implementation choices?
  If the only way to verify a requirement is to read the source code, it is not a behavioral
  requirement.
- Does each scenario have a clear, observable assertion — a specific output, state change, or error
  — that confirms the scenario passed or failed?
- Are there any guarantees that depend on third-party behavior the system cannot control (e.g.
  "the external service will respond in under 100 ms")? These must be rewritten as observable
  system behaviors (e.g. "if the external service does not respond within 100 ms, the system
  returns error X").

---

## 8. Security and Permission Surfaces

Authorization gaps discovered after implementation are expensive to fix.

Probing questions:
- For every operation in the spec, who is permitted to perform it? Is the authorization check
  stated explicitly, or is it assumed to be inherited from an unnamed outer boundary?
- Are there any operations that could be performed by an unauthenticated caller? If so, is the
  decision intentional and explicitly stated?
- Can one authenticated actor read or mutate data owned by a different actor? Does the spec
  define the isolation boundary and what constitutes a cross-tenant or cross-owner access?
- Are privilege levels distinguished? If different roles have different permissions, does the spec
  enumerate the permissions for each role rather than describing them relative to each other?
- Are there any indirect access paths — APIs, background jobs, event handlers, or internal RPC
  endpoints — that bypass the main authorization check? Does the spec require those paths to
  enforce the same policy?
- Does the spec address what is logged or audited for security-relevant operations? Is the audit
  trail tamper-evident?
- For any input accepted from external callers, does the spec define validation and rejection
  criteria? Absence of input validation requirements is a security gap.

---

## Pass Rule

The `harden-spec` gate passes when all three conditions hold simultaneously:

1. **Validation passes.** The spec artifacts pass formal validation (real `openspec validate` if
   present, otherwise format and structure checks). No required sections are missing; all `SHALL`
   statements have at least one scenario.

2. **No unresolved blocker.** Every finding classified as a blocker has been either resolved by
   updating the artifact or explicitly accepted with a documented rationale signed off by the
   change author. Major findings must be resolved or have a resolution plan before downstream
   stages may begin. Minor findings must be tracked.

3. **Findings synced back into the spec artifacts.** Every accepted finding that changes the
   meaning or content of a requirement has been incorporated into the relevant artifact
   (`proposal.md`, `design.md`, a spec delta, or `tasks.md` as appropriate) and the artifact
   re-validated. The review record (verdict, findings list, resolution notes) is stored in the
   change's sidecar directory so the gate-evidence digest can bind to it.

If any condition is not met, the gate fails and the artifacts route back for another revision
cycle. Partial passes are not permitted: all three conditions must hold at the same time.
