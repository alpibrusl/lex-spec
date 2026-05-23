# lex-spec — Spec ADT
#
# A `Spec` is a value: a named precondition over a small set of
# universally-quantified bindings. The shape mirrors the design
# extracted from the original Rust `spec-checker` crate, ported to
# pure Lex so the same value can be evaluated, property-checked,
# and re-emitted as SMT-LIB without a host-language detour.
#
# A Spec is what hangs off an A2A `Capability.precondition`:
# both ends — the server before dispatching an inbound skill, and
# the LLM-side client before exposing an outbound capability to the
# model — `eval` the same value against the same bindings.
#
# Effects: none. Specs are values; eval / property check / SMT
# export are pure folds.

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "std.float" as float

# ---- Types --------------------------------------------------------
#
# `Type` is the minimal type lattice the predicate language quantifies
# over. Records are nominal — referenced by `name` and resolved at
# eval time against the supplied bindings.
type Type = TInt | TStr | TBool | TFloat | TRecord(Str) | TList(Type)

fn type_name(t :: Type) -> Str {
  match t {
    TInt => "Int",
    TStr => "Str",
    TBool => "Bool",
    TFloat => "Float",
    TRecord(n) => n,
    TList(_) => "List",
  }
}

# ---- Values -------------------------------------------------------
#
# `SpecValue` is the runtime universe the evaluator walks over. It's
# the value half of `Type` — every typed leaf has a payload variant.
# Records are name → SpecValue maps; lists are SpecValue lists.
type SpecValue = VInt(Int) | VStr(Str) | VBool(Bool) | VFloat(Float) | VRecord(RecordValue) | VList(List[SpecValue]) | VNull

type RecordValue = { name :: Str, fields :: List[(Str, SpecValue)] }

# ---- Quantifiers --------------------------------------------------
#
# A spec is implicitly `forall <quantifiers>. predicate`. v0.1 only
# carries universally-quantified bindings (existentials are deferred —
# they need explicit witness search at eval time).
type SpecQuant = QRecord({ name :: Str, fields :: List[{ name :: Str, ty :: Type }] }) | QInt(Str) | QStr(Str) | QBool(Str) | QFloat(Str) | QList({ name :: Str, elem :: Type })

fn quant_binding_name(q :: SpecQuant) -> Str {
  match q {
    QRecord(r) => r.name,
    QInt(n) => n,
    QStr(n) => n,
    QBool(n) => n,
    QFloat(n) => n,
    QList(l) => l.name,
  }
}

# ---- Predicate expressions ----------------------------------------
#
# `SpecExpr` is the small expression language predicates are written
# in. It's deliberately tight: field lookup, constants, binops, and
# the three boolean connectives. The eval semantics return a Verdict,
# not Bool, so callers can distinguish "predicate false" from
# "predicate inconclusive because a binding was missing".
type SpecExpr = EField({ binding :: Str, field :: Str }) | EVar(Str) | EConst(SpecValue) | EBinop({ op :: Str, lhs :: SpecExpr, rhs :: SpecExpr }) | ENot(SpecExpr) | EAnd((SpecExpr, SpecExpr)) | EOr((SpecExpr, SpecExpr)) | EImplies((SpecExpr, SpecExpr))

fn op_eq() -> Str {
  "=="
}

fn op_neq() -> Str {
  "!="
}

fn op_lt() -> Str {
  "<"
}

fn op_le() -> Str {
  "<="
}

fn op_gt() -> Str {
  ">"
}

fn op_ge() -> Str {
  ">="
}

fn op_add() -> Str {
  "+"
}

fn op_sub() -> Str {
  "-"
}

fn op_mul() -> Str {
  "*"
}

fn op_mod() -> Str {
  "%"
}

# ---- Spec ---------------------------------------------------------
type Spec = { name :: Str, quantifiers :: List[SpecQuant], predicate :: SpecExpr }

# ---- Verdict ------------------------------------------------------
#
# The three-valued return of `eval`. `Inconclusive(reason)` is what
# A2A consumers translate into a `spec-denied` rejection — "I cannot
# prove this holds, so deny by default" is the safe stance for
# capability gating at trust boundaries.
type Verdict = Allow | Deny(Str) | Inconclusive(Str)

fn verdict_is_allow(v :: Verdict) -> Bool {
  match v {
    Allow => true,
    _ => false,
  }
}

fn verdict_reason(v :: Verdict) -> Str {
  match v {
    Allow => "",
    Deny(r) => r,
    Inconclusive(r) => r,
  }
}

fn verdict_label(v :: Verdict) -> Str {
  match v {
    Allow => "allow",
    Deny(_) => "deny",
    Inconclusive(_) => "inconclusive",
  }
}

# ---- Binding maps -------------------------------------------------
#
# Eval-time bindings are passed as a list of (name → SpecValue) pairs
# so the caller controls iteration order. The helper below resolves a
# binding by name; `None` means the binding wasn't supplied and the
# expression must be ruled `Inconclusive`.
fn lookup_binding(bindings :: List[(Str, SpecValue)], name :: Str) -> Option[SpecValue] {
  list.fold(bindings, None, fn (acc :: Option[SpecValue], pair :: (Str, SpecValue)) -> Option[SpecValue] {
    match acc {
      Some(_) => acc,
      None => match pair {
        (k, v) => if k == name {
          Some(v)
        } else {
          None
        },
      },
    }
  })
}

# Pull a field out of a record-shaped value. Returns `None` if the
# value isn't a record or the field is absent.
fn record_field(rec :: RecordValue, field :: Str) -> Option[SpecValue] {
  list.fold(rec.fields, None, fn (acc :: Option[SpecValue], pair :: (Str, SpecValue)) -> Option[SpecValue] {
    match acc {
      Some(_) => acc,
      None => match pair {
        (k, v) => if k == field {
          Some(v)
        } else {
          None
        },
      },
    }
  })
}

# ---- Pretty-printers ----------------------------------------------
#
# Useful for debugging and for the SMT-LIB exporter, which delegates
# to these for non-ambiguous constant rendering.
fn show_value(v :: SpecValue) -> Str {
  match v {
    VInt(n) => int.to_str(n),
    VStr(s) => str.concat("\"", str.concat(s, "\"")),
    VBool(b) => if b {
      "true"
    } else {
      "false"
    },
    VFloat(x) => float.to_str(x),
    VRecord(r) => str.concat("record:", r.name),
    VList(_) => "list:[...]",
    VNull => "null",
  }
}

# Predicate pretty-printer — round-trippable enough to drop into
# diagnostics. Not a parser target.
fn show_expr(e :: SpecExpr) -> Str {
  match e {
    EField(f) => str.concat(f.binding, str.concat(".", f.field)),
    EVar(n) => n,
    EConst(v) => show_value(v),
    EBinop(b) => str.concat("(", str.concat(show_expr(b.lhs), str.concat(" ", str.concat(b.op, str.concat(" ", str.concat(show_expr(b.rhs), ")")))))),
    ENot(x) => str.concat("(not ", str.concat(show_expr(x), ")")),
    EAnd(a, b) => str.concat("(", str.concat(show_expr(a), str.concat(" and ", str.concat(show_expr(b), ")")))),
    EOr(a, b) => str.concat("(", str.concat(show_expr(a), str.concat(" or ", str.concat(show_expr(b), ")")))),
    EImplies(a, b) => str.concat("(", str.concat(show_expr(a), str.concat(" => ", str.concat(show_expr(b), ")")))),
  }
}

