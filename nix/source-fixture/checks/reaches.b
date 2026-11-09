use("fixture", [:double])

test "a check reaches a package another repository holds"
  assert double(21) == 42
end
