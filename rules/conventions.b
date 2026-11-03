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
  if tree.nil? or not list?(tree) or quoted?(tree)
    here
  else
    children = map(
      (i) -> nodes(tree[i], append(path, [i])),
      range(length(tree))
    )
    append(*cons(here, children))
  end
end

def quoted?(node)
  call?(node, "quote", 1) or call?(node, "quasiquote", 1)
end

# Is `node` a call to `name` with `arity` arguments?
def call?(node, name, arity)
  node != nil and
    list?(node) and
    length(node) == arity + 1 and
    symbol?(first(node)) and
    to_s(first(node)) == name
end

# `x.nil?` over `nil?(x)` (B0047). They mean the same, so the fix is
# machine-applicable.
def nil_predicate(form)
  hits = filter((p) -> call?(last(p), "nil?", 1), nodes(form, []))
  map(
    fn(p)
      arg = last(p)[1]
      {
        at: first(p),
        message: "write `x.nil?`, not `nil?(x)`",
        help: "blue's convention (B0047); .nil? is true of nil and of nothing else",
        fix: quote
          unquote(arg).nil?
        end
      }
    end,
    hits
  )
end

@doc """
index_binding?: Whether a node binds a name to `index_of` or `position`.

    index_binding?(nil) #=> false
"""
def index_binding?(node)
  call?(node, "define", 2) and
    symbol?(node[1]) and
    (call?(node[2], "index_of", 2) or call?(node[2], "position", 2))
end

@doc """
nil_tested: The name a node tests against nil, as a string, or nil when it
tests none. `x == nil` reads as `x.nil?` in the tree, so two shapes cover all
three spellings.

    nil_tested(nil) #=> nil
"""
def nil_tested(node)
  if call?(node, "blue-field", 2) and node[2] == :nil? and symbol?(node[1])
    to_s(node[1])
  elsif call?(node, "not=", 2) and
      symbol?(node[1]) and
      (node[2].nil? or node[2] == [])
    to_s(node[1])
  end
end

@doc """
index_nil: `index_of` and `position` answer -1 on a miss and never nil, so a
nil test of a name bound to one always answers the same, and the miss reads as
a position. The fix is the test the name can answer.

    index_nil(nil) #=> []
"""
def index_nil(form)
  all = nodes(form, [])
  names = map(
    (p) -> to_s(last(p)[1]),
    filter((p) -> index_binding?(last(p)), all)
  )
  map(
    fn(p)
      n = last(p)
      name = n[1]
      {
        at: first(p),
        message: "`#{to_s(name)}` holds an index: a miss is -1, never nil",
        help: "index_of and position answer -1 on a miss; test the sign",
        fix: if call?(n, "not=", 2)
          quote
            unquote(name) >= 0
          end
        else
          quote
            unquote(name) < 0
          end
        end
      }
    end,
    filter((p) -> member?(nil_tested(last(p)), names), all)
  )
end

test "a nil test of an index is found, with its path and its fix"
  form = quote
    def f(xs)
      i = index_of(xs, 1)
      if i.nil?
        0
      end
    end
  end
  found = index_nil(form)
  assert count(found) == 1
  assert first(found)[:fix] ==
    quote
      i < 0
    end
end

test "every spelling of the nil test of a position is found"
  miss = quote
    def f(xs)
      j = position(1, xs)
      j.nil?
    end
  end
  assert count(index_nil(miss)) == 1
  hit = quote
    def f(xs)
      j = position(1, xs)
      j != nil
    end
  end
  assert first(index_nil(hit))[:fix] ==
    quote
      j >= 0
    end
end

test "a nil test of another name and a sign test of an index find nothing"
  assert index_nil(
    quote
      def f(xs, y)
        i = index_of(xs, 1)
        if i < 0 or y.nil?
          0
        end
      end
    end
  ) == []
  assert index_nil(nil) == []
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
  assert map((f) -> f[:at], found) == [[2, 1], [2, 2, 1]]
end

test "the fix is the same test written as the predicate"
  form = quote
    nil?(y)
  end
  fix = first(nil_predicate(form))[:fix]
  assert fix ==
    quote
      y.nil?
    end
end

test "an empty form and one with no nil? find nothing"
  assert nil_predicate(nil) == []
  assert nil_predicate(
    quote
      f(x.nil?)
    end
  ) == []
end
