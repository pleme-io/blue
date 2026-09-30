use("deeta", [:get_or])

use(
  "gyouretsu",
  [
    :dot,
    :matmul,
    :mvmul,
    :scale,
    :solve_gauss,
    :transpose,
    :vadd,
    :vdistance,
    :vector_near,
    :vsub
  ]
)

use("junjo", [:is_strictly_sorted, :sort_stable_by, :upper_bound])
use("kazu", [:abs, :clamp, :lerp, :max, :min, :near, :near_within, :square])

use("kyohi", [:refusal, :refuse])

use(
  "retsu",
  [
    :all_but_last,
    :concat_lists,
    :first,
    :indexes,
    :is_empty,
    :last,
    :push,
    :rest,
    :size,
    :update_at
  ]
)

legacy_names("0.1.1", "kj")

legacy_names(
  "0.1.2",
  [
    ["opt", "deeta::get_or"],
    ["refusal", "kyohi::refusal"],
    ["refusal_kind", "kyohi::kind"],
    ["refusal_why", "kyohi::why"],
    ["refuse", "kyohi::refuse"]
  ]
)

# kinji (近似) — approximation: numerical methods: ODEs, roots, minimisation, least squares, interpolation and quadrature.
#
# A state is a list of numbers, so a scalar problem is a one-element list and
# every vector function in gyouretsu applies to it. Every method that iterates
# takes a limit and reports running out of it as a refusal instead of handing
# back a half-answer. A result is a map; its :refusals are data, each one
# [kind, why], so a caller can test for them, and kj_value(result, key) returns
# the value or throws the refusals.
#
# Written for the design pipeline (nupastel docs/plans/design-pipeline.md,
# step 2): the thermal networks integrate with kj_ode, their parameters are
# fitted to bench curves with kj_fit, and a thermal dose is kj_trapz over a
# measured temperature curve.

# ── refusals ─────────────────────────────────────────────────────────

def refusal_kinds(result)
  map(fn(r) kyohi::kind(r) end, get(result, :refusals))
end

# A result's value, or a thrown error naming its refusals.
def value(result, key)
  refuse(get(result, :refusals))
  get(result, key)
end

# ── numbers ──────────────────────────────────────────────────────────

# A real number: not NaN (NaN is the one value unequal to itself) and not
# infinite. A sqrt of a negative or a blown-up ODE produces these silently.
def finite?(x)
  x == x && abs(x) < expt(10.0, 300)
end

def all_finite?(v)
  reduce(fn(acc, x) acc && finite?(x) end, true, v)
end

# A weighted sum of vectors: sum of ws[i] * ks[i].
def combo(ks, ws)
  reduce(
    fn(acc, i) vadd(acc, scale(nth(i, ws), nth(i, ks))) end,
    scale(0.0, first(ks)),
    indexes(ks)
  )
end

# ── ODEs ─────────────────────────────────────────────────────────────
# f(t, y) returns dy/dt as a list the size of y. A sample is [t, y].

def sample_t(s)
  nth(0, s)
end

def sample_y(s)
  nth(1, s)
end

# One classical Runge–Kutta step of size h.
def rk4_step(f, t, y, h)
  k1 = f(t, y)
  k2 = f(t + h / 2, vadd(y, scale(h / 2, k1)))
  k3 = f(t + h / 2, vadd(y, scale(h / 2, k2)))
  k4 = f(t + h, vadd(y, scale(h, k3)))
  vadd(y, scale(h / 6, combo([k1, k2, k3, k4], [1, 2, 2, 1])))
end

# n fixed steps of size h from (t0, y0): n + 1 samples. A state that stops
# being finite ends the run with :kinji_diverged.
def rk4(f, t0, y0, h, n)
  start = {t: t0, y: y0, back: [[t0, y0]], refusals: []}
  fin = reduce(fn(acc, _i) rk4_tick(f, h, acc) end, start, range(0, n))
  {samples: reverse(get(fin, :back)), refusals: get(fin, :refusals)}
end

