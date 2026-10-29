@moduledoc """
moji (文字) — strings.

Layered on blue's own `.length`, which the runtime installs because
tatara-lisp carries no string operations at all (see blue-lang-runtime's
stdlib module). These are the predicates a caller reaches for immediately
after `length` and would otherwise hand-roll at every call site.

# Three rules this package holds, because the layer beneath it does not

**The string comes FIRST, always.** `join` takes the list first and `split`
takes the string first; `take` and `nth` take the count and the index first.
A caller cannot infer an argument order from a sibling, so every function
here fixes one: subject, then everything else.

**Every index is a CHARACTER index**, matching blue's `length` (which counts
Unicode scalar values, not bytes — see the runtime's stdlib docs). Building
on `chars()` rather than on byte offsets is what makes that true for free.

**Out of range is a value, never an error.** `char_at` past the end answers
`""`, `char_index` that finds nothing answers -1, a pad narrower than its input
answers the input. A string library that raises on a short string forces a
length check at every call site, which is the thing it was supposed to remove.

# What is deliberately absent

`replace_all` — blue's builtin `replace` already replaces every occurrence
(Rust's `str::replace` semantics, pinned by a test below). The genuinely
missing half is `replace_first`, which is here.

`reverse_string` — the builtin `reverse` already reverses a string by
character, and correctly (a byte-wise reverse would produce invalid UTF-8).
Wrapping it would add a name and no behaviour; a test below pins it instead.

# Why several names here are longer than they need to be

`contains`, `repeat`, `index_of`, `slice` and `count_of` are all already
taken in this distribution — by `shuugou` (set membership) and `retsu` (list
repetition, position, window and tally) — and a string version of each would
have had **the same arity as the list version**. `slice(x, 1, 3)` and
`index_of(x, y)` would have type-punned silently: one definition shadows the
other wherever both packages are used, and neither the runtime nor the tests
would say a word. So the string forms are spelled `includes`, `repeated`,
`char_index`, `slice_chars` and `occurrences`. That is collision avoidance,
not taste — a language with no overloading makes one of the two yield, and
the newer package is the one that should.

The same reasoning renamed the internal `common_prefix_from`, which collided
with `ronri.prefix_len`. `use()` inlines a package's forms into one flat
namespace, so the sweep is over EVERY sibling's `def` list, not just the
ones this package imports.

    size("") #=> 0
"""

use("kazu", [:min])
use("retsu", %i[first is_empty repeat rest])

def empty(s)
  length(s) == 0
end

def present(s)
  length(s) > 0
end

@doc """
longer: Longer of two strings, ties going to the first. Ties must resolve
DETERMINISTICALLY or callers see different answers on different runs for
equal-length input.

    longer("a", "abc") #=> "abc"
"""
def longer(a, b)
  if length(b) > length(a)
    b
  else
    a
  end
end

# ── positional access ──────────────────────────────────────────────

@doc """
char_at: The character at index i, as a one-character string; "" past either end.

"" rather than nil for the miss, because every other function here consumes
strings — a nil would have to be checked before it could be passed on, and
"" flows through concat, length and the predicates unchanged.

    char_at("", 0) #=> ""
"""
def char_at(s, i)
  cs = chars(s)
  if i < 0 or i >= length(cs)
    ""
  else
    cs[i]
  end
end

@doc """
take_chars: The first n characters. Asking for more than there are yields all of them,
which is what makes `take_chars` safe to call on a string of unknown length.

    take_chars("hi", 0) #=> ""
"""
def take_chars(s, n)
  if n < 1
    ""
  else
    join(take(min(n, length(s)), chars(s)), "")
  end
end

def drop_chars(s, n)
  if n < 1
    s
  elsif n >= length(s)
    ""
  else
    join(drop(n, chars(s)), "")
  end
end

@doc """
slice_chars: `len` characters starting at `start` — the LENGTH-based form.

    slice_chars("abc", 9, 1) #=> ""
"""
def slice_chars(s, start, len)
  take_chars(drop_chars(s, start), len)
end

@doc """
substring: Characters from `start` up to but NOT including `stop` — the ENDPOINT-based
form. Both spellings exist because both appear in real calling code and
converting between them by hand is where the off-by-one lives.

    substring("abcdef", 2, 2) #=> ""
"""
def substring(s, start, stop)
  slice_chars(s, start, stop - start)
end

# ── searching ──────────────────────────────────────────────────────

def starts_with(s, prefix)
  starts_with?(s, prefix)
end

def ends_with(s, suffix)
  ends_with?(s, suffix)
end

@doc """
char_index_from: First index of `sub` at or after `from`, or -1.

-1 rather than an error, and rather than nil: a search that does not find is
an ordinary answer, and `char_index(s, x) >= 0` is the whole test.

    char_index_from("abcabc", "b", -3) #=> 1
"""
def char_index_from(s, sub, from)
  text_index(s, sub, from)
end

def char_index(s, sub)
  text_index(s, sub, 0)
end

def last_char_index_from(s, sub, from)
  text_last_index(s, sub, from)
end

def last_char_index(s, sub)
  text_last_index(s, sub, length(s) - length(sub))
end

@doc """
includes: Whether `sub` occurs in `s`: exactly what char_index(s, sub) >= 0 answers,
through the runtime's own substring search (contains?) rather than one blue
call per position. Measured 2026-09-25: made_of over an 18-character name
took 1.72 ms (about 95 µs per character against a 37-character set) and now
15 µs; kueri's q_ident, which calls it per identifier, went from 1.86 ms to
56 µs, and rendering NuPastel's 79 analytics views from 1.23 s to 0.09 s.

    includes("", "a") #=> false
"""
def includes(s, sub)
  contains?(s, sub)
end

