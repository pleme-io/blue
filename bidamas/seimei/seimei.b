use("retsu")
# seimei (生命) — cellular automata: elementary rules, and Life.
#
# The most compute per line of code in the distribution. Rule 110 is
# Turing-complete, so this package is, in a real sense, a universal computer
# expressed in about forty lines of blue.

# One cell's next state under an elementary rule, from its three-cell
# neighbourhood read as a binary index.
def elementary_step_cell(rule, l, c, r)
  idx = (l * 4) + (c * 2) + r
  bit_of(rule, idx)
end

def bit_of(n, i)
  floor(n / expt(2, i)) % 2
end

# One generation of an elementary automaton, with the row treated as a ring so
# the ends have neighbours rather than a special case.
def elementary_step(rule, row)
  n = size(row)
  map(fn(i) elementary_step_cell(rule,
        nth(((i - 1) % n + n) % n, row),
        nth(i, row),
        nth((i + 1) % n, row)) end,
      range(0, n))
end

def elementary_run(rule, row, gens)
  if gens < 1
    [row]
  else
    cons(row, elementary_run(rule, elementary_step(rule, row), gens - 1))
  end
end

# Conway's Life on a bounded grid, cells outside counting as dead.
def cell_at(grid, r, c)
  if r < 0 || c < 0
    0
  else
    if r >= size(grid) || c >= size(first(grid))
      0
    else
      nth(c, nth(r, grid))
    end
  end
end

def neighbours(grid, r, c)
  cell_at(grid, r - 1, c - 1) + cell_at(grid, r - 1, c) + cell_at(grid, r - 1, c + 1) +
  cell_at(grid, r, c - 1) + cell_at(grid, r, c + 1) +
  cell_at(grid, r + 1, c - 1) + cell_at(grid, r + 1, c) + cell_at(grid, r + 1, c + 1)
end

def life_cell(grid, r, c)
  n = neighbours(grid, r, c)
  if cell_at(grid, r, c) == 1
    if n == 2 || n == 3
      1
    else
      0
    end
  else
    if n == 3
      1
    else
      0
    end
  end
end

def life_step(grid)
  map(fn(r) map(fn(c) life_cell(grid, r, c) end, range(0, size(first(grid)))) end,
      range(0, size(grid)))
end

def population(grid)
  reduce(fn(a, row) a + reduce(fn(b, c) b + c end, 0, row) end, 0, grid)
end

test "rule bits are read correctly"
  # Rule 110 in binary is 01101110.
  assert bit_of(110, 0) == 0
  assert bit_of(110, 1) == 1
  assert bit_of(110, 6) == 1
  assert bit_of(110, 7) == 0
end

test "rule 90 builds a Sierpinski row from a single cell"
  row = [0, 0, 0, 1, 0, 0, 0]
  assert elementary_step(90, row) == [0, 0, 1, 0, 1, 0, 0]
end

test "rule 110 is not the identity, and rule 0 erases"
  row = [0, 1, 1, 0, 1, 0, 0]
  assert elementary_step(110, row) != row
  assert elementary_step(0, row) == [0, 0, 0, 0, 0, 0, 0]
end

test "elementary_run records every generation including the first"
  hist = elementary_run(90, [0, 1, 0], 3)
  assert size(hist) == 4
  assert first(hist) == [0, 1, 0]
end

test "a Life block is still life"
  # The 2x2 block is stable: the canonical check that the birth and survival
  # rules are not swapped.
  block = [[0, 0, 0, 0], [0, 1, 1, 0], [0, 1, 1, 0], [0, 0, 0, 0]]
  assert life_step(block) == block
  assert population(block) == 4
end

test "a Life blinker oscillates with period two"
  blinker = [[0, 0, 0, 0, 0], [0, 0, 1, 0, 0], [0, 0, 1, 0, 0], [0, 0, 1, 0, 0], [0, 0, 0, 0, 0]]
  once = life_step(blinker)
  assert once != blinker
  assert life_step(once) == blinker
  assert population(once) == 3
end

test "an empty universe stays empty"
  dead = [[0, 0], [0, 0]]
  assert life_step(dead) == dead
end

# ---------------------------------------------------------------------------
# Grid shape and construction.

# Dimensions, total on the empty grid: `size(first(grid))` is the expression
# every function above inlines, and it reads nil on [] rather than 0.
def grid_rows(grid)
  size(grid)
