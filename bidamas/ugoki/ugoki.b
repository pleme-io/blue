use("jisho")
use("kazu", [:abs, :clamp, :lerp])
use("moji", [:checked])
use("retsu", [:count_where, :first, :zip])
use("tesuto", [:raises?])

def named_curves()
  {
    ease: [0.25, 0.1, 0.25, 1.0],
    ease_in: [0.42, 0.0, 1.0, 1.0],
    ease_in_out: [0.42, 0.0, 0.58, 1.0],
    ease_out: [0.0, 0.0, 0.58, 1.0]
  }
end

def whole?(n)
  number?(n) and floor(n) == n
end

def bezier_points(points)
  if not list?(points) or
      retsu::size(points) != 4 or
      count_where(number?, points) != 4
    raise(:bad_option, "a bezier curve takes four numbers: x1, y1, x2, y2")
  end
  if nth(0, points) < 0 or
      nth(0, points) > 1 or
      nth(2, points) < 0 or
      nth(2, points) > 1
    raise(:bad_option, "a bezier curve keeps x1 and x2 within 0 and 1")
  end
  points
end

@doc """
curve: declare an easing curve: bezier, steps or named.

    curve(:linear, nil) #=> {kind: :linear}
"""
def curve(kind, params)
  if kind == :linear
    if params != nil
      raise(:bad_option, "a linear curve takes no params")
    end
    {kind: :linear}
  elsif kind == :bezier
    {kind: :bezier, points: bezier_points(params)}
  elsif kind == :steps
    if not whole?(params) or params < 1
      raise(:bad_option, "a steps curve takes a count of 1 or more")
    end
    {kind: :steps, count: params}
  elsif kind == :named
    points = get(named_curves, params)
    if points.nil?
      raise(
        :bad_option,
        "no curve named #{to_s(params)}; one of #{join(map(to_s, jisho::keys(named_curves)), ", ")}"
      )
    end
    {kind: :bezier, points:}
  else
    raise(
      :bad_option,
      "no curve kind #{to_s(kind)}; one of linear, bezier, steps, named"
    )
  end
end

def bezier_at(a, b, s)
  u = 1 - s
  3 * u * u * s * a + 3 * u * s * s * b + s * s * s
end

def solve(x1, x2, target, lo, hi, rounds)
  if rounds == 0
    (lo + hi) / 2
  else
    mid = (lo + hi) / 2
    if bezier_at(x1, x2, mid) < target
      solve(x1, x2, target, mid, hi, rounds - 1)
    else
      solve(x1, x2, target, lo, mid, rounds - 1)
    end
  end
end

@doc """
ease: progress from 0 to 1 along a curve at t.

    ease(curve(:steps, 1), 0.99) #=> 0
"""
def ease(c, t)
  u = clamp(t, 0, 1)
  kind = get(c, :kind)
  if kind == :linear
    u
  elsif kind == :steps
    floor(u * get(c, :count)) / get(c, :count)
  elsif u == 0 or u == 1
    u
  else
    p = get(c, :points)
    s = solve(nth(0, p), nth(2, p), u, 0.0, 1.0, 48)
    bezier_at(nth(1, p), nth(3, p), s)
  end
end

def channels(m, names)
  count_where((k) -> jisho::has?(m, k), names) == retsu::size(names)
end

def color?(v)
  map?(v) and channels(v, [:r, :g, :b])
end

def rotation?(v)
  map?(v) and channels(v, [:x, :y, :z, :w])
end

def mix_color(a, b, t)
  names = if jisho::has?(a, :a) and jisho::has?(b, :a)
    [:r, :g, :b, :a]
  else
    [:r, :g, :b]
  end
  reduce((acc, k) -> assoc(acc, k, lerp(get(a, k), get(b, k), t)), {}, names)
end

def quaternion_dot(a, b)
  get(a, :x) * get(b, :x) +
    get(a, :y) * get(b, :y) +
    get(a, :z) * get(b, :z) +
    get(a, :w) * get(b, :w)
end

def quaternion_blend(a, b, wa, wb)
  reduce(
    (acc, k) -> assoc(acc, k, wa * get(a, k) + wb * get(b, k)),
    {},
    [:x, :y, :z, :w]
  )
end

def quaternion_unit(q)
  n = sqrt(quaternion_dot(q, q))
  reduce((acc, k) -> assoc(acc, k, get(q, k) / n), {}, [:x, :y, :z, :w])
