# Tests for `src/smt.lex` — SMT-LIB 2 export.

import "std.list" as list
import "std.str"  as str

import "../src/spec" as sp
import "../src/smt"  as smt

fn small_spec() -> sp.Spec {
  {
    name: "demo",
    quantifiers: [QInt("x")],
    predicate: EBinop({
      op: ">",
      lhs: EBinop({ op: "+", lhs: EVar("x"), rhs: EConst(VInt(1)) }),
      rhs: EVar("x"),
    }),
  }
}

fn record_spec() -> sp.Spec {
  {
    name: "user_age",
    quantifiers: [
      QRecord({
        name: "u",
        fields: [{ name: "age", ty: TInt }, { name: "name", ty: TStr }],
      }),
    ],
    predicate: EBinop({
      op: ">=",
      lhs: EField({ binding: "u", field: "age" }),
      rhs: EConst(VInt(13)),
    }),
  }
}

fn includes_set_logic() -> Result[Unit, Str] {
  let s := smt.to_smt_lib(small_spec())
  if str.contains(s, "(set-logic ALL)") { Ok(()) } else { Err("missing set-logic") }
}

fn declares_int_const() -> Result[Unit, Str] {
  let s := smt.to_smt_lib(small_spec())
  if str.contains(s, "(declare-const x Int)") { Ok(()) } else {
    Err(str.concat("missing declare-const, got: ", s))
  }
}

fn asserts_negation() -> Result[Unit, Str] {
  let s := smt.to_smt_lib(small_spec())
  if str.contains(s, "(assert (not") { Ok(()) } else { Err("missing assert-not wrapper") }
}

fn binop_rendered() -> Result[Unit, Str] {
  let s := smt.to_smt_lib(small_spec())
  # `>` should be rendered as plain `>`; `+` as plain `+`.
  if str.contains(s, "(> ") and str.contains(s, "(+ ") { Ok(()) } else {
    Err("binop not rendered")
  }
}

fn eq_as_smt_equals() -> Result[Unit, Str] {
  let s := smt.to_smt_lib({
    name: "eq_demo",
    quantifiers: [QInt("x")],
    predicate: EBinop({
      op: "==",
      lhs: EVar("x"),
      rhs: EConst(VInt(0)),
    }),
  })
  if str.contains(s, "(= ") { Ok(()) } else { Err("`==` should become `=`") }
}

fn record_field_decls_emitted() -> Result[Unit, Str] {
  let s := smt.to_smt_lib(record_spec())
  if str.contains(s, "(declare-const u__age Int)")
    and str.contains(s, "(declare-const u__name String)")
  { Ok(()) } else { Err(str.concat("expected u__age + u__name decls, got: ", s)) }
}

fn record_field_referenced() -> Result[Unit, Str] {
  let s := smt.to_smt_lib(record_spec())
  if str.contains(s, "u__age") { Ok(()) } else { Err("field ref missing") }
}

fn check_sat_emitted() -> Result[Unit, Str] {
  let s := smt.to_smt_lib(small_spec())
  if str.contains(s, "(check-sat)") { Ok(()) } else { Err("missing check-sat") }
}

# Suite -------------------------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    includes_set_logic(),
    declares_int_const(),
    asserts_negation(),
    binop_rendered(),
    eq_as_smt_equals(),
    record_field_decls_emitted(),
    record_field_referenced(),
    check_sat_emitted(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_)  => acc,
      Err(_) => acc + 1,
    }
  })
}