def rk4_tick(f, h, acc)
  if is_empty(get(acc, :refusals)) == false
    acc
  else
    t = get(acc, :t) + h
    y = rk4_step(f, get(acc, :t), get(acc, :y), h)
    if all_finite?(y)
      {t: t, y: y, back: concat_lists([[t, y]], get(acc, :back)), refusals: []}
    else
      {
        t: t,
        y: y,
        back: get(acc, :back),
        refusals: [
          refusal(
            :kinji_diverged,
            "the state stopped being finite at t = #{to_s(t)}"
          )
        ]
      }
    end
  end
end

# The Dormand–Prince 5(4) pair: the fifth-order solution and the difference
# from the embedded fourth-order one, which is the error estimate.
def dopri_step(f, t, y, h)
  k1 = f(t, y)
  k2 = f(t + h * 0.2, vadd(y, scale(h, combo([k1], [0.2]))))
  k3 = f(t + h * 0.3, vadd(y, scale(h, combo([k1, k2], [3.0 / 40, 9.0 / 40]))))
  k4 = f(
    t + h * 0.8,
    vadd(y, scale(h, combo([k1, k2, k3], [44.0 / 45, -56.0 / 15, 32.0 / 9])))
  )
  k5 = f(
    t + h * 8.0 / 9,
    vadd(
      y,
      scale(
        h,
        combo(
          [k1, k2, k3, k4],
          [19372.0 / 6561, -25360.0 / 2187, 64448.0 / 6561, -212.0 / 729]
        )
      )
    )
  )
  k6 = f(
    t + h,
    vadd(
      y,
      scale(
        h,
        combo(
          [k1, k2, k3, k4, k5],
          [
            9017.0 / 3168,
            -355.0 / 33,
            46732.0 / 5247,
            49.0 / 176,
            -5103.0 / 18656
          ]
        )
      )
    )
  )
  y5 = vadd(
    y,
    scale(
      h,
      combo(
        [k1, k3, k4, k5, k6],
        [35.0 / 384, 500.0 / 1113, 125.0 / 192, -2187.0 / 6784, 11.0 / 84]
      )
    )
  )
  k7 = f(t + h, y5)
  err = scale(
    h,
    combo(
      [k1, k3, k4, k5, k6, k7],
      [
        71.0 / 57600,
        -71.0 / 16695,
        71.0 / 1920,
        -17253.0 / 339200,
        22.0 / 525,
        -1.0 / 40
      ]
    )
  )
  [y5, err]
end

# The scaled RMS error: at most 1 means the step met the tolerances.
def error_norm(err, y, ynew, rtol, atol)
  s = reduce(
    fn(acc, i)
      acc +
        square(
          nth(i, err) / (atol + rtol * max(abs(nth(i, y)), abs(nth(i, ynew))))
        )
    end,
    0.0,
    indexes(y)
  )
  sqrt(s / size(y))
end

# Adaptive integration from (t0, y0) to t1. Options: :rtol (1e-6), :atol
# (1e-9), :h0 (the first step, (t1 - t0) / 100), :hmin (1e-12 of the span),
# :max_steps (100000). Refusals: :kinji_diverged (the state stopped being
# finite), :kinji_step_underflow (the error could not be met above :hmin),
# :kinji_steps (t1 not reached within :max_steps).
def ode(f, t0, y0, t1, opts)
  span = t1 - t0
  if span <= 0
    {samples: [[t0, y0]], steps: 0, rejected: 0, refusals: []}
  else
    rtol = get_or(opts, :rtol, 0.000001)
    atol = get_or(opts, :atol, 0.000000001)
    hmin = get_or(opts, :hmin, span * 0.000000000001)
    start = {
      t: t0,
      y: y0,
      h: get_or(opts, :h0, span / 100),
      back: [[t0, y0]],
      steps: 0,
      rejected: 0,
      done: false,
      refusals: []
    }
    fin = reduce(
      fn(acc, _i) ode_tick(f, t1, rtol, atol, hmin, acc) end,
      start,
      range(0, get_or(opts, :max_steps, 100000))
    )
    late = if get(fin, :done)
      []
    else
      [
        refusal(
          :kinji_steps,
          "t1 = #{to_s(t1)} not reached in #{to_s(get(fin, :steps))} steps; stopped at t = #{to_s(get(fin, :t))}"
        )
      ]
    end
    {
      samples: reverse(get(fin, :back)),
      steps: get(fin, :steps),
      rejected: get(fin, :rejected),
      refusals: concat_lists(get(fin, :refusals), late)
    }
  end
