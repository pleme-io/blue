use("retsu")
# angou (暗号) — number theory and the classical ciphers built on it.
#
# Classical, and labelled as such: nothing here is secure, and the point of
# shipping it is that the mathematics underneath — modular exponentiation,
# primality, Euler's totient — is the same mathematics modern cryptography
# uses. A caesar cipher is the readable end of that; do not deploy it.

def is_prime(n)
  if n < 2
    false
  else
    if n < 4
      true
    else
      if n % 2 == 0
        false
      else
        no_factor_from(n, 3)
      end
    end
  end
end

def no_factor_from(n, k)
  if k * k > n
    true
  else
    if n % k == 0
      false
    else
      no_factor_from(n, k + 2)
    end
  end
end

def primes_below(n)
  filter(fn(k) is_prime(k) end, range(2, n))
end

def prime_factors(n)
  factor_from(n, 2)
end

def factor_from(n, k)
  if n < 2
    []
  else
    if k * k > n
      [n]
    else
      if n % k == 0
        cons(k, factor_from(floor(n / k), k))
      else
        factor_from(n, k + 1)
      end
    end
  end
end

# Modular exponentiation by repeated squaring.
#
# The naive `expt(base, e) % m` overflows long before it is useful — this is
# the function that makes the exponent size irrelevant.
def mod_pow(base, e, m)
  if e == 0
    1
  else
    half = mod_pow(base, floor(e / 2), m)
    sq = (half * half) % m
    if e % 2 == 1
      (sq * base) % m
    else
      sq
    end
  end
end

# Euler's totient: how many integers below n are coprime to it.
# Euler's totient: how many integers in [1, n] are coprime to n.
#
# n = 1 is special-cased because the general count runs over [1, n), which is
# empty for 1 — and the convention is totient(1) = 1, since 1 is coprime to
# itself. Every table agrees; the formula does not.
def totient(n)
  if n == 1
    1
  else
    size(filter(fn(k) gcd(k, n) == 1 end, range(1, n)))
  end
end

def alphabet()
  ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
   "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
end

def letter_index(ch)
  find_index_of(alphabet(), ch, 0)
end

def find_index_of(xs, v, i)
  if i >= size(xs)
    0 - 1
  else
    if nth(i, xs) == v
      i
    else
      find_index_of(xs, v, i + 1)
    end
  end
end

# Shift each letter by n; anything that is not a lowercase letter passes
# through untouched, so punctuation and spacing survive a round trip.
def caesar(text, n)
  join(map(fn(ch) shift_char(ch, n) end, chars(text)), "")
end

def shift_char(ch, n)
  i = letter_index(ch)
  if i < 0
    ch
  else
    nth(((i + n) % 26 + 26) % 26, alphabet())
  end
end

def rot13(text)
  caesar(text, 13)
end

test "primality, including the classic off-by-one cases"
  assert is_prime(2) == true
  assert is_prime(3) == true
  assert is_prime(1) == false
  assert is_prime(0) == false
  assert is_prime(9) == false
  assert is_prime(97) == true
  assert primes_below(12) == [2, 3, 5, 7, 11]
end

test "prime factorisation multiplies back"
  assert prime_factors(12) == [2, 2, 3]
  assert prime_factors(97) == [97]
  assert reduce(fn(a, b) a * b end, 1, prime_factors(360)) == 360
end

test "modular exponentiation stays in range where expt would overflow"
  assert mod_pow(2, 10, 1000) == 24
  assert mod_pow(3, 0, 7) == 1
  # Fermat's little theorem: a^(p-1) = 1 mod p for prime p.
  assert mod_pow(5, 96, 97) == 1
end

test "totient"
  assert totient(1) == 1
  assert totient(9) == 6
  # For a prime p, totient(p) is p-1.
  assert totient(97) == 96
end

test "caesar round-trips and rot13 is its own inverse"
  assert caesar("abc", 1) == "bcd"
  assert caesar(caesar("hello world", 5), 0 - 5) == "hello world"
  assert rot13(rot13("attack at dawn")) == "attack at dawn"
  # Non-letters pass through rather than being mangled.
  assert caesar("a b", 1) == "b c"
end
