use("retsu")
# angou (暗号) — number theory and the classical ciphers built on it.
#
# Classical, and labelled as such: nothing here is secure, and the point of
# shipping it is that the mathematics underneath — modular exponentiation,
# primality, Euler's totient — is the same mathematics modern cryptography
# uses. A caesar cipher is the readable end of that; do not deploy it.
#
# NONE OF THE CIPHERS BELOW ARE SECURE, and that is not a caveat, it is the
# curriculum. Every one of them is broken here, in this file, by code that is
# shorter than the cipher it breaks: `crack_caesar` recovers a caesar key with
# no key, and `letter_counts` is all it takes to see through the substitution
# cipher and the vigenere alike. Rail fence does not even change the letters.
# Use them to learn the shape of the problem; never to keep a secret.

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

# The sieve of Eratosthenes, in the only shape blue can express it.
#
# The textbook sieve mutates a board of flags; blue has no mutable array, so
# instead of crossing marks off in place we take the head as prime and drop
# its multiples from what is left. Be honest about what that costs: dropping
# the multiples of p means testing every survivor against p, so this is a
# sieve-shaped filter and not the near-linear sieve. What survives the change
# is the property that separates it from `primes_below` — that one asks
# `is_prime` of every candidate, this one never divides by a composite.
def sieve(n)
  sieve_from(range(2, n))
end

def sieve_from(xs)
  if is_empty(xs)
    []
  else
    p = first(xs)
    cons(p, sieve_from(filter(fn(k) k % p != 0 end, rest(xs))))
  end
end

# 1-indexed, because "the first prime" is 2 and nobody means the zeroth.
def nth_prime(k)
  if k < 1
    0 - 1
  else
    nth_prime_from(k, 2)
  end
end

def nth_prime_from(k, c)
  if is_prime(c)
    if k == 1
      c
    else
      nth_prime_from(k - 1, c + 1)
    end
  else
    nth_prime_from(k, c + 1)
  end
end

# Strictly greater than n, so next_prime(7) is 11 and not 7 — otherwise
# iterating with it never terminates.
def next_prime(n)
  if n < 2
    2
  else
    next_prime_from(n + 1)
  end
end

def next_prime_from(c)
  if is_prime(c)
    c
  else
    next_prime_from(c + 1)
  end
end

def is_coprime(a, b)
  gcd(a, b) == 1
end

# Bezout: returns [g, x, y] with a*x + b*y == g and g == gcd(a, b).
#
# The x is the whole reason this exists — when g is 1 it is a's inverse mod b,
# which plain gcd computes and throws away. Written for non-negative a and b;
# blue's `%` and `floor(a / b)` agree on floor division, so the identity
# survives negatives too, but the tests only pin the non-negative domain.
def extended_gcd(a, b)
  if b == 0
    [a, 1, 0]
  else
    r = extended_gcd(b, a % b)
    [nth(0, r), nth(2, r), nth(1, r) - floor(a / b) * nth(2, r)]
  end
end

# The inverse of a mod m, or 0-1 when there is none. An inverse exists exactly
# when gcd(a, m) == 1, so this doubles as a coprimality witness: a returned
# value is a proof, and 0-1 is the honest "no such number" rather than a
# plausible-looking wrong one.
def mod_inverse(a, m)
  if m < 1
    0 - 1
  else
    r = extended_gcd(a % m, m)
    if nth(0, r) != 1
      0 - 1
    else
      nth(1, r) % m
    end
  end
end

# Chinese remainder for exactly two congruences: the smallest non-negative x
# with x % n1 == a1 and x % n2 == a2, or 0-1 when no such x exists.
#
# Coprime moduli are the case everyone quotes, but the general one is barely
# more work and the difference is observable: x = 0 mod 2 and x = 1 mod 4 has
# no solution at all, and a version that assumes coprimality returns a wrong
# answer for it rather than saying so. The answer is unique mod lcm(n1, n2).
def crt2(a1, n1, a2, n2)
  g = gcd(n1, n2)
  diff = a2 - a1
  if diff % g != 0
    0 - 1
  else
    n1g = floor(n1 / g)
    n2g = floor(n2 / g)
    t = ((floor(diff / g) % n2g) * mod_inverse(n1g % n2g, n2g)) % n2g
    (a1 + n1 * t) % (n1 * n2g)
  end
end