@doc """
occurrences: How many NON-OVERLAPPING copies of `sub` are in `s`.

Non-overlapping is the choice `replace` already made, so the two agree:
occurrences("aaa", "aa") is 1, and replacing "aa" in "aaa" leaves one "a".
The empty needle answers 0 rather than recursing forever — there is no
sensible count of an empty match, and a hang is the worst possible answer.

    occurrences("", "a") #=> 0
"""
def occurrences(s, sub)
  if length(sub) == 0
    0
  else
    length(split(s, sub)) - 1
  end
end

# ── splitting on ONE separator ─────────────────────────────────────

@doc """
before_first: The two halves either side of the FIRST separator.

This is what `split` cannot do and what parsing actually needs.
`split("PATH=/a=/b", "=")` yields three pieces and loses which "=" was the
real one; after_first keeps the rest of the value intact, "=" and all.

The asymmetry on a MISS is deliberate and is the interesting half: with no
separator present, `before_first` answers the whole string and `after_first`
answers "". A bare "KEY" is a key with no value, not a value with no key —
so the two do NOT reassemble into the input, and that is the correct reading
rather than an oversight.

    before_first("", "=") #=> ""
"""
def before_first(s, sep)
  i = char_index(s, sep)
  if i < 0
    s
  else
    take_chars(s, i)
  end
end

def after_first(s, sep)
  i = char_index(s, sep)
  if i < 0
    ""
  else
    drop_chars(s, i + length(sep))
  end
end

@doc """
before_last: The same split, anchored at the LAST separator — which is the one a filename
or a dotted path is asking about. after_last("a.tar.gz", ".") is "gz", where
after_first would have answered "tar.gz".

    before_last("a.tar.gz", ".") #=> "a.tar"
"""
def before_last(s, sep)
  i = last_char_index(s, sep)
  if i < 0
    s
  else
    take_chars(s, i)
  end
end

def after_last(s, sep)
  i = last_char_index(s, sep)
  if i < 0
    ""
  else
    drop_chars(s, i + length(sep))
  end
end

def common_prefix_from(a, b, i)
  if i >= min(length(a), length(b))
    i
  elsif char_at(a, i) == char_at(b, i)
    common_prefix_from(a, b, i + 1)
  else
    i
  end
end

@doc """
common_prefix: The longest string both arguments start with.

    common_prefix("", "abc") #=> ""
"""
def common_prefix(a, b)
  take_chars(a, common_prefix_from(a, b, 0))
end

@doc """
chunk_chars: Cut into fixed-width pieces, the last one short.

The n < 1 guard is not decoration: chunking by zero would take "" off the
front forever and never shorten the remainder.

    chunk_chars("", 3) #=> []
"""
def chunk_chars(s, n)
  if n < 1 or length(s) == 0
    []
  else
    cons(take_chars(s, n), chunk_chars(drop_chars(s, n), n))
  end
end

# ── building and trimming ──────────────────────────────────────────

@doc """
repeated: `s` written n times end to end; "" for n < 1.

Named `repeated` and not `repeat` because `retsu.repeat(v, n)` builds a LIST
of n copies, and repeat("ab", 2) would then mean ["ab","ab"] or "abab"
depending on which package was used last. Two answers, no error.

    repeated("", 5) #=> ""
"""
def repeated(s, n)
  if n < 1
    ""
  else
    concat(s, repeated(s, n - 1))
  end
end

@doc """
fill_to: Exactly n characters of `pad`, repeated and then cut. `pad` may be more than
one character, in which case the last copy is truncated mid-pattern — that is
what makes pad_left(s, w, "-=") produce a ruler of exactly w columns.

An empty pad answers "" instead of looping forever. It is the one input that
can never reach the requested width, and a hang is the worst way to say so.

    fill_to(4, "") #=> ""
"""
def fill_to(n, pad)
  if n < 1 or length(pad) == 0
    ""
  else
    take_chars(grow_to(pad, pad, n), n)
  end
end

def grow_to(acc, pad, n)
  if length(acc) >= n
    acc
  else
    grow_to(concat(acc, pad), pad, n)
  end
end

@doc """
pad_left: Pad to `width` columns. A string already at or past `width` is returned
UNCHANGED rather than truncated — padding and truncating are different
intentions, and a pad that silently shortens is how a column of aligned text
quietly loses data. Reach for `ellipsize` when shortening is what you meant.

    pad_left("7", 3, "0") #=> "007"
"""
def pad_left(s, width, pad)
  concat(fill_to(width - length(s), pad), s)
end

def pad_right(s, width, pad)
  concat(s, fill_to(width - length(s), pad))
end

@doc """
pad_center: Centre, with the ODD character going to the RIGHT. Like `longer`'s tie rule,
this has to be pinned: a caller centring a column needs the same answer every
time, and "roughly centred" is not a specification.

    pad_center("abc", 1, " ") #=> "abc"
"""
def pad_center(s, width, pad)
  # Named `slack` and not `total` because `toukei` already defines `total` —
  # whether blue's `=` binds locally or globally, a name that is a function
  # somewhere in the distribution is not one to reuse for scratch arithmetic.
  slack = width - length(s)
  if slack < 1
    s
  else
    leftn = floor(slack / 2)
    concat(concat(fill_to(leftn, pad), s), fill_to(slack - leftn, pad))
  end
end

@doc """
replace_first: Replace only the FIRST occurrence — the half `replace` does not cover, since
the builtin is already global.

    replace_first("", "a", "X") #=> ""
"""
def replace_first(s, from, to)
  i = char_index(s, from)
  if i < 0 or length(from) == 0
    s
  else
    concat(concat(take_chars(s, i), to), drop_chars(s, i + length(from)))
  end
end

@doc """
strip_prefix: Remove an affix IF it is there, and otherwise leave the string alone.

The trap this closes is `drop_chars(s, length(p))`, which happily cuts
length(p) characters off a string that never had the prefix.

    strip_prefix("aab", "a") #=> "ab"
"""
def strip_prefix(s, p)
  if starts_with(s, p)
    drop_chars(s, length(p))
  else
    s
  end
