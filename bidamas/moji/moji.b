# moji (文字) — strings.
#
# Layered on blue's own `.length`, which the runtime installs because
# tatara-lisp carries no string operations at all (see blue-lang-runtime's
# stdlib module). These are the predicates a caller reaches for immediately
# after `length` and would otherwise hand-roll at every call site.

def empty(s)
  s.length == 0
end

def present(s)
  s.length > 0
end

# Longer of two strings, ties going to the first. Ties must resolve
# DETERMINISTICALLY or callers see different answers on different runs for
# equal-length input.
def longer(a, b)
  if b.length > a.length
    b
  else
    a
  end
end

test "empty and present are exact opposites"
  assert empty("") == true
  assert empty("a") == false
  assert present("") == false
  assert present("a") == true
end

test "longer picks the longer string"
  assert longer("abc", "a") == "abc"
  assert longer("a", "abc") == "abc"
end

test "the string primitives blue exposes"
  assert upcase("abc") == "ABC"
  assert downcase("ABC") == "abc"
  assert trim("  a  ") == "a"
  assert concat("a", "b") == "ab"
  assert chars("abc") == ["a", "b", "c"]
  assert join(["a", "b"], "-") == "a-b"
  assert split("a-b", "-") == ["a", "b"]
end

test "split and join round-trip"
  assert join(split("a,b,c", ","), ",") == "a,b,c"
end
