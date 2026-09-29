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

def kj_refusal(kind, why)
  [kind, why]
end

def kj_refusal_kind(r)
  nth(0, r)
end

def kj_refusal_why(r)
  nth(1, r)
end

def kj_refusal_kinds(result)
  map(fn(r) kj_refusal_kind(r) end, get(result, :refusals))
end

def kj_refuse(refusals)
  if is_empty(refusals) == false
    throw(
      error(
        kj_refusal_kind(first(refusals)),
        join(map(fn(r) kj_refusal_why(r) end, refusals), "; ")
      )
    )
  end
  nil
end

# A result's value, or a thrown error naming its refusals.
def kj_value(result, key)
  kj_refuse(get(result, :refusals))
  get(result, key)
end

# ── numbers ──────────────────────────────────────────────────────────

# A real number: not NaN (NaN is the one value unequal to itself) and not
# infinite. A sqrt of a negative or a blown-up ODE produces these silently.
def kj_finite?(x)
  x == x && abs(x) < expt(10.0, 300)
end

def kj_all_finite?(v)
  reduce(fn(acc, x) acc && kj_finite?(x) end, true, v)
end

# A weighted sum of vectors: sum of ws[i] * ks[i].
def kj_combo(ks, ws)
  reduce(
    fn(acc, i) vadd(acc, scale(nth(i, ws), nth(i, ks))) end,
    scale(0.0, first(ks)),
    indexes(ks)
  )
end

# An option from a map, or its default when absent.
def kj_opt(opts, key, default)
  v = get(opts, key)
  if v == nil
    default
  else
    v
  end
end

# ── ODEs ─────────────────────────────────────────────────────────────
# f(t, y) returns dy/dt as a list the size of y. A sample is [t, y].

def kj_sample_t(s)
  nth(0, s)
end

def kj_sample_y(s)
  nth(1, s)
end

# One classical Runge–Kutta step of size h.
def kj_rk4_step(f, t, y, h)
  k1 = f(t, y)
  k2 = f(t + h / 2, vadd(y, scale(h / 2, k1)))
  k3 = f(t + h / 2, vadd(y, scale(h / 2, k2)))
  k4 = f(t + h, vadd(y, scale(h, k3)))
  vadd(y, scale(h / 6, kj_combo([k1, k2, k3, k4], [1, 2, 2, 1])))
end

# n fixed steps of size h from (t0, y0): n + 1 samples. A state that stops
# being finite ends the run with :kinji_diverged.
def kj_rk4(f, t0, y0, h, n)
  start = {t: t0, y: y0, back: [[t0, y0]], refusals: []}
  fin = reduce(fn(acc, _i) kj_rk4_tick(f, h, acc) end, start, range(0, n))
  {samples: reverse(get(fin, :back)), refusals: get(fin, :refusals)}
end

