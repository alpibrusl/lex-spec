# lex-spec — Agent Guidelines

Capability-precondition + spec DSL for Lex. See `README.md` for the
surface; this doc carries the discipline specific to authoring
against the package.

---

## The Spec ADT shape is load-bearing

Both `lex-agent` (server-side) and `lex-llm` (client-side) consume
the same `Spec` value via `Capability.precondition`. Changing the
ADT shape — renaming `QInt` → `IntQuant`, reshuffling `EBinop`'s
record fields — is a coordinated bump across all three packages.

Add new variants by appending; the wire emitter (`smt.lex`) and the
evaluator (`eval.lex`) need parallel branches in their match arms,
and missing arms surface as type errors at `lex check` time. Don't
silence with `_ =>`.

---

## Verdict semantics

```lex
type Verdict =
    Allow
  | Deny(Str)
  | Inconclusive(Str)
```

| verdict | meaning |
|---|---|
| `Allow`              | predicate decidably true under the bindings |
| `Deny(why)`          | predicate decidably false; `why` carries the offending sub-expression |
| `Inconclusive(why)`  | a leaf couldn't be evaluated — missing binding, type mismatch, unsupported op |

**At a trust boundary, `Inconclusive` is a deny.** Don't write
`if verdict_is_allow(v) then run else inconclusive_means_allow`.
Surface the reason to the caller's diagnostics.

---

## Evaluator is strict, not short-circuit

`and` / `or` evaluate both operands. This is deliberate:

- An `Inconclusive` predicate is usually a typo (`u.aged` instead of
  `u.age`) — surfacing every reason at once helps the author fix
  the actual cause rather than chase the first miss.
- The SMT-LIB exporter doesn't care about evaluation order; the
  semantics line up.

If you genuinely want short-circuit, write it as an `EImplies`
(`A => B` only evaluates `B` if `A` is true).

---

## Randomized check generators

`check_random(spec, n, seed)` is **deterministic** given the seed —
two runs with the same seed produce the same outcome. v0.1
generators are bounded:

- `QInt`   → `[-1000, 1000]`
- `QStr`   → fixed pool of 10 representative strings
- `QBool`  → uniform
- `QFloat` → `[-100.0, 100.0]`
- `QList`  → empty list (placeholder; recursive list gen lands in v0.2)
- `QRecord` → walks the field types; one level of nesting

Don't reach for `std.random` directly in spec-evaluating code; the
seed is the contract. For un-seeded fuzz runs, pre-seed from
`crypto.random` in the caller and pass the seed in.

---

## SMT-LIB export — keep the vocabulary stable

The test suite asserts on visible substrings:

```
(set-logic ALL)
(declare-const x Int)
(assert (not ...))
(check-sat)
(get-model)
```

Renaming a section header (`; Asserts the negation ...` → `; This
script asserts...`) won't break tests, but reordering the
`declare-const` block before `(set-logic ALL)` will. The output is
consumed by external Z3 — sort-name vocabulary (`Int`, `String`,
`Bool`, `Real`) is fixed.

---

## Capability gating — the integration point

```lex
match cap.gate(skill.capability, bindings) {
  Allow             => dispatch_handler(),
  Deny(reason)      => respond_403_spec_denied(reason),
  Inconclusive(why) => respond_403_spec_denied(why),
}
```

`lex-agent` uses `-32099 spec-denied` for the JSON-RPC error code.
`lex-llm` filters the capability out of the model's tool list (or
annotates "currently unavailable"). Either way, the consumer is
the receiver: the gate doesn't trust the sender's earlier verdict.

---

## Effects

Nothing in `src/` should declare effects. The randomized check is
seed-driven; the SMT-LIB exporter is a string builder; the
evaluator is a pure fold. Anything that needs IO belongs in
consumer code (the A2A server, the LLM-side tool filter), not in
this package.

---

## Tests

```bash
lex test
```

3 suites covering: predicate eval (Allow / Deny / Inconclusive
paths, binop arithmetic, record-field access, And / Or / Not /
Implies), SMT-LIB shape (set-logic, declare-const, assert-not
wrapper, op renaming for `==` / `!=`, record field-name
mangling), randomized property check (Holds, Falsified,
deterministic seeding, counter-example rendering).

---

## Where to read more

- `README.md` — high-level pitch + module table
- `src/` — every module is short and documented inline
- [lex-agent](https://github.com/alpibrusl/lex-agent) — the
  server-side consumer (gates incoming A2A calls)
- [lex-llm](https://github.com/alpibrusl/lex-llm) — the
  client-side consumer (filters outbound capabilities before the
  model sees them)
