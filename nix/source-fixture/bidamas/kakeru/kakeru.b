@moduledoc """
kakeru: a package of the source fixture that needs a package another tree holds.

    quadruple(5) #=> 20
"""

use("fixture", [:double])
use("naibu/soto")

@doc """
quadruple: n doubled twice, through the sourced fixture package.

    quadruple(1) #=> 4
"""
def quadruple(n)
  double(naibu::soto::double(n))
end

test "quadruple reaches a sourced package and a sourced level"
  assert quadruple(5) == 20
  assert quadruple(0) == 0
end