end

def grid_cols(grid)
  if is_empty(grid)
    0
  else
    size(first(grid))
  end
end

def blank_grid(rows, cols)
  map(fn(r) map(fn(c) 0 end, range(0, cols)) end, range(0, rows))
end

# A grid from a sparse [[row, col], ...] list — how patterns are actually
# published, and far less error-prone to read back than a wall of 0s and 1s.
# Coordinates outside the grid are silently dropped rather than erroring, so a
# pattern can be placed on a canvas too small for it without a special case.
def life_from_coords(rows, cols, coords)
  map(fn(r) map(fn(c) if contains(coords, [r, c])
        1
      else
        0
      end end, range(0, cols)) end,
      range(0, rows))
end

# The live coordinates of a grid — the inverse of life_from_coords, so the two
# together are an identity a test can check.
#
# as_list because a dead grid folds `append([], [])`, which hands back nil: the
# caller would otherwise get the OTHER empty from an all-dead universe.
def live_coords(grid)
  as_list(flatten1(map(fn(r)
      filter(fn(rc) nth(1, rc) >= 0 end,
        map(fn(c) if cell_at(grid, r, c) == 1
            [r, c]
          else
            [0 - 1, 0 - 1]
          end end, range(0, grid_cols(grid)))) end,
    range(0, grid_rows(grid)))))
end

# Shift the contents by (dr, dc), keeping the frame the same size. Whatever
# falls off the edge is gone: this is a view of the same universe, not a torus.
def translate(grid, dr, dc)
  map(fn(r) map(fn(c) cell_at(grid, r - dr, c - dc) end,
        range(0, grid_cols(grid))) end,
      range(0, grid_rows(grid)))
end

# The canonical glider, top-left, in phase 0:
#   .#.
#   ..#
#   ###
def glider(rows, cols)
  life_from_coords(rows, cols, [[0, 1], [1, 2], [2, 0], [2, 1], [2, 2]])
end

# ---------------------------------------------------------------------------
# Running Life forward, and the questions asked of a running pattern.

# Iteration, once, for every rule set in this package. A step function is the
# whole of an automaton — Life, Life-on-a-torus, Seeds and Brian's Brain all
# differ only in that one argument, so running, recording and period-finding
# are written against `f` and never per rule.
def after_with(f, grid, gens)
  if gens < 1
    grid
  else
    after_with(f, f(grid), gens - 1)
  end
end

def run_with(f, grid, gens)
  if gens < 1
    [grid]
  else
    cons(grid, run_with(f, f(grid), gens - 1))
  end
end

# The state after n generations. life_run keeps the history; this keeps only
# the answer, which is what every identity test below actually compares.
def life_after(grid, gens)
  after_with(fn(g) life_step(g) end, grid, gens)
end

def life_run(grid, gens)
  run_with(fn(g) life_step(g) end, grid, gens)
end

def is_stable(grid)
  life_step(grid) == grid
end

# The period of the pattern, or 0 if it has not returned within max_period.
#
# 0 rather than nil so the answer is comparable, and a still life answers 1
# rather than 0: a block IS an oscillator, of period one. A glider on a bounded
# grid answers 0 — it leaves, and never comes back.
def is_oscillator(grid, max_period)
  period_with(fn(g) life_step(g) end, grid, max_period)
end

def period_with(f, grid, max_period)
  period_scan(f, grid, f(grid), 1, max_period)
end

def period_scan(f, start, now, p, max_period)
  if p > max_period
    0
  else
    if now == start
      p
    else
      period_scan(f, start, f(now), p + 1, max_period)
    end
  end
end

test "grid dimensions are total on the empty grid"
  assert grid_rows([[0, 0, 0]]) == 1
  assert grid_cols([[0, 0, 0]]) == 3
  assert grid_rows([]) == 0
  assert grid_cols([]) == 0
end

test "blank_grid has the shape asked for and nothing alive"
  g = blank_grid(2, 3)
  assert grid_rows(g) == 2
  assert grid_cols(g) == 3
  assert population(g) == 0
  assert is_stable(g)
end

test "coordinates round-trip through a grid"
  # The identity that pins both directions at once: a grid built from a
  # coordinate list gives that same list back, in row-major order.
  coords = [[0, 1], [1, 2], [2, 0], [2, 1], [2, 2]]
  assert live_coords(life_from_coords(4, 4, coords)) == coords
  assert live_coords(blank_grid(3, 3)) == []
