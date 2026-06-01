# Closed-Loop Walkthrough: Add a Rate Limit to an API Endpoint

This document walks through a complete `specpowers-flow` run at the `standard` tier. The feature is
small but realistic: rate-limit the `/search` API endpoint so that an authenticated user cannot
exceed 60 requests per minute. Every stage is shown with the actual artifact that was produced,
the gate that was checked, and the decision that followed.

---

## Scenario context

**Repository:** `api-service` (a Python/FastAPI application).
**Change name:** `add-rate-limit-api-endpoint`.
**Tier:** `standard` — the orchestrator selected it because the change touches an API surface,
introduces new error responses, and interacts with Redis (a shared resource). None of the
non-overridable escalation surfaces (authn/authz changes, data migration, billing) apply, so
`standard` is the ceiling.

---

## Stage 1 — `brainstorm`

The practitioner invokes `specpowers-flow` with the raw idea: "I want to stop users from hammering
the search endpoint." The orchestrator routes to `specpowers-brainstorm`, which asks one clarifying
question at a time rather than dumping a questionnaire.

**Outcome — `proposal.md` draft written to
`openspec/changes/add-rate-limit-api-endpoint/proposal.md`:**

```markdown
## Why

The `/search` endpoint has no call budget. A single authenticated user can issue thousands of
requests per minute during a retry storm, crowding out traffic from other users and pushing Redis
CPU to 100 %. Support has fielded three incidents in the past month that traced back to this
pattern.

## What changes

Add a per-user, per-minute request quota of 60 calls to the `/search` endpoint. Requests beyond
the quota receive HTTP 429 with a `Retry-After` header. The counter resets on a fixed 60-second
window boundary (not rolling). The feature is guarded behind the `RATE_LIMIT_ENABLED` environment
variable so it can be disabled without a code deploy if the Redis dependency is unhealthy.

## Impact

- Callers that exceed the quota receive a new 429 response they do not currently receive.
- No change to the response body or latency for callers within the quota.
- Introduces a Redis read/write on every `/search` call (existing Redis client reused).
- No persistent data model changes; the rate-limit counter is ephemeral and expires automatically.

## Non-goals

- Rate-limiting any endpoint other than `/search`.
- Per-IP or per-organization limits (only per-authenticated-user).
- A dashboard or admin override for the limit value.

## Risks

- Redis latency spike could add tail latency to `/search`.
- `RATE_LIMIT_ENABLED=false` disables the guard; operations must know to set this in runbooks.

## Open questions

- Should unauthenticated requests be limited separately or rejected outright? Decision: reject
  with 401 (existing behavior, no change required here).
```

**Gate check:** direction approved, requirement is specific enough (named endpoint, named quota
value, named error response). Gate passes. Proceed to `generate-spec`.

---

## Stage 2 — `generate-spec`

The orchestrator routes to `specpowers-spec`. It expands the proposal into the three required
artifacts and a spec delta.

**`design.md` (key excerpt):**

```markdown
## Technical approach

Rate-limit state is stored in Redis using an INCR + EXPIRE pattern on the key
`rate_limit:user:<user_id>:search`. On each request:

1. INCR the counter. If the result is 1, set EXPIRY to the next fixed-window boundary
   (ceiling of current epoch to 60-second grid).
2. If the counter exceeds 60, return 429 with `Retry-After: <seconds until next window>`.
3. Otherwise pass the request to the search handler.

The middleware is registered only for the `/search` route. The `RATE_LIMIT_ENABLED` flag is
checked at middleware registration time (startup), not per request.

## Files to modify

- `src/middleware/rate_limit.py` — new file, contains `RateLimitMiddleware` class.
- `src/routes/search.py` — register middleware on the search router.
- `src/config.py` — add `RATE_LIMIT_ENABLED` bool setting (default `True`).
- `tests/test_rate_limit.py` — new file, contains unit and integration tests.
```

