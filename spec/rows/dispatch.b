# Master verbs: a bare read, need, has?, put, update, delete, create, diff,
# info or exists? goes to the handler its subject's space registered
# (STDLIB 3.6). A subject is in a space by tag (in_space) or by its kind
# (space_for). Handlers here are lambdas so no bidama is needed.

row(
  "dispatch.tagged.read",
  join_lines(
    ["verb_for(\"s\", \"read\", (x) -> x + 1)", "read(in_space(\"s\", 1))"]
  ),
  value("2"),
  covers("builtin:verb_for", "builtin:in_space", "builtin:read")
)

row(
  "dispatch.extra_arguments_follow_the_subject",
  join_lines(
    [
      "verb_for(\"s\", \"diff\", (s, a, b) -> a - b)",
      "diff(in_space(\"s\", 0), 5, 3)"
    ]
  ),
  value("2"),
  covers("builtin:diff")
)

row(
  "dispatch.kind.put",
  join_lines(
    [
      "space_for(:map, \"m\")",
      "verb_for(\"m\", \"put\", (m, k, v) -> assoc(m, k, v))",
      "put({}, :a, 1)"
    ]
  ),
  value("{a: 1}"),
  covers("builtin:space_for", "builtin:put")
)

row(
  "dispatch.kind.need",
  join_lines(
    [
      "space_for(:map, \"m\")",
      "verb_for(\"m\", \"need\", (m, k) -> get(m, k))",
      "need({a: 7}, :a)"
    ]
  ),
  value("7"),
  covers("builtin:need")
)

row(
  "dispatch.kind.has",
  join_lines(
    [
      "space_for(:map, \"m\")",
      "verb_for(\"m\", \"has?\", (m, k) -> get(m, k) != nil)",
      "[has?({a: 1}, :a), has?({}, :a)]"
    ]
  ),
  value("[true, false]"),
  covers("builtin:has?")
)

row(
  "dispatch.kind.update",
  join_lines(
    [
      "space_for(:map, \"m\")",
      "verb_for(\"m\", \"update\", (m, k, f) -> assoc(m, k, f(get(m, k))))",
      "update({n: 1}, :n, (x) -> x + 1)"
    ]
  ),
  value("{n: 2}"),
  covers("builtin:update")
)

row(
  "dispatch.kind.delete",
  join_lines(
    [
      "space_for(:map, \"m\")",
      "verb_for(\"m\", \"delete\", (m, k) -> dissoc(m, k))",
      "[delete({a: 1}, :a), delete({}, :a)]"
    ]
  ),
  value("[{}, {}]"),
  covers("builtin:delete")
)

row(
  "dispatch.tagged.create",
  join_lines(
    [
      "verb_for(\"s\", \"create\", (s, k, v) -> [s, k, v])",
      "create(in_space(\"s\", 1), 2, 3)"
    ]
  ),
  value("[1, 2, 3]"),
  covers("builtin:create")
)

row(
  "dispatch.tagged.info",
  join_lines(
    ["verb_for(\"s\", \"info\", (s) -> {of: s})", "info(in_space(\"s\", 9))"]
  ),
  value("{of: 9}"),
  covers("builtin:info")
)

row(
  "dispatch.tagged.exists",
  join_lines(
    [
      "verb_for(\"s\", \"exists?\", (s, ref) -> s == ref)",
      "[exists?(in_space(\"s\", 1), 1), exists?(in_space(\"s\", 1), 2)]"
    ]
  ),
  value("[true, false]"),
  covers("builtin:exists?")
)

row(
  "dispatch.space_of",
  join_lines(
    [
      "space_for(:map, \"m\")",
      "[space_of({}), space_of(in_space(\"t\", 1)), space_of(1), space_of(nil)]"
    ]
  ),
  value("[\"m\", \"t\", nil, nil]"),
  covers("builtin:space_of")
)

row(
  "dispatch.tag_wins_over_kind",
  join_lines(
    [
      "space_for(:map, \"m\")",
      "verb_for(\"m\", \"read\", (x) -> :kind)",
      "verb_for(\"t\", \"read\", (x) -> :tag)",
      "[read({}), read(in_space(\"t\", {}))]"
    ]
  ),
  value("[:kind, :tag]")
)

row(
  "dispatch.no_space",
  "read(\"/etc/hosts\")",
  fails(:eval, "no space owns a string subject")
)

row(
  "dispatch.no_handler",
  join_lines(
    ["verb_for(\"s\", \"read\", (x) -> x)", "delete(in_space(\"s\", 1), 1)"]
  ),
  fails(:eval, "space s has no handler")
)

row(
  "dispatch.only_master_verbs",
  "verb_for(\"s\", \"fetch\", (x) -> x)",
  fails(:eval, "not a dispatched master verb")
)

row(
  "dispatch.handler_is_a_function",
  "verb_for(\"s\", \"read\", 3)",
  fails(:eval, "the handler is a function")
)

row(
  "dispatch.kind_has_one_owner",
  join_lines(["space_for(:map, \"a\")", "space_for(:map, \"b\")"]),
  fails(:eval, "kind map already belongs to space a")
)

row(
  "dispatch.subject_stays_in_its_space",
  "in_space(\"b\", in_space(\"a\", 1))",
  fails(:eval, "already in space a, not b")
)
