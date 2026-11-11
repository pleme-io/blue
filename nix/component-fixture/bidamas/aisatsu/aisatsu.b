@moduledoc """
aisatsu: the greeting line the component fixture's service answers, a package of the project and not of blue's distribution.

    salute("hello", "world") #=> "hello, world"
"""

@doc """
salute: the greeting, a comma, then the subject.

    salute("hi", "you") #=> "hi, you"
"""
def salute(greeting, subject)
  "#{greeting}, #{subject}"
end

test "salute joins the greeting and the subject"
  assert salute("hello", "world") == "hello, world"
  assert salute("", "") == ", "
end
