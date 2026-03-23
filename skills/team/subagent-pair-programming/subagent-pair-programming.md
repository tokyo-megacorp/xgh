---
name: xgh:subagent-pair-programming
description: "This skill should be used when the user wants TDD with enforced separation of concerns, asks for 'subagent pair programming', or wants to dispatch a spec-writer and implementer as separate agents. Coordinates two subagents — Spec Writer and Implementer — through lossless-claude memory: spec writer writes failing tests, implementer writes minimal code to pass."
---

# xgh:subagent-pair-programming — Subagent Pair Programming

> Dispatch two subagents — a Spec Writer and an Implementer — that coordinate through lossless-claude memory. The Spec Writer writes failing tests; the Implementer writes minimal code to pass. TDD enforced by architecture, not willpower.

## Iron Law

> **THE SPEC WRITER AND IMPLEMENTER MUST NEVER BE THE SAME AGENT.** Separation of concerns is physical, not logical. The spec writer cannot see the implementation; the implementer cannot modify the tests. lossless-claude memory is the contract between them.

## Rationalization Table

| Agent Thought | Reality |
|---|---|
| "I can do TDD in a single agent — just write tests first" | Single agents cheat by peeking at implementation while writing specs |
| "Two subagents is overkill for a small feature" | Small features are where TDD habits form. Skip it here, skip it everywhere |
| "The spec writer doesn't have enough context to write good tests" | That's exactly the point — specs should be writeable from requirements alone |
| "Coordinating through lossless-claude is slower than just coding" | Slower per-task, but catches design flaws that would cost 10x to fix later |
| "The implementer needs to modify tests for edge cases" | Edge cases go back to the spec writer. Round-trip is the feature, not the bug |

## When This Skill Activates

- Explicitly via `/xgh pair-program "[task description]"`
- Automatically for large implementation tasks (configurable threshold)
- When the `implement-ticket` skill dispatches TDD execution

---

## Orchestrator

The orchestrator (the main Claude session) manages the pair programming workflow:

### Step 1: Task decomposition

Break the work into TDD-sized units. Each unit should:
- Be testable in isolation
- Take 2-5 minutes to implement
- Have clear inputs and outputs

### Step 2: Initialize thread

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: |
    Pair programming session started.
    Task: [description]
    Units:
    1. [unit description]
    2. [unit description]
    ...
  metadata:
    thread: pair-[session-id]
    type: orchestration
    status: in_progress
```

### Step 3: Dispatch Spec Writer (per unit)

Dispatch a fresh subagent with ONLY these inputs:
- The unit description (what to test)
- Team conventions from lossless-claude (testing patterns)
- The thread ID for storing specs

The spec writer has NO access to:
- Existing implementation code
- The implementer's work
- Other units' implementations

### Step 4: Dispatch Implementer (per unit)

Dispatch a fresh subagent with ONLY these inputs:
- The test specs from the lossless-claude thread
- Team conventions from lossless-claude (coding patterns)
- The thread ID for storing implementation

The implementer has NO access to:
- The spec writer's reasoning (only the test code)
- Future unit specs
- The orchestrator's full plan

### Step 5: Review both outputs

The orchestrator reviews:
- Do tests actually fail before implementation? (RED)
- Does implementation make tests pass? (GREEN)
- Is implementation minimal (no gold-plating)?
- Are conventions followed?

### Step 6: Iterate or advance

If review finds issues:
- Send feedback to the appropriate subagent via lossless-claude thread
- Subagent re-does their work with the feedback

If review passes:
- Mark unit complete
- Advance to next unit

---

## Spec Writer

The spec writer subagent follows this process:

### Phase 1: Context gathering

```
Tool: lcm_search(query)
Parameters:
  query: "[domain] testing patterns conventions"
  scope: workspace
  filter:
    type: convention
    domain: testing