end

test "coordinates off the canvas are dropped, not fatal"
  g = life_from_coords(2, 2, [[0, 0], [9, 9]])
  assert population(g) == 1
  assert g == [[1, 0], [0, 0]]
end

test "translating by nothing is the identity, and by something is not"
  block = [[0, 0, 0], [0, 1, 1], [0, 1, 1]]
  assert translate(block, 0, 0) == block
  assert translate(block, 1, 1) == [[0, 0, 0], [0, 0, 0], [0, 0, 1]]
  # What leaves the frame does not come back the other side.
  assert population(translate(block, 0, 2)) == 0
end

test "life_after agrees with the end of life_run"
  blinker = [[0, 0, 0], [1, 1, 1], [0, 0, 0]]
  assert life_after(blinker, 0) == blinker
  assert life_after(blinker, 3) == last(life_run(blinker, 3))
  assert size(life_run(blinker, 3)) == 4
end

test "a glider MOVES one cell diagonally every four generations"
  # The single most valuable assertion in this package: a wrong neighbour
  # count, a swapped birth rule or an off-by-one in cell_at all still leave a
  # block stable and a blinker blinking, but none of them make a glider walk.
  g = glider(8, 8)
  assert life_after(g, 4) == translate(g, 1, 1)
  assert life_after(g, 8) == translate(g, 2, 2)
  # It really did move — the intermediate phases are none of the three.
  assert life_after(g, 4) != g
  assert population(life_after(g, 4)) == 5
end

test "stability and period tell still lifes, oscillators and gliders apart"
  block = [[0, 0, 0, 0], [0, 1, 1, 0], [0, 1, 1, 0], [0, 0, 0, 0]]
  blinker = [[0, 0, 0], [1, 1, 1], [0, 0, 0]]
  assert is_stable(block)
  assert !is_stable(blinker)
  # A still life is an oscillator of period one, not of period zero.
  assert is_oscillator(block, 4) == 1
  assert is_oscillator(blinker, 4) == 2
  # A glider never returns to where it started, so it has no period at all.
  assert is_oscillator(glider(8, 8), 8) == 0
  assert is_oscillator(blank_grid(3, 3), 4) == 1
end

# ---------------------------------------------------------------------------
# Life on a torus.
#
# Not a second copy of Conway's rule — a second SHAPE of universe. Wrapping a
# one-cell border on and cropping it off again means the birth and survival
# counts stay in life_cell, where a change to the rule reaches both variants.
# The elementary rules above already ring; this is the same closing, in 2D.

# The grid with a one-cell border copied from the opposite edge.
def wrap_row(row)
  append(cons(last(row), row), [first(row)])
end

def pad_toroidal(grid)
  wide = map(fn(row) wrap_row(row) end, grid)
  append(cons(last(wide), wide), [first(wide)])
end

def crop_border(grid)
  map(fn(row) slice(row, 1, size(row) - 2) end,
      slice(grid, 1, size(grid) - 2))
end

# The interior of the padded grid sees exactly the toroidal neighbourhood, so
# the bounded step computes the toroidal one and the crop throws the scaffolding
# away. On a one-row or one-column grid the wrap makes a cell its own neighbour,
# which is what a torus of that size genuinely is.
def life_step_toroidal(grid)
  crop_border(life_step(pad_toroidal(grid)))
end

def life_after_toroidal(grid, gens)
  after_with(fn(g) life_step_toroidal(g) end, grid, gens)
end

def neighbours_toroidal(grid, r, c)
  neighbours(pad_toroidal(grid), r + 1, c + 1)
end

test "padding then cropping is the identity"
  # If this fails, every toroidal answer is off by a row and nobody notices,
  # because a symmetric pattern still looks right.
  g = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
  assert crop_border(pad_toroidal(g)) == g
  assert grid_rows(pad_toroidal(g)) == 5
  assert grid_cols(pad_toroidal(g)) == 5
  # The corner of the border is the diagonally opposite cell of the original.
  assert first(first(pad_toroidal(g))) == 1
end

test "neighbour counts, bounded and wrapped"
  full = [[1, 1, 1], [1, 1, 1], [1, 1, 1]]
  assert neighbours(full, 1, 1) == 8
  # A corner has only three neighbours inside the frame — the whole reason a
  # bounded Life differs from an unbounded one.
  assert neighbours(full, 0, 0) == 3
  assert neighbours(full, 0, 1) == 5
  # On a 3x3 torus every cell is adjacent to all eight others.
  assert neighbours_toroidal(full, 0, 0) == 8
  assert neighbours_toroidal(full, 1, 1) == 8
