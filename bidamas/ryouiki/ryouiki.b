use("retsu")
use("junjo")
use("toukei")
use("ran")
# ryouiki (領域) — region: which region of the inputs produces an outcome.
#
# Scenario discovery by PRIM, the Patient Rule Induction Method (Friedman &
# Fisher 1999; as used for robust decision making by Bryant & Lempert 2010):
# given many runs, each a point of input values with a target (1 where the
# outcome of interest happened, else 0 — or any number to maximise), find a
# box — a range per input — inside which the target is dense, while it still
# holds much of the target.
#
# The algorithm peels. Start with the box around every point. At each step,
# try removing a thin slice (the `alpha` share, or the lowest or highest
# level when inputs sit on a grid) from the low or high end of each input,
# and keep the one peel that leaves the highest mean target inside. Stop when
# fewer than `min_support` of the points remain. Every step is kept: the
# trajectory trades COVERAGE (the share of all target inside the box) against
# DENSITY (the mean target inside), and the caller picks the box — usually
# the one with the most coverage at a density it can defend.
#
# A box is a list of [lo, hi] per input, inclusive. A trajectory row is
# [step, support, coverage, density, box]. Everything is deterministic: no
# randomness is used, so the same runs give the same boxes.

# The box around every point: [min, max] of each input.
def box_around(points)
  if is_empty(points)
    []
  else
    map(fn(j)
      xs = map(fn(p) nth(j, p) end, points)
      [smallest(xs), largest(xs)]
    end, range(0, size(first(points))))
  end
end

def in_box?(box, p)
  size(filter(fn(j) (nth(j, p) < first(nth(j, box))) || (nth(j, p) > last(nth(j, box))) end, range(0, size(box)))) == 0
end

def inside_of(box, points)
  filter(fn(i) in_box?(box, nth(i, points)) end, range(0, size(points)))
end

def mean_target(ids, ys)
  if is_empty(ids)
    0
  else
    mean(map(fn(i) nth(i, ys) end, ids))
  end
end

# The narrower edge for one input and side: the alpha-quantile of the values
# inside, or — where that removes nothing (tied grid levels) — the next
# distinct level. Returns nil when the input has only one level left.
def peeled_edge(values, side, alpha)
  levels = sort(distinct(values))
  if size(levels) < 2
    nil
  elsif side == :lo
    q = percentile(values, alpha)
    if q > first(levels)
      smallest(filter(fn(v) v >= q end, levels))
    else
      nth(1, levels)
    end
  else
    q = percentile(values, 1 - alpha)
    if q < last(levels)
      largest(filter(fn(v) v <= q end, levels))
    else
      nth(size(levels) - 2, levels)
    end
  end
end

# Every candidate peel from `box`: [box', inside', density'].
def peel_candidates(box, ids, points, ys, alpha)
  flat_map(fn(j)
    values = map(fn(i) nth(j, nth(i, points)) end, ids)
    flat_map(fn(side)
      edge = peeled_edge(values, side, alpha)
      if edge == nil
        []
      else
        narrowed = map(fn(k)
          if k != j
            nth(k, box)
          elsif side == :lo
            [edge, last(nth(k, box))]
          else
            [first(nth(k, box)), edge]
          end
        end, range(0, size(box)))
        kept = filter(fn(i) in_box?(narrowed, nth(i, points)) end, ids)
        if is_empty(kept) || (size(kept) == size(ids))
          []
        else
          [[narrowed, kept, mean_target(kept, ys)]]
        end
      end
    end, [:lo, :hi])
  end, range(0, size(box)))
end

# The peeling trajectory. alpha: the share peeled per step (0.05 is PRIM's
# usual); min_support: stop when fewer than this share of points remain.
def prim(points, ys, alpha, min_support)
  n = size(points)
  if n == 0
    []
  else
    total = sum(ys)
    row = fn(step, box, ids) [step, size(ids) / n, if_zero_total(total, sum(map(fn(i) nth(i, ys) end, ids)) / max(total, 0.000000001)), mean_target(ids, ys), box] end
    start = box_around(points)
    start_ids = range(0, n)
    walk = fn(self, step, box, ids, acc)
      cands = peel_candidates(box, ids, points, ys, alpha)
      if is_empty(cands) || ((size(ids) / n) <= min_support)
        acc
      else
        best = first(sort_by(fn(c) (0 - nth(2, c)) + (size(nth(1, c)) * 0.000000001) end, cands))
        if (size(nth(1, best)) / n) < min_support
          acc
        else
          self(self, step + 1, first(best), nth(1, best), concat_lists(acc, [row(step + 1, first(best), nth(1, best))]))
        end
      end
    end
    walk(walk, 0, start, start_ids, [row(0, start, start_ids)])
  end
end

def if_zero_total(total, value)
  if total == 0
    0
  else
    value
  end
end

# The box to report: the most coverage among steps at or above `density`,
# or nil when no step reaches it.
def prim_box(trajectory, density)
  ok = filter(fn(r) nth(3, r) >= density end, trajectory)
  if is_empty(ok)
    nil
  else
    first(sort_by(fn(r) (0 - nth(2, r)) + (nth(0, r) * 0.000000001) end, ok))
  end
end

# A box as text over named inputs: "x in [5, 9], y in [0, 3]" — only the
# inputs the box actually restricts relative to `full`.
def box_text(names, box, full)
  parts = flat_map(fn(j)
    if nth(j, box) == nth(j, full)
      []
    else
      [concat(concat(concat(concat(nth(j, names), " in ["), to_s(first(nth(j, box)))), concat(", ", to_s(last(nth(j, box))))), "]")]
    end
  end, range(0, size(box)))
  if is_empty(parts)
    "everywhere"
  else
    join(parts, ", ")
  end
end

# ── tests ──────────────────────────────────────────────────────────────────

def ryouiki_grid(k)
  flat_map(fn(x) map(fn(y) [x, y] end, range(0, k)) end, range(0, k))
end

test "the empty case: no points, no trajectory"
  assert prim([], [], 0.05, 0.05) == []
  assert box_around([]) == []
end

test "an identity: when every point is the outcome, the first box is dense and full"
  pts = ryouiki_grid(5)
  traj = prim(pts, map(fn(p) 1 end, pts), 0.05, 0.05)
  assert nth(3, first(traj)) == 1
  assert nth(2, first(traj)) == 1
  assert nth(4, prim_box(traj, 1)) == box_around(pts)
end

test "a planted box is recovered exactly: x >= 5 and y <= 3 on a 10x10 grid"
  pts = ryouiki_grid(10)
  ys = map(fn(p)
    if (first(p) >= 5) && (last(p) <= 3)
      1
    else
      0
    end
  end, pts)
  b = prim_box(prim(pts, ys, 0.05, 0.02), 1)
  assert nth(4, b) == [[5, 9], [0, 3]]
  assert nth(2, b) == 1
  assert box_text(["x", "y"], nth(4, b), box_around(pts)) == "x in [5, 9], y in [0, 3]"
end

test "a control: a target with no structure finds no dense box with real coverage"
  pts = ryouiki_grid(10)
  ys = map(fn(i)
    if next_float(stream_seed(7, i)) < 0.2
      1
    else
      0
    end
  end, range(0, size(pts)))
  b = prim_box(prim(pts, ys, 0.05, 0.1), 0.9)
  assert (b == nil) || (nth(2, b) < 0.25)
end
