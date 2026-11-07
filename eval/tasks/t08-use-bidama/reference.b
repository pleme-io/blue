use("kazu", [:max_of])
use("moji", [:words])

def longest_word(text)
  max_of(map(length, words(text)))
end
