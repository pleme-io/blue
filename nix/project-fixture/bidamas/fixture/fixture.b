# fixture: the one private package of blue's project-engine fixture.

def fixture_double(n)
  n * 2
end

test "an independently checkable value"
  assert fixture_double(21) == 42
end
