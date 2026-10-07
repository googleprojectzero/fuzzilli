---
name: change-verifier
description: High-precision, multi-agent code review and verification skill for Fuzzilli changes.
---

# Fuzzilli Change Code Review / Verification Skill

Use this skill to perform high-assurance, high-precision code reviews on Fuzzilli changes. This skill separates discovery of issues (using specialized subagents) from empirical verification (by the Lead Agent) so that reported Action Items are verified and free of avoidable false positives.

---

## I. Multi-Agent Audit Protocol

### Step 0: Change Intent Extraction
Before defining or invoking any subagents, inspect the target changes yourself using `run_command` (with `Cwd` set to the target repository/worktree):
1. Run `git status` and `git show --stat <commit>` or `git show <commit>` to identify the exact list of modified files (`[FILES]`) and modified line ranges as well as the commit message.
2. Formulate a concise, 2–4 sentence **Change Intent Summary** covering:
   - **Objective**: What problem is this change solving or what feature/instruction is it adding?
   - **Key Mechanism**: What files, operations, types, lifters, or mutators are modified and how?
3. You MUST include both the **Change Intent Summary** and the **exact commit SHA / diff command** (e.g., `git show <commit>` or `git diff`) in the prompt sent to all three subagents so they immediately focus on the changed lines and do not confuse modified code with pre-existing code.

---

### Step 1: Define Specialized Subagents
Define the three subagents using `define_subagent` (if not already defined in the conversation).

> **Important Tool Rule**: Keep `enable_write_tools: true` on all subagents so they have access to `run_command` for read-only Git and search commands (like `git diff`, `git show`, `git log`, `git grep`). Do not use the `code_search` tool as it uses remote indexes which are non-existent for Fuzzilli.

1. `architectural_auditor`:
   - `name`: `"architectural_auditor"`
   - `description`: `"Audits structural integrity, FuzzIL/TypeSystem invariants, fan-out propagation, and dual-path symmetry."`
   - `enable_write_tools`: `true`
   - `system_prompt`: `"Perform static architectural and invariant analysis on Fuzzilli code. Use view_file and read-only run_command calls (like git show, git diff, git status, git log, git grep) to inspect the diff and search the Fuzzilli repository. Do NOT use code_search for local Fuzzilli files. Do NOT edit or create files, and do NOT run swift build or swift test."`

2. `code_reviewer`:
   - `name`: `"code_reviewer"`
   - `description`: `"Performs line-by-line logic review, companion test verification, presubmit checks, and unit test execution."`
   - `enable_write_tools`: `true`
   - `system_prompt`: `"Perform line-by-line code review, style/presubmit verification (Tools/presubmit.py), companion test verification, and test execution (swift test). Use view_file and run_command (like git show, git diff, git grep, Tools/presubmit.py, swift test) as primary tools. Do NOT use code_search for local Fuzzilli files, and do NOT modify workspace files."`

3. `spec_conformance_auditor`:
   - `name`: `"spec_conformance_auditor"`
   - `description`: `"Audits runtime semantics, type lattices, and language features against official ECMA-262 and WebAssembly specifications."`
   - `enable_write_tools`: `true`
   - `system_prompt`: `"Audit Fuzzilli language feature modeling against official ECMA-262, WebAssembly, and WebIDL specifications and active proposals. Use search_web and read_url_content to reference spec texts, and use view_file and read-only run_command (like git show, git diff, git grep) to inspect local Fuzzilli code. Do NOT use code_search for local Fuzzilli files, do NOT modify files, and do NOT run swift build or swift test."`

---

### Step 2: Invoke Subagents in Parallel
Invoke all three subagents in a single `invoke_subagent` call using their registered `TypeName`s:
```json
{
  "Subagents": [
    { "TypeName": "architectural_auditor", "Role": "Architectural & Logic Auditor", "Prompt": "..." },
    { "TypeName": "code_reviewer", "Role": "Code Reviewer", "Prompt": "..." },
    { "TypeName": "spec_conformance_auditor", "Role": "Language Spec Auditor", "Prompt": "..." }
  ]
}
```

