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
