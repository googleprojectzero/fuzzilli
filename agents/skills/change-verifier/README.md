# Change Verifier / Review Skill

This skill is a specialized review skill for Fuzzilli. Its instructions (subagent invocation, tools etc.) target Antigravity and therefore work best in its harness but should generally work with any underlying model.

- What this skill tries to do:
  - Provide high-quality AI-based assistance for authors and/or reviewers
  - Provide a good signal-to-noise ratio by focusing on real issues, not intentional abstractions / simplifications in the fuzzer
  - Provide explanations and proposed fixes for reported findings
- What this skill doesn't try to do:
  - Find everything: The skill (while trying to be domain-specific) does not list specific issues to verify / prevent and does not aim to maintain such an ever-growing list.
  - Be an in-cycle agentic quality assurance: This skill is way too slow / expensive for using it inside agentic development cycles and is exclusively targeted as a final AI-review (after author review before sending it out to a human reviewer or before/after landing).
  - Be a "one size fits all" solution: This skill is based on many subjective design choices by mliedtke@. Feel free to fork it for your own use cases.