end

def mix_rotation(a, b, t)
  d = quaternion_dot(a, b)
  sign = if d < 0
    -1
  else
    1
  end
  cosine = abs(d)
  if cosine > 0.9995
    quaternion_unit(quaternion_blend(a, b, 1 - t, sign * t))
  else
    theta = acos(cosine)
    quaternion_blend(
      a,
      b,
      sin((1 - t) * theta) / sin(theta),
      sign * sin(t * theta) / sin(theta)
    )
  end
end

@doc """
mix: blend two numbers, vectors, colors or rotations at t.

    mix(10, 20, 0) #=> 10
"""
def mix(a, b, t)
  if number?(a) and number?(b)
    lerp(a, b, t)
  elsif list?(a) and list?(b) and retsu::size(a) == retsu::size(b)
    map((pair) -> mix(first(pair), nth(1, pair), t), zip(a, b))
  elsif color?(a) and color?(b)
    mix_color(a, b, t)
  elsif rotation?(a) and rotation?(b)
    mix_rotation(a, b, t)
  else
    raise(:bad_option, "cannot mix #{to_s(a)} with #{to_s(b)}")
  end
end

def positive_seconds(opts)
  seconds = get(opts, :seconds)
  if not number?(seconds) or seconds <= 0
    raise(:bad_option, "a tween takes seconds: a number above 0")
  end
  seconds
end

@doc """
tween: declare a change of value over a duration.
"""
def tween(from, to, opts)
  checked(opts, [:seconds, :curve])
  mix(from, to, 0)
  c = get(opts, :curve) or curve(:linear, nil)
  {kind: :tween, from:, to:, seconds: positive_seconds(opts), curve: c}
end

@doc """
spring: declare a damped spring motion.
"""
def spring(stiffness, damping, mass)
  if not number?(stiffness) or stiffness <= 0
    raise(:bad_option, "a spring takes a stiffness above 0")
  end
  if not number?(damping) or damping < 0
    raise(:bad_option, "a spring takes a damping of 0 or more")
  end
  if not number?(mass) or mass <= 0
    raise(:bad_option, "a spring takes a mass above 0")
  end
  {kind: :spring, stiffness:, damping:, mass:}
end

def spring_at(m, t)
  k = get(m, :stiffness)
  w0 = sqrt(k / get(m, :mass))
  zeta = get(m, :damping) / (2 * sqrt(k * get(m, :mass)))
  if t <= 0
    [0, 0]
  elsif zeta < 1
    wd = w0 * sqrt(1 - zeta * zeta)
    decay = exp(-zeta * w0 * t)
    [
      1 - decay * (cos(wd * t) + zeta * w0 / wd * sin(wd * t)),
      decay * w0 * w0 / wd * sin(wd * t)
    ]
  elsif zeta == 1
    decay = exp(-w0 * t)
    [1 - decay * (1 + w0 * t), w0 * w0 * t * decay]
  else
    root = w0 * sqrt(zeta * zeta - 1)
    s1 = -zeta * w0 + root
    s2 = -zeta * w0 - root
    e1 = exp(s1 * t)
    e2 = exp(s2 * t)
    [1 - (s2 * e1 - s1 * e2) / (s2 - s1), -(s1 * s2 * (e1 - e2)) / (s2 - s1)]
  end
end

@doc """
duration: how long a motion runs; nil for a spring.

    duration(tween(0, 1, {seconds: 3})) #=> 3
"""
def duration(m)
  get(m, :seconds)
end

@doc """
sample: the value of a motion at time t.
"""
def sample(m, t)
  if get(m, :kind) == :tween
    mix(get(m, :from), get(m, :to), ease(get(m, :curve), t / get(m, :seconds)))
  else
    first(spring_at(m, t))
  end
end

def elapsed(state)
  if state.nil?
    0
  else
    get(state, :t)
  end
end

@doc """
advance: move a motion state forward by dt.
"""
def advance(m, state, opts)
  checked(opts, [:seconds])
  dt = get(opts, :seconds)
  if not number?(dt) or dt < 0
    raise(:bad_option, "advance takes seconds: a number of 0 or more")
  end
  t = elapsed(state) + dt
  {t:, value: sample(m, t)}
end

