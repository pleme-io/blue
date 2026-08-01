# Arithmetic and precedence, specified in blue.
#
# This file is part of blue's gate, not a demo: blue-lang-test's
# `every_spec_file_passes` runs every `.b` file here and a failure fails the
# build.

test "addition and multiplication"
  assert 1 + 2 == 3
  assert 2 * 3 == 6
end
test "multiplication binds tighter than addition"
  assert 2 + 3 * 4 == 14
  assert (2 + 3) * 4 == 20
end
test "subtraction is left associative"
  assert 1 - 2 - 3 == -4
end
test "modulo comes from the Lisp stdlib"
  assert 7 % 3 == 1
  assert 6 % 3 == 0
end
test "comparison operators"
  assert 1 < 2
  assert 2 <= 2
  assert 3 > 2
  assert 3 >= 3
  assert 1 != 2
end
test "logical operators bind loosest"
  assert true && true
  assert true || false
  assert 1 < 2 && 2 < 3
end
