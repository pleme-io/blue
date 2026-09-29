# tatara-lisp forms used from blue
#
# A blue program IS a tatara-lisp program, so tatara's (def…) forms are
# callable wherever their arguments are plain values: defflow builds a
# pipeline, defsm a state machine. defmacro writes a new form of your own; it
# rewrites the unevaluated argument, so a macro may use it twice. A Lisp form
# whose arguments are binding lists (let, cond, dolist) has no blue spelling;
# docs/REFERENCE.md lists which is which.

defflow(slug, trim, downcase)

defsm(
  door,
  :initial,
  :closed,
  :transitions,
  [[:closed, :open, :opened], [:opened, :close, :closed]]
)

defmacro twice(e)
  quote
    [unquote(e), unquote(e)]
  end
end

test "defflow pipes its argument through each function in turn"
  assert slug("  Blue Shift ") == "blue shift"
end

test "defsm moves only along a declared transition"
  assert door(:current) == :closed
  assert door(:send, :close) == :closed
  assert door(:send, :open) == :opened
  assert door(:current) == :opened
end

test "a macro receives the form, not its value"
  assert twice(1 + 1) == [2, 2]
end
