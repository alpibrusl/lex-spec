# CLAUDE.md — lex-spec

> Copy this file into the root of any Lex project repository as
> `CLAUDE.md` (read by Claude Code), `AGENTS.md` (read by Cursor /
> Aider / Codex CLI / Copilot CLI), or both.

This repository is a **Lex** project. Read `lex agent-guidelines` in
full before writing code. The four highest-leverage discipline rules:

1. **Narrow effects, always.** `fn foo() -> [fs_write("/tmp/x")] T`,
   not `[fs_write]`. If the type checker rejects, narrow the **body**.
2. **Repair, don't regenerate.** `lex check --output json` → `lex repair --apply`.
3. **`examples {}` blocks on every pure fn.** They fold into the
   SigId; free regression tests with no `tests/` boilerplate.
4. **Use the stdlib.** `std.crypto` not hand-rolled crypto; `std.regex`
   not manual scanners.

## The loop

```sh
lex check --strict src/        # type-check with extra lints
lex fmt --check src/ tests/    # formatting (must be canonical)
lex test                       # all tests/test_*.lex files
```

## Project-specific overrides — lex-spec

- **Specs are pure values.** Nothing in `src/` declares effects.
  `check_random` is pure: the seed is supplied explicitly.
- **`Spec` shape is load-bearing.** Both lex-agent and lex-llm
  consume `Spec` values via `Capability.precondition`. Changing the
  ADT shape requires a coordinated bump in both downstream packages.
- **SMT-LIB output is the audit trail.** `to_smt_lib` is consumed by
  external Z3; output stability matters. The test suite asserts on
  visible substrings (`set-logic`, `(= `, `(declare-const x Int)`),
  not on the full string — so re-ordered emit is fine, but the
  vocabulary is fixed.
- **Don't reach for `std.random` directly.** `check_random` is
  seed-driven through a SplitMix64-style mixer so property checks
  are reproducible across platforms.
- **Verdict ≠ Bool.** A capability gate that drops `Inconclusive`
  into `false` is wrong by default; surface the reason to the
  caller's diagnostics.