end

def ode_tick(f, t1, rtol, atol, hmin, acc)
  if get(acc, :done)
    acc
  else
    t = get(acc, :t)
    y = get(acc, :y)
    h = min(get(acc, :h), t1 - t)
    r = dopri_step(f, t, y, h)
    ynew = nth(0, r)
    e = error_norm(nth(1, r), y, ynew, rtol, atol)
    if all_finite?(ynew) == false || finite?(e) == false
      ode_stop(
        acc,
        refusal(
          :kinji_diverged,
          "the state stopped being finite after t = #{to_s(t)}"
        )
      )
    elsif e <= 1
      tn = t + h
      grow = clamp(0.9 * exp(-0.2 * log(max(e, 0.0000000001))), 0.2, 5.0)
      {
        t: tn,
        y: ynew,
        h: h * grow,
        back: concat_lists([[tn, ynew]], get(acc, :back)),
        steps: get(acc, :steps) + 1,
        rejected: get(acc, :rejected),
        done: tn >= t1 - abs(t1) * 0.000000000001,
        refusals: []
      }
    else
      hn = h * max(0.2, 0.9 * exp(-0.2 * log(e)))
      if hn < hmin
        ode_stop(
          acc,
          refusal(
            :kinji_step_underflow,
            "the error could not be met with a step above #{to_s(hmin)} at t = #{to_s(t)}"
          )
        )
      else
        {
          t: t,
          y: y,
          h: hn,
          back: get(acc, :back),
          steps: get(acc, :steps),
          rejected: get(acc, :rejected) + 1,
          done: false,
          refusals: []
        }
      end
    end
  end
end

def ode_stop(acc, refusal)
  {
    t: get(acc, :t),
    y: get(acc, :y),
    h: get(acc, :h),
    back: get(acc, :back),
    steps: get(acc, :steps),
    rejected: get(acc, :rejected),
    done: true,
    refusals: [refusal]
  }
end

# The last sample's state.
def final(result)
  sample_y(last(value(result, :samples)))
end

# The state at time t, linearly interpolated between samples.
def state_at(samples, t)
  ts = map(fn(s) sample_t(s) end, samples)
  i = segment(ts, t)
  a = nth(i, samples)
  b = nth(i + 1, samples)
  w = (t - sample_t(a)) / (sample_t(b) - sample_t(a))
  vadd(sample_y(a), scale(w, vsub(sample_y(b), sample_y(a))))
end

# ── roots ────────────────────────────────────────────────────────────
# f maps a number to a number. Both methods need a bracket: f(lo) and f(hi)
# of opposite signs, or one of them zero.

def bracket_refusals(flo, fhi, lo, hi)
  if flo * fhi > 0
    [
      refusal(
        :kinji_no_bracket,
        "f(#{to_s(lo)}) and f(#{to_s(hi)}) have the same sign"
      )
    ]
  else
    []
  end
end

# Bisection: slow and certain, halving the bracket until it is under tol.
def bisect(f, lo, hi, tol, max_iter)
  flo = f(lo)
  bad = bracket_refusals(flo, f(hi), lo, hi)
  if is_empty(bad) == false
    {root: nil, iterations: 0, refusals: bad}
  else
    fin = reduce(
      fn(acc, _i) bisect_tick(f, tol, acc) end,
      {lo: lo, hi: hi, flo: flo, n: 0, done: false},
      range(0, max_iter)
    )
    {
      root: (get(fin, :lo) + get(fin, :hi)) / 2,
      iterations: get(fin, :n),
      refusals: iter_refusals(get(fin, :done), max_iter)
    }
  end
end

def bisect_tick(f, tol, acc)
  if get(acc, :done)
    acc
  else
    lo = get(acc, :lo)
    hi = get(acc, :hi)
    if hi - lo < tol
      {lo: lo, hi: hi, flo: get(acc, :flo), n: get(acc, :n), done: true}
    else
      mid = (lo + hi) / 2
      fm = f(mid)
      if fm * get(acc, :flo) > 0
        {lo: mid, hi: hi, flo: fm, n: get(acc, :n) + 1, done: false}
      else
        {lo: lo, hi: mid, flo: get(acc, :flo), n: get(acc, :n) + 1, done: false}
      end
    end
  end