**Spec delta — `openspec/changes/add-rate-limit-api-endpoint/specs/search-rate-limit/spec.md`:**

```markdown
## ADDED: Per-user rate limit on /search

### REQ-001
The `/search` endpoint SHALL reject any authenticated request from a user who has already issued
60 or more requests within the current 60-second fixed window, responding with HTTP 429 and a
`Retry-After` header whose value is the number of whole seconds remaining until the next window
boundary.

**Scenario A:** A user issues their 60th request in a window — it succeeds with HTTP 200.
**Scenario B:** The same user issues their 61st request in the same window — it receives HTTP 429
with `Retry-After` set to a positive integer.

### REQ-002
The rate-limit counter SHALL use fixed 60-second windows aligned to the Unix epoch (multiples of
60 seconds), not a rolling window from the time of the first request.

**Scenario C:** A user issues 60 requests starting at t=0 s into the window, then a 61st request
at t=1 s — it receives HTTP 429. The same user's 62nd request at t=61 s (one second into the next
window) receives HTTP 200, because the counter reset.

### REQ-003
When the `RATE_LIMIT_ENABLED` environment variable is set to `false` at application startup, the
rate-limit middleware SHALL be disabled and all requests to `/search` SHALL be processed without
quota enforcement.

**Scenario D:** With `RATE_LIMIT_ENABLED=false`, a user issues 200 requests in one minute — all
receive HTTP 200.
```

**Gate check:** change directory exists, all three required artifacts plus the spec delta are
present and non-empty. Gate passes. Proceed to `harden-spec`.

---

## Stage 3 — `harden-spec`

The orchestrator dispatches an independent adversarial reviewer (via
`references/independent-review.md`) with the instruction: "Your only job is to REFUTE this spec.
Default to rejecting if uncertain. List concrete blockers with file and section."

**Adversarial finding (blocker):**

> **Section REQ-001 — missing failure path for Redis unavailability.**
> REQ-001 specifies the quota enforcement path but says nothing about what happens when the Redis
> call fails. An implementation that raises an uncaught exception (or worse, silently passes all
> requests) when Redis is down satisfies the letter of REQ-001. The spec must state the expected
> behavior when the rate-limit backend is unreachable.
> Classification: **blocker** — a behavioral gap that an implementation could silently exploit.

The practitioner accepts the finding. The spec delta is updated:

```markdown
### REQ-004  (ADDED to address harden-spec finding)
When the Redis backend is unreachable at the time of a rate-limit check, the `/search` endpoint
SHALL respond with HTTP 503 and a `Retry-After: 5` header rather than processing the request
without quota enforcement or raising an unhandled exception.

**Scenario E:** Redis is unavailable; a user issues a request to `/search` — the response is
HTTP 503 with `Retry-After: 5`.
```

The reviewer re-runs validation. No further blockers. Finding is recorded in the sidecar review
record. All findings synced. Gate passes. Proceed to `plan-from-spec`.

---

## Stage 4 — `plan-from-spec`

The orchestrator routes to `specpowers-plan`. It writes the execution plan into
`openspec/changes/add-rate-limit-api-endpoint/tasks.md`:

