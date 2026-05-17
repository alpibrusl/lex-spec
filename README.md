# lex-spec

A **capability-precondition + spec DSL** for [lex-lang](https://github.com/alpibrusl/lex-lang),
written in pure Lex. Same evaluator, same DSL, same property check, same
SMT-LIB export — wired through the A2A `Capability` shape that
[lex-agent](https://github.com/alpibrusl/lex-agent) and
[lex-llm](https://github.com/alpibrusl/lex-llm) both consume.

The "evaluate at both ends" property is the win: the receiver does not
trust the sender's gate. `lex-agent` runs `spec.eval` server-side before
dispatching an inbound skill; `lex-llm` runs the same `spec.eval` on the
client before exposing an outbound capability to the model's tool list.

## Install

```toml
# lex.toml
[dependencies]
"lex-spec" = { git = "https://github.com/alpibrusl/lex-spec" }
```

## At a glance

```lex
import "lex-spec/spec"        as sp
import "lex-spec/eval"        as ev
import "lex-spec/check"       as ck
import "lex-spec/smt"         as smt
import "lex-spec/capability"  as cap

# A spec is a value. forall u :: { age :: Int }. u.age >= 13.
fn age_ok() -> sp.Spec {
  {
    name: "user_age_ok",
    quantifiers: [
      QRecord({ name: "u", fields: [{ name: "age", ty: TInt }] }),
    ],
    predicate: EBinop({
      op: ">=",
      lhs: EField({ binding: "u", field: "age" }),
      rhs: EConst(VInt(13)),
    }),
  }
}

# Evaluate against a concrete record:
ev.eval(age_ok(),
  [("u", VRecord({ name: "User", fields: [("age", VInt(21))] }))])
# => Allow

# Property-check it randomly (200 cases, seed 42):
ck.check_random(age_ok(), 200, 42)
# => Holds(200) | Falsified({...}) | Indeterminate({...})

# Emit a Z3-compatible script (pipe into `z3 -in`):
smt.to_smt_lib(age_ok())
```

## Capability gating — the integration point

```lex
let send_money := cap.outbound(
  "transfer_funds",
  "Transfer money to another account.",
  transfer_params_schema()
)

# Attach the precondition once; both ends evaluate it.
let guarded := cap.with_precondition(send_money, balance_ok_spec())

# Server side (lex-agent): before dispatch
match cap.gate(guarded, [("acct", account_value)]) {
  Allow             => dispatch(),
  Deny(reason)      => json_rpc_error(403, reason),     # "spec-denied"
  Inconclusive(why) => json_rpc_error(403, why),
}

# Client side (lex-llm): before tool-list exposure
if cap.allows(guarded, [("acct", account_value)]) {
  expose_in_tool_list()
} else {
  annotate_unavailable()
}
```

## Module surface

| Module | Purpose |
|---|---|
| `src/spec.lex`       | `Spec`, `SpecExpr`, `SpecQuant`, `SpecValue`, `Type`, `Verdict`; pretty-printers |
| `src/eval.lex`       | `eval(spec, bindings) -> Verdict` — three-valued: `Allow` / `Deny` / `Inconclusive` |
| `src/check.lex`      | `check_random(spec, n, seed)` — deterministic property check; returns `Holds` / `Falsified(counter)` / `Indeterminate(counter)` |
| `src/smt.lex`        | `to_smt_lib(spec)` — Z3-friendly script asserting the negation of the predicate |
| `src/capability.lex` | `Capability` ADT with `precondition :: Option[Spec]` + `gate` / `allows` evaluators |

Every `src/*` module is pure (no declared effects). The randomized
check is `seed`-driven so reproducible across runs and platforms.

## The Spec language

```lex
type Spec = {
  name :: Str,
  quantifiers :: List[SpecQuant],
  predicate :: SpecExpr,
}

type SpecQuant =
    QRecord({ name :: Str, fields :: List[{ name :: Str, ty :: Type }] })
  | QInt(Str)
  | QStr(Str)
  | QBool(Str)
  | QFloat(Str)
  | QList({ name :: Str, elem :: Type })

type SpecExpr =
    EField({ binding :: Str, field :: Str })   # u.age
  | EVar(Str)                                  # plain binding ref
  | EConst(SpecValue)
  | EBinop({ op :: Str, lhs :: SpecExpr, rhs :: SpecExpr })   # ==, !=, <, <=, >, >=, +, -, *, %
  | ENot(SpecExpr)
  | EAnd(SpecExpr, SpecExpr)
  | EOr(SpecExpr, SpecExpr)
  | EImplies(SpecExpr, SpecExpr)
```

The predicate language is deliberately small. Adding a new operator
means one branch in `eval.lex`'s `eval_binop` and one branch in
`smt.lex`'s `to_smt_op` — that's the "small total surface" Lex
design rule.

### Verdict semantics

```lex
type Verdict =
    Allow
  | Deny(Str)
  | Inconclusive(Str)
```

`Inconclusive` is what callers translate into "deny by default" at
trust boundaries. The reason carries the offending sub-expression
(missing binding, type mismatch, unsupported op) so diagnostics
flow without re-walking the AST.

### Why `eval` is strict, not short-circuit

`and` / `or` evaluate both operands — surfacing every inconclusive
reason at once. The trade-off vs. classical short-circuit is
explicit; the SMT-LIB exporter doesn't care about evaluation order.

## Examples

```bash
# Demo: evaluate + property-check the same spec.
lex run examples/01_finds_counter_example.lex demo

# Emit SMT-LIB and pipe to z3 (requires z3 installed):
lex run examples/02_smt_export.lex print | z3 -in
# Expected: `unsat` — the transfer-preserves-total spec holds.
```

## Tests

```bash
lex test
```

Coverage: predicate eval (Allow / Deny / Inconclusive paths), binop
arithmetic, record-field access, And / Or / Not / Implies, SMT-LIB
output shape (set-logic, declare-const, assert-not wrapper, op
renaming for `==` / `!=`), record field-name mangling, randomized
property check (Holds, Falsified, deterministic seeding,
counter-example rendering).

## What's NOT in v0.1

- In-process Z3 — `to_smt_lib` returns a script; callers shell out.
- Existential quantifiers — every binding is universally quantified.
- Spec composition operators (`compose`, `weaken`, `strengthen`).
- Spec migration tooling.
- Nested record / list generators for `check_random` — the
  random generator stops at one level of record nesting.

These mirror the "out of scope" list in issue #483; v0.2 will
revisit each.

## License

EUPL-1.2 — matches the parent `lex-lang` project.