```

### Phase 2: Write failing tests

Write tests based ONLY on the unit description and requirements. Tests must:
- Be runnable
- Fail for the right reason (missing implementation, not syntax errors)
- Cover the happy path and key edge cases
- Follow team testing conventions

### Phase 3: Store specs to thread

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: |
    ## Test Spec: [unit name]

    ### Test file: [path]
    ```[language]
    [complete test code]
    ```

    ### Expected behavior:
    - [assertion 1]: [why]
    - [assertion 2]: [why]

    ### Edge cases covered:
    - [edge case 1]
    - [edge case 2]

    ### Run command:
    [exact command to run tests]
  metadata:
    thread: pair-[session-id]
    type: test-spec
    unit: [unit-number]
    status: RED
    files: [test file path]
```

### Phase 4: Verify RED

Run the tests and confirm they fail:

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: "Tests verified RED. [N] tests, [N] failures. Failures are for the right reason: [missing implementation]."
  metadata:
    thread: pair-[session-id]
    type: test-spec
    unit: [unit-number]
    status: RED
    verified: true
```

---

## Implementer

The implementer subagent follows this process:

### Phase 1: Read specs from thread

```
Tool: lcm_search(query)
Parameters:
  query: "thread:pair-[session-id] unit:[unit-number] test-spec"
  scope: workspace
  filter:
    type: test-spec
    status: RED
```

### Phase 2: Query conventions

```
Tool: lcm_search(query)
Parameters:
  query: "[domain] implementation patterns conventions"
  scope: workspace
  filter:
    type: convention
```

### Phase 3: Write minimal implementation

Write ONLY enough code to make the failing tests pass. Rules:
- No code that isn't required by a test
- No premature optimization
- No speculative features
- Follow team conventions

### Phase 4: Store implementation to thread

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: |
    ## Implementation: [unit name]

    ### File: [path]
    ```[language]
    [complete implementation code]
    ```

    ### Decisions made:
    - [decision 1]: [why]

    ### Conventions followed:
    - [convention 1]
  metadata:
    thread: pair-[session-id]
    type: implementation
    unit: [unit-number]
    status: GREEN
    files: [implementation file path]
```

### Phase 5: Verify GREEN

Run the tests and confirm they pass:

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: "Tests verified GREEN. [N] tests, [N] passed."
  metadata:
    thread: pair-[session-id]
    type: implementation
    unit: [unit-number]
    status: GREEN
    verified: true
```

---

## Edge Case Round-Trip

When the implementer discovers an edge case not covered by tests:

1. Implementer stores a request back to thread:

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: |
    Edge case discovered: [description]
    Why it matters: [explanation]
    Request: spec writer to add test for this case
  metadata:
    thread: pair-[session-id]
    type: edge-case-request
    unit: [unit-number]
    for_agent: spec-writer
```

2. Orchestrator dispatches spec writer again for the edge case
3. Spec writer adds test, verifies RED
4. Implementer handles edge case, verifies GREEN

---

## Session Wrap-Up

After all units complete:

### Step 1: Full test suite

The orchestrator runs the complete test suite to verify all units work together.

### Step 2: Curate learnings

```
Tool: lcm_store(text, ["reasoning"])
Parameters:
  content: |
    Pair programming session complete.
    Task: [description]
    Units completed: [N]
    Total tests: [N]
    Patterns discovered: [list]
    Conventions followed: [list]
    Edge cases found via round-trip: [list]
  metadata:
    thread: pair-[session-id]
    type: orchestration
    status: completed
```

---

## Tool Reference

| Tool | Usage |
|---|---|
| `lcm_store(text, ["reasoning"])` | Store test specs (RED), implementations (GREEN), edge case requests, and session results |
| `lcm_search(query)` | Read test specs (implementer), query conventions (both), discover edge case requests |
| Extract 3-7 bullet summary → `lcm_store(text, context-tag)` | Extract session learnings for context tree curation |

## Composability

- Works with **convention-guardian**: Both subagents query conventions before their work
- Feeds into **pr-context-bridge**: Spec/implementation reasoning stored to PR thread
- Works with **implement-ticket**: Ticket implementation dispatches pair programming for TDD phases
- Feeds into **knowledge-handoff**: Patterns discovered during pair programming included in handoff
