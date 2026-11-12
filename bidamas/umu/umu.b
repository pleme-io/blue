@moduledoc """
umu (有無) — presence or absence, as a declared value: blue's Option.

A value that can be missing is an option: `some(v)` holds one, `none` holds
nothing, and a reader tests which before it reads. nil is never an option,
and `some(nil)` is refused, so an option never hides an undeclared nil.
`fold` is the one eliminator; every other word is built on it. `?` reads an
option inside a `def` body: `v = o?` binds the value of a `some` and returns
the `none` from the function at once.

    or_zero = (o) -> value_or(o, 0)
    [or_zero(some(4)), or_zero(none)] #=> [4, 0]

`umu` needs `kyohi`; `kyohi` does not know `umu`. `ok_or` and `to_option`
cross between the two. docs/ABSENCE.md is the design.
"""

use("kyohi", %i[ok ok? refused value])

@doc """
some wraps a present value; nil is refused, since nil is the absence an option replaces.

    some(3) #=> {some: true, value: 3}
"""
def some(v)
  if v.nil?
    raise(:usage, "umu::some takes a value, and nil is absence: use umu::none")
  end
  {some: true, value: v}
end

@doc """
none is the option that holds nothing.

    none #=> {some: false}
"""
none = {some: false}

@doc """
option? answers whether a value is an option at all, `some` or `none`.

    [option?(some(1)), option?(none), option?(nil), option?({})] #=> [true, true, false, false]
"""
def option?(o)
  o == {some: false} or
    map?(o) and o[:some] == true and count(o) == 2 and not o[:value].nil?
end

@doc """
some? answers whether an option holds a value.

    [some?(some(1)), some?(none)] #=> [true, false]
"""
def some?(o)
  fold(o, () -> false, (_v) -> true)
end

@doc """
none? answers whether an option holds nothing.

    [none?(none), none?(some(1))] #=> [true, false]
"""
def none?(o)
  not some?(o)
end

@doc """
fold calls `on_none` for a `none` and `on_some` with the value for a `some`, and refuses anything that is not an option.

    fold(some(2), () -> 0, (v) -> v * 10) #=> 20
"""
def fold(o, on_none, on_some)
  if not option?(o)
    raise(
      :usage,
      "umu::fold takes an option (umu::some or umu::none), and was given #{to_s(o)}"
    )
  end
  if o[:some]
    on_some(o[:value])
  else
    on_none()
  end
end

@doc """
value_or reads the value of a `some`, else `default`.

    [value_or(some(1), 9), value_or(none, 9)] #=> [1, 9]
"""
def value_or(o, default)
  fold(o, () -> default, (v) -> v)
end

@doc """
expect reads the value of a `some` and raises :not_found with `why` for a `none`.

    expect(some(5), "a port") #=> 5
"""
def expect(o, why)
  fold(o, () -> raise(:not_found, why), (v) -> v)
end

@doc """
map applies `f` to the value of a `some`; `f` answering nil is refused, through `some`.

    [map(some(2), (v) -> v + 1), map(none, (v) -> v + 1)] #=> [{some: true, value: 3}, {some: false}]
"""
def map(o, f)
  fold(o, () -> none, (v) -> some(f(v)))
end

@doc """
and_then hands the value of a `some` to `f`, which answers an option itself.

    [and_then(some(4), (n) -> some(n / 2)), and_then(some(3), (_n) -> none)] #=> [{some: true, value: 2}, {some: false}]
"""
def and_then(o, f)
  fold(o, () -> none, f)
end

@doc """
or_else keeps a `some` and asks `f` for an option in place of a `none`.

    [or_else(none, () -> some(7)), or_else(some(1), () -> some(7))] #=> [{some: true, value: 7}, {some: true, value: 1}]
"""
def or_else(o, f)
  fold(o, f, (_v) -> o)
end

@doc """
kept answers `o` when `keep` is true, else `none`.

    [kept(some(1), true), kept(some(1), false)] #=> [{some: true, value: 1}, {some: false}]
"""
def kept(o, keep)
  if keep
    o
  else
    none
  end
end