```markdown
# Tasks — add-rate-limit-api-endpoint
Based on: hardened spec delta at openspec/changes/add-rate-limit-api-endpoint/specs/search-rate-limit/spec.md
(validated by harden-spec gate, 2026-06-01T09:14:00Z)

- [ ] Task 1: Add `RATE_LIMIT_ENABLED` config flag to `src/config.py` with a default of `True`.
  Target files: `src/config.py`
  Verification: `tests/test_config.py::test_rate_limit_enabled_default` — asserts default is True.
  Rollback: revert `src/config.py`.

- [ ] Task 2: Implement `RateLimitMiddleware` in `src/middleware/rate_limit.py` — Redis INCR +
  EXPIRE on fixed-window key, returns 429 with `Retry-After` when over quota, returns 503 with
  `Retry-After: 5` on Redis error.
  Target files: `src/middleware/rate_limit.py`
  Verification: `tests/test_rate_limit.py` unit tests (mocked Redis).

- [ ] Task 3: Register `RateLimitMiddleware` on the `/search` router in `src/routes/search.py`.
  Middleware is registered only when `RATE_LIMIT_ENABLED` is True at startup.
  Target files: `src/routes/search.py`
  Verification: `tests/test_rate_limit.py::test_middleware_not_registered_when_disabled`.

- [ ] Task 4: Write integration tests covering REQ-001 Scenarios A/B, REQ-002 Scenario C/D,
  REQ-003 Scenario D, and REQ-004 Scenario E using a real (test-mode) Redis.
  Target files: `tests/test_rate_limit.py`
  Verification: full integration suite passes; each scenario has a named test function.
```

**Gate check:** plan exists in `tasks.md`, each task names the hardened spec version it is based
on. Gate passes. Proceed to `check-coverage`.

---

## Stage 5 — `check-coverage`

The orchestrator builds the coverage matrix:

| Requirement | Plan Step | Implementation Area | Test/Verification | Status |
|---|---|---|---|---|
| REQ-001: `/search` SHALL reject the 61st request with HTTP 429 + `Retry-After`. | Task 2, Task 3 | `src/middleware/rate_limit.py`, `src/routes/search.py` | `tests/test_rate_limit.py::test_search_rejects_at_61_calls` — asserts HTTP 429 on the 61st call; RED before Task 2, GREEN after Task 3 | Covered |
| REQ-001 Scenario A: 60th request succeeds. | Task 2, Task 3 | `src/middleware/rate_limit.py`, `src/routes/search.py` | `tests/test_rate_limit.py::test_search_allows_60th_call` — asserts HTTP 200 on the 60th call | Covered |
| REQ-001 Scenario B: 61st request receives HTTP 429 with positive `Retry-After`. | Task 2, Task 3 | `src/middleware/rate_limit.py`, `src/routes/search.py` | `tests/test_rate_limit.py::test_retry_after_is_positive_integer` | Covered |
| REQ-002: Fixed-window reset (not rolling). | Task 2 | `src/middleware/rate_limit.py` | `tests/test_rate_limit.py::test_counter_resets_on_window_boundary` — mocks epoch to verify the counter key expiry aligns to grid | Covered |
| REQ-002 Scenario C: Request at t=1 s in window is rejected; at t=61 s passes. | Task 4 | `src/middleware/rate_limit.py`, `src/routes/search.py` | `tests/test_rate_limit.py::test_fixed_window_not_rolling` — integration test with time-controlled Redis | Covered |
| REQ-003: `RATE_LIMIT_ENABLED=false` disables middleware entirely. | Task 1, Task 3 | `src/config.py`, `src/routes/search.py` | `tests/test_rate_limit.py::test_middleware_not_registered_when_disabled` — asserts 200 on 200th request | Covered |
| REQ-004: Redis unavailable → HTTP 503 + `Retry-After: 5`. | Task 2 | `src/middleware/rate_limit.py` | `tests/test_rate_limit.py::test_redis_error_returns_503` — mocks Redis to raise `ConnectionError` | Covered |

All seven rows are `Covered`. Every plan step maps to at least one requirement. Gate passes.
Proceed to `execute-plan`.

**Gate evidence record written to
`openspec/changes/add-rate-limit-api-endpoint/.specpowers/gates/check-coverage.yaml`:**

```yaml
stage: check-coverage
passed_at: 2026-06-01T09:28:00Z
artifacts:
  - path: openspec/changes/add-rate-limit-api-endpoint/specs/search-rate-limit/spec.md
    sha256: 4a7d3c1e9b2f0a8d5e6c4b3a1f9e2d7c8b5a4e3d2c1b0a9f8e7d6c5b4a3f2e1d
  - path: openspec/changes/add-rate-limit-api-endpoint/tasks.md
    sha256: 1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c
result: passed
```