def kj_rk4_tick(f, h, acc)
  if is_empty(get(acc, :refusals)) == false
    acc
  else
    t = get(acc, :t) + h
    y = kj_rk4_step(f, get(acc, :t), get(acc, :y), h)
    if kj_all_finite?(y)
      {t: t, y: y, back: concat_lists([[t, y]], get(acc, :back)), refusals: []}
    else
      {
        t: t,
        y: y,
        back: get(acc, :back),
        refusals: [
          kj_refusal(
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
def kj_dopri_step(f, t, y, h)
  k1 = f(t, y)
  k2 = f(t + h * 0.2, vadd(y, scale(h, kj_combo([k1], [0.2]))))
  k3 = f(
    t + h * 0.3,
    vadd(y, scale(h, kj_combo([k1, k2], [3.0 / 40, 9.0 / 40])))
  )
  k4 = f(
    t + h * 0.8,
    vadd(y, scale(h, kj_combo([k1, k2, k3], [44.0 / 45, -56.0 / 15, 32.0 / 9])))
  )
  k5 = f(
    t + h * 8.0 / 9,
    vadd(
      y,
      scale(
        h,
        kj_combo(
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
        kj_combo(
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
      kj_combo(
        [k1, k3, k4, k5, k6],
        [35.0 / 384, 500.0 / 1113, 125.0 / 192, -2187.0 / 6784, 11.0 / 84]
      )
    )
  )
  k7 = f(t + h, y5)
  err = scale(
    h,
    kj_combo(
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
def kj_error_norm(err, y, ynew, rtol, atol)
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
def kj_ode(f, t0, y0, t1, opts)
  span = t1 - t0
  if span <= 0
    {samples: [[t0, y0]], steps: 0, rejected: 0, refusals: []}
  else
    rtol = kj_opt(opts, :rtol, 0.000001)
    atol = kj_opt(opts, :atol, 0.000000001)
    hmin = kj_opt(opts, :hmin, span * 0.000000000001)
    start = {
      t: t0,
      y: y0,
      h: kj_opt(opts, :h0, span / 100),
      back: [[t0, y0]],
      steps: 0,
      rejected: 0,
      done: false,
      refusals: []
    }
    fin = reduce(
      fn(acc, _i) kj_ode_tick(f, t1, rtol, atol, hmin, acc) end,
      start,
      range(0, kj_opt(opts, :max_steps, 100000))
    )
    late = if get(fin, :done)
      []
    else
      [
        kj_refusal(
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

def kj_ode_tick(f, t1, rtol, atol, hmin, acc)
  if get(acc, :done)
    acc
  else
    t = get(acc, :t)
    y = get(acc, :y)
    h = min(get(acc, :h), t1 - t)
    r = kj_dopri_step(f, t, y, h)
    ynew = nth(0, r)
    e = kj_error_norm(nth(1, r), y, ynew, rtol, atol)
    if kj_all_finite?(ynew) == false || kj_finite?(e) == false
      kj_ode_stop(
        acc,
        kj_refusal(
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
        kj_ode_stop(
          acc,
          kj_refusal(
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

def kj_ode_stop(acc, refusal)
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
def kj_final(result)
  kj_sample_y(last(kj_value(result, :samples)))
end

# The state at time t, linearly interpolated between samples.
def kj_state_at(samples, t)
  ts = map(fn(s) kj_sample_t(s) end, samples)
  i = kj_segment(ts, t)
  a = nth(i, samples)
  b = nth(i + 1, samples)
  w = (t - kj_sample_t(a)) / (kj_sample_t(b) - kj_sample_t(a))
  vadd(kj_sample_y(a), scale(w, vsub(kj_sample_y(b), kj_sample_y(a))))
end

# ── roots ────────────────────────────────────────────────────────────
# f maps a number to a number. Both methods need a bracket: f(lo) and f(hi)
# of opposite signs, or one of them zero.

def kj_bracket_refusals(flo, fhi, lo, hi)
  if flo * fhi > 0
    [
      kj_refusal(
        :kinji_no_bracket,
        "f(#{to_s(lo)}) and f(#{to_s(hi)}) have the same sign"
      )
    ]
  else
    []
  end
end

# Bisection: slow and certain, halving the bracket until it is under tol.
def kj_bisect(f, lo, hi, tol, max_iter)
  flo = f(lo)
  bad = kj_bracket_refusals(flo, f(hi), lo, hi)
  if is_empty(bad) == false
    {root: nil, iterations: 0, refusals: bad}
  else
    fin = reduce(
      fn(acc, _i) kj_bisect_tick(f, tol, acc) end,
      {lo: lo, hi: hi, flo: flo, n: 0, done: false},
      range(0, max_iter)
    )
    {
      root: (get(fin, :lo) + get(fin, :hi)) / 2,
      iterations: get(fin, :n),
      refusals: kj_iter_refusals(get(fin, :done), max_iter)
    }
  end
end

def kj_bisect_tick(f, tol, acc)
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

def kj_iter_refusals(done, max_iter)
  if done
    []
  else
    [
      kj_refusal(
        :kinji_iterations,
        "no convergence in #{to_s(max_iter)} iterations"
      )
    ]
  end
end

# Brent's method: inverse quadratic interpolation or the secant when they are
# safe, bisection when they are not, so it converges as surely as bisection
# and usually far faster.
def kj_brent(f, lo, hi, tol, max_iter)
  fa = f(lo)
  fb = f(hi)
  bad = kj_bracket_refusals(fa, fb, lo, hi)
  if is_empty(bad) == false
    {root: nil, iterations: 0, refusals: bad}
  else
    start = kj_brent_order(
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
      fn(acc, _i) kj_brent_tick(f, tol, acc) end,
      start,
      range(0, max_iter)
    )
    {
      root: get(fin, :b),
      iterations: get(fin, :n),
      refusals: kj_iter_refusals(get(fin, :done), max_iter)
    }
  end
end

# b is kept as the better of the two bracket ends.
def kj_brent_order(s)
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

def kj_brent_candidate(s)
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
def kj_brent_bisect?(s, cand, tol)
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

def kj_brent_tick(f, tol, s)
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
    cand = kj_brent_candidate(s)
    bisect = kj_brent_bisect?(s, cand, tol)
    x = if bisect
      (get(s, :a) + get(s, :b)) / 2
    else
      cand
    end
    fx = f(x)
    n = get(s, :n) + 1
    if get(s, :fa) * fx < 0
      kj_brent_order(
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
      kj_brent_order(
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

def kj_nm_vertex(x, fx)
  [x, fx]
end

def kj_nm_x(v)
  nth(0, v)
end

def kj_nm_f(v)
  nth(1, v)
end

def kj_nelder_mead(f, x0, step, opts)
  ftol = kj_opt(opts, :ftol, 0.000000001)
  xtol = kj_opt(opts, :xtol, 0.000000001)
  max_iter = kj_opt(opts, :max_iter, 2000)
  corners = map(fn(i) update_at(x0, i, nth(i, x0) + step) end, indexes(x0))
  simplex = map(fn(x) kj_nm_vertex(x, f(x)) end, concat_lists([x0], corners))
  fin = reduce(
    fn(acc, _i) kj_nm_tick(f, ftol, xtol, acc) end,
    {simplex: kj_nm_sort(simplex), n: 0, done: false},
    range(0, max_iter)
  )
  best = first(get(fin, :simplex))
  {
    x: kj_nm_x(best),
    fx: kj_nm_f(best),
    iterations: get(fin, :n),
    refusals: kj_iter_refusals(get(fin, :done), max_iter)
  }
end

def kj_nm_sort(simplex)
  sort_stable_by(fn(v) kj_nm_f(v) end, simplex)
end

def kj_nm_converged?(simplex, ftol, xtol)
  best = first(simplex)
  reduce(
    fn(acc, v)
      acc &&
        abs(kj_nm_f(v) - kj_nm_f(best)) <= ftol &&
        vdistance(kj_nm_x(v), kj_nm_x(best)) <= xtol
    end,
    true,
    rest(simplex)
  )
end

def kj_nm_tick(f, ftol, xtol, acc)
  if get(acc, :done)
    acc
  else
    simplex = get(acc, :simplex)
    if kj_nm_converged?(simplex, ftol, xtol)
      {simplex: simplex, n: get(acc, :n), done: true}
    else
      {
        simplex: kj_nm_sort(kj_nm_move(f, simplex)),
        n: get(acc, :n) + 1,
        done: false
      }
    end
  end
end

# One move: reflect the worst vertex through the centroid of the rest, then
# expand, contract or shrink by the standard coefficients (1, 2, 1/2, 1/2).
def kj_nm_move(f, simplex)
  n = size(simplex)
  worst = last(simplex)
  keep = all_but_last(simplex)
  centroid = scale(
    1.0 / (n - 1),
    reduce(
      fn(acc, v) vadd(acc, kj_nm_x(v)) end,
      scale(0.0, kj_nm_x(worst)),
      keep
    )
  )
  xr = vadd(centroid, vsub(centroid, kj_nm_x(worst)))
  fr = f(xr)
  fbest = kj_nm_f(first(simplex))
  fsecond = kj_nm_f(last(keep))
  if fr < fbest
    xe = vadd(centroid, scale(2.0, vsub(xr, centroid)))
    fe = f(xe)
    if fe < fr
      push(keep, kj_nm_vertex(xe, fe))
    else
      push(keep, kj_nm_vertex(xr, fr))
    end
  elsif fr < fsecond
    push(keep, kj_nm_vertex(xr, fr))
  else
    xc = vadd(centroid, scale(0.5, vsub(kj_nm_x(worst), centroid)))
    fc = f(xc)
    if fc < kj_nm_f(worst)
      push(keep, kj_nm_vertex(xc, fc))
    else
      kj_nm_shrink(f, simplex)
    end
  end
end

def kj_nm_shrink(f, simplex)
  best = kj_nm_x(first(simplex))
  concat_lists(
    [first(simplex)],
    map(fn(v) kj_nm_shrunk(f, best, kj_nm_x(v)) end, rest(simplex))
  )
end

def kj_nm_shrunk(f, best, x)
  xs = vadd(best, scale(0.5, vsub(x, best)))
  kj_nm_vertex(xs, f(xs))
end

# ── least squares and fitting ────────────────────────────────────────

# The x minimising |A x - b|^2, through the normal equations A'A x = A'b. The
# normal equations square the condition number, which is harmless for the
# small, well-scaled fits this is for (a line, a few thermal constants); a
# badly conditioned design matrix should be rescaled first.
def kj_least_squares(a, b)
  at = transpose(a)
  x = solve_gauss(matmul(at, a), mvmul(at, b))
  if is_empty(x)
    {
      x: [],
      residuals: [],
      sse: nil,
      refusals: [
        kj_refusal(
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
def kj_fit_line(xs, ys)
  r = kj_least_squares(map(fn(x) [1, x] end, xs), ys)
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
def kj_sse(model, params, xs, ys)
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
def kj_fit(model, p0, xs, ys, opts)
  if size(xs) != size(ys) || is_empty(xs)
    {
      params: [],
      sse: nil,
      rmse: nil,
      n: size(xs),
      iterations: 0,
      refusals: [
        kj_refusal(
          :kinji_data,
          "#{to_s(size(xs))} xs against #{to_s(size(ys))} ys; a fit needs equal, non-empty lists"
        )
      ]
    }
  else
    r = kj_nelder_mead(
      fn(p) kj_sse(model, p, xs, ys) end,
      p0,
      kj_opt(opts, :step, 0.1),
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
def kj_segment(xs, x)
  clamp(upper_bound(xs, x) - 1, 0, size(xs) - 2)
end

def kj_interp_refusals(xs, ys, x)
  if size(xs) < 2 || size(xs) != size(ys)
    [
      kj_refusal(
        :kinji_data,
        "interpolation needs at least two xs and as many ys"
      )
    ]
  elsif is_strictly_sorted(xs) == false
    [kj_refusal(:kinji_data, "the xs must be strictly ascending")]
  elsif x < first(xs) || x > last(xs)
    [
      kj_refusal(
        :kinji_out_of_range,
        "#{to_s(x)} is outside [#{to_s(first(xs))}, #{to_s(last(xs))}]"
      )
    ]
  else
    []
  end
end

# Linear interpolation; outside the data it throws rather than extrapolate.
def kj_interp(xs, ys, x)
  kj_refuse(kj_interp_refusals(xs, ys, x))
  i = kj_segment(xs, x)
  lerp(
    nth(i, ys),
    nth(i + 1, ys),
    (x - nth(i, xs)) / (nth(i + 1, xs) - nth(i, xs))
  )
end

# The same, holding the end values outside the data: for a curve that is
# known to be flat beyond its ends, and chosen as such by the caller.
def kj_interp_clamped(xs, ys, x)
  kj_interp(xs, ys, clamp(x, first(xs), last(xs)))
end

# ── quadrature ───────────────────────────────────────────────────────

# The trapezoid rule over n equal panels.
def kj_trapezoid(f, a, b, n)
  h = (b - a) / n
  inner = reduce(fn(acc, i) acc + f(a + i * h) end, 0.0, range(1, n))
  h * ((f(a) + f(b)) / 2 + inner)
end

# Simpson's rule over n equal panels, n even: exact for cubics.
def kj_simpson(f, a, b, n)
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
def kj_trapz(xs, ys)
  reduce(
    fn(acc, i)
      acc + (nth(i + 1, xs) - nth(i, xs)) * (nth(i, ys) + nth(i + 1, ys)) / 2
    end,
    0.0,
    range(0, size(xs) - 1)
  )
end

# ── tests ────────────────────────────────────────────────────────────

def kj_decay(_t, y)
  scale(-1, y)
end

def kj_oscillator(_t, y)
  [nth(1, y), -nth(0, y)]
end

def kj_blowup(_t, y)
  [square(nth(0, y))]
end

test "an ODE over no time is its start"
  r = kj_ode(fn(t, y) kj_decay(t, y) end, 2.0, [1.0], 2.0, {})
  assert kj_value(r, :samples) == [[2.0, [1.0]]]
  assert get(r, :steps) == 0
end

test "decay matches exp(-t), by fixed and adaptive steps"
  # Independently checkable: y' = -y from y(0) = 1 is exp(-t).
  rk = kj_rk4(fn(t, y) kj_decay(t, y) end, 0.0, [1.0], 0.01, 100)
  assert size(kj_value(rk, :samples)) == 101
  assert near_within(
    nth(0, kj_sample_y(last(get(rk, :samples)))),
    exp(-1.0),
    0.0000001
  ) ==
    true
  dp = kj_ode(
    fn(t, y) kj_decay(t, y) end,
    0.0,
    [1.0],
    1.0,
    {rtol: 0.000000001, atol: 0.000000000001}
  )
  assert near_within(nth(0, kj_final(dp)), exp(-1.0), 0.00000001) == true
  # The adaptive solver takes far fewer steps than the fixed one for this.
  assert get(dp, :steps) < 100
  # Samples interpolate: halfway in time lands near exp(-0.5).
  assert near_within(
    nth(0, kj_state_at(get(dp, :samples), 0.5)),
    exp(-0.5),
    0.001
  ) ==
    true
end

test "an oscillator keeps its energy"
  # An identity: x'' = -x conserves x^2 + v^2; after one period it is back.
  two_pi = 2 * 3.141592653589793
  r = kj_ode(
    fn(t, y) kj_oscillator(t, y) end,
    0.0,
    [1.0, 0.0],
    two_pi,
    {rtol: 0.0000000001, atol: 0.0000000001}
  )
  y = kj_final(r)
  assert near_within(square(nth(0, y)) + square(nth(1, y)), 1.0, 0.00000001) ==
    true
  assert vector_near(y, [1.0, 0.0]) == true
end

test "an ODE that blows up is refused, not answered"
  # The control: y' = y^2 from y(0) = 1 is 1 / (1 - t), infinite at t = 1.
  r = kj_ode(fn(t, y) kj_blowup(t, y) end, 0.0, [1.0], 2.0, {})
  assert is_empty(get(r, :refusals)) == false
  assert error?(try(kj_final(r), catch(e(), e))) == true
  rk = kj_rk4(fn(t, y) kj_blowup(t, y) end, 0.0, [1.0], 0.1, 30)
  assert kj_refusal_kinds(rk) == [:kinji_diverged]
end

test "roots: sqrt(2), the Dottie number, and a refused bracket"
  sq = kj_brent(fn(x) x * x - 2 end, 0.0, 2.0, 0.000000000001, 100)
  assert near_within(kj_value(sq, :root), sqrt(2.0), 0.0000000001) == true
  # cos(x) = x at 0.7390851332151607 (the Dottie number).
  dottie = kj_brent(fn(x) cos(x) - x end, 0.0, 1.0, 0.000000000001, 100)
  assert near_within(
    kj_value(dottie, :root),
    0.7390851332151607,
    0.0000000001
  ) ==
    true
  bi = kj_bisect(fn(x) cos(x) - x end, 0.0, 1.0, 0.000000000001, 100)
  assert near_within(kj_value(bi, :root), 0.7390851332151607, 0.0000000001) ==
    true
  # Brent's point: the same answer in fewer evaluations.
  assert get(dottie, :iterations) < get(bi, :iterations)
  # The controls: no sign change, and too few iterations.
  assert kj_refusal_kinds(
    kj_brent(fn(x) x * x + 1 end, -1.0, 1.0, 0.000001, 100)
  ) ==
    [:kinji_no_bracket]
  assert kj_refusal_kinds(
    kj_bisect(fn(x) cos(x) - x end, 0.0, 1.0, 0.000000000001, 5)
  ) ==
    [:kinji_iterations]
end

test "Nelder–Mead finds the Rosenbrock minimum"
  rosen = fn(p)
    square(1 - nth(0, p)) + 100 * square(nth(1, p) - square(nth(0, p)))
  end
  r = kj_nelder_mead(rosen, [-1.2, 1.0], 0.5, {max_iter: 5000})
  assert is_empty(get(r, :refusals)) == true
  assert vector_near(kj_value(r, :x), [1.0, 1.0]) == true
  # The control: three iterations are not enough, and it says so.
  assert kj_refusal_kinds(
    kj_nelder_mead(rosen, [-1.2, 1.0], 0.5, {max_iter: 3})
  ) ==
    [:kinji_iterations]
end

test "least squares: an exact line, a known fit, and a rank refusal"
  exact = kj_fit_line([0, 1, 2, 3], [1, 3, 5, 7])
  assert near(get(exact, :intercept), 1) == true
  assert near(get(exact, :slope), 2) == true
  assert near(get(exact, :sse), 0) == true
  # Hand-computed: the least-squares line through (0,0) (1,1) (2,1) is
  # y = 1/6 + x/2, with SSE 1/6.
  fit = kj_fit_line([0, 1, 2], [0, 1, 1])
  assert near(get(fit, :intercept), 1.0 / 6) == true
  assert near(get(fit, :slope), 0.5) == true
  assert near(get(fit, :sse), 1.0 / 6) == true
  # The control: every x equal leaves the slope undetermined.
  assert kj_refusal_kinds(kj_fit_line([2, 2, 2], [1, 2, 3])) == [:kinji_rank]
end

test "kj_fit recovers a decay constant, with its error and point count"
  ts = [0, 1, 2, 3, 4, 5]
  ys = map(fn(t) 80 * exp(-0.3 * t) end, ts)
  r = kj_fit(
    fn(p, t) nth(0, p) * exp(-(nth(1, p) * t)) end,
    [50.0, 0.1],
    ts,
    ys,
    {max_iter: 5000}
  )
  assert vector_near(kj_value(r, :params), [80.0, 0.3]) == true
  assert get(r, :n) == 6
  assert get(r, :rmse) < 0.0001
  assert kj_refusal_kinds(kj_fit(fn(_p, t) t end, [1.0], [1, 2], [1], {})) ==
    [:kinji_data]
end

test "interpolation: at nodes, between them, and refused outside"
  xs = [0, 10, 20]
  ys = [100, 150, 130]
  assert near(kj_interp(xs, ys, 10), 150) == true
  assert near(kj_interp(xs, ys, 5), 125) == true
  assert near(kj_interp(xs, ys, 20), 130) == true
  assert error?(try(kj_interp(xs, ys, 25), catch(e(), e))) == true
  assert kj_refusal_kind(first(kj_interp_refusals(xs, ys, -1))) ==
    :kinji_out_of_range
  assert kj_refusal_kind(first(kj_interp_refusals([0, 0, 1], ys, 0))) ==
    :kinji_data
  assert near(kj_interp_clamped(xs, ys, 25), 130) == true
end

test "quadrature: the area under sin, and Simpson exact for a cubic"
  pi = 3.141592653589793
  assert near_within(
    kj_trapezoid(fn(x) sin(x) end, 0, pi, 1000),
    2.0,
    0.00001
  ) ==
    true
  assert near_within(
    kj_simpson(fn(x) sin(x) end, 0, pi, 100),
    2.0,
    0.0000001
  ) ==
    true
  # The integral of x^3 from 0 to 2 is 4, and Simpson is exact for cubics.
  assert near(kj_simpson(fn(x) x * x * x end, 0, 2, 2), 4) == true
  assert error?(try(kj_simpson(fn(x) x end, 0, 1, 3), catch(e(), e))) == true
  # Sampled: a straight line's trapezoid area is exact.
  assert near(kj_trapz([0, 1, 3], [0, 2, 6]), 9) == true
  # The empty case: one sample encloses no area.
  assert near(kj_trapz([5], [7]), 0) == true
end