@doc """
filter keeps a `some` whose value `keep` accepts, else `none`.

    [filter(some(4), (v) -> v > 3), filter(some(2), (v) -> v > 3)] #=> [{some: true, value: 4}, {some: false}]
"""
def filter(o, keep)
  fold(o, () -> none, (v) -> kept(o, keep(v)))
end

@doc """
zip pairs the values of two options, `none` when either is `none`.

    [zip(some(1), some(2)), zip(some(1), none)] #=> [{some: true, value: [1, 2]}, {some: false}]
"""
def zip(a, b)
  and_then(a, (x) -> map(b, (y) -> [x, y]))
end

@doc """
from_nil reads older nil-answering code as an option: nil is `none`, anything else `some`.

    [from_nil(3), from_nil(nil)] #=> [{some: true, value: 3}, {some: false}]
"""
def from_nil(v)
  if v.nil?
    none
  else
    some(v)
  end
end

@doc """
to_nil hands an option to code that still reads nil: the value, or nil for `none`.

    to_nil(some(3)) #=> 3
"""
def to_nil(o)
  fold(o, () -> o[:value], (v) -> v)
end

@doc """
ok_or turns an option into a kyohi result, the refusal `r` standing in for `none`.

    ok?(ok_or(some(1), [:not_found, "x"])) #=> true
"""
def ok_or(o, r)
  fold(o, () -> refused(r), (v) -> ok(v))
end

@doc """
to_option turns a kyohi result into an option: the value of an ok, and `none` for a refusal or for an ok of nil.

    [to_option(ok(2)), to_option(refused([:late, "x"]))] #=> [{some: true, value: 2}, {some: false}]
"""
def to_option(r)
  if ok?(r)
    from_nil(value(r))
  else
    none
  end
end

test "some and none are the two options, and nil is neither"
  assert some(1) == {some: true, value: 1}
  assert none == {some: false}
  assert option?(some(false)) == true
  assert option?(none) == true
  assert option?(nil) == false
  assert option?({some: true}) == false
  assert option?({some: false, value: 1}) == false
  assert option?({some: true, value: 1, extra: 2}) == false
  assert option?([1]) == false
  assert kyohi::raised(() -> some(nil)) == :usage
end

test "fold is the one eliminator and refuses what is not an option"
  assert fold(none, () -> :empty, (v) -> v) == :empty
  assert fold(some(:x), () -> :empty, (v) -> v) == :x
  assert kyohi::raised(() -> fold(nil, () -> 0, (v) -> v)) == :usage
  assert kyohi::raised(() -> fold({ok: true, value: 1}, () -> 0, (v) -> v)) ==
    :usage
end

test "the readers"
  assert some?(some(0)) == true
  assert some?(none) == false
  assert none?(none) == true
  assert value_or(some(false), true) == false
  assert value_or(none, :d) == :d
  assert expect(some(1), "why") == 1
  assert kyohi::raised(() -> expect(none, "no port")) == :not_found
end

test "the combinators keep none and refuse a nil from a mapper"
  assert map(some(2), (v) -> v * 2) == some(4)
  assert map(none, (v) -> v * 2) == none
  assert kyohi::raised(() -> map(some(2), (_v) -> nil)) == :usage
  assert and_then(some(2), (v) -> some(v + 1)) == some(3)
  assert and_then(some(2), (_v) -> none) == none
  assert and_then(none, some) == none
  assert or_else(none, () -> none) == none
  assert or_else(some(1), () -> none) == some(1)
  assert filter(none, (_v) -> true) == none
  assert filter(some(1), (_v) -> false) == none
  assert zip(none, some(1)) == none
  assert zip(some(1), some(2)) == some([1, 2])
end

test "the nil seam and the kyohi seam round-trip"
  assert from_nil(false) == some(false)
  assert to_nil(none).nil?
  assert to_nil(from_nil(3)) == 3
  assert to_option(ok(nil)) == none
  r = [:not_found, "absent"]
  assert to_option(ok_or(some(4), r)) == some(4)
  assert to_option(ok_or(none, r)) == none
  assert ok_or(to_option(ok(5)), r) == ok(5)
  assert ok_or(none, r) == refused(r)
end