# Every divisor of n, ascending, n included. Trial division over the whole
# range rather than pairing up at sqrt(n): the pairing version has to sort its
# two halves back together, and this package is read more than it is run.
def divisors(n)
  if n < 1
    []
  else
    filter(fn(k) n % k == 0 end, range(1, n + 1))
  end
end

def proper_divisors(n)
  filter(fn(k) k != n end, divisors(n))
end

# sigma(n), counting n itself — the convention every table uses.
def sum_of_divisors(n)
  reduce(fn(a, b) a + b end, 0, divisors(n))
end

# Perfect: equal to the sum of its PROPER divisors, which is sigma(n) == 2n.
# The pair of assertions that earns its keep is 6 and 1 together — an
# implementation that wrote sigma(n) == n instead calls 1 perfect and 6 not,
# and either one alone lets that through.
def is_perfect(n)
  n > 0 && sum_of_divisors(n) == 2 * n
end

def is_abundant(n)
  n > 0 && sum_of_divisors(n) > 2 * n
end

def is_deficient(n)
  n > 0 && sum_of_divisors(n) < 2 * n
end

# The smallest m >= 1 with a^m == 1 mod n, or 0-1 when a is not invertible.
#
# n < 2 answers 1 rather than looping: mod 1 everything is 0, so the loop's
# "did we reach 1 yet" test would never fire.
def multiplicative_order(a, n)
  if n < 2
    1
  else
    if is_coprime(a, n) == false
      0 - 1
    else
      order_from(a % n, n, 1, a % n)
    end
  end
end

def order_from(a, n, m, cur)
  if cur == 1
    m
  else
    order_from(a, n, m + 1, (cur * a) % n)
  end
end

# Carmichael's lambda: the exponent of the group of units mod n, i.e. the
# smallest m with a^m == 1 mod n for EVERY a coprime to n.
#
# It divides totient(n) and is often strictly smaller — lambda(8) is 2 while
# totient(8) is 4 — which is exactly why RSA is stated with lambda in the
# modern formulation and totient in the original one.
def carmichael_lambda(n)
  if n < 2
    1
  else
    reduce(fn(acc, a) lcm(acc, multiplicative_order(a, n)) end, 1,
           filter(fn(a) is_coprime(a, n) end, range(1, n)))
  end
end

# Fermat's test to base a. A `false` is a PROOF that n is composite; a `true`
# proves nothing at all, which is what is_carmichael below makes concrete.
def fermat_probable_prime(n, a)
  if n < 2
    false
  else
    mod_pow(a % n, n - 1, n) == 1
  end
end

# A Carmichael number is composite and yet passes Fermat's test for every base
# coprime to it — the reason the Fermat test is not a primality proof and the
# reason Miller-Rabin exists. 561 = 3 * 11 * 17 is the smallest.
def is_carmichael(n)
  if n < 2
    false
  else
    if is_prime(n)
      false
    else
      size(filter(fn(a) is_coprime(a, n) && fermat_probable_prime(n, a) == false end,
                  range(2, n))) == 0
    end
  end
end

# The smallest generator of the units mod a prime p — where Diffie-Hellman
# gets its base. Defined here only for prime p; 0-1 for anything else, since
# a composite modulus may have no primitive root at all (8 does not).
def primitive_root(p)
  if is_prime(p) == false
    0 - 1
  else
    if p == 2
      1
    else
      first(filter(fn(g) multiplicative_order(g, p) == p - 1 end, range(2, p)))
    end
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

# Vigenere: a caesar whose shift is driven by a repeating key.
#
# The trap is the non-letter. A space must pass through WITHOUT advancing the
# key, or encrypt and decrypt fall out of step the moment the two texts have
# punctuation in different places — and the bug is invisible until then,
# because a text of pure letters round-trips either way. That is what
# `vigenere("at tack", "lemon")` pins in the tests.
def vigenere(text, key)
  vigenere_with(text, key, 1)
end

def vigenere_decrypt(text, key)
  vigenere_with(text, key, 0 - 1)
end

def vigenere_with(text, key, dir)
  ks = key_shifts(key)
  if is_empty(ks)
    text
  else
    join(vigenere_chars(chars(text), ks, 0, dir), "")
  end
end

