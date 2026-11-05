@moduledoc """
ryouiki (領域) — region: which region of the inputs produces an outcome.

Scenario discovery by PRIM, the Patient Rule Induction Method (Friedman &
Fisher 1999; as used for robust decision making by Bryant & Lempert 2010):
given many runs, each a point of input values with a target (1 where the
outcome of interest happened, else 0 — or any number to maximise), find a
box — a range per input — inside which the target is dense, while it still
holds much of the target.

The algorithm peels. Start with the box around every point. At each step,
try removing a thin slice (the `alpha` share, or the lowest or highest
level when inputs sit on a grid) from the low or high end of each input,
and keep the one peel that leaves the highest mean target inside. Stop when
fewer than `min_support` of the points remain. Every step is kept: the
trajectory trades COVERAGE (the share of all target inside the box) against
DENSITY (the mean target inside), and the caller picks the box — usually
the one with the most coverage at a density it can defend.

A box is a list of [lo, hi] per input, inclusive. A trajectory row is
[step, support, coverage, density, box]. Everything is deterministic: no
randomness is used, so the same runs give the same boxes.

    box_around([]) #=> []
"""

use("junjo", %i[sort sort_by])
use("kazu", %i[max sum])
use("ran", %i[next_float stream_seed])
use("retsu", %i[concat_lists first flat_map is_empty last size])
use("toukei", %i[largest mean percentile smallest])

@doc """
box_around: The box around every point: [min, max] of each input.

    box_around([]) #=> []
"""
def box_around(points)
  if is_empty(points)
    []
  else
    map(
      fn(j)
        xs = map((p) -> p[j], points)
        [smallest(xs), largest(xs)]
      end,
      range(0, size(first(points)))
    )
  end
end

def in_box?(box, p)
  size(
    filter(
      (j) -> p[j] < first(box[j]) or p[j] > last(box[j]),
      range(0, size(box))
    )
  ) == 0
end

def inside_of(box, points)
  filter((i) -> in_box?(box, points[i]), range(0, size(points)))
end

def mean_target(ids, ys)
  if is_empty(ids)
    0
  else
    mean(map((i) -> ys[i], ids))
  end
end

@doc """
peeled_edge: The narrower edge for one input and side: the alpha-quantile of the values
inside, or — where that removes nothing (tied grid levels) — the next
distinct level. Returns nil when the input has only one level left.
"""
def peeled_edge(values, side, alpha)
  levels = sort(distinct(values))
  if size(levels) < 2
    nil
  elsif side == :lo
    q = percentile(values, alpha)
    if q > first(levels)
      smallest(filter((v) -> v >= q, levels))
    else
      levels[1]
    end
  else
    q = percentile(values, 1 - alpha)
    if q < last(levels)
      largest(filter((v) -> v <= q, levels))
    else
      levels[size(levels) - 2]
    end
  end
end

@doc """
peel_candidates: Every candidate peel from `box`: [box', inside', density'].
"""
def peel_candidates(box, ids, points, ys, alpha)
  flat_map(
    range(0, size(box)),
    fn(j)
      values = map((i) -> points[i][j], ids)
      flat_map(
        %i[lo hi],
        fn(side)
          edge = peeled_edge(values, side, alpha)
          if edge.nil?
            []
          else
            narrowed = map(
              fn(k)
                if k != j
                  box[k]
                elsif side == :lo
                  [edge, last(box[k])]
                else
                  [first(box[k]), edge]
                end
              end,
              range(0, size(box))
            )
            kept = filter((i) -> in_box?(narrowed, points[i]), ids)
            if is_empty(kept) or size(kept) == size(ids)
              []
            else
              [[narrowed, kept, mean_target(kept, ys)]]
            end
          end
        end
      )
    end
  )
end

@doc """
prim: The peeling trajectory. alpha: the share peeled per step (0.05 is PRIM's
usual); min_support: stop when fewer than this share of points remain.

    prim([], [], 0.05, 0.05) #=> []
"""
def prim(points, ys, alpha, min_support)
  n = size(points)
  if n == 0
    []
  else
    total = sum(ys)
    row = fn(step, box, ids)
      [
        step,
        size(ids) / n,
        if_zero_total(
          total,
          sum(map((i) -> ys[i], ids)) / max(total, 0.000000001)
        ),
        mean_target(ids, ys),
        box
      ]
    end
    start = box_around(points)
    start_ids = range(0, n)
    walk = fn(self, step, box, ids, acc)
      cands = peel_candidates(box, ids, points, ys, alpha)
      if is_empty(cands) or size(ids) / n <= min_support
        acc
      else
        best = first(sort_by((c) -> -c[2] + size(c[1]) * 0.000000001, cands))
        if size(best[1]) / n < min_support
          acc
        else
          self(
            self,
            step + 1,
            first(best),
            best[1],
            concat_lists(acc, [row(step + 1, first(best), best[1])])
          )
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

@doc """
prim_box: The box to report: the most coverage among steps at or above `density`,
or nil when no step reaches it.
"""
def prim_box(trajectory, density)
  ok = filter((r) -> r[3] >= density, trajectory)
  if is_empty(ok)
    nil
  else
    first(sort_by((r) -> -r[2] + r[0] * 0.000000001, ok))
  end
end

@doc """
box_text: A box as text over named inputs: "x in [5, 9], y in [0, 3]" — only the
inputs the box actually restricts relative to `full`.
"""
def box_text(names, box, full)
  parts = flat_map(
    range(0, size(box)),
    fn(j)
      if box[j] == full[j]
        []
      else
        [
          concat(
            concat(
              concat(concat(names[j], " in ["), to_s(first(box[j]))),
              concat(", ", to_s(last(box[j])))
            ),
            "]"
          )
        ]
      end
    end
  )
  if is_empty(parts)
    "everywhere"
  else
    join(parts, ", ")
  end
end

# ── tests ──────────────────────────────────────────────────────────────────

def grid(k)
  flat_map(range(0, k), (x) -> map((y) -> [x, y], range(0, k)))
end

test "the empty case: no points, no trajectory"
  assert prim([], [], 0.05, 0.05) == []
  assert box_around([]) == []
end

test "an identity: when every point is the outcome, the first box is dense and full"
  pts = grid(5)
  traj = prim(pts, map((_p) -> 1, pts), 0.05, 0.05)
  assert first(traj)[3] == 1
  assert first(traj)[2] == 1
  assert prim_box(traj, 1)[4] == box_around(pts)
end

test "a planted box is recovered exactly: x >= 5 and y <= 3 on a 10x10 grid"
  pts = grid(10)
  ys = map(
    fn(p)
      if first(p) >= 5 and last(p) <= 3
        1
      else
        0
      end
    end,
    pts
  )
  b = prim_box(prim(pts, ys, 0.05, 0.02), 1)
  assert b[4] == [[5, 9], [0, 3]]
  assert b[2] == 1
  assert box_text(%w[x y], b[4], box_around(pts)) == "x in [5, 9], y in [0, 3]"
end

test "a control: a target with no structure finds no dense box with real coverage"
  pts = grid(10)
  ys = map(
    fn(i)
      if next_float(stream_seed(7, i)) < 0.2
        1
      else
        0
      end
    end,
    range(0, size(pts))
  )
  b = prim_box(prim(pts, ys, 0.05, 0.1), 0.9)
  assert b.nil? or b[2] < 0.25
end
