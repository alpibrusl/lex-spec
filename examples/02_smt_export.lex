# lex-spec — SMT-LIB export demo
#
# Emits a Z3-friendly SMT-LIB 2 script for a spec, ready to pipe
# into `z3 -in`. If z3 returns `unsat`, the spec holds universally;
# `sat` means a counter-example exists (the printed model is it).
#
# Run:
#   lex run examples/02_smt_export.lex print
#
# Pipe through z3:
#   lex run examples/02_smt_export.lex print | z3 -in

import "../src/spec" as sp
import "../src/smt"  as smt

fn balance_invariant() -> sp.Spec {
  {
    name: "transfer_keeps_total",
    quantifiers: [
      QInt("a_before"),
      QInt("b_before"),
      QInt("amount"),
    ],
    # Predicate: (a_before + b_before) == ((a_before - amount) + (b_before + amount))
    # — total balance preserved across a transfer.
    predicate: EBinop({
      op: "==",
      lhs: EBinop({ op: "+", lhs: EVar("a_before"), rhs: EVar("b_before") }),
      rhs: EBinop({
        op: "+",
        lhs: EBinop({ op: "-", lhs: EVar("a_before"), rhs: EVar("amount") }),
        rhs: EBinop({ op: "+", lhs: EVar("b_before"), rhs: EVar("amount") }),
      }),
    }),
  }
}

fn print() -> Str {
  smt.to_smt_lib(balance_invariant())
}
