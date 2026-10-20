# Fixture rules for blue-lang-cli/tests/project_rules.rs.

# A call to `loud(x)` at the top of a definition's body: write `quiet(x)`.
def loud_call(form)
  body = if list?(form) and length(form) > 2
    nth(2, form)
  end
  if list?(body) and
    body != nil and
    symbol?(first(body)) and
    to_s(first(body)) == "loud"
    [
      {
        at: [2],
        message: "loud(x) is quiet(x)",
        fix: quote
          quiet(unquote(nth(1, body)))
        end
      }
    ]
  else
    []
  end
end

# A top-level `todo()` call, reported with no fix.
def todo_call(form)
  if list?(form) and
    form != nil and
    symbol?(first(form)) and
    to_s(first(form)) == "todo"
    [{at: [0], message: "a todo is left", help: "finish it"}]
  else
    []
  end
end