This is the gate-evidence concept in practice: every artifact that the gate verified is listed
with its content digest at the moment of passing. If `tasks.md` is edited after this gate passes,
the orchestrator recomputes the sha256 on resume, detects the mismatch, and invalidates this gate
plus all downstream gates before any further work proceeds.

---

## Stage 6 — `execute-plan`

The orchestrator routes to `specpowers-build`, which runs the subagent-driven execution protocol.
One fresh subagent handles each task. Each subagent must show a RED run before it writes any
implementation code.

**Task 1 — config flag**

RED: `pytest tests/test_config.py::test_rate_limit_enabled_default` — exits 1, `AttributeError:
module 'src.config' has no attribute 'RATE_LIMIT_ENABLED'`. Correct failure reason confirmed.

Minimal implementation: one line added to `src/config.py`:
```python
RATE_LIMIT_ENABLED: bool = True
```

GREEN: same test exits 0. Suite remains green. Committed.

**Task 2 — middleware implementation**

RED: `pytest tests/test_rate_limit.py::test_search_rejects_at_61_calls` — exits 1, `ImportError:
cannot import name 'RateLimitMiddleware'`. Correct failure reason confirmed.

Implementation: `src/middleware/rate_limit.py` created with `RateLimitMiddleware`. The middleware
reads `RATE_LIMIT_ENABLED` at startup, uses Redis INCR + EXPIRE on key
`rate_limit:user:<uid>:search`, returns 429 with a `Retry-After` value computed as
`60 - (int(time.time()) % 60)`, and catches `redis.ConnectionError` to return 503 with
`Retry-After: 5`.

GREEN: `pytest tests/test_rate_limit.py -k "unit"` — 6 passed, 0 failed. Full suite: 47 passed,
0 failed. Committed.

**Task 3 — route wiring**

RED: `pytest tests/test_rate_limit.py::test_middleware_not_registered_when_disabled` — exits 1,
`AssertionError: expected 200 but got 429 for the 61st request when RATE_LIMIT_ENABLED=false`.
Correct failure reason: middleware is not yet guarded by the flag.

Implementation: `src/routes/search.py` updated to register `RateLimitMiddleware` conditionally.

GREEN: test exits 0. Suite: 47 passed, 0 failed. Committed.

**Task 4 — integration tests**

RED: `pytest tests/test_rate_limit.py -k "integration"` — exits 1, 4 collected, 4 errors
(`fixture 'redis_test_client' not found`). Correct failure reason: integration fixtures not yet
defined.

Implementation: integration fixtures added to `tests/conftest.py`; four integration test functions
written covering Scenarios A–E.

GREEN: `pytest tests/test_rate_limit.py` — 14 passed, 0 failed (6 unit + 8 integration). Full
suite: 55 passed, 0 failed. Committed.

**Execute-plan gate check:** all four tasks complete, every task has preserved RED-before/GREEN-after
evidence, tests pass. Gate passes. Proceed to `verify-compliance`.

---

## Stage 7 — `verify-compliance`

The orchestrator applies `references/compliance-verification.md`. An independent adversarial
reviewer is dispatched with the hardened spec delta and the implementation diff.

**Compliance verdict: approved.** No unresolved blockers. The reviewer confirmed:

- REQ-001: `test_search_rejects_at_61_calls` and `test_retry_after_is_positive_integer` both pass
  and exercise the 429 path with a valid integer `Retry-After` value.
- REQ-002: `test_counter_resets_on_window_boundary` verifies the EXPIRE call targets the window
  grid, not a rolling 60-second offset from now.
- REQ-003: `test_middleware_not_registered_when_disabled` confirms the middleware is not in the
  stack when the flag is off.