end

def strip_suffix(s, p)
  if ends_with(s, p)
    take_chars(s, length(s) - length(p))
  else
    s
  end
end

@doc """
ellipsize: Shorten to at most `width` columns, marking the cut with "…" spelled as three
dots.

The invariant is `length(ellipsize(s, w)) <= w`, always — the common wrong
version appends the marker to a `width`-long cut and returns width + 3, which
overflows the column it was called to fit. Below four columns there is no room
for a marker at all, so it degrades to a plain cut.

    ellipsize("hello", 0) #=> ""
"""
def ellipsize(s, width)
  truncate(s, width, {})
end

@doc """
trim: drop space from both ends.

    trim("") #=> ""
"""
def trim(text, opts?)
  blue::trim(text, opts)
end

@doc """
truncate: cut text to a width with an ellipsis.

    truncate("hello", 5) #=> "hello"
"""
def truncate(text, width, opts?)
  marker = checked(opts, [:marker])[:marker] or "..."
  if length(text) <= width
    text
  elsif width <= length(marker)
    take_chars(text, width)
  else
    concat(take_chars(text, width - length(marker)), marker)
  end
end

def checked(opts, allowed)
  opts = opts or {}
  bad = filter((e) -> member?(first(e), allowed) == false, map_entries(opts))
  if is_empty(bad) == false
    raise(
      :bad_option,
      "unknown option #{first(first(bad))}; this verb takes #{join(map(to_s, allowed), ", ")}"
    )
  end
  opts
end

@doc """
lower: every letter in lower case.

    lower("") #=> ""
"""
def lower(text)
  downcase(text)
end

@doc """
size: number of code points.

    size("") #=> 0
"""
def size(text)
  length(chars(text))
end

# ── whitespace, words and lines ────────────────────────────────────

@doc """
is_space: True when `s` is non-empty and every character in it is whitespace.

Whitespace is defined by DELEGATION to `trim`, not by a hand-written set of
" \t\n\r". trim is Rust's, so it knows the whole Unicode whitespace class —
a non-breaking space, an ideographic space, a form feed — and a hand-written
set is wrong the first time a user pastes text from a word processor.

The empty string is NOT whitespace. Everything holds of nothing is exactly
how a predicate library goes wrong, and "" is better answered by `is_blank`.

    is_space(" ") #=> true
"""
def is_space(s)
  length(s) > 0 and length(trim(s)) == 0
end

@doc """
is_blank: Nothing there to read: empty, or whitespace only. The predicate a caller
actually wants before deciding a field was filled in.

    is_blank("") #=> true
"""
def is_blank(s)
  length(trim(s)) == 0
end

@doc """
words: Split on RUNS of whitespace, dropping the empties.

`split(s, " ")` cannot do this: it splits on one literal space, so a double
space yields a phantom "" between the words and a tab is not a separator at
all. Folding over the characters is what makes any run of any whitespace one
boundary.

    words("") #=> []
"""
def words(s)
  split_words(chars(s), "", [])
end

def split_words(cs, cur, acc)
  if is_empty(cs)
    if length(cur) == 0
      acc
    else
      append(acc, [cur])
    end
  elsif is_space(first(cs))
    if length(cur) == 0
      split_words(rest(cs), "", acc)
    else
      split_words(rest(cs), "", append(acc, [cur]))
    end
  else
    split_words(rest(cs), concat(cur, first(cs)), acc)
  end
end

@doc """
lines: One entry per line, with "\r\n" normalised and NO phantom last line.

The naive `split(s, "\n")` gets both halves wrong: "a\n" becomes ["a", ""],
inventing a line nobody wrote, and a file with Windows endings keeps a "\r"
glued to the end of every line where it is invisible and breaks every
comparison. A truly empty string has no lines at all — but "\n" has one, and
it is empty.

    lines("") #=> []
"""
def lines(s)
  if length(s) == 0
    []
  else
    split(
      strip_suffix(replace(s, unlines(["\r"]), line_break), line_break),
      line_break
    )
  end
end

@doc """
squish: Trim, and collapse every internal whitespace run to a single space.

    squish("") #=> ""
"""
def squish(s)
  join(words(s), " ")
end

@doc """
wrap_text: Greedy word wrap: the lines are as full as they can be without exceeding
`width`, joined by single spaces.

A word LONGER than the width gets its own over-long line rather than being
broken. Breaking mid-word would mangle a URL or a path, which is most of what
is too long in practice, and a caller that wants a hard cut has `ellipsize`.

    wrap_text("", 10) #=> []
"""
def wrap_text(s, width)
  wrap_from(words(s), "", [], width)
end

def wrap_from(ws, cur, acc, width)
  if is_empty(ws)
    if length(cur) == 0
      acc
    else
      append(acc, [cur])
    end
  elsif length(cur) == 0
    wrap_from(rest(ws), first(ws), acc, width)
  elsif length(cur) + 1 + length(first(ws)) <= width
    wrap_from(rest(ws), concat(concat(cur, " "), first(ws)), acc, width)
  else
    wrap_from(rest(ws), first(ws), append(acc, [cur]), width)
  end
end

# ── case ───────────────────────────────────────────────────────────

@doc """
capitalize: First character up, the REST DOWN — Ruby's `capitalize`, not "upcase the
first character". "hELLO" becoming "Hello" rather than "HELLO" is the whole
difference, and it is what makes capitalize idempotent.

    capitalize("") #=> ""
"""
def capitalize(s)
  concat(upcase(take_chars(s, 1)), downcase(drop_chars(s, 1)))
end

