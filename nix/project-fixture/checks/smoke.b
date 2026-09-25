use("fixture")
use("shisutemu")

test "a check sees the project's package"
  assert fixture_double(2) == 4
end

test "a check sees the declared tool"
  assert status_of(exec_capture("hello")) == 0
end