# Non-letters in the KEY are dropped rather than treated as shift zero, so
# "lemon" and "l e m o n" are the same key.
def key_shifts(key)
  filter(fn(i) i >= 0 end, map(fn(ch) letter_index(ch) end, chars(downcase(key))))
end

def vigenere_chars(cs, ks, ki, dir)
  if is_empty(cs)
    []
  else
    ch = first(cs)
    if letter_index(ch) < 0
      cons(ch, vigenere_chars(rest(cs), ks, ki, dir))
    else
      cons(shift_char(ch, nth(ki % size(ks), ks) * dir),
           vigenere_chars(rest(cs), ks, ki + 1, dir))
    end
  end
end

# Atbash reverses the alphabet: a<->z, b<->y. It has no key at all, so the
# only property worth asserting is that it is its own inverse.
def atbash(text)
  join(map(fn(ch) atbash_char(ch) end, chars(text)), "")
end

def atbash_char(ch)
  i = letter_index(ch)
  if i < 0
    ch
  else
    nth(25 - i, alphabet())
  end
end

# Rail fence: write the text down and up across `rails` lines, then read the
# lines off in order. A transposition rather than a substitution — the letters
# are the same ones, which is why letter frequency cannot touch it and why
# anagramming can.
def rail_fence(text, rails)
  if rails < 2
    text
  else
    join(map(fn(i) nth(i, chars(text)) end, rail_order(size(chars(text)), rails)), "")
  end
end

# Decryption is the inverse permutation. Building `rail_order` once and
# searching it is the whole trick: writing a second zigzag walk that fills the
# rails back in is where hand-written implementations get the ragged last
# rail wrong.
def rail_fence_decrypt(text, rails)
  if rails < 2
    text
  else
    cs = chars(text)
    order = rail_order(size(cs), rails)
    join(map(fn(i) nth(index_of(order, i), cs) end, range(0, size(cs))), "")
  end
end

# The positions of the original text, grouped by rail — i.e. cipher position
# j holds original character rail_order[j].
def rail_order(n, rails)
  flat_map(fn(r) filter(fn(i) rail_of(i, rails) == r end, range(0, n)) end,
           range(0, rails))
end

# The zigzag has period 2*rails-2: down to the bottom rail and back up,
# without repeating either end.
def rail_of(i, rails)
  cycle = 2 * rails - 2
  m = i % cycle
  if m < rails
    m
  else
    cycle - m
  end
end

# Counts of a..z in alphabet order, case-folded, ignoring everything that is
# not a letter. A plain 26-list rather than a map so it lines up with
# `alphabet()` by index — the shape a frequency attack actually consumes.
def letter_counts(text)
  ls = filter(fn(i) i >= 0 end,
              map(fn(ch) letter_index(ch) end, chars(downcase(text))))
  map(fn(i) count_of(ls, i) end, indexes(alphabet()))
end

def letter_count(text, ch)
  i = letter_index(downcase(ch))
  if i < 0
    0
  else
    nth(i, letter_counts(text))
  end
end

# Ties break toward the earlier letter, and a text with no letters at all
# answers "" rather than "a" — the vacuous case a max-index search gets wrong.
def most_common_letter(text)
  cnt = letter_counts(text)
  best = reduce(fn(a, b) max(a, b) end, 0, cnt)
  if best == 0
    ""
  else
    nth(index_of(cnt, best), alphabet())
  end
end

# A simple substitution cipher: `key` is a 26-letter permutation, so plaintext
# 'a' becomes the key's first letter and so on.
#
# The keyspace is 26! rather than caesar's 26, and it is still broken by
# `letter_counts` alone, because a substitution moves the frequency peak
# without flattening it. Anything the key does not cover passes through, so an
# empty key is the identity.
def substitution(text, key)
  ks = chars(downcase(key))
  join(map(fn(ch) substitute_char(ch, ks) end, chars(text)), "")
end

def substitute_char(ch, ks)
  i = letter_index(ch)
  if i < 0 || i >= size(ks)
    ch
  else
    nth(i, ks)
  end
end

def substitution_decrypt(text, key)
  substitution(text, invert_key(key))
end

# The inverse permutation, or "" when `key` is not one — which then makes
# `substitution_decrypt` the identity rather than a lookup of index 0-1.
def invert_key(key)
  if is_substitution_key(key) == false
    ""
  else
    ks = chars(downcase(key))
    join(map(fn(i) nth(index_of(ks, nth(i, alphabet())), alphabet()) end,
             indexes(alphabet())), "")
  end