end

def iter_refusals(done, max_iter)
  if done
    []
  else
    [
      refusal(
        :kinji_iterations,
        "no convergence in #{to_s(max_iter)} iterations"
      )
    ]
  end
end

# Brent's method: inverse quadratic interpolation or the secant when they are
# safe, bisection when they are not, so it converges as surely as bisection
# and usually far faster.
def brent(f, lo, hi, tol, max_iter)
  fa = f(lo)
  fb = f(hi)
  bad = bracket_refusals(fa, fb, lo, hi)
  if is_empty(bad) == false
    {root: nil, iterations: 0, refusals: bad}
  else
    start = brent_order(
      {
        a: lo,
        fa: fa,
        b: hi,
        fb: fb,
        c: lo,
        fc: fa,
        d: lo,
        mflag: true,
        n: 0,
        done: false
      }
    )
    fin = reduce(
      fn(acc, _i) brent_tick(f, tol, acc) end,
      start,
      range(0, max_iter)
    )
    {
      root: get(fin, :b),
      iterations: get(fin, :n),
      refusals: iter_refusals(get(fin, :done), max_iter)
    }
  end
end

# b is kept as the better of the two bracket ends.
def brent_order(s)
  if abs(get(s, :fa)) < abs(get(s, :fb))
    {
      a: get(s, :b),
      fa: get(s, :fb),
      b: get(s, :a),
      fb: get(s, :fa),
      c: get(s, :c),
      fc: get(s, :fc),
      d: get(s, :d),
      mflag: get(s, :mflag),
      n: get(s, :n),
      done: get(s, :done)
    }
  else
    s
  end
end

def brent_candidate(s)
  a = get(s, :a)
  b = get(s, :b)
  c = get(s, :c)
  fa = get(s, :fa)
  fb = get(s, :fb)
  fc = get(s, :fc)
  if fa != fc && fb != fc
    a * fb * fc / ((fa - fb) * (fa - fc)) +
      b * fa * fc / ((fb - fa) * (fb - fc)) +
      c * fa * fb / ((fc - fa) * (fc - fb))
  else
    b - fb * (b - a) / (fb - fa)
  end
end

# Whether the interpolated candidate must give way to bisection.
def brent_bisect?(s, cand, tol)
  a = get(s, :a)
  b = get(s, :b)
  c = get(s, :c)
  d = get(s, :d)
  q = (3 * a + b) / 4
  outside = if q < b
    cand < q || cand > b
  else
    cand < b || cand > q
  end
  if get(s, :mflag)
    outside || abs(cand - b) >= abs(b - c) / 2 || abs(b - c) < tol
  else
    outside || abs(cand - b) >= abs(c - d) / 2 || abs(c - d) < tol
  end
end

def brent_tick(f, tol, s)
  if get(s, :done)
    s
  elsif get(s, :fb) == 0 || abs(get(s, :b) - get(s, :a)) < tol
    {
      a: get(s, :a),
      fa: get(s, :fa),
      b: get(s, :b),
      fb: get(s, :fb),
      c: get(s, :c),
      fc: get(s, :fc),
      d: get(s, :d),
      mflag: get(s, :mflag),
      n: get(s, :n),
      done: true
    }
  else
    cand = brent_candidate(s)
    bisect = brent_bisect?(s, cand, tol)
    x = if bisect
      (get(s, :a) + get(s, :b)) / 2
    else
      cand
    end
    fx = f(x)
    n = get(s, :n) + 1
    if get(s, :fa) * fx < 0
      brent_order(
        {
          a: get(s, :a),
          fa: get(s, :fa),
          b: x,
          fb: fx,
          c: get(s, :b),
          fc: get(s, :fb),
          d: get(s, :c),
          mflag: bisect,
          n: n,
          done: false
        }
      )
    else
      brent_order(
        {
          a: x,
          fa: fx,
          b: get(s, :b),
          fb: get(s, :fb),
          c: get(s, :b),
          fc: get(s, :fb),
          d: get(s, :c),
          mflag: bisect,
          n: n,
          done: false
        }
      )
    end
  end
