@moduledoc """
kiwari cuts one grammar into every artifact.

    first([1, 2]) #=> 1
"""
# <- punctuation.delimiter.documentation

@doc """
inc adds one.
"""
def inc(x: Int) -> Int
# <- keyword.function
#   ^ function
#       ^ variable.parameter
#          ^ type
#                  ^ type
  x + 1
end

inc(1) #=> 2
#      ^ punctuation.special.doctest

s = "a #=> b"
#       ^ string
