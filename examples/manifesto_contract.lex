# lex-spec — manifesto demo: a spec is a contract you verify, not a body you read
#
# Manifesto §IV:
#   "The right interface for an agent is ... a small formal specification
#    ... from which it can generate a correct implementation. Not a
#    reference implementation to imitate, but a contract to satisfy."
#   "You would keep [property checks] ... Trust without comprehension."
#
# The arbiter of trust here is the randomized property check — not a
# human reading the predicate and convincing themselves. A correct
# invariant HOLDS over 200 random cases; a plausible-but-wrong one is
# FALSIFIED, and the checker hands back the exact counterexample.
#
# Self-validating: the `examples {}` blocks below assert the verdicts,
# and `check_random` is pure (the seed is supplied), so `lex check`
# runs them and *is* the proof. No runtime, no network, no API key.
#
# Print the counterexample the checker found (the effects come from the
# trail-logging path eval.lex pulls in transitively, not from the check):
#   lex run --allow-effects sql,fs_write,time examples/manifesto_contract.lex demo

import "std.str" as str

import "std.io" as io

import "../src/spec" as sp

import "../src/check" as ck

# A CORRECT contract: addition commutes. forall x, y :: Int. x+y == y+x.
# A randomized check over 200 cases finds no counterexample.
fn addition_commutes() -> sp.Spec {
  { name: "addition_commutes", quantifiers: [QInt("x"), QInt("y")], predicate: EBinop({ op: "==", lhs: EBinop({ op: "+", lhs: EVar("x"), rhs: EVar("y") }), rhs: EBinop({ op: "+", lhs: EVar("y"), rhs: EVar("x") }) }) }
}

# A WRONG contract someone might plausibly write: that subtraction
# commutes. forall x, y :: Int. x-y == y-x. False whenever x != y —
# the checker surfaces a concrete counterexample.
fn subtraction_commutes() -> sp.Spec {
  { name: "subtraction_commutes", quantifiers: [QInt("x"), QInt("y")], predicate: EBinop({ op: "==", lhs: EBinop({ op: "-", lhs: EVar("x"), rhs: EVar("y") }), rhs: EBinop({ op: "-", lhs: EVar("y"), rhs: EVar("x") }) }) }
}

# SELF-VALIDATING CLAIM 1: the correct contract holds under check.
fn correct_contract_holds() -> Str
  examples {
    correct_contract_holds() => "holds"
  }
{
  ck.check_result_label(ck.check_random(addition_commutes(), 200, 42))
}

# SELF-VALIDATING CLAIM 2: the broken contract is caught — verification,
# not comprehension, is what rejected it.
fn broken_contract_is_falsified() -> Str
  examples {
    broken_contract_is_falsified() => "falsified"
  }
{
  ck.check_result_label(ck.check_random(subtraction_commutes(), 200, 42))
}

fn demo() -> Str {
  let ok := ck.render_check_result(ck.check_random(addition_commutes(), 200, 42))
  let bad := ck.render_check_result(ck.check_random(subtraction_commutes(), 200, 42))
  str.concat("contract: addition_commutes\n", str.concat(ok, str.concat("\n\ncontract: subtraction_commutes\n", bad)))
}

