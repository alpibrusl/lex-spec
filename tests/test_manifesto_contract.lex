# CI-covered self-validation for the manifesto spec-as-contract demo
# (examples/manifesto_contract.lex). Asserts the same property under
# `lex test`: a correct invariant HOLDS, a broken one is FALSIFIED.
# Verification — not a human reading the predicate — is the arbiter.

import "std.str" as str

import "std.list" as list

import "../src/spec" as sp

import "../src/check" as ck

fn addition_commutes() -> sp.Spec {
  { name: "addition_commutes", quantifiers: [QInt("x"), QInt("y")], predicate: EBinop({ op: "==", lhs: EBinop({ op: "+", lhs: EVar("x"), rhs: EVar("y") }), rhs: EBinop({ op: "+", lhs: EVar("y"), rhs: EVar("x") }) }) }
}

fn subtraction_commutes() -> sp.Spec {
  { name: "subtraction_commutes", quantifiers: [QInt("x"), QInt("y")], predicate: EBinop({ op: "==", lhs: EBinop({ op: "-", lhs: EVar("x"), rhs: EVar("y") }), rhs: EBinop({ op: "-", lhs: EVar("y"), rhs: EVar("x") }) }) }
}

fn correct_contract_holds() -> Result[Unit, Str] {
  match ck.check_random(addition_commutes(), 200, 42) {
    Holds(_) => Ok(()),
    Falsified(c) => Err(str.concat("expected holds, got falsified: ", ck.render_counter(c))),
    Indeterminate(c) => Err(str.concat("expected holds, got indeterminate: ", ck.render_counter(c))),
  }
}

fn broken_contract_is_falsified() -> Result[Unit, Str] {
  match ck.check_random(subtraction_commutes(), 200, 42) {
    Falsified(_) => Ok(()),
    Holds(_) => Err("expected falsified, but the broken contract held"),
    Indeterminate(c) => Err(str.concat("expected falsified, got indeterminate: ", ck.render_counter(c))),
  }
}

fn run_all() -> Unit {
  let results := [correct_contract_holds(), broken_contract_is_falsified()]
  let failures := list.fold(results, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
  if failures == 0 {
    ()
  } else {
    let __discard := 1 / 0
    ()
  }
}

