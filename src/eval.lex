# lex-spec — predicate evaluator
#
# `eval(spec, bindings)` walks `spec.predicate` under the given
# bindings and returns a three-valued `Verdict`. The contract is:
#
#   - `Allow`         — every leaf evaluated; predicate true.
#   - `Deny(reason)`  — every leaf evaluated; predicate false; the
#                       reason carries the offending sub-expression
#                       so callers can render diagnostics.
#   - `Inconclusive(why)` — some leaf couldn't be evaluated (missing
#                       binding, type mismatch, unsupported op).
#                       A2A consumers treat this as Deny at the
#                       trust boundary.
#
# Effects: none for eval. eval_and_log adds [sql, time] for trail.

import "std.str" as str

import "./spec" as sp

import "lex-trail/log" as trail

import "lex-trail/kinds" as kinds

# ---- Public entry points ------------------------------------------
fn eval(spec :: sp.Spec, bindings :: List[(Str, sp.SpecValue)]) -> sp.Verdict {
  let r := eval_expr(spec.predicate, bindings)
  match r {
    EvalBool(true) => Allow,
    EvalBool(false) => Deny(str.concat("predicate false: ", sp.show_expr(spec.predicate))),
    EvalInc(why) => Inconclusive(why),
    EvalVal(_) => Inconclusive("predicate did not reduce to Bool"),
  }
}

fn eval_and_log(spec :: sp.Spec, bindings :: List[(Str, sp.SpecValue)], log :: trail.Log, parent :: Option[Str]) -> [sql, time] sp.Verdict {
  let verdict := eval(spec, bindings)
  let kind := match verdict {
    Allow => kinds.spec_allowed(),
    _ => kinds.spec_denied(),
  }
  let payload := spec_payload(spec.name, verdict)
  let trail_result := trail.append(log, kind, parent, payload)
  verdict
}

fn spec_payload(spec_name :: Str, verdict :: sp.Verdict) -> Str
  examples {
    spec_payload("my_spec", Allow) => "{\"spec\":\"my_spec\"}"
  }
{
  match verdict {
    Allow => str.join(["{\"spec\":\"", spec_name, "\"}"], ""),
    _ => str.join(["{\"spec\":\"", spec_name, "\",\"reason\":\"", sp.verdict_reason(verdict), "\"}"], ""),
  }
}

# ---- Internal eval result -----------------------------------------
#
# `EvalResult` is the inner three-way: a raw value, a boolean, or an
# inconclusive marker. Keeping the bool variant separate from the
# generic value lets the top-level predicate enforce "must reduce
# to Bool" without re-pattern-matching.
type EvalResult = EvalVal(sp.SpecValue) | EvalBool(Bool) | EvalInc(Str)

fn eval_expr(e :: sp.SpecExpr, bindings :: List[(Str, sp.SpecValue)]) -> EvalResult {
  match e {
    EField(f) => eval_field(f.binding, f.field, bindings),
    EVar(n) => match sp.lookup_binding(bindings, n) {
      None => EvalInc(str.concat("unbound: ", n)),
      Some(v) => to_eval_result(v),
    },
    EConst(v) => to_eval_result(v),
    EBinop(b) => eval_binop(b.op, b.lhs, b.rhs, bindings),
    ENot(x) => {
      let inner := eval_expr(x, bindings)
      match inner {
        EvalBool(b) => EvalBool(not b),
        EvalInc(r) => EvalInc(r),
        EvalVal(_) => EvalInc("`not` applied to non-Bool"),
      }
    },
    EAnd(a, b) => and_strict(eval_expr(a, bindings), eval_expr(b, bindings)),
    EOr(a, b) => or_strict(eval_expr(a, bindings), eval_expr(b, bindings)),
    EImplies(a, b) => {
      let av := eval_expr(a, bindings)
      match av {
        EvalBool(false) => EvalBool(true),
        EvalBool(true) => eval_expr(b, bindings),
        EvalInc(r) => EvalInc(r),
        EvalVal(_) => EvalInc("`=>` antecedent non-Bool"),
      }
    },
  }
}

