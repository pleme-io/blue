# Using a bidama
#
# use("kazoe") finds the package and brings in its definitions. The examples'
# Bluefile declares packages("bidamas"), so `blue test
# examples/10_using_a_bidama.b` finds kazoe there with no BLUE_PATH, and the
# standard bidamas kazoe uses come compiled into blue. Under nix the same
# declaration builds kazoe, runs its tests, gates its names against the whole
# public distribution, and puts it on BLUE_PATH for this file. BLUE_PATH is
# searched first, so a checkout on it overrides either.
use("kazoe", [:kz_counts])
use("retsu", [:first])

def top_word(text)
  first(first(kz_counts(text)))
end

test "the package's words are available after use"
  assert top_word("to be or not to be") == "to"
end

test "an empty text has no top word"
  assert top_word("") == nil
end