@doc """
title_case: Every word capitalised, joined by single spaces.

Note that this NORMALISES whitespace, because it is built on `words`: runs
collapse and leading/trailing space is dropped. Titles are being formatted,
not text being preserved; use `words` + `capitalize` directly to keep layout.

    title_case("") #=> ""
"""
def title_case(s)
  join(map(capitalize, words(s)), " ")
end

def swap_char(c)
  if c == upcase(c)
    downcase(c)
  else
    upcase(c)
  end
end

@doc """
swap_case: Case inverted character by character. Caseless characters — digits,
punctuation, kana — pass through, which is what makes it self-inverse.

    swap_case("") #=> ""
"""
def swap_case(s)
  join(map(swap_char, chars(s)), "")
end

# ── character-class predicates ─────────────────────────────────────

@doc """
made_of: True when `s` is non-empty and every character of it appears in `set`.

NON-EMPTY is the load-bearing half. "every character of "" is a digit" is
vacuously true, and a validator built on that accepts a blank form field as a
valid number. The name says it: a string made of nothing is made of nothing.

    made_of("a", "") #=> false
"""
def made_of(s, set)
  if length(s) == 0
    false
  else
    length(filter((c) -> includes(set, c), chars(s))) == length(s)
  end
end

def ascii_digits()
  "0123456789"
end

def ascii_letters()
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
end

@doc """
is_digit: ASCII, and said so rather than discovered.

A Unicode-wide `is_digit` would accept the Devanagari and fullwidth digits,
which `to_int` then fails to parse — so the predicate would promise something
the parser does not honour. These answer the question a caller is really
asking: "will this go through to_int / is it an identifier / is it a hash?"

    is_digit("") #=> false
"""
def is_digit(s)
  made_of(s, ascii_digits)
end

def is_alpha(s)
  made_of(s, ascii_letters)
end

def is_alnum(s)
  made_of(s, concat(ascii_letters, ascii_digits))
end

def is_hex(s)
  made_of(s, "0123456789abcdefABCDEF")
end

@doc """
is_upper: Cased, and entirely in one case.

`s == upcase(s)` alone is not enough: it is true of "123" and of "", neither
of which is upper-case text. The second clause demands at least one character
that HAS a case, which is what makes is_upper and is_lower both false for a
string of digits instead of both true.

    is_upper("") #=> false
"""
def is_upper(s)
  s == upcase(s) and s != downcase(s)
end

def is_lower(s)
  s == downcase(s) and s != upcase(s)
end

# ── ordering ───────────────────────────────────────────────────────

@doc """
same_text: Case-insensitive equality, for the comparisons a human means by "the same".

    same_text("", "") #=> true
"""
def same_text(a, b)
  downcase(a) == downcase(b)
end

@doc """
sorts_before: Strict lexicographic order.

`a < b` is a TYPE ERROR on strings in this runtime — `<` is numeric — so
every string ordering has to go through the `compare` primitive, which does
answer for strings and returns 0 - 1 / 0 / 1.

    sorts_before("Z", "a") #=> true
"""
def sorts_before(a, b)
  compare(a, b) < 0
end

def insert_text(x, xs)
  if is_empty(xs)
    [x]
  elsif compare(x, first(xs)) <= 0
    cons(x, xs)
  else
    cons(first(xs), insert_text(x, rest(xs)))
  end
end

@doc """
sort_strings: Sort a list of strings, stably.

`junjo.sort` cannot do this: it is phrased in `<=`, which raises on strings.
Insertion sort keeps equal elements in input order, so sorting by one key
does not scramble an earlier sort by another.

    sort_strings([]) #=> []
"""
def sort_strings(xs)
  if is_empty(xs)
    []
  else
    insert_text(first(xs), sort_strings(rest(xs)))
  end
end

@doc """
upper_snake: a name written with hyphens or spaces, as one upper-case word joined
by underscores: the shape of an environment variable.

    upper_snake("cache-url") #=> "CACHE_URL"
"""
def upper_snake(name)
  upcase(replace(replace(name, "-", "_"), " ", "_"))
end

@doc """
env_key: an environment variable name from its parts, each upper-snaked and
joined by underscores; an empty last part leaves a trailing underscore, a prefix.

    env_key(["input", "cache-url"]) #=> "INPUT_CACHE_URL"
"""
def env_key(parts)
  upper_snake(join(parts, "-"))
end

test "env_key builds a variable name or a prefix from parts"
  assert env_key(%w[input blue-only]) == "INPUT_BLUE_ONLY"
  assert env_key(["kensa", ""]) == "KENSA_"
  assert env_key(["x"]) == "X"
end

test "upper_snake joins a kebab or spaced name into one upper-case word"
  assert upper_snake("cache-url") == "CACHE_URL"
  assert upper_snake("blue only") == "BLUE_ONLY"
  assert upper_snake("x") == "X"
end

test "empty and present are exact opposites"
  assert empty("") == true
  assert empty("a") == false
  assert present("") == false
  assert present("a") == true
end

test "longer picks the longer string"
  assert longer("abc", "a") == "abc"
  assert longer("a", "abc") == "abc"
end

test "the string primitives blue exposes"
  assert upcase("abc") == "ABC"
  assert downcase("ABC") == "abc"
  assert trim("  a  ") == "a"
  assert concat("a", "b") == "ab"
  assert chars("abc") == %w[a b c]
  assert join(%w[a b], "-") == "a-b"
  assert split("a-b", "-") == %w[a b]
end

test "split and join round-trip"
  assert join(split("a,b,c", ","), ",") == "a,b,c"
end

test "lower, size and truncate"
  assert lower("ABC dE") == "abc de"
  assert lower("") == ""
  assert size("héllo") == 5
  assert size("") == 0
  assert truncate("hello world", 8, {}) == "hello..."
  assert truncate("hello world", 8, {marker: "~"}) == "hello w~"
  assert truncate("hello", 5, {}) == "hello"
  assert truncate("hello", 2, {}) == "he"
  bad = truncate("hello", 3, {cut: 1}) rescue "caught"
  assert bad == "caught"
