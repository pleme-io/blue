# Map spread: `{**a, b: 1}` and its call form `f(x, **a, b: 1)`.

def show(a, opts)
  [a, opts]
end

test "a map spread inherits every key and a later entry overrides it"
  ctx = {x: 1, y: 2}
  assert {**ctx, y: 3} == {x: 1, y: 3}
  assert {y: 3, **ctx} == {x: 1, y: 2}
end

test "spreads and entries mix in any order"
  ctx = {x: 1}
  y = 9
  assert {**nil} == {}
  assert {**ctx, **{z: 1}, "k" => 2} == {"k" => 2, x: 1, z: 1}
  assert {a: 1, **ctx, b: 2, y:} == {a: 1, b: 2, x: 1, y: 9}
end

test "a call's last argument is the map its spreads and entries build"
  ctx = {x: 1, y: 2}
  assert show(1, **ctx, y: 5) == [1, {x: 1, y: 5}]
  assert show(0, **ctx) == [0, {x: 1, y: 2}]
  assert show(2, a: 1, **ctx) == [2, {a: 1, x: 1, y: 2}]
end
