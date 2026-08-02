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