- REQ-004: `test_redis_error_returns_503` passes a mocked `ConnectionError` through the middleware
  and asserts HTTP 503 with `Retry-After: 5`.

**One minor finding** was raised and accepted with rationale: "The integration test for Scenario C
uses `time.freeze` rather than a real elapsed-time wait, which means it does not exercise the Redis
TTL clock. A future change should add a slow-clock integration test." Accepted: the frozen-clock
test still verifies the key-naming and counter-reset logic; a real-clock test would be slow and
flaky in CI. Logged in the compliance record; no new implementation required.

**Gate evidence record written (excerpt):**

```yaml
stage: verify-compliance
passed_at: 2026-06-01T11:02:00Z
artifacts:
  - path: openspec/changes/add-rate-limit-api-endpoint/specs/search-rate-limit/spec.md
    sha256: 4a7d3c1e9b2f0a8d5e6c4b3a1f9e2d7c8b5a4e3d2c1b0a9f8e7d6c5b4a3f2e1d
  - path: openspec/changes/add-rate-limit-api-endpoint/design.md
    sha256: 9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9f8e
implementation:
  coverage_file_digests:
    - path: src/middleware/rate_limit.py
      sha256: c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4
    - path: src/routes/search.py
      sha256: d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5
    - path: src/config.py
      sha256: e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6
    - path: tests/test_rate_limit.py
      sha256: f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7
  base_ref: origin/main
  base_oid: 3a7f91c2e8b4d6f0a1c3e5f7a9b2d4f6a8c0e2f4a6b8d0f2a4c6e8f0a2c4e6f8
  merge_base_oid: 3a7f91c2e8b4d6f0a1c3e5f7a9b2d4f6a8c0e2f4a6b8d0f2a4c6e8f0a2c4e6f8
  commit_range: "3a7f91c2e8b4d6f0a1c3e5f7a9b2d4f6a8c0e2f4a6b8d0f2a4c6e8f0a2c4e6f8..d84be02a1f3c5e7a9b2d4f6a8c0e2f4a6b8d0f2a4c6e8f0a2c4e6f8a0c2e4f6"
  head_tree: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2
  dirty_diff_sha256: e3b0c44298fc1c149afbf4c8996fb924270b24ee5e4e9e5d7a9c8b3f2d1e0f9a8
  untracked_relevant: []
result: passed
```

The `base_ref` was resolved as `origin/main` (the first matching well-known trunk ref found). The
`commit_range` covers the four task commits introduced by this change. `untracked_relevant` is
empty — no uncommitted files exist under the implementation-area paths. Gate passes.

---

## Stage 8 — `archive`

The orchestrator routes to `specpowers-archive`. It first recomputes the full compliance
implementation evidence set against the same recorded `base_ref: origin/main`.

All seven prior gate evidence records are present. Every artifact digest recomputed at archive time
still matches the stored value. The recomputed `commit_range` and `head_tree` match the compliance
record exactly (no commits or file changes since compliance ran). `dirty_diff_sha256` is the sha256
of empty output — the working tree is clean. `untracked_relevant` is empty.

The change is behavioral, and a spec delta exists under
`openspec/changes/add-rate-limit-api-endpoint/specs/` — the behavioral-change spec-delta assertion
passes.

Because this is `standard` tier (not `full`) and no non-overridable escalation surface was touched,
user confirmation is not required by the tier rules. The one accepted minor finding is surfaced in
the archive summary for information.

The real `openspec archive` CLI is not available in this environment. The conservative fallback runs:

1. Preflight diff generated for `specs/search-rate-limit/spec.md` against the living spec at
   `openspec/specs/search-rate-limit/spec.md` (did not exist — new capability). Diff shown to
   practitioner.