In each prompt template replace `[REQUIRED_EVIDENTIARY_FORMAT]` with:
```text
Required Evidentiary Format for Every Finding:
For each issue or hypothesis reported, you MUST explicitly state:
- **Location**: Exact `file:line` references (and spec/proposal section if applicable).
- **Trigger & Reachability**: Exact sequence of generator, mutator, reducer, or API calls that reaches the defective state.
- **Testable Hypothesis & Concrete Impact**: How and under what conditions this causes invalid code, validation failure, or wrong behavior, plus proposed remediation code.
- **Proposed remediation code**: The proposed change to fix the issue.
```

#### 2.1 Architectural & Logic Audit (`architectural_auditor`)
*   **Prompt Template**:
    ```text
    Perform a comprehensive structural and architectural audit of the changes in [REPOSITORY_PATH] (inspect via `[GIT_SHOW_COMMAND]`; modified files: [FILES]).

    Change Intent Summary:
    [CHANGE_INTENT_SUMMARY]

    Execute the following [Trigger] -> [Mandatory Tool Action] -> [Defect Condition] checks:

    1. Exhaustive Variant, Opcode & Property Propagation (Fan-out Audit):
       - [Trigger]: An enum case/associated value, `Opcode`, `Operation` subclass, struct field, `Context` bit, or function signature is added or modified.
       - [Tool Action]: Run `git grep` across `Sources/` and `Tests/` for all pattern matches, switches, initializers, and usages of the modified type/operation.
       - [Defect Condition]: Any consumer silently ignores the new case/field via wildcards (`default:` / `_`), fails to propagate a property, or omits required handling across the FuzzIL pipeline.

    2. Sibling & Dual-Path Symmetry & Inconsistency Investigation:
       - [Trigger]: Logic updates, guards, or feature support added to one helper, opcode handler, lifter/typer branch, mutator, reducer, or serializer.
       - [Tool Action]: Identify all sibling, parallel, or inverse paths operating on the same data structures, opcodes, or shared helper functions (e.g., encode vs. decode, `Begin*` vs. `End*`, parallel operation variants, or all callers of the same helper).
       - [Defect Condition]: If ANY asymmetry, partial update, or omission is identified:
         a. Trace callers and downstream consumers to determine whether the discrepancy causes invalid code emission, assertion failures, type confusion, silent property dropping, or behavioral drift.
         b. Static False-Positive Check (Derive from Code, Never Assume):
            - *Shared Helper vs. Specialized Handler*: General routine handling multiple variants vs. specialized handler where the condition is intrinsically guaranteed.
            - *Immutable Invariant vs. Mutator-Reachable State*: Read the relevant mutators, reducers, and validators to verify whether a hard invariant prevents the state (never dismiss an issue merely because `CodeGenerator`s don't emit it).
            - *Intra-File Sibling Precedent & Consumer Requirements*: Inspect sibling operations and downstream consumers/tests to verify whether the omission is intentional by design.
         c. If proven benign/intentional, briefly note the `file:line` proof under "Verified Safe / Benign Asymmetries" and do not report it as an action item.
         d. If it can be triggered or creates a concrete maintenance/correctness hazard, report it under "Architectural Inconsistencies & Action Items".

    3. Producer-Consumer Parity:
       - Verify that type, context, or behavioral updates are consistently supported across both producers (generators, `ProgramBuilder`, initializers) and consumers (`JSTyper`, all lifters, mutators and reducers).

    4. Adjacent & Pre-Existing Defect Discovery:
       - Audit both modified files and their unmodified sibling/downstream consumers in the affected subsystem.
       - If you identify broken, semantically incorrect, or incomplete behavior in untouched or adjacent code, report it in a dedicated "Adjacent & Pre-Existing Issues" section with the same evidentiary rigor. Do NOT omit a real bug just because the current change did not touch that line or file.

    Core Fuzzilli Architectural Invariants:
    1. Context & Program Validity: Operations emitted via `ProgramBuilder` or transformed by mutators/reducers must only be placed into matching contexts (`requiredContext`) and preserve structural program validity.
    2. Deterministic Lifting: Lifters must **always** be deterministic (never use randomness or depend on non-deterministic iteration order of a `Set` or `Dictionary` when lifting a `Program`). Stochastic choices in generators and mutators are expected and not lifting bugs.
    3. Cross-Pipeline Operation Handling: When a new operation is added or its properties change, ensure it is handled consistently especially across `OperationMutator`, `JSTyper`, the lifters (`JavaScriptLifter` / `WasmLifter` / `FuzzILLifter`), `BlockReducer` (preserving context consistency during simplification), and protobuf conversion in `Instruction.swift` / `operations.proto`.
    4. Type System Rules: Changes to `TypeSystem.swift` must preserve type lattice laws (reflexivity, subsumption transitivity, union/intersection/merge bounds). When auditing typing rules, inspect downstream consumers to distinguish where types are strict correctness requirements vs. best-effort heuristics.
    5. Operation & Execution Contracts: Verify that `Operation` subclasses remain immutable and use the appropriate base class when parameterized or variable-arity so operation caching is not violated, and inspect `Docs/` or caller queues before flagging concurrency/locking issues.

    [REQUIRED_EVIDENTIARY_FORMAT]
    ```

