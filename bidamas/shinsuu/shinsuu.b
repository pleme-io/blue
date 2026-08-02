use("retsu")
# shinsuu (進数) — base conversion and checksums.
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

# ---------------------------------------------------------------------------
# Digit LISTS, most-significant-first, in any base.
#
# `to_base_digits` above answers with CHARACTERS, least-significant-first,
# because that is what `to_base` needs to reverse-and-join. Everything below
# wants the other thing: digit VALUES in reading order, so arithmetic can be
# done on them. The two are deliberately separate rather than one function with
# a flag — a caller that mixes them up gets a type error at the first `+`
# rather than a plausible wrong number.

def base_digits(n, base)
  if n < base
    [n]
  else
    push(base_digits(floor(n / base), base), n % base)
  end
end

# The inverse of base_digits. Horner's rule, so no `expt` and no float.
#
# The empty list answers 0 rather than erroring, which is what makes it safe to
# feed the result of a filter or a `rest` straight back in.
def from_digits(ds, base)
  reduce(fn(acc, d) (acc * base) + d end, 0, ds)
end

# Left-pad a digit list to a fixed width with zeros.
#
# This is the alignment step every pairwise bit operation needs: 5 is [1,0,1]
# and 12 is [1,1,0,0], and zipping those without padding pairs the 1 of 5 with
# the 1 of 12 — off by one place, silently.
def pad_digits(ds, width)
  if size(ds) >= width
    ds
  else
    append(repeat(0, width - size(ds)), ds)
  end
end

def bits_of(n)
  base_digits(n, 2)
end

def from_bits(bs)
  from_digits(bs, 2)
end

# ---------------------------------------------------------------------------
# Bit operations, defined over digit lists and lifted to numbers.
#
# There are no native bitwise operators in this language, so these are the
# arithmetic identities on 0/1 digits: AND is a product, OR is a max, XOR is a
# sum mod 2. Doing it on the digit list rather than with `%` tricks means the
# list form is available too, which is what a caller formatting a bit pattern
# actually wants.

def bits_zip(f, a, b)
  w = max(size(a), size(b))
  x = pad_digits(a, w)
  y = pad_digits(b, w)
  map(fn(i) f(nth(i, x), nth(i, y)) end, range(0, w))
end

def bits_and(a, b)
  bits_zip(fn(p, q) p * q end, a, b)
end

def bits_or(a, b)
  bits_zip(fn(p, q) max(p, q) end, a, b)
end

def bits_xor(a, b)
  bits_zip(fn(p, q) (p + q) % 2 end, a, b)
end

def bits_not(bs)
  map(fn(p) 1 - p end, bs)
end

def bit_and(a, b)
  from_bits(bits_and(bits_of(a), bits_of(b)))
end

def bit_or(a, b)
  from_bits(bits_or(bits_of(a), bits_of(b)))
end

def bit_xor(a, b)
  from_bits(bits_xor(bits_of(a), bits_of(b)))
end

# NOT takes a width, and that is not an oversight.
#
# The complement of 5 is 250 in eight bits and 65530 in sixteen; there is no
# answer without a word size. AND/OR/XOR need no width because they cannot set
# a bit above the wider operand, so their result is width-independent.
def bit_not(n, width)
  from_bits(bits_not(pad_digits(bits_of(n), width)))
end

def bit_at(n, i)
  floor(n / expt(2, i)) % 2
end

def shift_left(n, k)
  n * expt(2, k)
end

def shift_right(n, k)
  floor(n / expt(2, k))
end

def popcount(n)
  reduce(fn(a, b) a + b end, 0, bits_of(n))
end

# Bits needed to write n, with zero needing none.
#
# `size(bits_of(0))` is 1, not 0 — base_digits stops at `n < base` and hands
# back [0], because a digit list has to have a digit. So the zero case is taken
# out by hand here, and both power-of-two functions lean on that.
def bit_length(n)
  if n < 1
    0
  else
    size(bits_of(n))
  end
end

def is_power_of_two(n)
  n > 0 && popcount(n) == 1
end

