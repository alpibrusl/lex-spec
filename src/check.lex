# lex-spec — randomized property check
#
# `check_random(spec, n, seed)` generates `n` random bindings for the
# spec's quantifiers and evaluates the predicate against each. The
# return is structured so callers can render a counter-example.
#
# Matches the surface of the original `lex spec check` (which today
# uses an internal Rust property checker for record-typed quantifiers).
# This pure-Lex version covers the same surface.
#
# Effects: `[random]` for `crypto.random`. Callers that need a
# deterministic seed pass `seed != 0`; the implementation hashes that
# seed forward via a SplitMix64-style step.

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "./spec" as sp

import "./eval" as ev

# ---- Result types -------------------------------------------------
type Counter = { bindings :: List[(Str, sp.SpecValue)], reason :: Str }

type CheckResult = Holds(Int) | Falsified(Counter) | Indeterminate(Counter)

fn check_result_label(r :: CheckResult) -> Str {
  match r {
    Holds(_) => "holds",
    Falsified(_) => "falsified",
    Indeterminate(_) => "indeterminate",
  }
}

# ---- Public entry point -------------------------------------------
fn check_random(spec :: sp.Spec, n :: Int, seed :: Int) -> CheckResult {
  loop_check(spec, n, 0, init_rng(seed))
}

# Recurse n iterations. Each iteration: bump rng, generate a binding
# row, eval, branch on the verdict.
fn loop_check(spec :: sp.Spec, n :: Int, i :: Int, rng :: Int) -> CheckResult {
  if i >= n {
    Holds(i)
  } else {
    let next_rng := mix(rng)
    let row := generate_row(spec.quantifiers, next_rng)
    let verdict := ev.eval(spec, row.bindings)
    match verdict {
      Allow => loop_check(spec, n, i + 1, row.rng),
      Deny(why) => Falsified({ bindings: row.bindings, reason: why }),
      Inconclusive(why) => Indeterminate({ bindings: row.bindings, reason: why }),
    }
  }
}

# ---- Generator ---------------------------------------------------
#
# `generate_row` walks the quantifier list and synthesises a value
# for each binding. The RNG state is threaded through so the same
# seed produces the same sequence — deterministic property tests.
#
# v0.1 generators are bounded: Int in [-1000, 1000], Str picked from
# a small fixed pool, Float scaled to [-100.0, 100.0]. Tightening
# generators is a follow-up.
type Row = { bindings :: List[(Str, sp.SpecValue)], rng :: Int }

fn generate_row(qs :: List[sp.SpecQuant], rng :: Int) -> Row {
  list.fold(qs, { bindings: [], rng: rng }, fn (acc :: Row, q :: sp.SpecQuant) -> Row {
    let stepped := mix(acc.rng)
    let pair := generate_for(q, stepped)
    { bindings: list.concat(acc.bindings, [(sp.quant_binding_name(q), pair.value)]), rng: pair.rng }
  })
}

type Gen = { value :: sp.SpecValue, rng :: Int }

fn generate_for(q :: sp.SpecQuant, rng :: Int) -> Gen {
  match q {
    QInt(_) => { value: VInt(int_in_range(rng, -1000, 1000)), rng: mix(rng) },
    QStr(_) => { value: VStr(pick_str(rng)), rng: mix(rng) },
    QBool(_) => { value: VBool(int_mod(rng, 2) == 0), rng: mix(rng) },
    QFloat(_) => { value: VFloat(float_in_range(rng, 0.0 - 100.0, 100.0)), rng: mix(rng) },
    QRecord(r) => generate_record(r, rng),
    QList(_) => { value: VList([]), rng: mix(rng) },
  }
}