end

def is_substitution_key(key)
  ks = chars(downcase(key))
  size(ks) == 26 && size(filter(fn(c) contains(ks, c) end, alphabet())) == 26
end

# The classical way a human generated a substitution key without memorising
# 26 letters: write the keyword first, dropping repeats, then the rest of the
# alphabet in order. "zebras" gives the textbook zebrascdfghijklmnopqtuvwxy.
def keyword_key(word)
  ws = dedupe_letters(chars(downcase(word)), [])
  join(concat_lists(ws, filter(fn(c) contains(ws, c) == false end, alphabet())), "")
end

def dedupe_letters(cs, seen)
  if is_empty(cs)
    seen
  else
    ch = first(cs)
    if letter_index(ch) < 0 || contains(seen, ch)
      dedupe_letters(rest(cs), seen)
    else
      dedupe_letters(rest(cs), push(seen, ch))
    end
  end
end

# Every decryption of a caesar text, indexed by the shift that produced it —
# candidate 0 is the input itself. Twenty-six is a keyspace you can exhaust
# by eye, which is the first half of why caesar is not a cipher.
def caesar_candidates(text)
  map(fn(n) caesar(text, 0 - n) end, range(0, 26))
end

# The second half: you do not even have to look. Scoring each candidate
# against English letter frequencies picks the shift with no key and no
# guesswork, and this is the same attack that breaks the substitution cipher
# above once you let it work per-letter instead of per-shift.
def crack_caesar(text)
  scores = map(fn(n) english_score(caesar(text, 0 - n)) end, range(0, 26))
  index_of(scores, reduce(fn(a, b) max(a, b) end, 0, scores))
end

def english_score(text)
  cnt = letter_counts(text)
  reduce(fn(a, b) a + b end, 0,
         map(fn(i) nth(i, cnt) * nth(i, english_weights()) end, indexes(alphabet())))
end

# English letter frequencies per 1000 characters, a..z, rounded to whole
# numbers so the score stays in integer arithmetic and never has to be
# compared with `near`.
def english_weights()
  [82, 15, 28, 43, 127, 22, 20, 61, 70, 2, 8, 40, 24,
   67, 75, 19, 1, 60, 63, 91, 28, 10, 24, 2, 20, 1]
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

test "the sieve agrees with trial division, and is empty below 2"
  assert sieve(12) == [2, 3, 5, 7, 11]
  assert is_empty(sieve(2)) == true
  assert is_empty(sieve(0)) == true
  # Two independent implementations of the same set: if either drifts, this
  # is where it shows up.
  assert sieve(200) == primes_below(200)
end

test "nth_prime and next_prime"
  assert nth_prime(1) == 2
  assert nth_prime(6) == 13
  assert nth_prime(25) == 97
  assert nth_prime(0) == 0 - 1
  # Strictly greater: a prime input must move on, not sit still.
  assert next_prime(7) == 11
  assert next_prime(0) == 2
  assert next_prime(1) == 2
  # The famous gap: nothing prime between 89 and 97.
  assert next_prime(89) == 97
end

test "coprimality"
  assert is_coprime(8, 15) == true
  assert is_coprime(8, 12) == false
  assert is_coprime(1, 1) == true
  # 1 is coprime to everything, including 0.
  assert is_coprime(1, 0) == true
  assert is_coprime(0, 0) == false
end

test "extended gcd returns a Bezout pair, not just the gcd"
  r = extended_gcd(240, 46)
  assert nth(0, r) == 2
  # The coefficients are the point; check the identity rather than the
  # particular pair, since several pairs are correct.
  assert 240 * nth(1, r) + 46 * nth(2, r) == 2
  assert extended_gcd(5, 0) == [5, 1, 0]
  s = extended_gcd(0, 5)
  assert nth(0, s) == 5
  assert 0 * nth(1, s) + 5 * nth(2, s) == 5
end

test "modular inverse, and the honest failure when there is none"
  assert mod_inverse(3, 7) == 5
  assert (3 * mod_inverse(3, 7)) % 7 == 1
  assert mod_inverse(17, 3120) == 2753
  # 6 and 8 share a factor, so no inverse exists — the failure must be
  # reported, not approximated.
  assert mod_inverse(6, 8) == 0 - 1
  assert mod_inverse(4, 1) == 0