@doc """
settled?: whether a motion has come to rest.

    settled?(spring(100, 0, 1), {t: 100}) #=> false
"""
def settled?(m, state)
  t = elapsed(state)
  if get(m, :kind) == :tween
    t >= get(m, :seconds)
  else
    at = spring_at(m, t)
    abs(first(at) - 1) < 0.001 and abs(nth(1, at)) < 0.001
  end
end

def close?(a, b)
  abs(a - b) < 0.0001
end

test "curve declares each kind and refuses what it cannot draw"
  assert curve(:linear, nil) == {kind: :linear}
  assert curve(:steps, 4) == {kind: :steps, count: 4}
  assert curve(:bezier, [0.1, 0.2, 0.3, 0.4]) ==
    {kind: :bezier, points: [0.1, 0.2, 0.3, 0.4]}
  assert curve(:named, :ease_in) ==
    {kind: :bezier, points: [0.42, 0.0, 1.0, 1.0]}
  assert curve(:named, :ease) == curve(:bezier, [0.25, 0.1, 0.25, 1.0])
  assert raises?(:bad_option, () -> curve(:linear, 3))
  assert raises?(:bad_option, () -> curve(:steps, 0))
  assert raises?(:bad_option, () -> curve(:steps, 2.5))
  assert raises?(:bad_option, () -> curve(:bezier, [0, 0, 1]))
  assert raises?(:bad_option, () -> curve(:bezier, [2, 0, 0.5, 1]))
  assert raises?(:bad_option, () -> curve(:bezier, [0.5, 0, -0.1, 1]))
  assert raises?(:bad_option, () -> curve(:bezier, [0.5, 0, 1.5, 1]))
  assert raises?(:bad_option, () -> curve(:bezier, [-0.5, 0, 0.5, 1]))
  assert raises?(:bad_option, () -> curve(:bezier, nil))
  assert raises?(:bad_option, () -> curve(:named, :wobble))
  assert raises?(:bad_option, () -> curve(:spline, nil))
end

test "ease is the identity on linear and pins both ends on every curve"
  lin = curve(:linear, nil)
  assert ease(lin, 0.25) == 0.25
  assert ease(lin, -3) == 0
  assert ease(lin, 7) == 1
  assert map(
    (c) -> ease(c, 0),
    [lin, curve(:named, :ease), curve(:steps, 3)]
  ) == [0, 0, 0]
  assert map(
    (c) -> ease(c, 1),
    [lin, curve(:named, :ease), curve(:steps, 3)]
  ) == [1, 1, 1]
  assert ease(curve(:named, :ease), -1) == 0
  assert ease(curve(:named, :ease), 2) == 1
end

test "ease follows a bezier to the value CSS gives"
  assert abs(ease(curve(:named, :ease), 0.5) - 0.8024) < 0.001
  assert close?(ease(curve(:named, :ease_in_out), 0.5), 0.5)
  assert ease(curve(:named, :ease_in), 0.5) < 0.5
  assert ease(curve(:named, :ease_out), 0.5) > 0.5
  assert close?(ease(curve(:bezier, [0.0, 0.0, 1.0, 1.0]), 0.3), 0.3)
end

test "ease steps jump at the end of each step"
  four = curve(:steps, 4)
  assert ease(four, 0.49) == 0.25
  assert ease(four, 0.5) == 0.5
  assert ease(four, 0.99) == 0.75
  assert ease(four, 1) == 1
  assert ease(curve(:steps, 1), 0.99) == 0
end

test "mix blends numbers and is exact at both ends"
  assert mix(10, 20, 0.5) == 15
  assert mix(10, 20, 0) == 10
  assert mix(10, 20, 1) == 20
  assert mix(10, 20, 2) == 30
  assert mix(0.0, 1.0, 0.25) == 0.25
end

test "mix blends vectors element by element and refuses unequal sizes"
  assert mix([0, 10], [10, 20], 0.5) == [5, 15]
  assert mix([], [], 0.5) == []
  assert mix([[0, 0], [2, 2]], [[2, 2], [4, 4]], 0.5) == [[1, 1], [3, 3]]
  assert raises?(:bad_option, () -> mix([1, 2], [1], 0.5))
end

test "mix blends colors channel by channel, with alpha only when both have it"
  black = {r: 0, g: 0, b: 0}
  white = {r: 255, g: 255, b: 255}
  assert mix(black, white, 0.5) == {r: 127.5, g: 127.5, b: 127.5}
  assert mix({r: 0, g: 0, b: 0, a: 0}, {r: 10, g: 10, b: 10, a: 1}, 0.5) ==
    {r: 5, g: 5, b: 5, a: 0.5}
  assert mix({r: 0, g: 0, b: 0, a: 0}, white, 0) == black