#### 2.2 Code Review & Style Audit (`code_reviewer`)
*   **Prompt Template**:
    ```text
    Perform a detailed logical, implementation, and test audit of the changes in [REPOSITORY_PATH] (inspect via `[GIT_SHOW_COMMAND]`; modified files: [FILES]).

    Change Intent Summary:
    [CHANGE_INTENT_SUMMARY]

    Verify the following:
    1. FuzzIL & Swift Implementation Correctness:
       - Check for unhandled edge cases, off-by-one errors, or broken invariants in the modified control flow.
       - When reviewing builders, mutators, reducers, or lifters that allocate variables, modify instruction inputs/outputs, or queue/inline expressions, read the underlying `Code`, `Instruction`, `ProgramBuilder`, or writer implementation to verify that variable numbering, input/output arity, and evaluation order invariants are preserved.
       - Check for code duplication (DRY violations), leftover debug statements, unresolved FIXME comments, and adherence to workspace naming/style conventions.

    2. Companion Test Suite Verification:
       - Before claiming a change lacks unit tests, use `git grep` and `view_file` to search `Tests/FuzzilliTests/` for existing companion test suites covering the modified subsystem.
       - Verify whether new features or bug fixes have corresponding unit/regression test coverage, and whether assertions in new tests actually exercise the edge cases of the change.

    3. Build & Unit Test Execution:
       - Run `swift test` in `[REPOSITORY_PATH]` and verify that all tests pass and compile cleanly without new warnings or diagnostics in modified files. (If `swift` is not found on the default `PATH`, check common toolchain paths such as `$HOME/.local/share/swiftly/bin`.)

    4. Presubmit & Formatting Check:
       - Run `python3 Tools/presubmit.py` in `[REPOSITORY_PATH]` to verify formatting and check that generated protobuf files (`*.pb.swift`, `program.proto`) are up-to-date.

    [REQUIRED_EVIDENTIARY_FORMAT]
    Output your review as a clean, structured report and a final Sign-off Status.
    ```