end

test "a blinker straddling the edge only survives on a torus"
  # Vertical blinker at column 2, rows 4-0-1, i.e. wrapped over the top edge.
  b = life_from_coords(5, 5, [[0, 2], [1, 2], [4, 2]])
  # On the torus it turns, like any blinker.
  assert life_step_toroidal(b) == life_from_coords(5, 5, [[0, 1], [0, 2], [0, 3]])
  assert is_oscillator_toroidal(b, 4) == 2
  # Bounded, the same three cells are three isolated cells, and all three die.
  assert population(life_step(b)) == 0
end

test "a glider crosses the torus and comes home"
  # 4n generations on an n x n torus: the glider walks the diagonal and lands
  # back on its own starting cells. Proof that the wrap is joined on BOTH axes
  # — a grid that wrapped rows only would drift sideways for ever. 6x6 is the
  # smallest frame measured to hold it comfortably (5x5 also returns, but the
  # glider passes within one cell of its own wrapped image getting there).
  g = glider(6, 6)
  assert life_after_toroidal(g, 24) == g
  assert life_after_toroidal(g, 4) == translate(g, 1, 1)
end

def is_oscillator_toroidal(grid, max_period)
  period_with(fn(g) life_step_toroidal(g) end, grid, max_period)
end

# ---------------------------------------------------------------------------
# Elementary automata from a seed, and the rules worth knowing by name.

# A row of `width` cells with the middle one alive. Every published elementary
# picture starts here, so the seed is a function rather than a literal a reader
# has to count the zeros in.
def seed_row(width)
  map(fn(i) if i == floor(width / 2)
      1
    else
      0
    end end, range(0, width))
end

def elementary_from_seed(rule, width, gens)
  elementary_run(rule, seed_row(width), gens)
end

# The elementary rules with an established character. The catalog is data, not
# a chain of ifs, so a caller can also enumerate it.
def rule_catalog()
  [[0, "extinction"], [30, "chaos"], [90, "sierpinski"], [110, "universal"],
   [150, "parity"], [184, "traffic"], [204, "identity"], [255, "saturation"]]
end

def rule_name(rule)
  hit = find_first(fn(p) first(p) == rule end, rule_catalog())
  if hit == nil
    "unnamed"
  else
    last(hit)
  end
end

test "the seed is one live cell in the middle"
  assert seed_row(7) == [0, 0, 0, 1, 0, 0, 0]
  # Even widths have no middle; the right of the two centre cells is the choice.
  assert seed_row(4) == [0, 0, 1, 0]
  assert population([seed_row(9)]) == 1
end

test "rule 30 from a seed opens the way everybody has seen it"
  # Rule 30 is l XOR (c OR r): the three cells below a single one are all live.
  hist = elementary_from_seed(30, 7, 1)
  assert first(hist) == [0, 0, 0, 1, 0, 0, 0]
  assert last(hist) == [0, 0, 1, 1, 1, 0, 0]
end

test "rule 90 from a seed counts Sierpinski's bits"
  # Generation n of rule 90 from a single cell holds 2^(bits set in n) live
  # cells. It is the strongest cheap check there is: an off-by-one in the
  # neighbourhood gives a plausible-looking triangle with the wrong counts.
  gens = elementary_from_seed(90, 17, 4)
  assert map(fn(row) population([row]) end, gens) == [1, 2, 2, 4, 2]
end

test "a rule's name is checked against what the rule actually does"
  # A name table nobody verifies is decoration. Each name below is asserted
  # together with the behaviour it claims.
  row = [0, 1, 1, 0, 1, 0, 0]
  assert rule_name(204) == "identity"
  assert elementary_step(204, row) == row
  assert rule_name(255) == "saturation"
  assert elementary_step(255, row) == [1, 1, 1, 1, 1, 1, 1]
  assert rule_name(0) == "extinction"
  assert elementary_step(0, row) == [0, 0, 0, 0, 0, 0, 0]
  assert rule_name(90) == "sierpinski"
  assert rule_name(110) == "universal"
  # An unlisted rule is still a perfectly good rule.
  assert rule_name(137) == "unnamed"
  assert size(rule_catalog()) == 8