# The smallest power of two that is not less than n.
#
# An exact power must answer itself — the `2^bit_length` shortcut alone would
# turn 8 into 16 — and 0 answers 1, since 1 is the smallest power of two.
def next_power_of_two(n)
  if n < 1
    1
  else
    if is_power_of_two(n)
      n
    else
      expt(2, bit_length(n))
    end
  end
end

test "digit lists round-trip through any base"
  assert base_digits(0, 10) == [0]
  assert base_digits(1234, 10) == [1, 2, 3, 4]
  assert base_digits(5, 2) == [1, 0, 1]
  assert base_digits(255, 16) == [15, 15]
  # The inverse, including the empty list that a filter can hand back.
  assert from_digits([], 10) == 0
  assert from_digits([1, 2, 3], 10) == 123
  assert from_digits(base_digits(48879, 16), 16) == 48879
  # And it agrees with the character-level pair already in this package.
  assert from_digits(base_digits(1234, 10), 10) == from_base(to_base(1234, 10), 10)
end

test "padding a digit list is what makes two of them comparable"
  assert pad_digits([1, 0, 1], 8) == [0, 0, 0, 0, 0, 1, 0, 1]
  # Padding never truncates: a list already wider than the width survives.
  assert pad_digits([1, 1, 1], 2) == [1, 1, 1]
  assert pad_digits([], 3) == [0, 0, 0]
  # The value is unchanged, which is the whole point of padding with zeros.
  assert from_bits(pad_digits(bits_of(5), 16)) == 5
end

test "bitwise operations on unequal widths"
  # 12 is 1100 and 5 is 0101 — the case that is wrong by one place if the
  # shorter operand is not padded first.
  assert bit_and(12, 5) == 4
  assert bit_or(12, 5) == 13
  assert bit_xor(12, 5) == 9
  assert bits_and(bits_of(12), bits_of(5)) == [0, 1, 0, 0]
  # And the same three with the SHORTER operand first, which is the half of the
  # alignment bug the argument order above cannot see: padding to size(a) rather
  # than to the wider of the two still gets 12 AND 5 right.
  assert bit_and(5, 12) == 4
  assert bit_or(5, 12) == 13
  assert bit_xor(5, 12) == 9
  assert bits_or(bits_of(5), bits_of(12)) == [1, 1, 0, 1]
  # x XOR x is 0 and x XOR 0 is x, for every x — the identities that a
  # mis-aligned zip still fails.
  assert bit_xor(48879, 48879) == 0
  assert bit_xor(48879, 0) == 48879
  assert bit_and(255, 0) == 0
  assert bit_or(0, 0) == 0
end

test "NOT is width-relative"
  assert bit_not(5, 8) == 250
  assert bit_not(5, 16) == 65530
  # Complementing twice at the same width is the identity.
  assert bit_not(bit_not(5, 8), 8) == 5
  assert bits_not([1, 0, 1]) == [0, 1, 0]
end

test "shifts and single-bit reads"
  assert shift_left(1, 10) == 1024
  assert shift_right(1024, 10) == 1
  # A right shift past the top is 0, not an error and not 1.
  assert shift_right(1, 5) == 0
  assert shift_right(shift_left(48879, 7), 7) == 48879
  # 5 is 101: bits 0 and 2 set, bit 1 clear, everything above clear.
  assert bit_at(5, 0) == 1
  assert bit_at(5, 1) == 0
  assert bit_at(5, 2) == 1
  assert bit_at(5, 9) == 0
end

test "popcount, bit_length and the powers of two"
  # Zero is the input every one of these gets wrong in a different way.
  assert popcount(0) == 0
  assert bit_length(0) == 0
  assert is_power_of_two(0) == false
  assert next_power_of_two(0) == 1

  assert popcount(255) == 8
  assert popcount(256) == 1
  assert bit_length(255) == 8
  assert bit_length(256) == 9

  assert is_power_of_two(1) == true
  assert is_power_of_two(1024) == true
  assert is_power_of_two(6) == false
  assert is_power_of_two(0 - 4) == false

  # An exact power answers itself; only a strictly larger n rounds up.
  assert next_power_of_two(8) == 8
  assert next_power_of_two(9) == 16
  assert next_power_of_two(5) == 8
  assert next_power_of_two(1) == 1
end

