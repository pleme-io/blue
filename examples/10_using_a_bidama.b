# Using a bidama
#
# use("kazoe") finds the package on BLUE_PATH and brings in its definitions.
# In this project the examples' Bluefile declares packages("bidamas"), so nix
# builds kazoe, runs its tests, gates its names against the whole public
# distribution, and puts it on BLUE_PATH for this file. A standalone run:
#   BLUE_PATH=examples/bidamas:bidamas blue test examples/10_using_a_bidama.b
use("retsu")
use("kazoe")

def top_word(text)
  first(first(kz_counts(text)))
end

test "the package's words are available after use"
  assert top_word("to be or not to be") == "to"
end

test "an empty text has no top word"
  assert top_word("") == nil
end
