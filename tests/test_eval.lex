# Tests for `src/eval.lex` — predicate evaluation.

import "std.list" as list

import "std.str" as str

import "../src/spec" as sp

import "../src/eval" as ev

# A predicate that holds: `x + 1 > x`.
fn spec_simple_lt() -> sp.Spec {
  { name: "x_plus_one_gt_x", quantifiers: [QInt("x")], predicate: EBinop({ op: ">", lhs: EBinop({ op: "+", lhs: EVar("x"), rhs: EConst(VInt(1)) }), rhs: EVar("x") }) }
}

# A predicate over a record binding.
fn spec_user_age_ok() -> sp.Spec {
  { name: "user_age_ok", quantifiers: [QRecord({ name: "u", fields: [{ name: "age", ty: TInt }] })], predicate: EBinop({ op: ">=", lhs: EField({ binding: "u", field: "age" }), rhs: EConst(VInt(13)) }) }
}

# Helpers -----------------------------------------------------------
fn binding_x(n :: Int) -> List[(Str, sp.SpecValue)] {
  [("x", VInt(n))]
}

fn binding_user(age :: Int) -> List[(Str, sp.SpecValue)] {
  [("u", VRecord({ name: "User", fields: [("age", VInt(age))] }))]
}

# Cases -------------------------------------------------------------
fn eval_allow_simple() -> Result[Unit, Str] {
  let v := ev.eval(spec_simple_lt(), binding_x(5))
  if sp.verdict_is_allow(v) {
    Ok(())
  } else {
    Err(sp.verdict_label(v))
  }
}

fn eval_deny_record() -> Result[Unit, Str] {
  let v := ev.eval(spec_user_age_ok(), binding_user(7))
  match v {
    Deny(_) => Ok(()),
    other => Err(str.concat("expected Deny, got: ", sp.verdict_label(other))),
  }
}

fn eval_allow_record() -> Result[Unit, Str] {
  let v := ev.eval(spec_user_age_ok(), binding_user(21))
  if sp.verdict_is_allow(v) {
    Ok(())
  } else {
    Err(sp.verdict_label(v))
  }
}

fn eval_inconclusive_missing() -> Result[Unit, Str] {
  let v := ev.eval(spec_user_age_ok(), [])
  match v {
    Inconclusive(_) => Ok(()),
    other => Err(str.concat("expected Inconclusive, got: ", sp.verdict_label(other))),
  }
}

fn eval_and_or() -> Result[Unit, Str] {
  let spec := { name: "and_or_demo", quantifiers: [QInt("x")], predicate: EAnd(EBinop({ op: ">", lhs: EVar("x"), rhs: EConst(VInt(0)) }), EOr(EBinop({ op: "<", lhs: EVar("x"), rhs: EConst(VInt(100)) }), EConst(VBool(false)))) }
  let allow := ev.eval(spec, [("x", VInt(50))])
  let deny := ev.eval(spec, [("x", VInt(0 - 5))])
  match sp.verdict_is_allow(allow) {
    true => match deny {
      Deny(_) => Ok(()),
      _ => Err("expected Deny on negative input"),
    },
    false => Err("expected Allow on 50"),
  }
}

fn eval_implies() -> Result[Unit, Str] {
  let spec := { name: "implies_demo", quantifiers: [QInt("x")], predicate: EImplies(EBinop({ op: ">", lhs: EVar("x"), rhs: EConst(VInt(0)) }), EBinop({ op: ">=", lhs: EVar("x"), rhs: EConst(VInt(1)) })) }
  let r := ev.eval(spec, [("x", VInt(5))])
  if sp.verdict_is_allow(r) {
    Ok(())
  } else {
    Err("implies should hold")
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [eval_allow_simple(), eval_deny_record(), eval_allow_record(), eval_inconclusive_missing(), eval_and_or(), eval_implies()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