# ---------------------------------------------------------------------------
# Fixed-width output.
#
# `pad_digits_left` is `moji`'s by value, and is repeated here on purpose: shinsuu's
# only dependency is retsu, so that the numeral core carries no edge to the
# string package for one three-line helper. If a caller has both, moji's is the
# one to prefer — these agree, and only one of them is a string library's job.

def pad_digits_left(s, width, pad)
  if size(s) >= width
    s
  else
    pad_digits_left(join([pad, s], ""), width, pad)
  end
end

# A base rendering that is exactly `width` characters wide.
#
# Byte and word dumps need this: to_hex(10) is "a", and a hex dump that prints
# "a" where every other byte prints two characters is unreadable and unparsable.
# Over-wide input is NOT truncated — silently dropping the high digits of a
# number is worse than a ragged column.
def to_base_width(n, base, width)
  pad_digits_left(to_base(n, base), width, "0")
end

def to_hex_width(n, width)
  to_base_width(n, 16, width)
end

def to_binary_width(n, width)
  to_base_width(n, 2, width)
end

# ---------------------------------------------------------------------------
# Properties of the decimal representation.

# Repeated digit sum until one digit is left.
#
# The closed form n % 9 is the usual shortcut and it is wrong twice: it gives 0
# for 9, and 9 for 0 if written as ((n - 1) % 9) + 1. Iterating is slower and
# right for both.
def digital_root(n)
  if n < 10
    n
  else
    digital_root(digit_sum(n))
  end
end

# The digits read backwards, as a number.
#
# Trailing zeros do not survive — 1200 reverses to 21, not to "0021" — because
# the result is a number and a number has no leading zeros. That is the reason
# reverse_digits is not an involution, and why the palindrome test below
# compares digit LISTS instead of calling this twice.
def reverse_digits(n)
  from_digits(reverse(digits_of(n)), 10)
end

def is_palindrome_number(n)
  digits_of(n) == reverse(digits_of(n))
end

# The same question asked in another base, where the answer often differs:
# 5 is 101 in binary and a palindrome there, while 6 is 110 and is not.
def is_palindrome_in_base(n, base)
  base_digits(n, base) == reverse(base_digits(n, base))
end

# ---------------------------------------------------------------------------
# Gray code — a numeral system where counting changes one bit at a time.
#
# Included because it is base conversion that is not positional: the value of a
# digit depends on the digits left of it. Encoding is one XOR; decoding is not
# its own inverse and needs the running fold, which is the asymmetry that makes
# a naive `gray_decode = gray_encode` implementation pass for 0, 1, 2 and 3 and
# then fail.
def gray_encode(n)
  bit_xor(n, shift_right(n, 1))
end

def gray_decode(g)
  gray_decode_from(g, shift_right(g, 1))
end

def gray_decode_from(acc, shifted)
  if shifted < 1
    acc
  else
    gray_decode_from(bit_xor(acc, shifted), shift_right(shifted, 1))
  end
end

test "fixed-width rendering"
  assert to_hex_width(10, 2) == "0a"
  assert to_hex_width(255, 2) == "ff"
  assert to_binary_width(5, 8) == "00000101"
  assert to_base_width(0, 16, 4) == "0000"
  # Over-wide input keeps every digit rather than losing the high end.
  assert to_hex_width(4096, 2) == "1000"
  assert pad_digits_left("7", 3, " ") == "  7"
  assert pad_digits_left("abcd", 2, "0") == "abcd"
  assert pad_digits_left("", 2, "0") == "00"
  # Padding is invisible to the parser, which is the property that makes a
  # fixed-width dump round-trip.
  assert from_base(to_hex_width(10, 8), 16) == 10
end

test "digital root"
  # Zero and nine are exactly where the mod-9 shortcut breaks.
  assert digital_root(0) == 0
  assert digital_root(9) == 9
  assert digital_root(99) == 9
  assert digital_root(12345) == 6
  # It really is repeated: 999999 sums to 54, then to 9.
  assert digital_root(999999) == 9
  assert digital_root(7) == 7
end

