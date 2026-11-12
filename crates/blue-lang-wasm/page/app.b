@moduledoc """
app: one program for two placements, the command line and the wasm engine in a page. Its value is the page section it renders, and both placements must give the same section and the same receipt.

    contains?(main, "<h1>one program, two placements</h1>") #=> true
"""

use("gamen", %i[render view])

@doc """
squared: the line for one number.

    squared(3) #=> "3 squared is 9"
"""
def squared(n)
  "#{to_s(n)} squared is #{to_s(n * n)}"
end

@doc """
sum_of_squares: the squares of 1 to n, added.

    sum_of_squares(5) #=> 55
"""
def sum_of_squares(n)
  reduce((acc, i) -> acc + i * i, 0, range(1, n + 1))
end

def main()
  render(
    view(
      :section,
      {},
      [
        view(:h1, {}, ["one program, two placements"]),
        view(:ul, {}, map((i) -> view(:li, {}, [squared(i)]), range(1, 6))),
        view(:p, {}, ["sum: #{to_s(sum_of_squares(5))} & <done>"])
      ]
    ),
    :html
  )
end