end

test "chinese remainder for two congruences"
  x = crt2(2, 3, 3, 5)
  assert x == 8
  assert x % 3 == 2
  assert x % 5 == 3
  # Non-coprime but compatible: the general algorithm must still solve it.
  y = crt2(1, 4, 3, 6)
  assert y == 9
  assert y % 4 == 1
  assert y % 6 == 3
  # Non-coprime and incompatible: there is no such x, and saying 0 would be
  # a plausible-looking lie.
  assert crt2(0, 2, 1, 4) == 0 - 1
end

test "divisors, sigma, and the perfect numbers"
  assert divisors(12) == [1, 2, 3, 4, 6, 12]
  assert divisors(1) == [1]
  assert is_empty(divisors(0)) == true
  assert proper_divisors(12) == [1, 2, 3, 4, 6]
  assert sum_of_divisors(6) == 12
  assert sum_of_divisors(28) == 56
  # A prime's divisors are exactly 1 and itself.
  assert divisors(97) == [1, 97]
  assert sum_of_divisors(97) == 98
  assert is_perfect(6) == true
  assert is_perfect(28) == true
  # 1 is deficient, not perfect — the case a forgotten "exclude n" passes.
  assert is_perfect(1) == false
  assert is_deficient(1) == true
  assert is_abundant(12) == true
  assert is_perfect(12) == false
end

test "multiplicative order and Carmichael's lambda"
  # 3 generates all of the units mod 7: 3,2,6,4,5,1.
  assert multiplicative_order(3, 7) == 6
  assert multiplicative_order(2, 7) == 3
  assert multiplicative_order(1, 7) == 1
  # No order without an inverse.
  assert multiplicative_order(6, 8) == 0 - 1
  assert carmichael_lambda(1) == 1
  # The separating case: lambda(8) is 2 while totient(8) is 4.
  assert carmichael_lambda(8) == 2
  assert totient(8) == 4
  assert carmichael_lambda(15) == 4
  # For a prime the two agree.
  assert carmichael_lambda(7) == 6
  assert carmichael_lambda(7) == totient(7)
end

test "Fermat's test lies, and 561 is how you see it lie"
  assert fermat_probable_prime(97, 2) == true
  assert fermat_probable_prime(15, 2) == false
  # 561 is composite and yet passes to every coprime base.
  assert is_prime(561) == false
  assert prime_factors(561) == [3, 11, 17]
  assert fermat_probable_prime(561, 2) == true
  assert is_carmichael(561) == true
  # A prime is not a Carmichael number, and neither is an ordinary composite.
  assert is_carmichael(97) == false
  assert is_carmichael(15) == false
end

test "primitive roots"
  assert primitive_root(7) == 3
  assert primitive_root(5) == 2
  assert primitive_root(11) == 2
  assert primitive_root(2) == 1
  # Defined here for primes only; 8 has no primitive root at all.
  assert primitive_root(8) == 0 - 1
  # A generator's powers must cover every unit.
  assert multiplicative_order(primitive_root(11), 11) == 10
end

test "vigenere, including the key-advance trap at a non-letter"
  # The canonical worked example: ATTACKATDAWN keyed LEMON.
  assert vigenere("attackatdawn", "lemon") == "lxfopvefrnhr"
  assert vigenere_decrypt("lxfopvefrnhr", "lemon") == "attackatdawn"
  # The space must NOT consume a key letter, so the ciphertext is the
  # unspaced one with the space put back in the same place.
  assert vigenere("at tack", "lemon") == "lx fopv"
  # Round trip survives punctuation only if both sides agree about that.
  assert vigenere_decrypt(vigenere("attack at dawn!", "lemon"), "lemon") == "attack at dawn!"
  # A one-letter key is exactly a caesar.
  assert vigenere("hello", "b") == caesar("hello", 1)
  # Non-letters in the key are dropped, not read as shift zero.
  assert vigenere("attackatdawn", "l e m o n") == "lxfopvefrnhr"
  # No key at all leaves the text alone rather than erroring.
  assert vigenere("hello", "") == "hello"
  assert vigenere("", "lemon") == ""
end

test "atbash is its own inverse"
  assert atbash("abc") == "zyx"
  assert atbash("zyx") == "abc"
  assert atbash(atbash("attack at dawn")) == "attack at dawn"
  # The fixed point of the map: m and n swap with each other.
  assert atbash("mn") == "nm"
  assert atbash("") == ""
  assert atbash("a b!") == "z y!"