test "reversing digits, and where the reversal is not reversible"
  assert reverse_digits(1234) == 4321
  assert reverse_digits(0) == 0
  assert reverse_digits(7) == 7
  # Trailing zeros are destroyed, so this is NOT an involution in general.
  assert reverse_digits(1200) == 21
  assert reverse_digits(reverse_digits(1200)) == 12
  # It is an involution whenever the last digit is not zero.
  assert reverse_digits(reverse_digits(1234)) == 1234
end

test "palindromic numbers, in decimal and elsewhere"
  assert is_palindrome_number(0) == true
  assert is_palindrome_number(7) == true
  assert is_palindrome_number(1221) == true
  assert is_palindrome_number(12321) == true
  assert is_palindrome_number(10) == false
  assert is_palindrome_number(1231) == false
  # The base changes the answer: 5 is 101 in binary, 6 is 110.
  assert is_palindrome_in_base(5, 2) == true
  assert is_palindrome_in_base(6, 2) == false
  assert is_palindrome_in_base(9, 2) == true
end

test "Gray code is a bijection whose successive values differ by one bit"
  assert gray_encode(0) == 0
  assert gray_encode(1) == 1
  assert gray_encode(2) == 3
  assert gray_encode(3) == 2
  # Both sweeps run the whole 7-bit space rather than a sample, so every
  # carry pattern a 7-bit counter can produce is covered.
  #
  # Decoding undoes encoding for every n — the fold, not a second XOR. A
  # `gray_decode = gray_encode` implementation passes for 0, 1, 2 and 3 and
  # first disagrees at 4.
  assert size(filter(fn(n) !(gray_decode(gray_encode(n)) == n) end, range(0, 128))) == 0
  # And the defining property: one bit changes per step, for every step.
  assert size(filter(fn(n) !(popcount(bit_xor(gray_encode(n), gray_encode(n + 1))) == 1) end, range(0, 128))) == 0
end

# ---------------------------------------------------------------------------
# Roman numerals — a numeral system that is not positional at all.
#
# Worth carrying in a base-conversion package precisely because none of the
# machinery above applies: there is no base, no digit list, no zero, and the
# value of a symbol depends on what follows it. Anything that works for both
# this and base 16 is working for the right reason.
#
# The six subtractive pairs are entries in the table rather than a special case
# in the loop. Written as a rule ("if the next symbol is larger, subtract") the
# encoder emits IC for 99 and IM for 999, which parse back correctly and are
# not Roman numerals.

