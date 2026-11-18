@moduledoc """
henkan (変換) — a nanopass library: a compiler written as many small passes, each a rewrite between two declared languages.

A language is the set of form heads a tree may hold, each with its argument count. A pass names the language it reads and the one it writes, and a table of rewrites keyed by head; every head it does not name is carried through unchanged. A pass checks its input against its source language and its output against its target, so a rewrite that leaves a form its target forbids is refused where it is made, naming the path to the form.

    head_of(check(language("ir", [["ret", 1]]), read_forms("(ret 7)")[0])) #=> "ret"
"""

use("retsu", %i[find_first flat_map is_empty rest])

@doc """
language: a language of the given name whose trees hold only these forms, each [head, argument count] or [head, :any].

    language("ir", [["ret", 1]])[:name] #=> "ir"
"""
def language(name, forms)
  {name:, forms:}
end

@doc """
head_of: the head symbol of a form as text, or nil for anything that is not a form headed by a symbol.

    head_of(read_forms("(add 1 2)")[0]) #=> "add"
    head_of(7).nil? #=> true
"""
def head_of(form)
  if list?(form) and length(form) > 0 and symbol?(form[0])
    to_s(form[0])
  end
end

@doc """
spec_of: the [head, argument count] row a language gives a head, or nil when the language has no such form.

    spec_of(language("l", [["ret", 1]]), "ret")[1] #=> 1
    spec_of(language("l", [["ret", 1]]), "add").nil? #=> true
"""
def spec_of(lang, head)
  row = find_first((r) -> r[0] == head, lang[:forms])
  if row.nil?
    nil
  else
    row
  end
end

@doc """
arity_ok?: whether an argument count meets what a language's form wants, a number or :any.

    arity_ok?(2, 2) #=> true
    arity_ok?(2, 3) #=> false
    arity_ok?(:any, 9) #=> true
"""
def arity_ok?(want, got)
  want == :any or want == got
end

@doc """
child_problems: the problems of every child of a form, each path extended by the child's index.

    child_problems(language("l", [["ret", 1]]), [], []) #=> []
"""
def child_problems(lang, kids, path)
  flat_map(
    range(0, length(kids)),
    (i) -> problems(lang, kids[i], append(path, [i + 1]))
  )
end

@doc """
problems: every place a tree leaves a language, as {path, message}; a path is the child indices from the root.

    problems(language("l", [["ret", 1]]), read_forms("(ret 7)")[0], []) #=> []
    length(problems(language("l", [["ret", 1]]), read_forms("(ret 7 8)")[0], [])) #=> 1
    length(problems(language("l", [["ret", 1]]), read_forms("(add 7 8)")[0], [])) #=> 1
"""
def problems(lang, form, path)
  if not list?(form) or length(form) == 0
    []
  else
    head = head_of(form)
    spec = if head.nil?
      nil
    else
      spec_of(lang, head)
    end
    own = if head.nil?
      [
        {
          path:,
          message: "a form of language #{lang[:name]} starts with a symbol"
        }
      ]
    elsif spec.nil?
      [{path:, message: "`#{head}` is not a form of language #{lang[:name]}"}]
    elsif not arity_ok?(spec[1], length(form) - 1)
      [
        {
          path:,
          message: "`#{head}` takes #{to_s(spec[1])} argument(s) in language #{lang[:name]}, got #{to_s(length(form) - 1)}"
        }
      ]
    else
      []
    end
    append(own, child_problems(lang, rest(form), path))
  end
end

@doc """
check: the tree itself if it stays in the language, and a :henkan_violation naming the first path that leaves it if it does not.

    head_of(check(language("l", [["ret", 1]]), read_forms("(ret 7)")[0])) #=> "ret"
"""
def check(lang, form)
  bad = problems(lang, form, [])
  if is_empty(bad)
    form
  else
    raise(:henkan_violation, "#{bad[0][:message]} (at #{to_s(bad[0][:path])})")
  end
end

@doc """
pass: a pass named name from one language to another; rewrites is a list of [head, function], each taking a form whose children are already rewritten.

    pass("p", language("a", []), language("b", []), [])[:name] #=> "p"
"""
def pass(name, from, to, rewrites)
  {name:, from:, to:, rewrites:}