end

test "trim cuts whitespace with or without options, and agrees with the builtin"
  assert trim("  a  ") == "a"
  assert trim("  a  ", {}) == "a"
  assert trim("  a  ", nil) == "a"
  assert trim("") == ""
  assert trim("   ") == ""
  assert trim("  a  ", {side: :start}) == "a  "
  assert trim("  a  ", {side: :end}) == "  a"
  assert trim("--a--", {chars: "-"}) == "a"
  assert trim("--a--", {chars: "-", side: :end}) == "--a"
  assert trim(unlines(["\t a b "])) == blue::trim(unlines(["\t a b "]))
  assert map(trim, [" a", "b "]) == %w[a b]
end

test "trim refuses an unknown option, a bad side and a bad character set by kind"
  unknown = begin
    trim("a", {sid: :end})
  rescue e
    e.kind
  end
  assert unknown == :bad_option
  side = begin
    trim("a", {side: :middle})
  rescue e
    e.kind
  end
  assert side == :bad_option
  chars = begin
    trim("a", {chars: 1})
  rescue e
    e.kind
  end
  assert chars == :bad_option
end

test "the cut takes its options or none"
  assert truncate("hello world", 8) == "hello..."
  assert truncate("hello world", 8, nil) == "hello..."
  assert truncate("hello world", 8, {}) == truncate("hello world", 8)
  assert truncate("hello world", 8, {marker: "~"}) == "hello w~"
  assert truncate("hello", 5) == "hello"
  unknown = begin
    truncate("hello", 3, {cut: 1})
  rescue e
    e.kind
  end
  assert unknown == :bad_option
end

test "the two builtins this package deliberately does NOT wrap"
  # `replace` is already global — so `replace_all` would be a second name for
  # one behaviour, and `replace_first` is the half that was missing.
  assert replace("banana", "a", "X") == "bXnXnX"
  # `reverse` already handles strings, by character.
  assert reverse("abc") == "cba"
end

test "char_at is total at both ends"
  assert char_at("abc", 0) == "a"
  assert char_at("abc", 2) == "c"
  # The three ways to fall off, none of which may raise.
  assert char_at("abc", 3) == ""
  assert char_at("abc", -1) == ""
  assert char_at("", 0) == ""
end

test "take_chars and drop_chars partition the string"
  assert take_chars("hello", 2) == "he"
  assert drop_chars("hello", 2) == "llo"
  # Over-asking clamps rather than raising — the reason these exist.
  assert take_chars("hi", 99) == "hi"
  assert drop_chars("hi", 99) == ""
  assert take_chars("hi", 0) == ""
  assert take_chars("hi", -5) == ""
  # And the two halves always rejoin into the original, for any n.
  assert concat(take_chars("hello", 3), drop_chars("hello", 3)) == "hello"
  assert concat(take_chars("hello", 0), drop_chars("hello", 0)) == "hello"
  assert concat(take_chars("hello", 9), drop_chars("hello", 9)) == "hello"
end

test "slice is length-based and substring is endpoint-based"
  assert slice_chars("abcdef", 1, 3) == "bcd"
  assert substring("abcdef", 1, 4) == "bcd"
  # The distinguishing case: same second argument, different third meaning.
  assert slice_chars("abcdef", 2, 2) == "cd"
  assert substring("abcdef", 2, 2) == ""
  assert slice_chars("abc", 1, 99) == "bc"
  assert slice_chars("abc", 9, 1) == ""
end

test "indices are characters, not bytes"
  # "héllo" is 6 bytes and 5 characters; a byte-wise slice would split the é
  # and produce garbage. Every index here is a character index.
  assert length("héllo") == 5
  assert char_at("héllo", 1) == "é"
  assert take_chars("héllo", 2) == "hé"
  assert char_index("héllo", "llo") == 2
end

test "starts_with and ends_with, including the empty affix"
  assert starts_with("hello", "he") == true
  assert starts_with("hello", "lo") == false
  assert ends_with("hello", "lo") == true
  assert ends_with("hello", "he") == false
  # A longer affix than the string must be false, not an index error.
  assert starts_with("ab", "abc") == false
  assert ends_with("ab", "abc") == false
  # Every string starts and ends with the empty string.
  assert starts_with("ab", "") == true
  assert ends_with("ab", "") == true
  assert starts_with("", "") == true
end

test "char_index finds the FIRST and last_char_index the LAST"
  # The case that separates them: a needle that appears twice.
  assert char_index("abcabc", "abc") == 0
  assert last_char_index("abcabc", "abc") == 3
  assert char_index("abcabc", "b") == 1
  assert last_char_index("abcabc", "b") == 4
  # A miss is -1, never an error and never nil.
  assert char_index("abc", "z") == -1
  assert last_char_index("abc", "z") == -1
  assert char_index("", "a") == -1
  # A needle longer than the haystack cannot match.
  assert char_index("ab", "abc") == -1
end

test "char_index_from resumes a scan without re-finding the same hit"
  assert char_index_from("abcabc", "abc", 1) == 3
  assert char_index_from("abcabc", "abc", 4) == -1
  # A negative start is clamped rather than reading backwards.
  assert char_index_from("abcabc", "b", -3) == 1
end

test "includes agrees with char_index"
  assert includes("hello", "ell") == true
  assert includes("hello", "z") == false
  assert includes("", "a") == false
  # Every string includes the empty string, which is what char_index 0 means.
  assert includes("hello", "") == true
  assert char_index("hello", "") == 0
  # The differential: the runtime's search and char_index agree on every case,
  # the empty ones, a needle longer than the text, overlaps, punctuation and
  # characters beyond ASCII.
  cases = [
    %w[hello ell],
    %w[hello z],
    ["", "a"],
    ["", ""],
    ["hello", ""],
    %w[abc abcd],
    %w[aaa aa],
    %w[a.b .],
    %w[ação ç],
    %w[ação ão],
    %w[pão a],
    %w[_x9 _]
  ]
  assert map(
    (c) -> includes(first(c), c[1]) == (char_index(first(c), c[1]) >= 0),
    cases
  ) == repeat(true, length(cases))
