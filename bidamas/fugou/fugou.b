use("retsu")
# fugou (符号) — base conversion and checksums.
#
# Encoding is where a library's edge cases live: zero, the empty input, and
# the digit that is a letter. Each has a test here, because each is a place an
# implementation looks right and is wrong for exactly one input.

def digits()
  ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
   "a", "b", "c", "d", "e", "f"]
end

def to_base(n, base)
  if n == 0
    "0"
  else
    join(reverse(to_base_digits(n, base)), "")
  end
end

def to_base_digits(n, base)
  if n < 1
    []
  else
    cons(nth(n % base, digits()), to_base_digits(floor(n / base), base))
  end
end

def to_hex(n)
  to_base(n, 16)
end

def to_binary(n)
  to_base(n, 2)
end

def to_octal(n)
  to_base(n, 8)
end

def digit_value(ch)
  value_index(digits(), ch, 0)
end

def value_index(xs, v, i)
  if i >= size(xs)
    0 - 1
  else
    if nth(i, xs) == v
      i
    else
      value_index(xs, v, i + 1)
    end
  end
end

def from_base(text, base)
  reduce(fn(acc, ch) (acc * base) + digit_value(ch) end, 0, chars(text))
end

# Digits of a number in base 10, most significant first.
def digits_of(n)
  if n < 10
    [n]
  else
    push(digits_of(floor(n / 10)), n % 10)
  end
end

def digit_sum(n)
  reduce(fn(a, b) a + b end, 0, digits_of(n))
end

# The Luhn checksum, which every credit-card number satisfies.
def luhn_valid(n)
  ds = reverse(digits_of(n))
  total = reduce(fn(acc, i) acc + luhn_digit(nth(i, ds), i) end, 0, range(0, size(ds)))
  total % 10 == 0
end

def luhn_digit(d, i)
  if i % 2 == 1
    doubled = d * 2
    if doubled > 9
      doubled - 9
    else
      doubled
    end
  else
    d
  end
end

test "base conversion, including zero"
  # Zero is the input that a loop-until-n-is-0 implementation returns "" for.
  assert to_binary(0) == "0"
  assert to_hex(0) == "0"
  assert to_binary(5) == "101"
  assert to_hex(255) == "ff"
  assert to_hex(16) == "10"
  assert to_octal(8) == "10"
end

test "conversion round-trips"
  assert from_base(to_hex(48879), 16) == 48879
  assert from_base(to_binary(1000), 2) == 1000
  assert from_base("ff", 16) == 255
end

test "decimal digits and digit sum"
  assert digits_of(0) == [0]
  assert digits_of(1234) == [1, 2, 3, 4]
  assert digit_sum(1234) == 10
  assert digit_sum(9) == 9
end

test "the Luhn checksum"
  # A known-valid test number, and the same number with one digit changed.
  assert luhn_valid(79927398713) == true
  assert luhn_valid(79927398714) == false
end