# ---- Field access -------------------------------------------------
fn eval_field(binding :: Str, field :: Str, bindings :: List[(Str, sp.SpecValue)]) -> EvalResult {
  match sp.lookup_binding(bindings, binding) {
    None => EvalInc(str.concat("unbound: ", binding)),
    Some(v) => match v {
      VRecord(rec) => match sp.record_field(rec, field) {
        None => EvalInc(str.concat("missing field: ", str.concat(binding, str.concat(".", field)))),
        Some(x) => to_eval_result(x),
      },
      _ => EvalInc(str.concat("not a record: ", binding)),
    },
  }
}

# ---- Binops -------------------------------------------------------
#
# Each branch picks a typed evaluator based on the operator string.
# Unknown ops are inconclusive — never a runtime panic.
fn eval_binop(op :: Str, lhs :: sp.SpecExpr, rhs :: sp.SpecExpr, bindings :: List[(Str, sp.SpecValue)]) -> EvalResult {
  let l := eval_expr(lhs, bindings)
  let r := eval_expr(rhs, bindings)
  if op == "==" {
    eq(l, r)
  } else {
    if op == "!=" {
      neq(l, r)
    } else {
      if op == "<" {
        cmp_int(l, r, "<")
      } else {
        if op == "<=" {
          cmp_int(l, r, "<=")
        } else {
          if op == ">" {
            cmp_int(l, r, ">")
          } else {
            if op == ">=" {
              cmp_int(l, r, ">=")
            } else {
              if op == "+" {
                arith_int(l, r, "+")
              } else {
                if op == "-" {
                  arith_int(l, r, "-")
                } else {
                  if op == "*" {
                    arith_int(l, r, "*")
                  } else {
                    if op == "%" {
                      arith_int(l, r, "%")
                    } else {
                      EvalInc(str.concat("unsupported op: ", op))
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

# Polymorphic equality over the SpecValue universe. Mismatched
# variants → false (not inconclusive); inconclusive operands
# propagate.
fn eq(l :: EvalResult, r :: EvalResult) -> EvalResult {
  match l {
    EvalInc(s) => EvalInc(s),
    EvalBool(_) => match r {
      EvalInc(s) => EvalInc(s),
      _ => EvalBool(values_equal(unwrap_value(l), unwrap_value(r))),
    },
    EvalVal(_) => match r {
      EvalInc(s) => EvalInc(s),
      _ => EvalBool(values_equal(unwrap_value(l), unwrap_value(r))),
    },
  }
}

fn neq(l :: EvalResult, r :: EvalResult) -> EvalResult {
  let e := eq(l, r)
  match e {
    EvalBool(b) => EvalBool(not b),
    other => other,
  }
}

fn values_equal(a :: sp.SpecValue, b :: sp.SpecValue) -> Bool {
  match a {
    VInt(n) => match b {
      VInt(m) => n == m,
      _ => false,
    },
    VStr(s) => match b {
      VStr(t) => s == t,
      _ => false,
    },
    VBool(x) => match b {
      VBool(y) => x == y,
      _ => false,
    },
    VFloat(x) => match b {
      VFloat(y) => x == y,
      _ => false,
    },
    VNull => match b {
      VNull => true,
      _ => false,
    },
    VRecord(r1) => match b {
      VRecord(r2) => r1.name == r2.name,
      _ => false,
    },
    VList(_) => false,
  }
}

# Apply a comparison op to two int operands. Returns Inconclusive on
# non-Int operands; logically separates "structural type mismatch"
# from "predicate decided false".
fn cmp_int(l :: EvalResult, r :: EvalResult, op :: Str) -> EvalResult {
  match l {
    EvalInc(s) => EvalInc(s),
    EvalBool(_) => EvalInc("comparison expects Int operands"),
    EvalVal(lv) => match r {
      EvalInc(s) => EvalInc(s),
      EvalBool(_) => EvalInc("comparison expects Int operands"),
      EvalVal(rv) => match lv {
        VInt(a) => match rv {
          VInt(b) => EvalBool(apply_cmp(op, a, b)),
          _ => EvalInc("comparison expects Int operands"),
        },
        _ => EvalInc("comparison expects Int operands"),
      },
    },
  }
}

fn apply_cmp(op :: Str, a :: Int, b :: Int) -> Bool {
  if op == "<" {
    a < b
  } else {
    if op == "<=" {
      a <= b
    } else {
      if op == ">" {
        a > b
      } else {
        if op == ">=" {
          a >= b
        } else {
          false
        }
      }
    }
  }
}

fn arith_int(l :: EvalResult, r :: EvalResult, op :: Str) -> EvalResult {
  match l {
    EvalInc(s) => EvalInc(s),
    EvalBool(_) => EvalInc("arithmetic expects Int operands"),
    EvalVal(lv) => match r {
      EvalInc(s) => EvalInc(s),
      EvalBool(_) => EvalInc("arithmetic expects Int operands"),
      EvalVal(rv) => match lv {
        VInt(a) => match rv {
          VInt(b) => apply_arith(op, a, b),
          _ => EvalInc("arithmetic expects Int operands"),
        },
        _ => EvalInc("arithmetic expects Int operands"),
      },
    },
  }
}

fn apply_arith(op :: Str, a :: Int, b :: Int) -> EvalResult {
  if op == "+" {
    EvalVal(VInt(a + b))
  } else {
    if op == "-" {
      EvalVal(VInt(a - b))
    } else {
      if op == "*" {
        EvalVal(VInt(a * b))
      } else {
        if op == "%" {
          if b == 0 {
            EvalInc("modulo by zero")
          } else {
            EvalVal(VInt(a - a / b * b))
          }
        } else {
          EvalInc(str.concat("unsupported arith op: ", op))
        }
      }
    }
  }
}

# ---- Strict boolean connectives -----------------------------------
#
# v0.1 evaluates both sides — no short-circuit. Reasoning: in an
# inconclusive predicate, callers want to know *all* the reasons it
# couldn't decide, not just the first one. The trade-off vs. classic
# logical short-circuit is explicit; the SMT-LIB exporter doesn't
# care.
fn and_strict(l :: EvalResult, r :: EvalResult) -> EvalResult {
  match l {
    EvalBool(false) => EvalBool(false),
    EvalBool(true) => match r {
      EvalBool(b) => EvalBool(b),
      EvalInc(s) => EvalInc(s),
      EvalVal(_) => EvalInc("`and` rhs non-Bool"),
    },
    EvalInc(s) => match r {
      EvalBool(false) => EvalBool(false),
      _ => EvalInc(s),
    },
    EvalVal(_) => EvalInc("`and` lhs non-Bool"),
  }
}

fn or_strict(l :: EvalResult, r :: EvalResult) -> EvalResult {
  match l {
    EvalBool(true) => EvalBool(true),
    EvalBool(false) => match r {
      EvalBool(b) => EvalBool(b),
      EvalInc(s) => EvalInc(s),
      EvalVal(_) => EvalInc("`or` rhs non-Bool"),
    },
    EvalInc(s) => match r {
      EvalBool(true) => EvalBool(true),
      _ => EvalInc(s),
    },
    EvalVal(_) => EvalInc("`or` lhs non-Bool"),
  }
}

# ---- Helpers ------------------------------------------------------
fn to_eval_result(v :: sp.SpecValue) -> EvalResult {
  match v {
    VBool(b) => EvalBool(b),
    _ => EvalVal(v),
  }
}

fn unwrap_value(r :: EvalResult) -> sp.SpecValue {
  match r {
    EvalVal(v) => v,
    EvalBool(b) => VBool(b),
    EvalInc(_) => VNull,
  }
}