end

test "occurrences counts non-overlapping copies"
  assert occurrences("banana", "a") == 3
  assert occurrences("banana", "na") == 2
  # THE case: overlapping matches count once, which is what makes this agree
  # with replace. A naive scan-every-index count would say 2.
  assert occurrences("aaa", "aa") == 1
  assert occurrences("aaa", "a") == 3
  assert occurrences("abc", "z") == 0
  assert occurrences("", "a") == 0
  # The empty needle is 0, not a hang.
  assert occurrences("abc", "") == 0
end

test "searching a 200 000 character text is one pass, not one call per position"
  long = "#{join(map((_) -> "ab", range(100_000)), "")}é!"
  assert char_index(long, "é!") == 200_000
  assert char_index_from(long, "ab", 7) == 8
  assert last_char_index(long, "ab") == 199_998
  assert last_char_index_from(long, "ab", 5) == 4
  assert occurrences(long, "ab") == 100_000
  assert after_first(long, "é") == "!"
  assert replace_first(long, "é!", "") ==
    join(map((_) -> "ab", range(100_000)), "")
end

test "repeated builds a string, not a list"
  assert repeated("ab", 3) == "ababab"
  assert repeated("ab", 1) == "ab"
  # The two edges, both of which must be the empty STRING.
  assert repeated("ab", 0) == ""
  assert repeated("ab", -2) == ""
  assert repeated("", 5) == ""
  # Length is exactly n copies — a fencepost error here shows as n+1 or n-1.
  assert length(repeated("xyz", 4)) == 12
end

test "fill_to produces EXACTLY n characters, cutting a multi-char pad"
  assert fill_to(3, "-") == "---"
  assert fill_to(0, "-") == ""
  assert fill_to(-1, "-") == ""
  # The case a naive `repeated(pad, n)` gets wrong: the pad is 2 wide, so 5
  # columns means two and a half copies, not five copies.
  assert fill_to(5, "-=") == "-=-=-"
  assert length(fill_to(5, "-=")) == 5
  # An empty pad cannot reach any width; "" rather than a hang.
  assert fill_to(4, "") == ""
end

test "padding reaches the width and never truncates"
  assert pad_left("7", 3, "0") == "007"
  assert pad_right("ab", 5, ".") == "ab..."
  assert length(pad_left("7", 3, "0")) == 3
  # Already at or past the width: unchanged, NOT cut. This is the behaviour
  # that separates padding from ellipsize.
  assert pad_left("abcd", 2, "0") == "abcd"
  assert pad_right("abcd", 2, "0") == "abcd"
  assert pad_left("abc", 3, "0") == "abc"
  # Padding an empty string is just the fill.
  assert pad_right("", 3, "x") == "xxx"
end

test "pad_center splits the slack, odd character to the right"
  assert pad_center("ab", 6, " ") == "  ab  "
  # THE case: 5 - 3 = 2 is even, 6 - 3 = 3 is odd. The odd one must land right,
  # deterministically, or two callers centring the same column disagree.
  assert pad_center("abc", 6, " ") == " abc  "
  assert pad_center("abc", 5, " ") == " abc "
  assert length(pad_center("abc", 6, " ")) == 6
  assert pad_center("abc", 1, " ") == "abc"
end

test "replace_first stops after one, where replace does not"
  assert replace_first("banana", "a", "X") == "bXnana"
  assert replace("banana", "a", "X") == "bXnXnX"
  # A miss changes nothing rather than raising.
  assert replace_first("banana", "z", "X") == "banana"
  assert replace_first("", "a", "X") == ""
  # An empty needle is a no-op, not an insertion at every position.
  assert replace_first("abc", "", "X") == "abc"
  # Deleting the first occurrence is replace_first with an empty replacement.
  assert replace_first("a-b-c", "-", "") == "ab-c"
end

test "strip_prefix and strip_suffix only cut what is actually there"
  assert strip_prefix("prefix-body", "prefix-") == "body"
  assert strip_suffix("name.txt", ".txt") == "name"
  # The trap: a plain drop_chars would cut 7 characters off a string that
  # never carried the prefix.
  assert strip_prefix("body", "prefix-") == "body"
  assert strip_suffix("name.md", ".txt") == "name.md"
  # The empty affix is present in every string, so stripping it is identity.
  assert strip_prefix("abc", "") == "abc"
  assert strip_suffix("abc", "") == "abc"
  # Only ONE copy comes off.
  assert strip_prefix("aab", "a") == "ab"
end

test "ellipsize never returns more than the width it was given"
  assert ellipsize("hello world", 8) == "hello..."
  assert length(ellipsize("hello world", 8)) == 8
  # A string that fits is untouched, marker and all.
  assert ellipsize("hello", 5) == "hello"
  assert ellipsize("hello", 99) == "hello"
  # Below four columns there is no room for the marker, so it is a plain cut —
  # and the bound still holds, which is the whole point.
  assert ellipsize("hello", 3) == "hel"
  assert ellipsize("hello", 0) == ""
  assert length(ellipsize("hello", 3)) == 3
end

test "is_space delegates to trim, so it knows every whitespace character"
  assert is_space(" ") == true
  assert is_space("\t") == true
  assert is_space(line_break) == true
  assert is_space("   ") == true
  assert is_space("a") == false
  assert is_space("a b") == false
  # The vacuous case: nothing is not whitespace. A predicate that says true
  # here accepts a blank field as "a space was typed".
  assert is_space("") == false
end

