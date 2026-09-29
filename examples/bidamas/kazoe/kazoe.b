# kazoe (数え) — counting words in text: the example bidama.
#
# A package is a directory holding a Bluefile and a .b file of the same name.
# Its definitions join one flat namespace with every other package a program
# imports, so each name carries the package's prefix (kz_). Its tests live in
# the same file; `use` strips them, so importing a package never runs them.
use("junjo", [:sort_stable_by])
use("moji", [:is_alnum, :words])
use("retsu", [:drop_while, :last, :size])
use("shuugou", [:unique])

# Whether a token counts as a word: it holds at least one letter or digit.
def kz_word?(token)
  any?(fn(c) is_alnum(c) end, chars(token))
end

# The words of a text, lower-cased, punctuation at either end removed.
def kz_words(text)
  tokens = map(fn(w) downcase(kz_strip(w)) end, words(text))
  filter(fn(w) kz_word?(w) end, tokens)
end

def kz_strip(word)
  cs = chars(word)
  kept = drop_while(fn(c) !is_alnum(c) end, cs)
  join(reverse(drop_while(fn(c) !is_alnum(c) end, reverse(kept))), "")
end

# [word, count] pairs, most frequent first, ties in first-seen order.
def kz_counts(text)
  ws = kz_words(text)
  seen = unique(ws)
  pairs = map(fn(w) [w, size(filter(fn(x) x == w end, ws))] end, seen)
  sort_stable_by(fn(p) -last(p) end, pairs)
end

test "words are lower-cased and stripped of punctuation"
  assert kz_words("Blue, blue; BLUE!") == ["blue", "blue", "blue"]
end

test "a token with no letters is not a word"
  assert kz_words("a -- b") == ["a", "b"]
  assert !kz_word?("--")
end

test "counts come most frequent first, ties in first-seen order"
  assert kz_counts("b a b c a b") == [["b", 3], ["a", 2], ["c", 1]]
end

test "no text, no words"
  assert kz_words("") == []
  assert kz_counts("") == []
end
