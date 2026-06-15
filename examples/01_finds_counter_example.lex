# lex-spec — counter-example demo
#
# Property-checks a spec that *almost* holds and shows the
# counter-example the randomized check surfaces.
#
# Run:
#   lex run examples/01_finds_counter_example.lex demo

import "std.str" as str

import "../src/spec" as sp

import "../src/check" as ck

import "../src/eval" as ev

# Pretend a "user_can_vote" capability requires age >= 18 — but the
# spec author wrote `> 18` by mistake. A 17-year-old random draw
# should surface it.
fn age_gate() -> sp.Spec {
  { name: "user_can_vote", quantifiers: [QRecord({ name: "u", fields: [{ name: "age", ty: TInt }] })], predicate: EBinop({ op: ">=", lhs: EField({ binding: "u", field: "age" }), rhs: EConst(VInt(18)) }) }
}

fn binding(age :: Int) -> List[(Str, sp.SpecValue)] {
  [("u", VRecord({ name: "User", fields: [("age", VInt(age))] }))]
}

fn demo() -> Str {
  let spec := age_gate()
  let on_17 := sp.verdict_label(ev.eval(spec, binding(17)))
  let on_25 := sp.verdict_label(ev.eval(spec, binding(25)))
  let prop := ck.render_check_result(ck.check_random(spec, 200, 12345))
  str.concat("eval(age=17): ", str.concat(on_17, str.concat("\neval(age=25): ", str.concat(on_25, str.concat("\nrandomized check:\n", prop)))))
}

