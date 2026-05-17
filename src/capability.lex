# lex-spec — Capability ADT (with optional Spec precondition)
#
# The single type both `lex-agent` and `lex-llm` carry. The shape is
# the design surface called out in the v0.1 spec for issue #483:
#
#   - `params`  / `reply`  — lex-schema `ModelSchema` values; on the
#     wire they emit JSON Schema 2020-12 via the schema → schema
#     emitters already in lex-schema.
#   - `precondition`       — an optional `Spec`. Both ends evaluate
#     it. The server-side rejects `tasks/send` with a `spec-denied`
#     JSON-RPC error when the verdict isn't `Allow`. The client-side
#     filters the capability out of the model's tool list (or
#     annotates it "currently unavailable") to keep the LLM from
#     dispatching anything that would be rejected anyway.
#
# The "evaluate at both ends" property is the win: the receiver
# doesn't trust the sender's gate.
#
# Effects: none. Capability values are pure declarations.

import "lex-schema/schema" as sch

import "./spec" as sp
import "./eval" as ev

# Direction of a capability — Lex's view of who initiates the call.
#
#   - `Inbound`        — a remote agent invokes this capability on us.
#   - `Outbound`       — we invoke this capability on a remote agent.
#   - `Local`          — pure local skill (in-process, no A2A wire).
#   - `EscalateHuman`  — surface the request to a human operator.
type CapDirection =
    Inbound
  | Outbound
  | Local
  | EscalateHuman

fn direction_label(d :: CapDirection) -> Str {
  match d {
    Inbound       => "inbound",
    Outbound      => "outbound",
    Local         => "local",
    EscalateHuman => "escalate-human",
  }
}

# The Capability ADT itself. `precondition` is `Option[Spec]` —
# zero-cost if the capability is unconditional.
type Capability = {
  name :: Str,
  description :: Str,
  params :: sch.ModelSchema,
  reply :: Option[sch.ModelSchema],
  direction :: CapDirection,
  precondition :: Option[sp.Spec],
}

# Convenience constructors --------------------------------------------

fn inbound(name :: Str, description :: Str, params :: sch.ModelSchema) -> Capability {
  {
    name: name,
    description: description,
    params: params,
    reply: None,
    direction: Inbound,
    precondition: None,
  }
}

fn outbound(name :: Str, description :: Str, params :: sch.ModelSchema) -> Capability {
  {
    name: name,
    description: description,
    params: params,
    reply: None,
    direction: Outbound,
    precondition: None,
  }
}

fn with_reply(cap :: Capability, reply :: sch.ModelSchema) -> Capability {
  {
    name: cap.name,
    description: cap.description,
    params: cap.params,
    reply: Some(reply),
    direction: cap.direction,
    precondition: cap.precondition,
  }
}

fn with_precondition(cap :: Capability, pre :: sp.Spec) -> Capability {
  {
    name: cap.name,
    description: cap.description,
    params: cap.params,
    reply: cap.reply,
    direction: cap.direction,
    precondition: Some(pre),
  }
}

# ---- Gate evaluation ----------------------------------------------
#
# `gate(cap, bindings)` is the single function both sides call. If
# the capability has no precondition, the verdict is `Allow`
# unconditionally. Otherwise the spec evaluator runs against the
# supplied bindings. Callers map the verdict to their transport
# (HTTP/JSON-RPC on the server, tool-list filtering on the client).

fn gate(
  cap :: Capability,
  bindings :: List[(Str, sp.SpecValue)]
) -> sp.Verdict {
  match cap.precondition {
    None       => Allow,
    Some(spec) => ev.eval(spec, bindings),
  }
}

# Convenience: a Bool projection of `gate`. Loses the reason; use
# `gate` directly when you need to surface that to a caller.
fn allows(
  cap :: Capability,
  bindings :: List[(Str, sp.SpecValue)]
) -> Bool {
  sp.verdict_is_allow(gate(cap, bindings))
}