end

@doc """
rewrite: a tree with every form that has a rule replaced by the rule's answer, children first; forms without a rule are kept.

    rewrite([], 7) #=> 7
"""
def rewrite(rules, form)
  if not list?(form) or length(form) == 0
    form
  else
    kids = map((c) -> rewrite(rules, c), rest(form))
    rebuilt = cons(form[0], kids)
    row = find_first((r) -> r[0] == head_of(form), rules)
    if row.nil?
      rebuilt
    else
      apply(row[1], [rebuilt])
    end
  end
end

@doc """
run: the tree a pass makes: its input checked against the source language, rewritten bottom up, and its output checked against the target.

    run(pass("p", language("a", [["x", 0]]), language("b", [["y", 0]]), [["x", (_f) -> read_forms("(y)")[0]]]), read_forms("(x)")[0])[0] == read_forms("(y)")[0][0] #=> true
"""
def run(p, form)
  check(p[:to], rewrite(p[:rewrites], check(p[:from], form)))
end

test "a form outside the language is refused and names its path"
  lang = language("l", [["ret", 1], ["add", 2]])
  bad = problems(lang, read_forms("(ret (mul 1 2))")[0], [])
  assert length(bad) == 1
  assert bad[0][:path] == [1]
  assert bad[0][:message] == "`mul` is not a form of language l"
end

test "an arity mismatch is refused where it is"
  lang = language("l", [["ret", 1], ["add", 2]])
  bad = problems(lang, read_forms("(ret (add 1))")[0], [])
  assert length(bad) == 1
  assert bad[0][:path] == [1]
end

test "a :any form takes any number of arguments"
  lang = language("l", [["begin", :any], ["x", 0]])
  assert problems(lang, read_forms("(begin (x) (x) (x))")[0], []) == []
end

test "a pass rewrites bottom up and carries every other form through"
  a = language("a", [["ret", 1], ["add", 2]])
  b = language("b", [["ret", 1], ["plus", 2]])
  rename = (f) -> cons(read_forms("plus")[0], rest(f))
  p = pass("rename", a, b, [["add", rename]])
  out = run(p, read_forms("(ret (add 1 (add 2 3)))")[0])
  assert out == read_forms("(ret (plus 1 (plus 2 3)))")[0]
end

test "a pass that leaves a form its target forbids is refused"
  a = language("a", [["ret", 1], ["add", 2]])
  b = language("b", [["ret", 1], ["plus", 2]])
  keeps = (f) -> f
  p = pass("forgets", a, b, [["ret", keeps]])
  caught = begin
    run(p, read_forms("(ret (add 1 2))")[0])
  rescue e
    e.kind
  end
  assert caught == :henkan_violation
end

test "a pass refuses an input that is not in its source language"
  a = language("a", [["ret", 1]])
  p = pass("p", a, a, [])
  caught = begin
    run(p, read_forms("(ret (add 1 2))")[0])
  rescue e
    e.message
  end
  assert caught == "`add` is not a form of language a (at [1])"
end

test "every definition is exercised by name"
  lang = language("l", [["ret", 1], ["x", 0]])
  assert lang[:name] == "l"
  assert head_of(read_forms("(ret 1)")[0]) == "ret"
  assert head_of(3).nil?
  assert spec_of(lang, "ret")[1] == 1
  assert spec_of(lang, "nope").nil?
  assert arity_ok?(1, 1)
  assert not arity_ok?(1, 2)
  assert arity_ok?(:any, 5)
  assert child_problems(lang, read_forms("(x) (ret 1)"), [0]) == []
  assert length(child_problems(lang, read_forms("(y)"), [0])) == 1
  assert check(lang, read_forms("(x)")[0]) == read_forms("(x)")[0]
  p = pass("same", lang, lang, [])
  assert p[:name] == "same"
  assert rewrite([], read_forms("(x)")[0]) == read_forms("(x)")[0]
  assert run(p, read_forms("(ret (x))")[0]) == read_forms("(ret (x))")[0]
end