end

test "mix slerps rotations along the shortest arc"
  turn = {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
  quarter = {
    x: 0.0,
    y: 0.0,
    z: sin(0.7853981633974483),
    w: cos(0.7853981633974483)
  }
  half = mix(turn, quarter, 0.5)
  assert close?(get(half, :z), sin(0.39269908169872414))
  assert close?(get(half, :w), cos(0.39269908169872414))
  assert close?(get(mix(turn, quarter, 0), :w), 1)
  assert close?(get(mix(turn, quarter, 1), :z), get(quarter, :z))
  flipped = {x: 0.0, y: 0.0, z: -get(quarter, :z), w: -get(quarter, :w)}
  assert close?(get(mix(turn, flipped, 0.5), :z), sin(0.39269908169872414))
  same = mix(turn, turn, 0.5)
  assert close?(get(same, :w), 1)
  assert close?(quaternion_dot(half, half), 1)
end

test "mix refuses values of different kinds"
  assert raises?(:bad_option, () -> mix(1, "a", 0.5))
  assert raises?(:bad_option, () -> mix({r: 0, g: 0, b: 0}, 1, 0.5))
  assert raises?(
    :bad_option,
    () -> mix({r: 0, g: 0, b: 0}, {x: 0, y: 0, z: 0, w: 1}, 0.5)
  )
  assert raises?(:bad_option, () -> mix(nil, nil, 0.5))
end

test "tween declares a change, defaults to linear, and refuses what cannot run"
  m = tween(0, 100, {seconds: 2})
  assert get(m, :kind) == :tween
  assert get(m, :curve) == {kind: :linear}
  assert get(m, :seconds) == 2
  eased = tween(0, 1, {seconds: 1, curve: curve(:steps, 2)})
  assert get(eased, :curve) == {kind: :steps, count: 2}
  assert raises?(:bad_option, () -> tween(0, 1, {}))
  assert raises?(:bad_option, () -> tween(0, 1, {seconds: 0}))
  assert raises?(:bad_option, () -> tween(0, 1, {seconds: -1}))
  assert raises?(:bad_option, () -> tween(0, 1, {seconds: "2"}))
  assert raises?(:bad_option, () -> tween(0, 1, {seconds: 1, speed: 2}))
  assert raises?(:bad_option, () -> tween(0, "a", {seconds: 1}))
end

test "spring declares a unit motion and refuses non-physical parameters"
  s = spring(100, 20, 1)
  assert get(s, :kind) == :spring
  assert get(s, :stiffness) == 100
  assert spring(100, 0, 1) != nil
  assert raises?(:bad_option, () -> spring(0, 1, 1))
  assert raises?(:bad_option, () -> spring(100, -1, 1))
  assert raises?(:bad_option, () -> spring(100, 1, 0))
  assert raises?(:bad_option, () -> spring("a", 1, 1))
end

test "duration is the seconds of a tween and nil for a spring"
  assert duration(tween(0, 1, {seconds: 3})) == 3
  assert duration(spring(100, 20, 1)).nil?
end

test "sample of a tween follows its curve, clamped to the ends"
  m = tween(10, 20, {seconds: 2})
  assert sample(m, 0) == 10
  assert sample(m, 1) == 15
  assert sample(m, 2) == 20
  assert sample(m, -5) == 10
  assert sample(m, 99) == 20
  stepped = tween(0, 100, {seconds: 1, curve: curve(:steps, 4)})
  assert sample(stepped, 0.5) == 50
  vector = tween([0, 0], [10, 20], {seconds: 1})
  assert sample(vector, 0.5) == [5, 10]
  hue = tween({r: 0, g: 0, b: 0}, {r: 100, g: 0, b: 0}, {seconds: 1})
  assert get(sample(hue, 0.25), :r) == 25
end

test "sample of a spring starts at 0, overshoots when underdamped, and rests at 1"
  critical = spring(100, 20, 1)
  assert sample(critical, 0) == 0
  assert sample(critical, -1) == 0
  assert close?(sample(critical, 0.1), 1 - exp(-1) * 2)
  assert close?(sample(critical, 5), 1)
  assert all_below(
    map((t) -> sample(critical, t), [0.1, 0.2, 0.5, 1, 2]),
    1.0001
  )
  bouncy = spring(100, 2, 1)
  assert sample(bouncy, 0.35) > 1
  heavy = spring(100, 60, 1)
  assert sample(heavy, 0.5) < 1
  assert close?(sample(heavy, 20), 1)
end

def all_below(xs, limit)
  count_where((x) -> x < limit, xs) == retsu::size(xs)
end

test "a spring at rest has no velocity and an underdamped one swings through it"
  at = spring_at(spring(100, 2, 1), 0)
  assert at == [0, 0]
  swing = spring_at(spring(100, 2, 1), 0.31)
  assert nth(1, swing) != 0
  assert close?(first(spring_at(spring(100, 20, 1), 30)), 1)
  assert close?(nth(1, spring_at(spring(100, 20, 1), 30)), 0)
end

test "advance moves a state forward by seconds and starts from nil"
  m = tween(0, 10, {seconds: 10})
  first_step = advance(m, nil, {seconds: 1})
  assert first_step == {t: 1, value: 1}
  second = advance(m, first_step, {seconds: 2})
  assert second == {t: 3, value: 3}
  assert advance(m, second, {seconds: 0}) == second
  assert get(advance(m, second, {seconds: 100}), :value) == 10
  assert raises?(:bad_option, () -> advance(m, nil, {}))
  assert raises?(:bad_option, () -> advance(m, nil, {seconds: -1}))
  assert raises?(:bad_option, () -> advance(m, nil, {seconds: 1, speed: 1}))
end

test "stepping a motion by small steps meets sampling it at the total"
  m = tween(0, 100, {seconds: 4, curve: curve(:named, :ease_in_out)})
  state = reduce((s, _i) -> advance(m, s, {seconds: 0.5}), nil, range(0, 6))
  assert close?(get(state, :t), 3.0)
  assert close?(get(state, :value), sample(m, 3.0))
end

test "settled? holds from the end of a tween and when a spring has come to rest"
  m = tween(0, 1, {seconds: 2})
  assert settled?(m, nil) == false
  assert settled?(m, {t: 1.99}) == false
  assert settled?(m, {t: 2}) == true
  assert settled?(m, {t: 10}) == true
  s = spring(100, 20, 1)
  assert settled?(s, nil) == false
  assert settled?(s, {t: 0.2}) == false
  assert settled?(s, {t: 3}) == true
  assert settled?(spring(100, 0, 1), {t: 100}) == false
end

test "ease holds both ends exactly on any bezier, not only the named ones"
  odd = [
    [0.1, 0.9, 0.3, 0.7],
    [0.0, 0.0, 0.0, 0.0],
    [1.0, 0.0, 1.0, 1.0],
    [0.3, -0.5, 0.7, 1.5],
    [0.9, 0.1, 0.1, 0.9]
  ]
  assert map((p) -> ease(curve(:bezier, p), 1), odd) == [1, 1, 1, 1, 1]
  assert map((p) -> ease(curve(:bezier, p), 0), odd) == [0, 0, 0, 0, 0]
end

test "the spring velocity is the slope of its position in every damping regime"
  h = 0.00001
  regimes = [spring(100, 2, 1), spring(100, 20, 1), spring(100, 60, 1)]
  slopes = map(
    fn(m)
      map(
        (t) -> (sample(m, t + h) - sample(m, t - h)) / (2 * h),
        [0.05, 0.2, 0.7]
      )
    end,
    regimes
  )
  speeds = map(
    (m) -> map((t) -> nth(1, spring_at(m, t)), [0.05, 0.2, 0.7]),
    regimes
  )
  assert count_where(
    (p) -> blue::abs(first(p) - nth(1, p)) < 0.001,
    zip(append(*slopes), append(*speeds))
  ) == 9
end

test "an overdamped spring creeps up from 0 and never overshoots"
  heavy = spring(100, 60, 1)
  assert close?(sample(heavy, 0.001), 0)
  assert sample(heavy, 0.001) >= 0
  assert sample(heavy, 0.001) < sample(heavy, 0.01)
  assert sample(heavy, 0.01) < sample(heavy, 0.1)
  assert sample(heavy, 100) <= 1.0000001
end

test "a spring crossing its target at speed is not settled"
  bouncy = spring(100, 2, 1)
  assert abs(sample(bouncy, 0.16789) - 1) < 0.001
  assert settled?(bouncy, {t: 0.16789}) == false
  assert settled?(bouncy, {t: 500}) == true
end