def roman_values()
  [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
end

def roman_symbols()
  ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
end

# Zero and anything below it render as the empty string.
#
# There is no Roman zero, so there is nothing honest to return; "" is the one
# answer that stays consistent under from_roman, which reads "" as 0.
def to_roman(n)
  to_roman_from(n, roman_values(), roman_symbols(), 0)
end

# The two tables are carried down the recursion rather than re-read from the
# functions above. `roman_values()` builds a fresh thirteen-element list every
# time it is named, and the naive version names it three times per step of a
# recursion that runs fifteen deep — building the tables once per numeral
# instead of forty-five times is most of this package's test-suite runtime.
def to_roman_from(n, vs, ss, i)
  if n < 1 || i >= size(vs)
    ""
  else
    v = nth(i, vs)
    if n >= v
      join([nth(i, ss), to_roman_from(n - v, vs, ss, i)], "")
    else
      to_roman_from(n, vs, ss, i + 1)
    end
  end
end

def roman_value(ch)
  roman_value_of(upcase(ch))
end

def roman_value_of(c)
  if c == "M"
    1000
  else
    if c == "D"
      500
    else
      if c == "C"
        100
      else
        if c == "L"
          50
        else
          if c == "X"
            10
          else
            if c == "V"
              5
            else
              if c == "I"
                1
              else
                0
              end
            end
          end
        end
      end
    end
  end
end

# Read a numeral by looking one symbol ahead: a symbol worth less than the one
# after it is subtracted, otherwise added. That single rule covers all six
# subtractive pairs without listing them, which is why the ASYMMETRY with
# to_roman is deliberate — the reader is permissive, the writer is not.
def from_roman(text)
  from_roman_at(chars(upcase(trim(text))), 0)
end

# These call roman_value_of, not roman_value: from_roman has already upcased the
# whole string, and upcasing each character a second time is a string
# allocation per symbol per lookahead for no change in the answer.
def from_roman_at(cs, i)
  if i >= size(cs)
    0
  else
    v = roman_value_of(nth(i, cs))
    if v < roman_next(cs, i + 1)
      from_roman_at(cs, i + 1) - v
    else
      from_roman_at(cs, i + 1) + v
    end
  end
end

def roman_next(cs, i)
  if i >= size(cs)
    0
  else
    roman_value_of(nth(i, cs))
  end
end

# Does this text spell exactly the canonical numeral for the number it reads as?
#
# "IIII" and "IC" both parse, to 4 and 99; neither is what a Roman wrote. The
# check is round-tripping through the encoder, which is the only definition of
# canonical that cannot drift from the encoder's own table.
def is_canonical_roman(text)
  n = from_roman(text)
  n > 0 && to_roman(n) == upcase(trim(text))
end

test "writing Roman numerals, including every subtractive pair"
  assert to_roman(1) == "I"
  assert to_roman(4) == "IV"
  assert to_roman(9) == "IX"
  assert to_roman(40) == "XL"
  assert to_roman(90) == "XC"
  assert to_roman(400) == "CD"
  assert to_roman(900) == "CM"
  assert to_roman(1994) == "MCMXCIV"
  assert to_roman(2024) == "MMXXIV"
  assert to_roman(3999) == "MMMCMXCIX"
  # There is no Roman zero, and no negative numeral either.
  assert to_roman(0) == ""
  assert to_roman(0 - 5) == ""
  # 99 is XCIX, never IC — the case a subtract-if-smaller encoder gets wrong.
  assert to_roman(99) == "XCIX"
  assert to_roman(999) == "CMXCIX"
end

test "reading Roman numerals"
  assert from_roman("I") == 1
  assert from_roman("MCMXCIV") == 1994
  assert from_roman("MMMCMXCIX") == 3999
  # Case is not part of the numeral.
  assert from_roman("mcmxciv") == 1994
  assert from_roman("  XIV  ") == 14
  # The empty numeral is 0, which is what makes to_roman(0) == "" consistent.
  assert from_roman("") == 0
  # The reader is permissive on purpose: these parse even though no Roman
  # would have written them.
  assert from_roman("IIII") == 4
  assert from_roman("IC") == 99
end

test "every numeral from 1 to 3999 survives the round trip"
  # The one assertion that catches a table typo anywhere in the range, which
  # spot-checking a dozen values would not.
  #
  # It is chunked at 400 because `range` is recursive in this interpreter and
  # overflows the process stack somewhere between 400 and 800 elements —
  # `range(1, 4000)` aborts before a single numeral is built. The chunk width is
  # a runtime limit, not anything about Roman numerals.
  assert reduce(fn(acc, s) acc + size(filter(fn(n) !(from_roman(to_roman(n)) == n) end, range(s, min(s + 400, 4000)))) end, 0, [1, 401, 801, 1201, 1601, 2001, 2401, 2801, 3201, 3601]) == 0
end

test "canonical spelling is stricter than parseable spelling"
  assert is_canonical_roman("XCIX") == true
  assert is_canonical_roman("MCMXCIV") == true
  assert is_canonical_roman("IIII") == false
  assert is_canonical_roman("IC") == false
  # Nothing is the canonical spelling of nothing.
  assert is_canonical_roman("") == false
end

# ---------------------------------------------------------------------------
# Bases up to 36, and parsing that can fail.
#
# `digits()` at the top of this file stops at "f" because it was written for
# hex, and `to_base(n, 36)` therefore reads off the end of it. Widening that
# list in place would change what `to_base` accepts, so the wide table is a
# second one — and because its first sixteen entries are the same characters,
# `to_base_n` and `to_base` agree everywhere both are defined. That agreement is
# asserted below rather than assumed.

def digits36()
  ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
   "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
   "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
   "u", "v", "w", "x", "y", "z"]
end

def digit_value36(ch)
  value_index(digits36(), downcase(ch), 0)
end

def to_base_n(n, base)
  if n == 0
    "0"
  else
    join(reverse(to_base_n_digits(n, base)), "")
  end
end

def to_base_n_digits(n, base)
  if n < 1
    []
  else
    cons(nth(n % base, digits36()), to_base_n_digits(floor(n / base), base))
  end
