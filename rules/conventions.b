# blue's own project rules: conventions AGENTS.md states, checked by
# `blue check` on every file under this repository (the root Bluefile's
# `rule` rows). Each rule receives one top-level form as data and returns
# findings; see docs/DIAGNOSTICS.md, "Project rules".
#
# Over builtins only, so the rules load with no BLUE_PATH.

# Every [path, node] in a tree, the tree itself first. A path is the child
# indices from the root. A quoted form is data, not code: it is a node, and
# nothing inside it is. `blue check` on this file is the test: its own tests
# quote nil? as input, and without this it reported them.
def nodes(tree, path)
  here = [[path, tree]]
  if tree == nil || !list?(tree) || quoted?(tree)
    here
  else
    children = map(
      fn(i) nodes(nth(i, tree), append(path, [i])) end,
      range(length(tree))
    )
    apply(append, cons(here, children))
  end
end

def quoted?(node)
  call?(node, "quote", 1) || call?(node, "quasiquote", 1)
end

# Is `node` a call to `name` with `arity` arguments?
def call?(node, name, arity)
  node != nil &&
    list?(node) &&
    length(node) == arity + 1 &&
    symbol?(first(node)) &&
    to_s(first(node)) == name
end

# `x == nil` over `nil?(x)` (AGENTS.md, Conventions). They mean the same:
# nil equals only nil (okite D0001), so the fix is machine-applicable.
def nil_predicate(form)
  hits = filter(fn(p) call?(last(p), "nil?", 1) end, nodes(form, []))
  map(
    fn(p)
      arg = nth(1, last(p))
      {
        at: first(p),
        message: "write `x == nil`, not `nil?(x)`",
        help: "blue's convention (AGENTS.md); == compares structurally and nil equals only nil",
        fix: quote
          unquote(arg) == nil
        end
      }
    end,
    hits
  )
end

test "a nil? call anywhere in a form is found, with its path"
  form = quote
    def f(x)
      if nil?(x)
        g(nil?(first(x)))
      end
    end
  end
  found = nil_predicate(form)
  assert map(fn(f) get(f, :at) end, found) == [[2, 1], [2, 2, 1]]
end

test "the fix is the same test written with =="
  form = quote
    nil?(y)
  end
  fix = get(first(nil_predicate(form)), :fix)
  assert fix ==
    quote
      y == nil
    end
end

test "an empty form and one with no nil? find nothing"
  assert nil_predicate(nil) == []
  assert nil_predicate(
    quote
      f(x == nil)
    end
  ) ==
    []
end
