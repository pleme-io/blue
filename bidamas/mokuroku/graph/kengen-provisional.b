space("kengen?", {status: :provisional})

verb(
  "kengen?",
  "allow?",
  {
    kind: :pure,
    shape: "allow?(subject, action, resource, ctx) -> Bool",
    laterals: %w[trace validate],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "policies permit this action",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kengen?",
  "bind",
  {
    kind: :effect,
    shape: "bind(subject, role, scope) -> binding",
    laterals: %w[idempotent log],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "give a subject a role inside a scope",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kengen?",
  "decide",
  {
    kind: :pure,
    shape: "decide(request, policies) -> decision",
    laterals: %w[trace validate],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "full answer: effect, matched rules, obligations",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kengen?",
  "delegate",
  {
    kind: :effect,
    shape: "delegate(from, to, permission, opts) -> grant",
    laterals: %w[idempotent log time],
    fleet: nil,
    today: "absent",
    meaning: "pass on part of my power for a limited time",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kengen?",
  "expand",
  {
    kind: :effect,
    shape: "expand(object, relation) -> tree",
    laterals: %w[resource trace],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "tree of everyone holding a relation to an object",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kengen?",
  "grant",
  {
    kind: :effect,
    shape: "grant(subject, permission, resource, opts) -> relation",
    laterals: %w[idempotent log],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "let a subject do something to a resource",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kengen?",
  "grants?",
  {
    kind: :pure,
    shape: "grants?(permission, requested) -> Bool",
    laterals: ["validate"],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "a held permission covers the requested one",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kengen?",
  "holders",
  {
    kind: :effect,
    shape: "holders(action, resource, opts) -> [subject]",
    laterals: %w[cache resource],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "everyone who may do an action to a resource",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kengen?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, language) -> policy",
    laterals: %w[serialize validate],
    fleet: nil,
    today: "absent",
    meaning: "policy text in a policy language to a policy",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kengen?",
  "permission",
  {
    kind: :decl,
    shape: "permission(resource, action) -> permission",
    laterals: ["config"],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "one resource and action pair, wildcards allowed",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kengen?",
  "permit",
  {
    kind: :pure,
    shape: "permit(subject, action, resource, ctx) -> nil",
    laterals: %w[error log validate],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "raise :denied unless allowed; the guard form",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kengen?",
  "policy",
  {
    kind: :decl,
    shape: "policy(name, rules, opts) -> policy",
    laterals: %w[config validate],
    fleet: nil,
    today: "absent",
    meaning: "rules over subject, action, resource and context",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kengen?",
  "powers",
  {
    kind: :effect,
    shape: "powers(subject, opts) -> [record]",
    laterals: %w[cache resource],
    fleet: nil,
    today: "absent",
    meaning: "every action and resource a subject can reach",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kengen?",
  "relation",
  {
    kind: :decl,
    shape: "relation(object, relation, subject) -> tuple",
    laterals: ["config"],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "one relationship fact such as editor of document",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kengen?",
  "revoke",
  {
    kind: :effect,
    shape: "revoke(subject, permission, resource) -> nil",
    laterals: %w[idempotent log],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "withdraw a grant",
    wave: 1,
    origin: "D",
    contract: "revoke(subject, permission, opts) -> nil"
  }
)

verb(
  "kengen?",
  "role",
  {
    kind: :decl,
    shape: "role(name, permissions, opts) -> role",
    laterals: ["config"],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "a named set of permissions",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kengen?",
  "rule",
  {
    kind: :decl,
    shape: "rule(effect, match, opts) -> rule",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "one permit or forbid with a condition",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kengen?",
  "visible",
  {
    kind: :effect,
    shape: "visible(subject, action, resources) -> [resource]",
    laterals: %w[cache resource],
    fleet: nil,
    today: "absent",
    meaning: "the resources a subject may act on, in one pass",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kengen?",
  "why",
  {
    kind: :pure,
    shape: "why(decision) -> [rule]",
    laterals: ["trace"],
    fleet: nil,
    today: "absent",
    meaning: "the rules that produced a decision",
    wave: 2,
    origin: "D"
  }
)

edge(
  "kengen?::permit",
  :composes,
  "kengen?::allow?",
  "raise :denied when false"
)

edge("kengen?::decide", :composes, "kengen?::grants?", "permission matching")
edge("kengen?::role", :composes, "kengen?::permission", "a set of permissions")

edge(
  "kengen?::decide",
  :composes,
  "kengen?::policy",
  "evaluate policies over a request"
)

edge("kengen?::grant", :composes, "kengen?::relation", "stores one tuple")
edge("kengen?::policy", :composes, "kengen?::rule", "a named list of rules")

edge(
  "kengen?::relation",
  :generalizes,
  "kengen?::grant",
  "a grant is a relation tuple"
)

edge(
  "kengen?::permission",
  :generalizes,
  "kengen?::grants?",
  "a permission with wildcards"
)

edge(
  "kengen?::allow?",
  :generalizes,
  "waku::allows?",
  "any subject, action and resource"
)

edge(
  "kengen?::allow?",
  :guards,
  "himitsu::read",
  "secrets read only when allowed"
)

edge("kengen?::grants?", :guards, "kengen?::allow?", "wildcard match step")

edge(
  "kengen?::parse",
  :guards,
  "kengen?::policy",
  "bad text never becomes a policy"
)

edge(
  "kengen?::permit",
  :guards,
  "kyohi::enforce",
  "denial raises a ledger refusal"
)

edge("kengen?::revoke", :inverse, "kengen?::grant", "removes the tuple")
edge("kengen?::grant", :inverse, "kengen?::revoke", "removes the tuple")

edge(
  "kengen?::holders",
  :lifts,
  "kengen?::allow?",
  "all subjects where allow? is true"
)

edge(
  "kengen?::powers",
  :lifts,
  "kengen?::allow?",
  "all resources where allow? is true"
)

edge(
  "kengen?::visible",
  :lifts,
  "kengen?::allow?",
  "filter resources by allow?"
)

edge("kengen?::expand", :lifts, "kengen?::holders", "tree form of holders")
edge("kengen?::role", :pairs, "kengen?::bind", "declared then assigned")

edge(
  "kengen?::powers",
  :pairs,
  "kengen?::holders",
  "a subject's view and a resource's view"
)

edge("kengen?::grant", :pairs, "kengen?::revoke", "each grant can be withdrawn")
edge("kengen?::rule", :pairs, "kengen?::why", "why names the rules that fired")

edge(
  "kengen?::allow?",
  :refines,
  "kengen?::decide",
  "the boolean of the decision"
)

edge(
  "kengen?::bind",
  :refines,
  "kengen?::grant",
  "grant by role instead of permission"
)

edge(
  "kengen?::delegate",
  :refines,
  "kengen?::grant",
  "a grant with an end time"
)

edge(
  "kengen?::grants?",
  :refines,
  "waku::allows?",
  "permission wildcards versus name grants"
)

edge(
  "kengen?::delegate",
  :requires,
  "kengen?::allow?",
  "cannot pass on what you lack"
)

edge("kengen?::why", :requires, "kengen?::decide", "explains a decision")
edge("kengen?::parse", :requires, "kengen?::policy", "text becomes a policy")

edge(
  "kengen?::rule",
  :requires,
  "kengen?::policy",
  "rules live inside policies"
)

edge("kengen?::bind", :requires, "kengen?::role", "assign a declared role")