#### 2.3 Language Specification & Protocol Audit (`spec_conformance_auditor`)
*   **Prompt Template**:
    ```text
    Perform a specification and language semantics audit of the changes in [REPOSITORY_PATH] (inspect via `[GIT_SHOW_COMMAND]`; modified files: [FILES]).

    Change Intent Summary:
    [CHANGE_INTENT_SUMMARY]

    Step 1 — Triage Gate (Early Exit):
    First, inspect the diff to determine if the changes touch or affect any language-level semantics, JS/Wasm instructions, lifters, compilers/parsers, built-in environment definitions, minimizer semantic simplifications, or type definitions. If NO language semantics are affected (e.g., pure CLI flags, statistics counters, or build scripts), state this clearly and finish immediately.

    Step 2 — Specification Audit (When Language Semantics Are Touched):
    Verify the changes against the relevant official specifications (ECMA-262, active TC39 proposals, WebAssembly specifications/proposals, or engine-specific V8/d8 contracts) and check especially the following:

    1. Syntactic Invariants & Early Error Prevention:
       - Identify any operations or constructs that could emit code producing uncatchable early errors (e.g., parse-time SyntaxErrors, early module linking failures, or uncatchable static validation errors) in target engines.
       - Verify that FuzzIL structural constraints (such as `requiredContext`, block hierarchies, and code generation preconditions) strictly prevent operations from being emitted in invalid syntactic or lexical contexts.
       - Distinguish between runtime-catchable exceptions (which can be safely wrapped in try-catch or guarded operations) and early/static errors (which must be prevented structurally).

    2. Scoping, Lifetime & Namespace Isolation:
       - Verify that all scopes (e.g., lexical, block, function) and variable lifecycles are modeled accurately.
       - Ensure distinct identifier namespaces do not pollute or shadow one another across lifting, compilation, type inference, or minimization.
       - Check that inheritance semantics correctly differentiate between lexical scope boundaries and prototype chain traversal.

    3. Environment & Type System Fidelity:
       - For any added or modified built-ins, globals, methods, accessors, or constructors in the environment/profiles:
         a. Parameter count, types, optionality, and rest argument handling conform to the spec.
         b. Return types, promise resolution types, and produced object shapes accurately reflect the specification.
         c. Constructor vs. function callability semantics (e.g., [[Construct]] vs. [[Call]]) are preserved.
       - For WebAssembly: verify that value types, reference types, type hierarchies (subtyping/casting), and instruction signatures strictly adhere to the WebAssembly specification.

    4. Language Protocol, Evaluation Order & Operator Semantics:
       - Verify that the implemented semantics (e.g. evaluation order, variable visibility, inferred types) fully match the specification.
       - When reviewing minimization reducers, verify that simplified instruction sequences preserve side effects, evaluation order, and variable bindings required for the program to remain valid.

    5. Fuzzing Abstraction vs. True Violation (Pragmatism Check):
       - Differentiate between:
         a. True Semantic/Syntactic Violations (which cause invalid code generation, uncatchable engine errors, or incorrect type narrowing).
         b. Intentional Sound Abstractions (where FuzzIL intentionally uses coarse approximations, such as open object bounds or `.jsAnything`, to balance fuzzer performance and state complexity). Do NOT flag intentional sound abstractions as violations unless they lead to invalid code, broken invariants or ineffective fuzzing.

    Grounding & Active Proposal Lookup Protocol:
    - Always use `search_web` to verify complex grammar rules, Wasm binary encodings, or newly proposed features (e.g., active Wasm or TC39 Stage 1–4 proposals, V8 `d8.test` builtins or `%` prefixed builtins) rather than guessing from memory.
    - Only flag a feature/instruction as non-existent if NO finalized spec, active proposal, or V8 engine implementation exists for it.

    [REQUIRED_EVIDENTIARY_FORMAT]

    Output your review as a structured report:
    - Specification Alignment Summary (Compliant / Violation / Intentional Fuzzing Tradeoff / N/A)
    - Identified Semantic Discrepancies & Testable Hypotheses
    - Adjacent & Pre-Existing Issues (in untouched/adjacent code within the subsystem)
    ```

---

### Step 3: Lead Agent Active Falsification, Verification & Synthesis Protocol

**Attention**: Start verifying findings (`Step 3.A`) as soon as the first subagent report arrives, but wait until all three subagents have completed and returned their reports before synthesizing the final report (and before running `swift test` or editing files in `Step 3.A.3`).