test "is_blank covers the empty string that is_space deliberately does not"
  assert is_blank("") == true
  assert is_blank(join_lines(["  \t", " "])) == true
  assert is_blank("a") == false
  assert is_blank("  a  ") == false
  # The two predicates differ on exactly one input, which is why both exist.
  assert is_space("") == false
  assert is_blank("") == true
end

test "words splits on RUNS of any whitespace"
  assert words("a b c") == %w[a b c]
  # THE case split(s, " ") gets wrong: a double space would yield a phantom "".
  assert words("a  b") == %w[a b]
  assert words("  a  b  ") == %w[a b]
  # A tab is not a literal space, so a split on " " would not separate here.
  assert words(join_lines(["a\tb", "c"])) == %w[a b c]
  assert words("") == []
  assert words("   ") == []
  assert words("word") == ["word"]
end

test "squish is words put back together"
  assert squish("  a   b  ") == "a b"
  assert squish("a\t\tb") == "a b"
  assert squish("") == ""
  assert squish("   ") == ""
  # Already squished text is unchanged — squish is idempotent.
  assert squish(squish("  a   b ")) == squish("  a   b ")
end

test "lines invents no trailing line and eats no \\r"
  assert lines(join_lines(%w[a b])) == %w[a b]
  # THE case: split("a\n", "\n") is ["a", ""] — a line nobody wrote.
  assert lines(unlines(["a"])) == ["a"]
  assert lines(unlines(%w[a b])) == %w[a b]
  # Windows endings must not leave a "\r" glued to each line.
  assert lines(join_lines(["a\r", "b"])) == %w[a b]
  assert lines(unlines(["a\r", "b\r"])) == %w[a b]
  # A genuinely blank line is real and must survive.
  assert lines(join_lines(["a", "", "b"])) == ["a", "", "b"]
  assert lines(line_break) == [""]
  # No text at all is no lines at all.
  assert lines("") == []
end

test "wrap_text fills each line without exceeding the width"
  assert wrap_text("a b c d", 3) == ["a b", "c d"]
  assert wrap_text("aa bb cc", 5) == ["aa bb", "cc"]
  # Everything fits: one line.
  assert wrap_text("a b", 99) == ["a b"]
  assert wrap_text("", 10) == []
  # A word longer than the width gets its own line rather than being cut in
  # half — a broken URL is worse than a ragged margin.
  assert wrap_text("hi enormousword ok", 4) == %w[hi enormousword ok]
  # Every line either fits, or is a single unbreakable word.
  assert length(wrap_text("a b c d e f", 3)) == 3
end

test "capitalize lowercases the tail, and is idempotent"
  assert capitalize("hello") == "Hello"
  # THE case that separates it from "upcase the first character".
  assert capitalize("hELLO") == "Hello"
  assert capitalize("HELLO") == "Hello"
  assert capitalize("") == ""
  assert capitalize("a") == "A"
  assert capitalize(capitalize("hELLO")) == capitalize("hELLO")
  # A non-letter first character is left alone rather than dropped.
  assert capitalize("1st") == "1st"
end

test "title_case capitalizes every word and normalises the spacing"
  assert title_case("the quick brown fox") == "The Quick Brown Fox"
  assert title_case("hELLO wORLD") == "Hello World"
  # Built on words, so runs collapse — stated, and asserted so nobody is
  # surprised by it later.
  assert title_case("  a   b  ") == "A B"
  assert title_case("") == ""
end

test "swap_case is its own inverse"
  assert swap_case("Hello") == "hELLO"
  # The identity is the real test: any wrong branch breaks the round trip.
  assert swap_case(swap_case("Hello World")) == "Hello World"
  assert swap_case(swap_case("aBcDeF 123!")) == "aBcDeF 123!"
  # Caseless characters pass through rather than vanishing.
  assert swap_case("a1!") == "A1!"
  assert swap_case("") == ""
end

test "made_of is false for the empty string, not vacuously true"
  assert made_of("abc", "abcd") == true
  assert made_of("abx", "abcd") == false
  # Everything holds of nothing is how a validator accepts a blank field.
  assert made_of("", "abcd") == false
  # A set that contains nothing accepts nothing.
  assert made_of("a", "") == false
end

test "the character-class predicates, including their empty and mixed cases"
  assert is_digit("12345") == true
  assert is_digit("7") == true
  assert is_digit("12a") == false
  assert is_digit("1.5") == false
  assert is_digit("") == false
  assert is_alpha("abcXYZ") == true
  assert is_alpha("abc1") == false
  assert is_alpha("") == false
  assert is_alnum("abc123") == true
  assert is_alnum("abc-123") == false
  assert is_hex("deadBEEF00") == true
  assert is_hex("xyz") == false
  # A digit is hex; a letter past f is not. The pair pins the boundary.
  assert is_hex("f") == true
  assert is_hex("g") == false
end

test "is_upper and is_lower need a CASED character to be true"
  assert is_upper("HELLO") == true
  assert is_lower("hello") == true
  assert is_upper("Hello") == false
  assert is_lower("Hello") == false
  # THE case a bare `s == upcase(s)` gets wrong: digits and punctuation have
  # no case, so they are neither upper nor lower — not both.
  assert is_upper("123") == false
  assert is_lower("123") == false
  assert is_upper("") == false
  assert is_lower("") == false
  # Mixed cased-and-caseless is decided by the cased characters.
  assert is_upper("A1!") == true
  assert is_lower("a1!") == true
end

test "same_text ignores case where == does not"
  assert same_text("Hello", "hello") == true
  assert "Hello" == "hello" == false
  assert same_text("HELLO", "hello") == true
  assert same_text("hello", "world") == false
  assert same_text("", "") == true
end

