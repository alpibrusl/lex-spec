# Tests for `src/check.lex` — randomized property check.

import "std.list" as list

import "std.str" as str

import "../src/spec" as sp

import "../src/check" as ck

# `x + 1 > x` holds for any int — should return Holds.
fn always_holds_spec() -> sp.Spec {
  { name: "x_plus_one_gt_x", quantifiers: [QInt("x")], predicate: EBinop({ op: ">", lhs: EBinop({ op: "+", lhs: EVar("x"), rhs: EConst(VInt(1)) }), rhs: EVar("x") }) }
}

# `x > 0` is falsified by negative random draws — should return
# Falsified with a counter-example.
fn sometimes_false_spec() -> sp.Spec {
  { name: "x_positive", quantifiers: [QInt("x")], predicate: EBinop({ op: ">", lhs: EVar("x"), rhs: EConst(VInt(0)) }) }
}

fn holds_finds_no_counter() -> Result[Unit, Str] {
  let r := ck.check_random(always_holds_spec(), 50, 7)
  match r {
    Holds(n) => if n == 50 {
      Ok(())
    } else {
      Err(str.concat("expected 50 checks, got: ", ck.check_result_label(r)))
    },
    _ => Err(str.concat("expected Holds, got: ", ck.check_result_label(r))),
  }
}

fn falsifies_negative_x() -> Result[Unit, Str] {
  let r := ck.check_random(sometimes_false_spec(), 200, 42)
  match r {
    Falsified(_) => Ok(()),
    _ => Err(str.concat("expected Falsified, got: ", ck.check_result_label(r))),
  }
}

fn render_counter_includes_binding() -> Result[Unit, Str] {
  let r := ck.check_random(sometimes_false_spec(), 200, 42)
  match r {
    Falsified(c) => {
      let txt := ck.render_counter(c)
      if str.contains(txt, "x =") {
        Ok(())
      } else {
        Err(str.concat("counter missing x: ", txt))
      }
    },
    _ => Err("expected Falsified"),
  }
}

fn deterministic_seed() -> Result[Unit, Str] {
  let a := ck.check_random(sometimes_false_spec(), 50, 123)
  let b := ck.check_random(sometimes_false_spec(), 50, 123)
  if ck.check_result_label(a) == ck.check_result_label(b) {
    Ok(())
  } else {
    Err("seed not deterministic")
  }
}

fn suite() -> List[Result[Unit, Str]] {
  [holds_finds_no_counter(), falsifies_negative_x(), render_counter_includes_binding(), deterministic_seed()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