2. No conflicts detected (new file).
3. Timestamped backup written: `openspec/specs/search-rate-limit/.archive-backup/2026-06-01T11-08-22-spec.md`.
4. Per-capability merge confirmed by practitioner.
5. Merged content written atomically to a temp file and renamed; read-back verification passed.
6. Idempotency marker written to
   `openspec/changes/add-rate-limit-api-endpoint/.specpowers/archive-applied/search-rate-limit`.
7. Change directory moved to
   `openspec/changes/archive/2026-06-01-add-rate-limit-api-endpoint/`.

**Archive summary written to
`openspec/changes/archive/2026-06-01-add-rate-limit-api-endpoint/archive-summary.md`:**

---

### Archive summary

**Change:** `add-rate-limit-api-endpoint`
**Archived:** 2026-06-01T11:08:40Z
**Commit range:** `3a7f91c..d84be02`

**Implementation summary.** Three source files were modified and two new files were created.
`src/middleware/rate_limit.py` (new) implements `RateLimitMiddleware` using Redis INCR + EXPIRE on
per-user fixed-window keys, returning HTTP 429 with a `Retry-After` header on quota exhaustion and
HTTP 503 with `Retry-After: 5` on Redis unavailability. `src/routes/search.py` registers the
middleware conditionally on `RATE_LIMIT_ENABLED`. `src/config.py` gains a `RATE_LIMIT_ENABLED`
boolean setting (default `True`). `tests/test_rate_limit.py` (new) contains 14 tests covering all
four requirements across unit and integration layers. The `search-rate-limit` capability spec is
now reflected in the living spec at `openspec/specs/search-rate-limit/spec.md`.

**Verification summary.** Compliance verdict: `approved` (standard tier, one independent
adversarial review pass). Test suite: 55 passed, 0 failed (full suite, including the 14 new tests).
One minor finding accepted: frozen-clock integration test for Scenario C does not exercise the
Redis TTL clock in real time; logged for a future improvement, no implementation gap for the
current requirements.

**Archive path.** `openspec/changes/archive/2026-06-01-add-rate-limit-api-endpoint/`.
Conservative fallback procedure used (openspec CLI not present). Capability `search-rate-limit`
merged; backup at `openspec/specs/search-rate-limit/.archive-backup/2026-06-01T11-08-22-spec.md`;
post-merge read-back verification passed.

**Living-spec update.** `openspec/specs/search-rate-limit/spec.md` created with the full four-
requirement spec delta. Callers consulting the living spec will now find REQ-001 through REQ-004
documented as part of the canonical search capability definition.

**Residual risks.** The frozen-clock integration test for Scenario C (fixed-window reset) covers
key naming and counter logic but does not exercise Redis TTL expiry against a real clock. This is
the only known test gap. `src/middleware/rate_limit.py` is closely coupled to the Redis client
configuration in `src/config.py`; a future change to the Redis connection pool settings should
re-run the rate-limit integration suite. No deferred work items remain in committed code.

---

## End-to-end summary

The `add-rate-limit-api-endpoint` change passed all eight stages and their gates without routing
back except once: the adversarial review at `harden-spec` added REQ-004 (Redis failure behavior),
which caused the plan and coverage matrix to grow by one task and one row respectively before
implementation began. That is the expected and intended behavior — the spec was incomplete, the
harden-spec reviewer found it, and the gap was closed before a single line of implementation code
was written.

Key observations for practitioners:

- The gate-evidence binding (sha256 digests on every verified artifact) meant that the orchestrator
  could trust its cached stage on resume without re-reading every file — it only recomputes digests,
  which is fast.
- The coverage matrix made the scope of the change explicit before execution: four requirements,
  four plan tasks, seven test functions named before the code existed.
- The RED→GREEN evidence per task (stored in the execute-plan gate record) gave the compliance
  reviewer a concrete basis for the verdict instead of requiring a full re-read of the test file.
- The conservative fallback archive ran safely because the recomputed implementation evidence set
  matched the compliance record exactly — no code had been edited between the compliance gate and
  archive.