end

# ── minimisation ─────────────────────────────────────────────────────
# Nelder–Mead: no derivatives, so it fits models whose gradient nobody wrote
# down. f maps a list of numbers to a number; step is the initial simplex's
# edge along each axis. Converged when every vertex's value is within ftol of
# the best and every vertex within xtol of it.

def nm_vertex(x, fx)
  [x, fx]
end

def nm_x(v)
  nth(0, v)
end

def nm_f(v)
  nth(1, v)
end

def nelder_mead(f, x0, step, opts)
  ftol = get_or(opts, :ftol, 0.000000001)
  xtol = get_or(opts, :xtol, 0.000000001)
  max_iter = get_or(opts, :max_iter, 2000)
  corners = map(fn(i) update_at(x0, i, nth(i, x0) + step) end, indexes(x0))
  simplex = map(fn(x) nm_vertex(x, f(x)) end, concat_lists([x0], corners))
  fin = reduce(
    fn(acc, _i) nm_tick(f, ftol, xtol, acc) end,
    {simplex: nm_sort(simplex), n: 0, done: false},
    range(0, max_iter)
  )
  best = first(get(fin, :simplex))
  {
    x: nm_x(best),
    fx: nm_f(best),
    iterations: get(fin, :n),
    refusals: iter_refusals(get(fin, :done), max_iter)
  }
end

def nm_sort(simplex)
  sort_stable_by(fn(v) nm_f(v) end, simplex)
end

def nm_converged?(simplex, ftol, xtol)
  best = first(simplex)
  reduce(
    fn(acc, v)
      acc &&
        abs(nm_f(v) - nm_f(best)) <= ftol &&
        vdistance(nm_x(v), nm_x(best)) <= xtol
    end,
    true,
    rest(simplex)
  )
end

def nm_tick(f, ftol, xtol, acc)
  if get(acc, :done)
    acc
  else
    simplex = get(acc, :simplex)
    if nm_converged?(simplex, ftol, xtol)
      {simplex: simplex, n: get(acc, :n), done: true}
    else
      {simplex: nm_sort(nm_move(f, simplex)), n: get(acc, :n) + 1, done: false}
    end
  end
end

# One move: reflect the worst vertex through the centroid of the rest, then
# expand, contract or shrink by the standard coefficients (1, 2, 1/2, 1/2).
def nm_move(f, simplex)
  n = size(simplex)
  worst = last(simplex)
  keep = all_but_last(simplex)
  centroid = scale(
    1.0 / (n - 1),
    reduce(fn(acc, v) vadd(acc, nm_x(v)) end, scale(0.0, nm_x(worst)), keep)
  )
  xr = vadd(centroid, vsub(centroid, nm_x(worst)))
  fr = f(xr)
  fbest = nm_f(first(simplex))
  fsecond = nm_f(last(keep))
  if fr < fbest
    xe = vadd(centroid, scale(2.0, vsub(xr, centroid)))
    fe = f(xe)
    if fe < fr
      push(keep, nm_vertex(xe, fe))
    else
      push(keep, nm_vertex(xr, fr))
    end
  elsif fr < fsecond
    push(keep, nm_vertex(xr, fr))
  else
    xc = vadd(centroid, scale(0.5, vsub(nm_x(worst), centroid)))
    fc = f(xc)
    if fc < nm_f(worst)
      push(keep, nm_vertex(xc, fc))
    else
      nm_shrink(f, simplex)
    end
  end
end

def nm_shrink(f, simplex)
  best = nm_x(first(simplex))
  concat_lists(
    [first(simplex)],
    map(fn(v) nm_shrunk(f, best, nm_x(v)) end, rest(simplex))
  )
end

def nm_shrunk(f, best, x)
  xs = vadd(best, scale(0.5, vsub(x, best)))
  nm_vertex(xs, f(xs))
end

# ── least squares and fitting ────────────────────────────────────────