end

def to_base36(n)
  to_base_n(n, 36)
end

def all_digits_in_base(cs, base)
  is_empty(filter(fn(c) digit_value36(c) < 0 || digit_value36(c) >= base end, cs))
end

# Is every character of `text` a digit of `base`?
#
# Emptiness is false, not vacuously true: "" is not a number in any base, and a
# caller reaching for this is about to parse.
def is_valid_in_base(text, base)
  cs = chars(downcase(trim(text)))
  size(cs) > 0 && all_digits_in_base(cs, base)
end

# Parse, answering nil when the text is not a numeral in this base.
#
# `from_base` above cannot fail: digit_value returns 0 - 1 for an unknown
# character and the Horner fold happily folds it in, so from_base("zz", 16)
# returns a number that looks like an answer and is not one. That is the trap
# this function exists to close — nil is not a number, so a caller cannot use
# the result by accident.
#
# Surface whitespace and letter case are not errors; a sign, a digit outside the
# base, and the empty string are.
def parse_int(text, base)
  cs = chars(downcase(trim(text)))
  if is_empty(cs)
    nil
  else
    if first(cs) == "-"
      parse_signed(rest(cs), base, 0 - 1)
    else
      parse_signed(cs, base, 1)
    end
  end
end

def parse_signed(cs, base, sign)
  if is_empty(cs) || !(all_digits_in_base(cs, base))
    nil
  else
    sign * reduce(fn(acc, c) (acc * base) + digit_value36(c) end, 0, cs)
  end
end

def from_base36(text)
  parse_int(text, 36)
end

test "the wide table agrees with the narrow one wherever both apply"
  # If these ever diverge, one of the two digit lists has been edited alone.
  assert to_base_n(255, 16) == to_hex(255)
  assert to_base_n(1000, 2) == to_binary(1000)
  assert to_base_n(8, 8) == to_octal(8)
  assert to_base_n(0, 16) == "0"
end

test "base 36"
  assert to_base36(35) == "z"
  assert to_base36(36) == "10"
  assert to_base36(0) == "0"
  assert to_base36(1295) == "zz"
  assert from_base36("zz") == 1295
  assert from_base36("10") == 36
  # Round trip on a value with digits from both halves of the table.
  assert from_base36(to_base36(123456789)) == 123456789
end

test "parse_int refuses what from_base would have swallowed"
  assert parse_int("ff", 16) == 255
  # Case and surrounding space are not errors.
  assert parse_int("FF", 16) == 255
  assert parse_int("  ff  ", 16) == 255
  assert parse_int("0", 10) == 0
  assert parse_int("-ff", 16) == 0 - 255
  # A digit outside the base is nil rather than a plausible number — the
  # distinguishing case, since from_base("zz", 16) returns a number here.
  assert parse_int("zz", 16) == nil
  assert parse_int("9", 8) == nil
  assert parse_int("", 10) == nil
  assert parse_int("-", 16) == nil
  assert parse_int("12x4", 10) == nil
  # The same digit is legal one base higher.
  assert parse_int("9", 10) == 9
  assert parse_int("g", 17) == 16
  # Control: on input from_base handles, the two agree.
  assert parse_int("beef", 16) == from_base("beef", 16)
end

test "validity is decided before parsing, and empty is not valid"
  assert is_valid_in_base("ff", 16) == true
  assert is_valid_in_base("FF", 16) == true
  assert is_valid_in_base("zz", 16) == false
  assert is_valid_in_base("101", 2) == true
  assert is_valid_in_base("102", 2) == false
  # Vacuous truth is the wrong answer here.
  assert is_valid_in_base("", 10) == false
  # A sign is not a digit, so the validity check and parse_int disagree on
  # "-5" on purpose: one asks about digits, the other about numerals.
  assert is_valid_in_base("-5", 10) == false
  assert parse_int("-5", 10) == 0 - 5
end

# ---------------------------------------------------------------------------
# Checksums.
#
# Every one of these comes in a pair — a verifier and the digit that MAKES a
# number verify — and the pair is what gets tested, because a verifier alone can
# be wrong in a way no hand-picked example reveals. If `check_digit` and `valid`
# are both derived from the same weights, then "appending the check digit makes
# it valid" is an identity that has to hold for every input, and a swapped
# weight or an off-by-one in the position breaks it immediately.

