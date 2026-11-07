test "eval t10: the program does what it did"
  assert area(2, 3) == 6
  assert area(-1, 3).nil?
  assert describe({name: "box", w: 2, h: 2}) == "box: 4"
  shapes = [
    {name: "a", w: 1, h: 2},
    {name: "bad", w: -1, h: 2},
    {name: "c", w: 3, h: 3}
  ]
  assert describe_all(shapes) == "a: 2; c: 9"
end