fn generate_record(r :: { name :: Str, fields :: List[{ name :: Str, ty :: sp.Type }] }, rng :: Int) -> Gen {
  let walked := list.fold(r.fields, { entries: [], rng: rng }, fn (acc :: { entries :: List[(Str, sp.SpecValue)], rng :: Int }, f :: { name :: Str, ty :: sp.Type }) -> { entries :: List[(Str, sp.SpecValue)], rng :: Int } {
    let stepped := mix(acc.rng)
    let g := generate_for_type(f.ty, stepped)
    { entries: list.concat(acc.entries, [(f.name, g.value)]), rng: g.rng }
  })
  let rec_val := VRecord({ name: r.name, fields: walked.entries })
  { value: rec_val, rng: walked.rng }
}

fn generate_for_type(t :: sp.Type, rng :: Int) -> Gen {
  match t {
    TInt => { value: VInt(int_in_range(rng, -1000, 1000)), rng: mix(rng) },
    TStr => { value: VStr(pick_str(rng)), rng: mix(rng) },
    TBool => { value: VBool(int_mod(rng, 2) == 0), rng: mix(rng) },
    TFloat => { value: VFloat(float_in_range(rng, 0.0 - 100.0, 100.0)), rng: mix(rng) },
    TRecord(_) => { value: VNull, rng: mix(rng) },
    TList(_) => { value: VList([]), rng: mix(rng) },
  }
}

# ---- RNG ----------------------------------------------------------
#
# Deterministic SplitMix64-style 64-bit mixer. Pure: no `[random]`
# effect declared because the seed is supplied explicitly. Callers
# that want a non-deterministic seed pre-seed from `crypto.random`
# in their own caller.
fn init_rng(seed :: Int) -> Int {
  if seed == 0 {
    12345
  } else {
    seed
  }
}

# Single-step mixer — folds the bits enough that successive draws
# decorrelate. Multipliers chosen to be coprime with 2^63 and have
# bits distributed across the word.
fn mix(s :: Int) -> Int {
  let a := s + 2654435769
  let b := a * 1664525
  if b < 0 {
    0 - b
  } else {
    b
  }
}

fn int_mod(s :: Int, m :: Int) -> Int {
  if m <= 0 {
    0
  } else {
    let r := s - s / m * m
    if r < 0 {
      r + m
    } else {
      r
    }
  }
}

fn int_in_range(s :: Int, lo :: Int, hi :: Int) -> Int {
  let span := hi - lo + 1
  if span <= 0 {
    lo
  } else {
    lo + int_mod(s, span)
  }
}

fn float_in_range(s :: Int, lo :: Float, hi :: Float) -> Float {
  let bucket := int_mod(s, 1000)
  let unit := int.to_float(bucket) / 1000.0
  lo + unit * (hi - lo)
}

# A small fixed pool — covers the empty / numeric-ish / alpha cases
# typical predicates branch on. Callers wanting structured strings
# should provide a custom generator (deferred to v0.2).
fn pick_str(s :: Int) -> Str {
  let pool := ["", "a", "abc", "0", "1", "true", "false", "hello", "test", "z"]
  let idx := int_mod(s, list.len(pool))
  let walked := list.fold(list.enumerate(pool), "", fn (acc :: Str, p :: (Int, Str)) -> Str {
    let i := match p {
      (a, _) => a,
    }
    let v := match p {
      (_, b) => b,
    }
    if i == idx {
      v
    } else {
      acc
    }
  })
  walked
}

# ---- Pretty rendering ---------------------------------------------
fn render_counter(c :: Counter) -> Str {
  let lines := list.map(c.bindings, fn (pair :: (Str, sp.SpecValue)) -> Str {
    match pair {
      (k, v) => str.concat("  ", str.concat(k, str.concat(" = ", sp.show_value(v)))),
    }
  })
  str.concat("counter-example:\n", str.concat(str.join(lines, "\n"), str.concat("\nreason: ", c.reason)))
}

fn render_check_result(r :: CheckResult) -> Str {
  match r {
    Holds(n) => str.concat("ok: predicate held over ", str.concat(int.to_str(n), " random cases")),
    Falsified(c) => str.concat("FALSIFIED\n", render_counter(c)),
    Indeterminate(c) => str.concat("INDETERMINATE\n", render_counter(c)),
  }
}

