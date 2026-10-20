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
  any?((c) -> is_alnum(c), chars(token))
end

# The words of a text, lower-cased, punctuation at either end removed.
def kz_words(text)
  tokens = map((w) -> downcase(kz_strip(w)), words(text))
  filter((w) -> kz_word?(w), tokens)
end

def kz_strip(word)
  cs = chars(word)
  kept = drop_while((c) -> not is_alnum(c), cs)
  join(reverse(drop_while((c) -> not is_alnum(c), reverse(kept))), "")
end

# [word, count] pairs, most frequent first, ties in first-seen order.
def kz_counts(text)
  ws = kz_words(text)
  seen = unique(ws)
  pairs = map((w) -> [w, size(filter((x) -> x == w, ws))], seen)
  sort_stable_by((p) -> -last(p), pairs)
end

test "words are lower-cased and stripped of punctuation"
  assert kz_words("Blue, blue; BLUE!") == ["blue", "blue", "blue"]
end

test "a token with no letters is not a word"
  assert kz_words("a -- b") == ["a", "b"]
  assert not kz_word?("--")
end

test "counts come most frequent first, ties in first-seen order"
  assert kz_counts("b a b c a b") == [["b", 3], ["a", 2], ["c", 1]]
end

test "no text, no words"
  assert kz_words("") == []
  assert kz_counts("") == []
end