end

# ---------------------------------------------------------------------------
# Measuring a universe.

# Live fraction of the frame. Beware the runtime's division: an evenly divided
# grid answers with an Int (a full grid is 1, not 1.0) and any other with a
# Float, so a caller comparing to 1.0 is comparing to the wrong empty's cousin.
def density(grid)
  cells = grid_rows(grid) * grid_cols(grid)
  if cells == 0
    0
  else
    population(grid) / cells
  end
end

# Where two generations disagree, as a grid — so population, live_coords and
# render all work on it unchanged, instead of needing a diff-shaped sibling of
# each. Cells outside `a` read as dead, so grids of different sizes still diff.
def diff_grid(a, b)
  map(fn(r) map(fn(c) if cell_at(a, r, c) == cell_at(b, r, c)
        0
      else
        1
      end end, range(0, grid_cols(a))) end,
      range(0, grid_rows(a)))
end

def generation_diff(a, b)
  population(diff_grid(a, b))
end

def changed_coords(a, b)
  live_coords(diff_grid(a, b))
end

test "density of the empty, the half and the full"
  assert density(blank_grid(3, 3)) == 0
  assert density([[1, 1], [1, 1]]) == 1
  assert density([[1, 0], [1, 0]]) == 0.5
  # No grid, no cells, no division by zero.
  assert density([]) == 0
end

test "a diff counts changes, not survivors"
  block = [[0, 0, 0, 0], [0, 1, 1, 0], [0, 1, 1, 0], [0, 0, 0, 0]]
  blinker = [[0, 0, 0, 0, 0], [0, 0, 1, 0, 0], [0, 0, 1, 0, 0], [0, 0, 1, 0, 0], [0, 0, 0, 0, 0]]
  # Four cells move: two die at the ends, two are born at the sides. The three
  # that survive — and the centre that never changes — must not be counted.
  assert generation_diff(blinker, life_step(blinker)) == 4
  assert changed_coords(blinker, life_step(blinker)) == [[1, 2], [2, 1], [2, 3], [3, 2]]
  assert generation_diff(block, life_step(block)) == 0
  # Stability is exactly a zero diff, which is what makes both worth having.
  assert is_stable(block) == (generation_diff(block, life_step(block)) == 0)
end

# ---------------------------------------------------------------------------
# Reading a universe with human eyes.

def render_cell(v)
  if v == 1
    "#"
  else
    if v == 2
      "+"
    else
      "."
    end
  end
end

def render_row(row)
  join(map(fn(v) render_cell(v) end, row), "")
end

def render_grid(grid)
  map(fn(row) render_row(row) end, grid)
end

test "an elementary history renders as the triangle it is"
  # An elementary run is a list of rows, which is exactly the shape of a Life
  # grid — so the same renderer draws both, and the Sierpinski triangle can be
  # read off the page rather than trusted.
  assert render_grid(elementary_from_seed(90, 7, 2)) == ["...#...", "..#.#..", ".#...#."]
end

test "a rendered glider is recognisable on the page"
  # Also pins the phase and orientation of glider(), which every movement test
  # above depends on and which a coordinate list hides.
  assert render_grid(glider(3, 3)) == [".#.", "..#", "###"]
  assert render_row([1, 0, 2]) == "#.+"
  assert render_grid(blank_grid(1, 4)) == ["...."]
end

# ---------------------------------------------------------------------------
# Two more rule sets on the same grid.
#
# Life is one point in a space of rules; a package that only ever runs B3/S23
# cannot tell which of its parts are Life and which are cellular automata. The
# neighbourhood, the frame, the runner and the measures below are shared with
# Life verbatim — only the cell function differs.

# The eight offsets, as data. Life's `neighbours` writes them out longhand and
# sums; a rule with more than two states has to ask WHICH neighbours, so the
# count is folded over the offsets instead.
def neighbour_offsets()
  [[0 - 1, 0 - 1], [0 - 1, 0], [0 - 1, 1],
   [0, 0 - 1], [0, 1],
   [1, 0 - 1], [1, 0], [1, 1]]
end

# Neighbours in state v. Outside the frame reads as 0, so asking for v == 0
# counts the void as dead cells — right for a bounded universe, and the reason
# this is not the way to ask "how many are not alive".
def neighbours_equal(grid, r, c, v)
  reduce(fn(a, d) if cell_at(grid, r + nth(0, d), c + nth(1, d)) == v
      a + 1
    else
      a
    end end, 0, neighbour_offsets())
