---
name: specpowers-brainstorm
description: Use as stage 1 of specpowers-flow — turn a raw idea into an approved direction and a proposal.md draft. Produces problem statement, scope boundary, success criteria, non-goals, risks, and open questions.
---

## Purpose

This skill owns stage 1 of the specpowers-flow pipeline. It takes an unformed idea and produces a
direction that is concrete enough to generate a change: a named change, a clear problem statement,
agreed-upon scope, testable success criteria, explicit non-goals, known risks, and a list of open
questions that must be resolved before specification work can begin.

The discipline ends with an approved direction and a `proposal.md` draft written directly into the
change directory. There is no separate brainstorm document — the proposal *is* the brainstorm
output.

---

## Brainstorm discipline

Work one question at a time. Do not present a complete answer in one shot. Surface uncertainty
rather than burying it in confident-sounding prose. When multiple approaches exist, name them,
weigh them, and record the one chosen and why.

The conversation moves through four phases:

1. **Understand the problem.** What is broken, missing, or desired? Who is affected? What evidence
   shows this is real? Ask one clarifying question at a time and wait for the answer before moving
   on. Resist restating the idea as a solution; keep exploring the problem space.

2. **Frame the scope.** Draw a boundary around what this change will and will not touch. Name the
   systems, data, users, and behaviors inside the boundary. Explicitly list what is excluded. A
   fuzzy scope is a blocker; do not advance until the boundary is crisp.

3. **Explore approaches.** Identify at least two realistic implementation directions. For each,
   state its key tradeoff, rough reversibility, and any high-risk surface (authentication,
   permissions, schema changes, irreversible operations, billing, tenant boundaries). Surface
   tradeoffs directly — do not recommend without showing the alternatives. Record the chosen
   direction and the rationale.

4. **Resolve open questions.** List every unanswered question that could invalidate the chosen
   direction or block spec generation. For each, state who can answer it and what the impact is if
   it is answered differently.

---

## Required outputs

Before the completion gate can be evaluated, the following six elements must be present in
`openspec/changes/<change>/proposal.md` (see `references/openspec-artifact-format.md` for the
full proposal shape including required sections):

| Output | What it must contain |
|---|---|
| **Problem statement** | One paragraph: current situation, the gap or failure, and measurable impact |
| **Scope boundary** | What is in scope (systems, behaviors, data); what is explicitly out of scope |
| **Success criteria** | Numbered, testable conditions — each must be verifiable without interpretation |
| **Non-goals** | Explicit list of outcomes this change does not pursue, to prevent later scope creep |
| **Risks** | Each risk identified during approach exploration, with severity and a mitigation or acceptance note |
| **Open questions** | Every unresolved question with owner and consequence if answered differently |

These outputs are written **directly into `openspec/changes/<change>/proposal.md`** as the draft
takes shape during the brainstorm. They are not copied into a separate file afterward. The
proposal draft and the brainstorm output are the same artifact.

If no change directory exists yet, create it at `openspec/changes/<change>/` using the chosen
change name before writing the file.

---

## Completion gate

The brainstorm stage is complete when both of the following are true:

1. **Direction approved.** The human has explicitly accepted the chosen approach and scope. A lack
   of objection is not acceptance; ask for it directly.

2. **Requirement is specific enough to generate a change.** The problem statement, scope, and
   success criteria are concrete enough that `specpowers-spec` can produce `design.md`, `tasks.md`,
   and a spec delta from them without guessing. If ambiguity remains that would force a spec author
   to make unstated assumptions, resolve it here first.

If either condition is not met, continue the brainstorm. Do not advance.

---

## What this stage does NOT do

- It does not generate `design.md`, `tasks.md`, or spec deltas — those belong to `specpowers-spec`.
- It does not write implementation code or validation commands.
- It does not attempt to resolve open questions by inventing answers; it surfaces them.

---

## Handoff

When the gate is satisfied, hand control back to the orchestrator (`specpowers-flow`). The
orchestrator will confirm tier selection (informed by the scope and any high-risk surfaces
identified during brainstorm) and route to `specpowers-spec` for stages 2–3.

**Next stage:** `specpowers-spec` — generate OpenSpec artifacts from the approved proposal, then
harden them via validation and adversarial review.
