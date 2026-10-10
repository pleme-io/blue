# Fixture rules for blue-lang-cli/tests/project_rules.rs.

# A call to `loud(x)` at the top of a definition's body: write `quiet(x)`.
def loud_call(form)
  body = if list?(form) && length(form) > 2
    nth(2, form)
  else
    nil
  end
  if list?(body) &&
    body != nil &&
    symbol?(first(body)) &&
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
  if list?(form) &&
    form != nil &&
    symbol?(first(form)) &&
    to_s(first(form)) == "todo"
    [{at: [0], message: "a todo is left", help: "finish it"}]
  else
    []
  end
end