end

# Seeds — B2/S: born on exactly two neighbours, and NOTHING ever survives.
def seeds_cell(grid, r, c)
  if cell_at(grid, r, c) == 1
    0
  else
    if neighbours(grid, r, c) == 2
      1
    else
      0
    end
  end
end

def seeds_step(grid)
  map(fn(r) map(fn(c) seeds_cell(grid, r, c) end, range(0, grid_cols(grid))) end,
      range(0, grid_rows(grid)))
end

# Brian's Brain — three states: 0 off, 1 firing, 2 refractory. A firing cell
# ALWAYS goes refractory and a refractory cell always goes off, whatever the
# neighbours are doing; only an off cell looks around, and only for firing
# neighbours. That is why the count here is neighbours_equal(.., 1) and not
# `neighbours`, which would add the refractory 2s in as two live cells each.
def brain_cell(grid, r, c)
  if cell_at(grid, r, c) == 1
    2
  else
    if cell_at(grid, r, c) == 2
      0
    else
      if neighbours_equal(grid, r, c, 1) == 2
        1
      else
        0
      end
    end
  end
end

def brain_step(grid)
  map(fn(r) map(fn(c) brain_cell(grid, r, c) end, range(0, grid_cols(grid))) end,
      range(0, grid_rows(grid)))
end

test "neighbours and neighbours_equal agree on a live/dead grid"
  # Two different mechanisms — eight written-out terms versus a fold over the
  # offset list — must give the same answer, including at a corner.
  g = [[1, 1, 0], [1, 0, 1], [0, 1, 1]]
  assert neighbours_equal(g, 1, 1, 1) == neighbours(g, 1, 1)
  assert neighbours_equal(g, 0, 0, 1) == neighbours(g, 0, 0)
  assert neighbours_equal(g, 1, 1, 1) == 6
  # Off the grid counts as dead: a corner has five neighbours outside the frame,
  # and one dead one inside it, so six of its eight read as 0.
  assert neighbours_equal(g, 0, 0, 0) == 6
end

test "Seeds never lets anything survive"
  # A domino sows four cells around itself and then vanishes. If survival crept
  # in, the two originals would still be there and the population would be 6.
  d = life_from_coords(5, 5, [[2, 1], [2, 2]])
  n = seeds_step(d)
  assert live_coords(n) == [[1, 1], [1, 2], [3, 1], [3, 2]]
  assert population(n) == 4
  assert cell_at(n, 2, 1) == 0
  # A lone cell has no two-neighbour dead cell anywhere, so Seeds starves.
  assert population(seeds_step(life_from_coords(5, 5, [[2, 2]]))) == 0
end

test "Brian's Brain fires, then cools, whatever the neighbours say"
  # Under Life this grid keeps its corners alive for ever. Under the Brain
  # every firing cell is refractory next tick and off the tick after: the case
  # that catches a Brain implemented by pasting Life's survival rule in.
  full = [[1, 1, 1], [1, 1, 1], [1, 1, 1]]
  assert brain_step(full) == [[2, 2, 2], [2, 2, 2], [2, 2, 2]]
  assert after_with(fn(g) brain_step(g) end, full, 2) == blank_grid(3, 3)
  # Refractory cells must not be counted as firing when a birth is decided.
  d = life_from_coords(5, 5, [[2, 1], [2, 2]])
  n = brain_step(d)
  assert live_coords(n) == [[1, 1], [1, 2], [3, 1], [3, 2]]
  assert cell_at(n, 2, 1) == 2
  assert render_grid(n) == [".....", ".##..", ".++..", ".##..", "....."]
end

test "the generic runner drives any of the rule sets"
  # One iterator, four automata: if this drifts apart, life_after and its
  # siblings have quietly become four copies of the same loop again.
  blinker = [[0, 0, 0], [1, 1, 1], [0, 0, 0]]
  assert after_with(fn(g) life_step(g) end, blinker, 2) == blinker
  assert size(run_with(fn(g) seeds_step(g) end, blinker, 3)) == 4
  assert period_with(fn(g) life_step(g) end, blinker, 4) == 2
  # A rule with no fixed point inside the bound answers 0 rather than looping.
  assert period_with(fn(g) brain_step(g) end, blinker, 3) == 0
end