Subagent findings and hypotheses are **untrusted leads**, NEVER direct outputs. Your primary responsibility as the Lead Agent is to act as an **active falsifier and empirical verifier** so that the final report achieves both high precision (zero avoidable false positives in Action Items) and high recall (zero dropped real bugs).

#### A. Mandatory Verification Loop (Execute Before Writing the Report)
For every candidate finding, asymmetry, or hypothesis raised by any subagent:

1. **Live Codebase & False-Positive Verification (Derive from Code, Never Assume)**:
   - Use `view_file` and `git grep` to inspect the exact lines, callers, helper wrappers, and sibling implementations in the repository yourself.
   - Apply these **General False-Positive Verification Checks**:
     1. *Shared Helper vs. Specialized Handler*: Is one path a general routine handling multiple operations/variants (requiring a guard) while the other is a specialized handler where that condition is intrinsically guaranteed?
     2. *Inspect Actual Producer / Mutator / Reducer Guards*: Never guess what states a mutator or reducer can produce, and never assume a validation check is missing. Read the relevant mutators, reducers, and validators in the codebase to determine whether the hypothesized state is prevented by an existing guard or is genuinely reachable.
     3. *Check Sibling Precedent & Consumer Requirements*: Inspect how sibling operations in the same file and downstream consumers (lifters, validators, companion tests in `Tests/FuzzilliTests/`) are implemented to distinguish intentional coarse approximations or minimal representations from real defects.
   - **Critical Override Rule**: Evaluate the **concrete Fuzzilli code mechanism**, NOT dramatic or alarmist phrasing in a subagent report. Even if a subagent claims *"critical crash / severe corruption"*, discard the finding if the underlying mechanism is unreachable or benign by design.

2. **Construct a Concrete Trigger Trace & Verify Meaningful Impact**:
   - Before promoting any logic, type, lifter, reducer, compiler, or spec finding to Tier 1 or Tier 2, you MUST construct a **concrete, step-by-step trigger trace** showing how a valid FuzzIL program, JS input, or mutation sequence reaches the broken state and causes a meaningful failure (e.g., exact `assert`/`fatalError` line, uncatchable JS early `SyntaxError`, Wasm validation error, silent state/property loss, non-deterministic lifting, broken type lattice laws, or wrong minimization/compilation semantics) that a Fuzzilli maintainer would genuinely want fixed.
   - If you cannot construct a reachable trigger sequence (and it is not a deterministic style/DRY/exhaustive-switch/missing-test issue), the bug claim is falsified and MUST NOT be placed in Tier 1 or Tier 2.

3. **Empirical Verification via `swift test` (When Static Analysis Leaves Doubt)**:
   - Whenever a subagent raises a plausible hypothesis about subtle behavior in `TypeSystem`, `JSTyper`, lifters, compilers, or minimization reducers that is not 100% obvious from reading the code alone, verify it empirically (e.g., by running `swift test --filter <TestName>` or briefly testing the trace). If you temporarily edit a test file to check a hypothesis, revert any temporary test edits (`git checkout -- ...`) and ensure the workspace is clean before outputting your report.

#### B. Synthesis & Bundling Rules
- **Independent Subagent Evaluation**: Negative constraints in one subagent's domain (e.g., ignoring coarse JS types in `spec_conformance_auditor`) do NOT suppress valid findings in another domain (e.g., missing switch case or DRY violation in `architectural_auditor` / `code_reviewer`).
- **Scope-Agnostic Retention for Verified Bugs**: Never dismiss a verified bug merely because it is in an untouched file or pre-existing—place in Tier 2.
- **Multi-Site Comment Bundling**: If the same underlying issue occurs across multiple lines, operations, or files, consolidate them into **one** comprehensive Action Item at the primary location and list `"Other occurrences:"` with clickable `file:line` links.

#### C. Mandatory Report Structure
Organize the final review report into the following clear sections:

1. **Executive Summary & Sign-Off Status**:
   - Target commit/change, final verdict (`APPROVED`, `APPROVED WITH NON-BLOCKING OBSERVATIONS`, or `CHANGES REQUESTED`), and a 1–2 sentence high-level assessment. Do not include a build/test/presubmit bullet unless a check failed, and do not enumerate affected files/classes in the assessment.

2. **Tier 1: Verified Action Items (Blocking / PR Scope)**:
   - Verified bugs, regressions, missing fan-out updates, missing tests, or style/DRY issues directly introduced or exacerbated by the change under review.
   - Tag every item with **Severity (`S0–S3`)**:
     - `S0 (Blocker)`: Breaks build/tests/presubmit, triggers Fuzzilli `assert`/`fatalError`, breaks `TypeSystem` lattice laws, introduces lifting non-determinism, or emits uncatchable JS early `SyntaxError`s / invalid Wasm binaries under normal fuzzing.
     - `S1 (Critical)`: Causes invalid code emission, silent property/instruction dropping, or wrong semantics under realistic mutator/splicing/minimization edge cases, or omits required operation fan-out handling.
     - `S2 (Improvement)`: Non-blocking architectural, DRY/duplication, test coverage, or type-precision improvement where current behavior is safe but suboptimal.
     - `S3 (Nit)`: Minor naming, comment, style, or polish suggestion.

3. **Tier 2: Verified Pre-Existing & Adjacent Defects (Non-Blocking / Follow-up)**:
   - Verified bugs, omissions, or semantic defects uncovered during the audit in untouched files or pre-existing code in the affected subsystem (held to the **exact same verification and proof-of-impact bar** as Tier 1).
   - Include this section **only** if there is something relevant to report in it.
   - Always include this note at the top of Tier 2 if there are any entries for this section:
     > *Note for PR Authors: The items in Tier 2 are pre-existing or adjacent issues uncovered in the surrounding subsystem during the audit. They do **not** block merging your current change, but are documented here so you can either address them opportunistically or track them in a follow-up issue.*

4. **Tier 3: Design & Intent Clarifications (Optional — Non-Prescriptive Questions Only)**:
   - Include this section **only** if there is an edge case where you have verified the exact code behavior, but whether that behavior is intentional depends on author intent or an ambiguous spec/engine tradeoff.
   - Frame items here strictly as neutral, concise questions explaining the trade-off—**never** as unverified bug claims or directives to rewrite working code.

#### D. Action Item Template (Adaptive Depth)
Every item in **Tier 1** and **Tier 2** MUST be numbered and use this 3-part structure, scaling explanation depth to the complexity of the issue:

```markdown
#### 1. [S1 Critical] <Short Descriptive Title>
- **Location**: [`FileName.swift:120-134`](file:///abs/path/to/FileName.swift#L120-L134) (and related [`OtherFile.swift:45`](file:///abs/path/to/OtherFile.swift#L45))
- **Explanation & Impact**:
  - *For mechanical omissions* (e.g., missing switch case, forgotten flag/property forwarding, DRY/style/test gap): State what was omitted and its direct consequence in 1–2 sentences. List multiple affected cases compactly on a single line (e.g., `.caseA` (L10), `.caseB` (L20)) rather than vertical bullet lists.
  - *For subtle or non-obvious bugs* (e.g., cross-pass interactions, mutator/reducer reachability, lifter expression inlining, or JS/Wasm spec edge cases): Explain the underlying Fuzzilli invariant or spec rule and include a compact (3–5 line) FuzzIL/JS trigger example showing how the broken state is reached.
- **Proposed Fix**:
  State the fix in 1–2 sentences (or Option A vs. Option B if multiple approaches exist). Omit code blocks for mechanical omissions; include a short code snippet only when the logic is non-trivial.
```

---

## II. Interactive Walkthrough (For Interactive Sessions Only)

- If running in an interactive session and there are Tier 1 or Tier 2 items, conclude the report by offering to walk through the items one by one with the user.
- If the user accepts, present the first item with its concise example and proposed fix (or options if multiple approaches exist), apply the user's chosen resolution, and proceed item by item until all selected items are resolved.