# The x minimising |A x - b|^2, through the normal equations A'A x = A'b. The
# normal equations square the condition number, which is harmless for the
# small, well-scaled fits this is for (a line, a few thermal constants); a
# badly conditioned design matrix should be rescaled first.
def least_squares(a, b)
  at = transpose(a)
  x = solve_gauss(matmul(at, a), mvmul(at, b))
  if is_empty(x)
    {
      x: [],
      residuals: [],
      sse: nil,
      refusals: [
        refusal(
          :kinji_rank,
          "the design matrix has dependent columns, so no unique fit exists"
        )
      ]
    }
  else
    res = vsub(mvmul(a, x), b)
    {x: x, residuals: res, sse: dot(res, res), refusals: []}
  end
end

# The straight line y = intercept + slope * x through (xs, ys), by least squares.
def fit_line(xs, ys)
  r = least_squares(map(fn(x) [1, x] end, xs), ys)
  if is_empty(get(r, :refusals))
    {
      intercept: nth(0, get(r, :x)),
      slope: nth(1, get(r, :x)),
      sse: get(r, :sse),
      refusals: []
    }
  else
    {intercept: nil, slope: nil, sse: nil, refusals: get(r, :refusals)}
  end
end

# The sum of squared errors of model(params, x) against (xs, ys).
def sse(model, params, xs, ys)
  reduce(
    fn(acc, i) acc + square(model(params, nth(i, xs)) - nth(i, ys)) end,
    0.0,
    indexes(xs)
  )
end

# Fit a model's parameters to data by minimising the SSE with Nelder–Mead.
# model(params, x) returns the prediction. The result carries the RMS error
# and the point count, so every fitted constant reports how well it fits and
# on how much data.
def fit(model, p0, xs, ys, opts)
  if size(xs) != size(ys) || is_empty(xs)
    {
      params: [],
      sse: nil,
      rmse: nil,
      n: size(xs),
      iterations: 0,
      refusals: [
        refusal(
          :kinji_data,
          "#{to_s(size(xs))} xs against #{to_s(size(ys))} ys; a fit needs equal, non-empty lists"
        )
      ]
    }
  else
    r = nelder_mead(
      fn(p) sse(model, p, xs, ys) end,
      p0,
      get_or(opts, :step, 0.1),
      opts
    )
    {
      params: get(r, :x),
      sse: get(r, :fx),
      rmse: sqrt(get(r, :fx) / size(xs)),
      n: size(xs),
      iterations: get(r, :iterations),
      refusals: get(r, :refusals)
    }
  end
end

# ── interpolation ────────────────────────────────────────────────────

# The index i of the segment [xs[i], xs[i+1]] holding x, for ascending xs.
def segment(xs, x)
  clamp(upper_bound(xs, x) - 1, 0, size(xs) - 2)
end

def interp_refusals(xs, ys, x)
  if size(xs) < 2 || size(xs) != size(ys)
    [refusal(:kinji_data, "interpolation needs at least two xs and as many ys")]
  elsif is_strictly_sorted(xs) == false
    [refusal(:kinji_data, "the xs must be strictly ascending")]
  elsif x < first(xs) || x > last(xs)
    [
      refusal(
        :kinji_out_of_range,
        "#{to_s(x)} is outside [#{to_s(first(xs))}, #{to_s(last(xs))}]"
      )
    ]
  else
    []
  end
end

# Linear interpolation; outside the data it throws rather than extrapolate.
def interp(xs, ys, x)
  refuse(interp_refusals(xs, ys, x))
  i = segment(xs, x)
  lerp(
    nth(i, ys),
    nth(i + 1, ys),
    (x - nth(i, xs)) / (nth(i + 1, xs) - nth(i, xs))
  )
end

# The same, holding the end values outside the data: for a curve that is
# known to be flat beyond its ends, and chosen as such by the caller.
def interp_clamped(xs, ys, x)
  interp(xs, ys, clamp(x, first(xs), last(xs)))
end

# ── quadrature ───────────────────────────────────────────────────────

# The trapezoid rule over n equal panels.
def trapezoid(f, a, b, n)
  h = (b - a) / n
  inner = reduce(fn(acc, i) acc + f(a + i * h) end, 0.0, range(1, n))
  h * ((f(a) + f(b)) / 2 + inner)
end