# The simplest checksum there is: the digit sum, modulo m.
def mod_checksum(n, m)
  digit_sum(n) % m
end

# The digit to append so that the result checksums to zero.
#
# Only meaningful for m up to 10, because the answer has to BE a digit — and
# the outer % m is what turns the m case back into 0 rather than emitting "m".
def mod_check_digit(n, m)
  (m - mod_checksum(n, m)) % m
end

def mod_check_valid(n, m)
  mod_checksum(n, m) == 0
end

# The Luhn digit to append. Note the `i + 1`: appending shifts every existing
# digit one place further from the right, so the doubling alternates the other
# way round from luhn_valid's. Reusing luhn_digit with the same index would
# produce a check digit that fails the checker it was computed for.
def luhn_check_digit(n)
  ds = reverse(digits_of(n))
  total = reduce(fn(acc, i) acc + luhn_digit(nth(i, ds), i + 1) end, 0, range(0, size(ds)))
  (10 - (total % 10)) % 10
end

# Luhn over a digit LIST rather than a number, so a card number with leading
# zeros can be represented at all. Empty is false, not vacuously true: the
# checksum of no digits is not a passing checksum.
def luhn_valid_digits(ds)
  if is_empty(ds)
    false
  else
    rs = reverse(ds)
    reduce(fn(acc, i) acc + luhn_digit(nth(i, rs), i) end, 0, range(0, size(rs))) % 10 == 0
  end
end

# Luhn on the form a card number is actually written in. Spaces and hyphens are
# grouping, not data; anything else is a rejection rather than a skipped
# character, since silently ignoring a stray letter would validate a typo.
def luhn_valid_text(text)
  cs = chars(replace(replace(trim(text), " ", ""), "-", ""))
  size(cs) > 0 && all_digits_in_base(cs, 10) && luhn_valid_digits(map(fn(c) digit_value36(c) end, cs))
end

# ---------------------------------------------------------------------------
# ISBN-10 — a mod-11 checksum, which is why it needs an eleventh digit.
#
# X is not a letter that happens to appear in book numbers; it is the digit 10,
# and it is legal only in the check position. That is the whole reason ISBN-10
# is a better test than Luhn: the check "digit" is not always a digit.

def isbn10_chars(text)
  chars(upcase(replace(replace(trim(text), "-", ""), " ", "")))
end

def isbn10_char_value(ch)
  if ch == "X"
    10
  else
    digit_value36(ch)
  end
end

def isbn10_char_ok(ch, i)
  if ch == "X"
    i == 9
  else
    digit_value36(ch) >= 0 && digit_value36(ch) < 10
  end
end

def isbn10_ok_chars(cs)
  is_empty(filter(fn(i) !(isbn10_char_ok(nth(i, cs), i)) end, range(0, size(cs))))
end

# Weights run 10, 9, 8 … down to 1, so this is also the partial sum over a
# nine-character prefix — which is what isbn10_check_char needs.
def isbn10_weighted(cs)
  reduce(fn(acc, i) acc + ((10 - i) * isbn10_char_value(nth(i, cs))) end, 0, range(0, size(cs)))
end

def isbn10_valid(text)
  cs = isbn10_chars(text)
  size(cs) == 10 && isbn10_ok_chars(cs) && (isbn10_weighted(cs) % 11 == 0)
end

def isbn10_digit_char(v)
  if v == 10
    "X"
  else
    to_s(v)
  end
end

def isbn10_check_char(first9)
  cs = isbn10_chars(first9)
  if !(size(cs) == 9) || !(isbn10_ok_chars(cs))
    nil
  else
    isbn10_digit_char((11 - (isbn10_weighted(cs) % 11)) % 11)
  end
end

def isbn10_complete(first9)
  cs = isbn10_chars(first9)
  c = isbn10_check_char(first9)
  if c == nil
    nil
  else
    join(push(cs, c), "")
  end
end