end

test "rail fence transposes and comes back"
  # The textbook example, three rails.
  assert rail_fence("wearediscoveredfleeatonce", 3) == "wecrlteerdsoeefeaocaivden"
  assert rail_fence_decrypt("wecrlteerdsoeefeaocaivden", 3) == "wearediscoveredfleeatonce"
  # A ragged last rail is where hand-rolled decoders break; 7 is not a
  # multiple of the period 4.
  assert rail_fence_decrypt(rail_fence("abcdefg", 3), 3) == "abcdefg"
  assert rail_fence_decrypt(rail_fence("abcdefghij", 4), 4) == "abcdefghij"
  # Fewer than two rails is the identity, not a crash.
  assert rail_fence("abc", 1) == "abc"
  assert rail_fence("", 3) == ""
  # It is a transposition: the letters are unchanged, only their order.
  assert letter_counts(rail_fence("wearediscoveredfleeatonce", 4)) == letter_counts("wearediscoveredfleeatonce")
end

test "letter frequency"
  assert letter_count("hello", "l") == 2
  assert letter_count("Hello", "h") == 1
  assert letter_count("hello", "z") == 0
  # Case-folded and non-letters ignored.
  assert letter_count("A a! a?", "a") == 3
  assert nth(0, letter_counts("aab")) == 2
  assert nth(1, letter_counts("aab")) == 1
  assert size(letter_counts("")) == 26
  assert reduce(fn(a, b) a + b end, 0, letter_counts("")) == 0
  assert most_common_letter("aab") == "a"
  # A tie goes to the earlier letter, and no letters at all is "" — not "a".
  assert most_common_letter("ba") == "a"
  assert most_common_letter("123 !") == ""
  # A caesar shift moves the peak but does not flatten it, which is the whole
  # weakness the crack below exploits.
  assert most_common_letter(caesar("eeeeaaab", 3)) == "h"
end

test "substitution cipher and its key"
  key = keyword_key("zebras")
  assert key == "zebrascdfghijklmnopqtuvwxy"
  assert is_substitution_key(key) == true
  # 'a' maps to the key's first letter, 'b' to its second.
  assert substitution("ab", key) == "ze"
  assert substitution_decrypt(substitution("flee at once", key), key) == "flee at once"
  # Repeats in the keyword are dropped, so it stays a permutation.
  assert is_substitution_key(keyword_key("mississippi")) == true
  assert keyword_key("") == join(alphabet(), "")
  # The identity key is the identity cipher.
  assert substitution("hello", join(alphabet(), "")) == "hello"
  # A key that is not a permutation is rejected rather than half-applied.
  assert is_substitution_key("abc") == false
  assert is_substitution_key("aaaaaaaaaaaaaaaaaaaaaaaaaa") == false
  assert invert_key("abc") == ""
  assert substitution_decrypt("hello", "abc") == "hello"
end

test "the substitution cipher permutes the frequency profile, it does not hide it"
  key = keyword_key("zebras")
  msg = "seventeen tests of the letter e"
  assert most_common_letter(msg) == "e"
  # The peak does not flatten, it just moves to wherever the key sent 'e' —
  # which is the entire frequency attack, and the reason 26! keys buy nothing.
  assert substitution("e", key) == "a"
  assert most_common_letter(substitution(msg, key)) == substitution("e", key)
  # Same for vigenere with a one-letter key, which is a caesar wearing a hat.
  assert most_common_letter(vigenere(msg, "d")) == "h"
end

test "caesar falls to a frequency attack with no key at all"
  plain = "the quick brown fox jumps over the lazy dog"
  assert crack_caesar(caesar(plain, 7)) == 7
  assert crack_caesar(caesar(plain, 0)) == 0
  assert crack_caesar(rot13(plain)) == 13
  assert caesar(caesar(plain, 7), 0 - crack_caesar(caesar(plain, 7))) == plain
  # The exhaustive list is the other half of the argument: 26 candidates,
  # and candidate 0 is the untouched input.
  assert size(caesar_candidates("abc")) == 26
  assert nth(0, caesar_candidates("abc")) == "abc"
  assert nth(1, caesar_candidates("abc")) == "zab"
end