test "sorts_before goes through compare, because < raises on strings"
  assert sorts_before("a", "b") == true
  assert sorts_before("b", "a") == false
  # Not before itself — the strictness a <= would blur.
  assert sorts_before("a", "a") == false
  # A prefix sorts before its extension.
  assert sorts_before("ab", "abc") == true
  # Byte order, so every capital sorts before every lowercase letter. Stated
  # rather than assumed: this is NOT dictionary order.
  assert sorts_before("Z", "a") == true
end

test "sort_strings sorts what junjo.sort cannot"
  assert sort_strings(%w[c a b]) == %w[a b c]
  assert sort_strings([]) == []
  assert sort_strings(["only"]) == ["only"]
  # Duplicates survive — a set-like sort would silently drop one.
  assert sort_strings(%w[b a b]) == %w[a b b]
  # Already sorted stays put, and sorting twice changes nothing.
  assert sort_strings(sort_strings(%w[c a])) == sort_strings(%w[c a])
  # nil is the other empty, and it must not reach the recursion.
  assert sort_strings(blue::rest(["x"])) == []
  # Capitals first, consistent with sorts_before.
  assert sort_strings(%w[b A]) == %w[A b]
end

test "before_first and after_first keep the rest of the value intact"
  assert before_first("KEY=value", "=") == "KEY"
  assert after_first("KEY=value", "=") == "value"
  # THE case split cannot express: the value itself contains the separator.
  assert after_first("PATH=/a=/b", "=") == "/a=/b"
  assert before_first("PATH=/a=/b", "=") == "PATH"
  # The deliberate asymmetry on a miss — a bare key has no value.
  assert before_first("KEY", "=") == "KEY"
  assert after_first("KEY", "=") == ""
  # A separator at either end still yields an empty half rather than an error.
  assert before_first("=v", "=") == ""
  assert after_first("k=", "=") == ""
  assert before_first("", "=") == ""
  assert after_first("", "=") == ""
end

test "before_last and after_last anchor at the other end"
  assert after_last("a.tar.gz", ".") == "gz"
  assert before_last("a.tar.gz", ".") == "a.tar"
  # The pair that shows the two are genuinely different functions.
  assert after_first("a.tar.gz", ".") == "tar.gz"
  assert before_first("a.tar.gz", ".") == "a"
  # With one separator they agree, which is why a single test cannot tell
  # them apart and both cases above are needed.
  assert after_last("a.b", ".") == "b"
  assert after_first("a.b", ".") == "b"
  assert before_last("noseparator", ".") == "noseparator"
  assert after_last("noseparator", ".") == ""
  # Multi-character separators work, and are not treated as a set of chars.
  assert after_last("a::b::c", "::") == "c"
  assert before_first("a::b::c", "::") == "a"
end

test "common_prefix"
  assert common_prefix("prefix-a", "prefix-b") == "prefix-"
  assert common_prefix("abc", "abc") == "abc"
  # One string being a prefix of the other stops at the shorter — not past
  # the end of it, which is where an unguarded index walk would read.
  assert common_prefix("ab", "abcdef") == "ab"
  assert common_prefix("abcdef", "ab") == "ab"
  assert common_prefix("xyz", "abc") == ""
  assert common_prefix("", "abc") == ""
  # It is symmetric, which a one-sided implementation can easily break.
  assert common_prefix("abcd", "abx") == common_prefix("abx", "abcd")
end

test "chunk_chars cuts into fixed widths with a short tail"
  assert chunk_chars("abcdefg", 3) == %w[abc def g]
  # An exact multiple leaves no empty final chunk.
  assert chunk_chars("abcdef", 3) == %w[abc def]
  assert chunk_chars("ab", 5) == ["ab"]
  assert chunk_chars("", 3) == []
  # Zero width would loop forever; it answers [] instead.
  assert chunk_chars("abc", 0) == []
  assert chunk_chars("abc", -1) == []
  # Nothing is lost or duplicated: the chunks rejoin into the original.
  assert join(chunk_chars("abcdefg", 3), "") == "abcdefg"
end

def glob_match?(pattern, s)
  glob_segments?(split(pattern, "/"), split(s, "/"))
end

def glob_segments?(ps, ss)
  if is_empty(ps)
    is_empty(ss)
  elsif first(ps) == "**"
    glob_segments?(rest(ps), ss) or
      not is_empty(ss) and glob_segments?(ps, rest(ss))
  else
    not is_empty(ss) and
      glob_segment?(first(ps), first(ss)) and
      glob_segments?(rest(ps), rest(ss))
  end
end

def glob_segment?(p, s)
  if p == s
    true
  elsif not contains?(p, "*") and not contains?(p, "?")
    false
  else
    glob_chars?(chars(p), chars(s))
  end
end

def glob_chars?(p, s)
  if is_empty(p)
    is_empty(s)
  elsif first(p) == "*"
    glob_chars?(rest(p), s) or not is_empty(s) and glob_chars?(p, rest(s))
  elsif is_empty(s)
    false
  elsif first(p) == "?" or first(p) == first(s)
    glob_chars?(rest(p), rest(s))
  else
    false
  end
end

test "glob_match? reads * within a segment, ** across them, ? as one character"
  assert glob_match?("lib/*.nix", "lib/nodes.nix") == true
  assert glob_match?("lib/*.nix", "lib/x/nodes.nix") == false
  assert glob_match?("nodes/**", "nodes/plo/default.nix") == true
  assert glob_match?("nodes/**/default.nix", "nodes/default.nix") == true
  assert glob_match?("nodes/**/default.nix", "nodes/a/b/default.nix") == true
  assert glob_match?("secrets*.yaml", "secrets.yaml") == true
  assert glob_match?("?.nix", "a.nix") == true
  assert glob_match?("?.nix", "/.nix") == false
  assert glob_match?("flake.nix", "flake.lock") == false
  assert glob_match?("", "") == true
  assert glob_match?("", "a") == false
  assert glob_match?("**", "") == true
end