test "the mod-N checksum and its check digit are inverses"
  assert mod_checksum(1234, 9) == 1
  assert mod_checksum(1234, 10) == 0
  assert mod_check_digit(1234, 9) == 8
  assert mod_check_valid(1234, 9) == false
  # Zero is already its own checksum in every modulus.
  assert mod_check_digit(9, 9) == 0

  # The identity: appending the check digit makes the number check out. This is
  # what a swapped sign or a missing outer modulo fails, and no single
  # hand-picked pair would.
  assert size(filter(fn(n) !(mod_check_valid((n * 10) + mod_check_digit(n, 7), 7)) end, range(1, 256))) == 0
  assert size(filter(fn(n) !(mod_check_valid((n * 10) + mod_check_digit(n, 9), 9)) end, range(1, 256))) == 0
end

test "the Luhn check digit is the one the Luhn checker wants"
  # 79927398713 is the standard valid number, so its first ten digits must
  # generate a 3.
  assert luhn_check_digit(7992739871) == 3
  # And the identity over a range, which the off-by-one in the doubling
  # position fails on roughly half of all inputs.
  assert size(filter(fn(n) !(luhn_valid((n * 10) + luhn_check_digit(n))) end, range(1, 256))) == 0
end

test "Luhn over digit lists and over written text"
  assert luhn_valid_digits(digits_of(79927398713)) == true
  assert luhn_valid_digits(digits_of(79927398714)) == false
  # A checksum of nothing does not pass.
  assert luhn_valid_digits([]) == false
  # Leading zeros are unrepresentable as an integer, and it turns out they can
  # never change the verdict — every position is counted from the RIGHT, and a
  # zero contributes zero whether it is doubled or not. That is what makes the
  # integer-taking luhn_valid safe rather than merely lucky.
  assert luhn_valid_digits([0, 7, 9, 9, 2, 7, 3, 9, 8, 7, 1, 3]) == true
  assert luhn_valid_digits([0, 0, 7, 9, 9, 2, 7, 3, 9, 8, 7, 1, 3]) == true

  # Grouping characters are not data.
  assert luhn_valid_text("4539 1488 0343 6467") == true
  assert luhn_valid_text("4539-1488-0343-6467") == true
  assert luhn_valid_text("4539148803436467") == true
  assert luhn_valid_text("4539 1488 0343 6468") == false
  # A stray non-digit is a rejection, not a character to skip past.
  assert luhn_valid_text("4539 1488 0343 646z") == false
  assert luhn_valid_text("") == false
end

test "ISBN-10, where the check digit is sometimes not a digit"
  # Two independently checkable ISBNs, the second ending in X.
  assert isbn10_valid("0306406152") == true
  assert isbn10_valid("080442957X") == true
  assert isbn10_valid("0-306-40615-2") == true
  assert isbn10_valid("0 306 40615 2") == true
  # One digit changed, and one transposition — mod 11 catches both, which is
  # the reason ISBN uses 11 rather than 10.
  assert isbn10_valid("0306406153") == false
  assert isbn10_valid("0306406512") == false
  # Wrong length, lowercase-x, and X out of position are all rejections.
  assert isbn10_valid("030640615") == false
  assert isbn10_valid("03064061522") == false
  assert isbn10_valid("X306406152") == false
  assert isbn10_valid("") == false
end

test "the ISBN-10 check character, including the X case"
  assert isbn10_check_char("030640615") == "2"
  assert isbn10_check_char("080442957") == "X"
  # Not nine characters, or not all digits, is nil rather than a guess.
  assert isbn10_check_char("0306406152") == nil
  assert isbn10_check_char("03064061X") == nil
  assert isbn10_check_char("") == nil

  assert isbn10_complete("030640615") == "0306406152"
  assert isbn10_complete("080442957") == "080442957X"

  # The identity: a completed prefix always validates, for every prefix.
  #
  # The window really does contain the X case rather than only decimal check
  # digits — asserted rather than assumed, since that is the branch a to_s-only
  # implementation renders as "10" and fails on. 000000006 is the smallest such
  # prefix: its weighted sum is 2 x 6 = 12, and 12 is 1 mod 11.
  assert isbn10_check_char("000000006") == "X"
  assert size(filter(fn(n) !(isbn10_valid(isbn10_complete(to_base_width(n, 10, 9)))) end, range(1, 128))) == 0
end