# Simpson's rule over n equal panels, n even: exact for cubics.
def simpson(f, a, b, n)
  if n % 2 != 0
    throw(
      error(
        :kinji_data,
        "Simpson's rule needs an even number of panels, not #{to_s(n)}"
      )
    )
  end
  h = (b - a) / n
  inner = reduce(
    fn(acc, i)
      acc +
        if i % 2 == 1
          4
        else
          2
        end *
          f(a + i * h)
    end,
    0.0,
    range(1, n)
  )
  h / 3 * (f(a) + f(b) + inner)
end

# The trapezoid rule over samples (xs ascending), for a measured curve.
def trapz(xs, ys)
  reduce(
    fn(acc, i)
      acc + (nth(i + 1, xs) - nth(i, xs)) * (nth(i, ys) + nth(i + 1, ys)) / 2
    end,
    0.0,
    range(0, size(xs) - 1)
  )
end

# ── tests ────────────────────────────────────────────────────────────

def decay(_t, y)
  scale(-1, y)
end

def oscillator(_t, y)
  [nth(1, y), -nth(0, y)]
end

def blowup(_t, y)
  [square(nth(0, y))]
end

test "an ODE over no time is its start"
  r = ode(fn(t, y) decay(t, y) end, 2.0, [1.0], 2.0, {})
  assert value(r, :samples) == [[2.0, [1.0]]]
  assert get(r, :steps) == 0
end

test "decay matches exp(-t), by fixed and adaptive steps"
  # Independently checkable: y' = -y from y(0) = 1 is exp(-t).
  rk = rk4(fn(t, y) decay(t, y) end, 0.0, [1.0], 0.01, 100)
  assert size(value(rk, :samples)) == 101
  assert near_within(
    nth(0, sample_y(last(get(rk, :samples)))),
    exp(-1.0),
    0.0000001
  ) ==
    true
  dp = ode(
    fn(t, y) decay(t, y) end,
    0.0,
    [1.0],
    1.0,
    {rtol: 0.000000001, atol: 0.000000000001}
  )
  assert near_within(nth(0, final(dp)), exp(-1.0), 0.00000001) == true
  # The adaptive solver takes far fewer steps than the fixed one for this.
  assert get(dp, :steps) < 100
  # Samples interpolate: halfway in time lands near exp(-0.5).
  assert near_within(
    nth(0, state_at(get(dp, :samples), 0.5)),
    exp(-0.5),
    0.001
  ) ==
    true
end

test "an oscillator keeps its energy"
  # An identity: x'' = -x conserves x^2 + v^2; after one period it is back.
  two_pi = 2 * 3.141592653589793
  r = ode(
    fn(t, y) oscillator(t, y) end,
    0.0,
    [1.0, 0.0],
    two_pi,
    {rtol: 0.0000000001, atol: 0.0000000001}
  )
  y = final(r)
  assert near_within(square(nth(0, y)) + square(nth(1, y)), 1.0, 0.00000001) ==
    true
  assert vector_near(y, [1.0, 0.0]) == true
end

test "an ODE that blows up is refused, not answered"
  # The control: y' = y^2 from y(0) = 1 is 1 / (1 - t), infinite at t = 1.
  r = ode(fn(t, y) blowup(t, y) end, 0.0, [1.0], 2.0, {})
  assert is_empty(get(r, :refusals)) == false
  assert error?(try(final(r), catch(e(), e))) == true
  rk = rk4(fn(t, y) blowup(t, y) end, 0.0, [1.0], 0.1, 30)
  assert refusal_kinds(rk) == [:kinji_diverged]
end

test "roots: sqrt(2), the Dottie number, and a refused bracket"
  sq = brent(fn(x) x * x - 2 end, 0.0, 2.0, 0.000000000001, 100)
  assert near_within(value(sq, :root), sqrt(2.0), 0.0000000001) == true
  # cos(x) = x at 0.7390851332151607 (the Dottie number).
  dottie = brent(fn(x) cos(x) - x end, 0.0, 1.0, 0.000000000001, 100)
  assert near_within(value(dottie, :root), 0.7390851332151607, 0.0000000001) ==
    true
  bi = bisect(fn(x) cos(x) - x end, 0.0, 1.0, 0.000000000001, 100)
  assert near_within(value(bi, :root), 0.7390851332151607, 0.0000000001) == true
  # Brent's point: the same answer in fewer evaluations.
  assert get(dottie, :iterations) < get(bi, :iterations)
  # The controls: no sign change, and too few iterations.
  assert refusal_kinds(brent(fn(x) x * x + 1 end, -1.0, 1.0, 0.000001, 100)) ==
    [:kinji_no_bracket]
  assert refusal_kinds(
    bisect(fn(x) cos(x) - x end, 0.0, 1.0, 0.000000000001, 5)
  ) ==
    [:kinji_iterations]
