# fixture: the one private package of blue's project-engine fixture.

def double(n)
  n * 2
end

test "an independently checkable value"
  assert double(21) == 42
end
