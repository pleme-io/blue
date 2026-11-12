use("kazu", [:max_of])
use("moji", [:words])

def longest_word(text)
  max_of(map(length, words(text)))
end

test "longest_word of a blank text is nil"
  assert longest_word("   ").nil?
  assert longest_word("").nil?
end

test "longest_word splits on any whitespace"
  assert longest_word("a  bcd\tef") == 3
  assert longest_word(join_lines(["one", "three  xy"])) == 5
end