end

test "Nelder–Mead finds the Rosenbrock minimum"
  rosen = fn(p)
    square(1 - nth(0, p)) + 100 * square(nth(1, p) - square(nth(0, p)))
  end
  r = nelder_mead(rosen, [-1.2, 1.0], 0.5, {max_iter: 5000})
  assert is_empty(get(r, :refusals)) == true
  assert vector_near(value(r, :x), [1.0, 1.0]) == true
  # The control: three iterations are not enough, and it says so.
  assert refusal_kinds(nelder_mead(rosen, [-1.2, 1.0], 0.5, {max_iter: 3})) ==
    [:kinji_iterations]
end

test "least squares: an exact line, a known fit, and a rank refusal"
  exact = fit_line([0, 1, 2, 3], [1, 3, 5, 7])
  assert near(get(exact, :intercept), 1) == true
  assert near(get(exact, :slope), 2) == true
  assert near(get(exact, :sse), 0) == true
  # Hand-computed: the least-squares line through (0,0) (1,1) (2,1) is
  # y = 1/6 + x/2, with SSE 1/6.
  fit = fit_line([0, 1, 2], [0, 1, 1])
  assert near(get(fit, :intercept), 1.0 / 6) == true
  assert near(get(fit, :slope), 0.5) == true
  assert near(get(fit, :sse), 1.0 / 6) == true
  # The control: every x equal leaves the slope undetermined.
  assert refusal_kinds(fit_line([2, 2, 2], [1, 2, 3])) == [:kinji_rank]
end

test "kj_fit recovers a decay constant, with its error and point count"
  ts = [0, 1, 2, 3, 4, 5]
  ys = map(fn(t) 80 * exp(-0.3 * t) end, ts)
  r = fit(
    fn(p, t) nth(0, p) * exp(-(nth(1, p) * t)) end,
    [50.0, 0.1],
    ts,
    ys,
    {max_iter: 5000}
  )
  assert vector_near(value(r, :params), [80.0, 0.3]) == true
  assert get(r, :n) == 6
  assert get(r, :rmse) < 0.0001
  assert refusal_kinds(fit(fn(_p, t) t end, [1.0], [1, 2], [1], {})) ==
    [:kinji_data]
end

test "interpolation: at nodes, between them, and refused outside"
  xs = [0, 10, 20]
  ys = [100, 150, 130]
  assert near(interp(xs, ys, 10), 150) == true
  assert near(interp(xs, ys, 5), 125) == true
  assert near(interp(xs, ys, 20), 130) == true
  assert error?(try(interp(xs, ys, 25), catch(e(), e))) == true
  assert kyohi::kind(first(interp_refusals(xs, ys, -1))) == :kinji_out_of_range
  assert kyohi::kind(first(interp_refusals([0, 0, 1], ys, 0))) == :kinji_data
  assert near(interp_clamped(xs, ys, 25), 130) == true
end

test "quadrature: the area under sin, and Simpson exact for a cubic"
  pi = 3.141592653589793
  assert near_within(trapezoid(fn(x) sin(x) end, 0, pi, 1000), 2.0, 0.00001) ==
    true
  assert near_within(simpson(fn(x) sin(x) end, 0, pi, 100), 2.0, 0.0000001) ==
    true
  # The integral of x^3 from 0 to 2 is 4, and Simpson is exact for cubics.
  assert near(simpson(fn(x) x * x * x end, 0, 2, 2), 4) == true
  assert error?(try(simpson(fn(x) x end, 0, 1, 3), catch(e(), e))) == true
  # Sampled: a straight line's trapezoid area is exact.
  assert near(trapz([0, 1, 3], [0, 2, 6]), 9) == true
  # The empty case: one sample encloses no area.
  assert near(trapz([5], [7]), 0) == true
end
