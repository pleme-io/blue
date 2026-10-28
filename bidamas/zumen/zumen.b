@moduledoc """
zumen (図面) — technical drawings: 2-D entities on layers, sheets with a title block, feature-edge views of solids, written as DXF R12 and SVG.

A drawing is data first: a list of entities, each on a layer, in the
units of the part (millimetres in the design pipeline). The writers are
rendered bridges (the kueri rule): DXF R12 for the cutting shop (the
oldest version, the one every CAM program and laser controller reads), and
SVG for people, turned into PDF or PNG by rsvg-convert at a process
boundary. Every number is written by zu_num, to six decimals at most, so
the same drawing always produces the same bytes and the same hash.

Written for nupastel docs/plans/design-pipeline.md, step 6.

    num(2) #=> "2"
"""

use("gyouretsu", [:dot, :magnitude, :scale, :vadd, :vector_near, :vsub])
use("kazu", [:abs, :max, :min, :mod_positive, :near, :sum])

use(
  "kikagaku",
  [
    :bounding_box,
    :circle_polygon,
    :midpoint,
    :px,
    :py,
    :radians,
    :rect_polygon,
    :region_holes,
    :region_outline
  ]
)

use("maakuappu")

use("moji", [:includes, :pad_left, :take_chars])

use(
  "retsu",
  [
    :concat_lists,
    :contains,
    :first,
    :flat_map,
    :indexes,
    :is_empty,
    :last,
    :size,
    :take_n
  ]
)

use("rittai")

use("ronri", [:every])
use("shuugou", [:as_set])

legacy_names("0.1.1", "zu")

legacy_names("0.1.2", [["opt_lines", "shuugou::as_set"]])

# ── numbers ──────────────────────────────────────────────────────────

@doc """
num: A number to at most six decimals, trailing zeros dropped, never an
exponent, and never "-0".

    num(2) #=> "2"
"""
def num(x)
  n = round(x * 1_000_000)
  a = abs(n)
  whole = floor(a / 1_000_000)
  frac = a - whole * 1_000_000
  sign = if n < 0
    "-"
  else
    ""
  end
  if frac == 0
    "#{sign}#{to_s(whole)}"
  else
    "#{sign}#{to_s(whole)}.#{trim_zeros(pad_left(to_s(frac), 6, "0"))}"
  end
end

def trim_zeros(s)
  if ends_with?(s, "0")
    trim_zeros(take_chars(s, length(s) - 1))
  else
    s
  end
end

# ── entities ─────────────────────────────────────────────────────────
# Each entity is a map with :kind and :layer.

def line(a, b, layer)
  {kind: :line, a:, b:, layer:}
end

def circle(c, r, layer)
  {kind: :circle, c:, r:, layer:}
end

@doc """
arc: An arc counter-clockwise from a0 to a1, in degrees (DXF's convention).
"""
def arc(c, r, a0, a1, layer)
  {kind: :arc, c:, r:, a0:, a1:, layer:}
end

def polyline(pts, closed, layer)
  {kind: :polyline, pts:, closed:, layer:}
end

def text(p, height, s, layer)
  {kind: :text, p:, h: height, s:, layer:}
end

def kind(e)
  e[:kind]
end

def layer(e)
  e[:layer]
end

@doc """
layers: The layers a drawing uses, each [name, DXF colour number, linetype].
Bend lines are dashed, as a shop expects.
"""
def layers()
  [
    ["OUTLINE", 7, "CONTINUOUS"],
    ["HOLES", 1, "CONTINUOUS"],
    ["BEND", 3, "DASHED"],
    ["DIM", 4, "CONTINUOUS"],
    ["TEXT", 7, "CONTINUOUS"],
    ["FRAME", 8, "CONTINUOUS"],
    ["VIEW", 7, "CONTINUOUS"]
  ]
end

def layer_names()
  map((l) -> first(l), layers)
end

@doc """
region: A kikagaku region as entities: the outline, and each hole.
"""
def region(r)
  concat_lists(
    [polyline(region_outline(r), true, "OUTLINE")],
    map((h) -> polyline(h, true, "HOLES"), region_holes(r))
  )
end

@doc """
dim: A linear dimension between a and b, drawn offset to the left of a -> b:
two extension lines, the dimension line with tick marks, and the length
as text to one decimal.
"""
def dim(a, b, offset, text_h)
  d = vsub(b, a)
  len = magnitude(d)
  u = scale(1.0 / len, d)
  nrm = [-py(u), px(u)]
  pa = vadd(a, scale(offset, nrm))
  pb = vadd(b, scale(offset, nrm))
  tick = scale(text_h * 0.4, vadd(u, nrm))
  mid = vadd(midpoint(pa, pb), scale(text_h * 0.4, nrm))
  [
    line(a, vadd(pa, scale(text_h * 0.3, nrm)), "DIM"),
    line(b, vadd(pb, scale(text_h * 0.3, nrm)), "DIM"),
    line(pa, pb, "DIM"),
    line(vsub(pa, tick), vadd(pa, tick), "DIM"),
    line(vsub(pb, tick), vadd(pb, tick), "DIM"),
    text(mid, text_h, num(round(len * 10) / 10), "DIM")
  ]
end

@doc """
table: A table as text entities, one row per line from origin downward: the
header, then each row's cells in the given columns, each column width
wide. Rows are maps (a cut list, a bill of materials).
"""
def table(rows, columns, widths, origin, h)
  lines = concat_lists(
    [map((c) -> upcase(to_s(c)), columns)],
    map((r) -> map((c) -> cell(get(r, c)), columns), rows)
  )
  flat_map(
    indexes(lines),
    fn(i)
      table_row(lines[i], widths, [px(origin), py(origin) - i * h * 1.8], h)
    end
  )
end

def table_row(cells, widths, p, h)
  map(
    (j) -> text([px(p) + sum(take_n(widths, j)), py(p)], h, cells[j], "TEXT"),
    indexes(cells)
  )
end

@doc """
cell: A cell's text: numbers to one decimal (a cut list is read at a saw), nil
as empty, anything else as itself.
"""
def cell(v)
  if v.nil?
    ""
  elsif number?(v)
    num(round(v * 10) / 10)
  else
    to_s(v)
  end
end

# ── bounds ───────────────────────────────────────────────────────────

def entity_points(e)
  k = kind(e)
  if k == :line
    [e[:a], e[:b]]
  elsif k == :polyline
    e[:pts]
  elsif k == :circle or k == :arc
    c = e[:c]
    r = e[:r]
    [[px(c) - r, py(c) - r], [px(c) + r, py(c) + r]]
  else
    [e[:p], vadd(e[:p], [e[:h] * 0.6 * length(e[:s]), e[:h]])]
  end
end

@doc """
bounds: [[min x, min y], [max x, max y]] over every entity; nil for none.
"""
def bounds(entities)
  bounding_box(flat_map(entities, entity_points))
end

# ── sheets ───────────────────────────────────────────────────────────
# A sheet is the part's drawing: its entities and its title fields. The
# title block goes below the drawing, the width of the drawing's extent.

def sheet(entities, title)
  {entities:, title:}
end

def title_rows(title)
  keys = [:part, :revision, :material, :thickness, :units, :source]
  concat_lists(
    map(
      (k) -> "#{upcase(to_s(k))}: #{to_s(get(title, k))}",
      filter((k) -> get(title, k) != nil, keys)
    ),
    as_set(title[:notes])
  )
end

@doc """
sheet_entities: Every entity of the sheet, the frame and title block included.
"""
def sheet_entities(sheet)
  ents = sheet[:entities]
  bb = bounds(ents)
  lo = bb[0]
  hi = bb[1]
  w = max(px(hi) - px(lo), 100)
  h = 3.5
  rows = title_rows(sheet[:title])
  top = py(lo) - 15
  texts = map(
    (i) -> text([px(lo), top - i * h * 1.6], h, rows[i], "TEXT"),
    indexes(rows)
  )
  bottom = top - size(rows) * h * 1.6 - 3
  frame = polyline(
    [
      [px(lo) - 5, bottom],
      [px(lo) + w + 5, bottom],
      [px(lo) + w + 5, top + h + 3],
      [px(lo) - 5, top + h + 3]
    ],
    true,
    "FRAME"
  )
  concat_lists(ents, concat_lists([frame], texts))
end

# ── feature-edge views of a solid ────────────────────────────────────
# An orthographic view draws each edge where the two faces meeting at it
# turn by more than half a degree, and each boundary edge, projected onto
# the view's plane. Coplanar triangulation diagonals disappear; a
# tessellated curve shows its facets. Hidden edges are drawn too (there is
# no hidden-line removal yet).

@doc """
project: feature-edge view of a solid.

    project([1, 2], :top) #=> [1, 2]
"""
def project(p, view)
  if view == :top
    [rittai::x(p), rittai::y(p)]
  elsif view == :front
    [rittai::x(p), rittai::z(p)]
  else
    [rittai::y(p), rittai::z(p)]
  end
end

def view(mesh, view)
  m = rittai::weld(mesh)
  vs = rittai::vertices(m)
  faces = rittai::faces(m)
  normals = map((f) -> rittai::face_normal(m, f), faces)
  table = reduce((acc, i) -> edge_faces(acc, faces[i], i), {}, indexes(faces))
  keys = distinct_keys(faces)
  drawn = filter((k) -> feature?(get(table, k), normals), keys)
  map((k) -> edge_line(k, vs, view), drawn)
end

def edge_key(a, b)
  "#{to_s(min(a, b))}-#{to_s(max(a, b))}"
end

def edges_of(f)
  [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]
end

def edge_faces(acc, f, i)
  reduce((t, e) -> add_face(t, edge_key(e[0], e[1]), i), acc, edges_of(f))
end

def add_face(t, k, i)
  prev = get(t, k)
  if prev.nil?
    assoc(t, k, [i])
  else
    assoc(t, k, concat_lists(prev, [i]))
  end
end

def distinct_keys(faces)
  get(
    reduce(
      fn(acc, f)
        reduce((a2, e) -> note_key(a2, edge_key(e[0], e[1])), acc, edges_of(f))
      end,
      {seen: {}, keys: []},
      faces
    ),
    :keys
  )
end

def note_key(acc, k)
  if get(acc[:seen], k).nil?
    {seen: assoc(acc[:seen], k, true), keys: concat_lists([k], acc[:keys])}
  else
    acc
  end
end

def feature?(fs, normals)
  if size(fs) != 2
    true
  else
    dot(normals[fs[0]], normals[fs[1]]) < 0.99996
  end
end

def edge_line(k, vs, view)
  ij = map((s) -> to_int(s), split(k, "-"))
  line(project(vs[ij[0]], view), project(vs[ij[1]], view), "VIEW")
end

# ── DXF R12 ──────────────────────────────────────────────────────────
# Group code, then value, one per line. HEADER names the version (AC1009 is
# R12) and the extents; TABLES declares the line types and layers every
# entity names; ENTITIES holds the drawing. A polyline is POLYLINE, its
# VERTEXes and SEQEND, R12's only polyline.

def dxf_pairs(pairs)
  join(map((p) -> unlines([to_s(p[0]), to_s(p[1])]), pairs), "")
end

def dxf(entities)
  bb = if is_empty(entities)
    [[0, 0], [0, 0]]
  else
    bounds(entities)
  end
  header = [
    [0, "SECTION"],
    [2, "HEADER"],
    [9, "$ACADVER"],
    [1, "AC1009"],
    [9, "$EXTMIN"],
    [10, num(px(bb[0]))],
    [20, num(py(bb[0]))],
    [9, "$EXTMAX"],
    [10, num(px(bb[1]))],
    [20, num(py(bb[1]))],
    [0, "ENDSEC"]
  ]
  ltypes = [
    [0, "TABLE"],
    [2, "LTYPE"],
    [70, 2],
    [0, "LTYPE"],
    [2, "CONTINUOUS"],
    [70, 0],
    [3, "Solid line"],
    [72, 65],
    [73, 0],
    [40, "0.0"],
    [0, "LTYPE"],
    [2, "DASHED"],
    [70, 0],
    [3, "Dashed __ __ __"],
    [72, 65],
    [73, 2],
    [40, "6.0"],
    [49, "4.0"],
    [49, "-2.0"],
    [0, "ENDTAB"]
  ]
  layers = concat_lists(
    [[0, "TABLE"], [2, "LAYER"], [70, size(zumen::layers)]],
    concat_lists(
      flat_map(
        zumen::layers,
        (l) -> [[0, "LAYER"], [2, l[0]], [70, 0], [62, l[1]], [6, l[2]]]
      ),
      [[0, "ENDTAB"]]
    )
  )
  tables = concat_lists(
    [[0, "SECTION"], [2, "TABLES"]],
    concat_lists(ltypes, concat_lists(layers, [[0, "ENDSEC"]]))
  )
  body = concat_lists(
    [[0, "SECTION"], [2, "ENTITIES"]],
    concat_lists(flat_map(entities, dxf_entity), [[0, "ENDSEC"], [0, "EOF"]])
  )
  dxf_pairs(concat_lists(header, concat_lists(tables, body)))
end

def xy(code, p)
  [[code, num(px(p))], [code + 10, num(py(p))], [code + 20, "0"]]
end

def dxf_entity(e)
  k = kind(e)
  l = [8, layer(e)]
  if k == :line
    concat_lists([[0, "LINE"], l], concat_lists(xy(10, e[:a]), xy(11, e[:b])))
  elsif k == :circle
    concat_lists(
      [[0, "CIRCLE"], l],
      concat_lists(xy(10, e[:c]), [[40, num(e[:r])]])
    )
  elsif k == :arc
    concat_lists(
      [[0, "ARC"], l],
      concat_lists(
        xy(10, e[:c]),
        [[40, num(e[:r])], [50, num(e[:a0])], [51, num(e[:a1])]]
      )
    )
  elsif k == :polyline
    flag = if e[:closed]
      1
    else
      0
    end
    concat_lists(
      [
        [0, "POLYLINE"],
        l,
        [66, 1],
        [70, flag],
        [10, "0"],
        [20, "0"],
        [30, "0"]
      ],
      concat_lists(
        flat_map(e[:pts], (p) -> concat_lists([[0, "VERTEX"], l], xy(10, p))),
        [[0, "SEQEND"], l]
      )
    )
  else
    concat_lists(
      [[0, "TEXT"], l],
      concat_lists(xy(10, e[:p]), [[40, num(e[:h])], [1, e[:s]]])
    )
  end
end

# ── SVG ──────────────────────────────────────────────────────────────
# Drawing units map one to one onto the SVG's user units, with y flipped
# (SVG's y runs down) and a margin. Width and height are stated in mm, so a
# printer or rsvg-convert keeps the scale 1:1.

def svg_escape(s)
  maakuappu::escape(s)
end

def svg_style(layer)
  if layer == "BEND"
    "stroke=\"#1a7f37\" stroke-width=\"0.35\" stroke-dasharray=\"4 2\" fill=\"none\""
  elsif layer == "HOLES"
    "stroke=\"#cf222e\" stroke-width=\"0.5\" fill=\"none\""
  elsif layer == "DIM" or layer == "FRAME"
    "stroke=\"#57606a\" stroke-width=\"0.25\" fill=\"none\""
  else
    "stroke=\"#1f2328\" stroke-width=\"0.5\" fill=\"none\""
  end
end

def svg(entities, margin)
  bb = bounds(entities)
  x0 = px(bb[0]) - margin
  y1 = py(bb[1]) + margin
  w = px(bb[1]) - px(bb[0]) + 2 * margin
  h = py(bb[1]) - py(bb[0]) + 2 * margin
  body = join(map((e) -> svg_entity(e, x0, y1), entities), line_break)
  unlines(
    [
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{num(w)}mm\" height=\"#{num(h)}mm\" viewBox=\"0 0 #{num(w)} #{num(h)}\">",
      "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>",
      body,
      "</svg>"
    ]
  )
end

def sx(p, x0)
  num(px(p) - x0)
end

def sy(p, y1)
  num(y1 - py(p))
end

def svg_entity(e, x0, y1)
  k = kind(e)
  st = svg_style(layer(e))
  if k == :line
    "<line x1=\"#{sx(e[:a], x0)}\" y1=\"#{sy(e[:a], y1)}\" x2=\"#{sx(e[:b], x0)}\" y2=\"#{sy(e[:b], y1)}\" #{st}/>"
  elsif k == :circle
    "<circle cx=\"#{sx(e[:c], x0)}\" cy=\"#{sy(e[:c], y1)}\" r=\"#{num(e[:r])}\" #{st}/>"
  elsif k == :polyline
    tag = if e[:closed]
      "polygon"
    else
      "polyline"
    end
    "<#{tag} points=\"#{join(map((p) -> "#{sx(p, x0)},#{sy(p, y1)}", e[:pts]), " ")}\" #{st}/>"
  elsif k == :arc
    svg_arc(e, x0, y1, st)
  else
    "<text x=\"#{sx(e[:p], x0)}\" y=\"#{sy(e[:p], y1)}\" font-family=\"sans-serif\" font-size=\"#{num(e[:h])}\" fill=\"#1f2328\">#{svg_escape(e[:s])}</text>"
  end
end

def svg_arc(e, x0, y1, st)
  c = e[:c]
  r = e[:r]
  a0 = radians(e[:a0])
  a1 = radians(e[:a1])
  p0 = [px(c) + r * cos(a0), py(c) + r * sin(a0)]
  p1 = [px(c) + r * cos(a1), py(c) + r * sin(a1)]
  sweep = mod_positive(e[:a1] - e[:a0], 360)
  large = if sweep > 180
    1
  else
    0
  end
  "<path d=\"M #{sx(p0, x0)} #{sy(p0, y1)} A #{num(r)} #{num(r)} 0 #{to_s(large)} 0 #{sx(p1, x0)} #{sy(p1, y1)}\" #{st}/>"
end

# ── tests ────────────────────────────────────────────────────────────

# waive B0013: `count` is a builtin zumen also uses, so the prefix stays; zumen::count names it too
@doc """
zu_count: How many (0, kind) pairs the DXF text holds: group code 0 starts a
record, so this counts records of that kind and not the same word used as a
layer name or a value.
"""
def zu_count(text, kind)
  ls = split(text, line_break)
  size(
    filter(
      (i) -> ls[i] == "0" and ls[i + 1] == kind,
      filter((i) -> i % 2 == 0, range(0, size(ls) - 1))
    )
  )
end

test "numbers: six decimals at most, no exponent, no negative zero"
  assert num(2) == "2"
  assert num(1.5) == "1.5"
  assert num(1.0 / 3) == "0.333333"
  assert num(-2.25) == "-2.25"
  assert num(0.0000000001) == "0"
  assert num(-0.0000000001) == "0"
  # A value that prints with an exponent by default does not here.
  assert num(123456789.125) == "123456789.125"
end

test "an empty drawing is still a whole DXF"
  d = dxf([])
  assert starts_with?(d, unlines(["0", "SECTION", "2", "HEADER"])) == true
  assert ends_with?(d, unlines(["0", "EOF"])) == true
  assert zu_count(d, "ENDSEC") == 3
  assert zu_count(d, "LAYER") == size(layers)
end

test "every entity is written once, of its own kind, on a declared layer"
  plate = kikagaku::region(
    rect_polygon(0, 0, 100, 50),
    [circle_polygon([25, 25], 5, 16)]
  )
  ents = concat_lists(
    region(plate),
    concat_lists(
      [
        line([0, 60], [100, 60], "BEND"),
        circle([75, 25], 4, "HOLES"),
        arc([50, 25], 10, 0, 90, "OUTLINE"),
        text([0, -10], 3.5, "TRAY & <PAN>", "TEXT")
      ],
      dim([0, 0], [100, 0], -8, 3.5)
    )
  )
  d = dxf(ents)
  # An identity: counts in the text equal counts in the list.
  assert zu_count(d, "POLYLINE") == 2
  assert zu_count(d, "VERTEX") == 4 + 16
  assert zu_count(d, "SEQEND") == 2
  assert zu_count(d, "LINE") == 1 + 5
  assert zu_count(d, "CIRCLE") == 1
  assert zu_count(d, "ARC") == 1
  assert zu_count(d, "TEXT") == 2
  # Every layer named on an entity is declared in the table.
  assert every((e) -> contains(layer_names, layer(e)), ents) == true
  # The dimension reads the length it measures.
  assert last(dim([0, 0], [100, 0], -8, 3.5))[:s] == "100"
end

test "SVG: y is flipped, the scale is 1:1 in mm, text is escaped"
  s = svg(
    [line([0, 0], [100, 50], "OUTLINE"), text([0, 0], 3, "a<b", "TEXT")],
    10
  )
  assert starts_with?(
    s,
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120mm\""
  ) == true
  # (0, 0) is 10 in from the left and 10 up from the bottom of a 70 high box.
  assert includes(s, "x1=\"10\" y1=\"60\" x2=\"110\" y2=\"10\"") == true
  assert includes(s, "a&lt;b") == true
end

test "a view of a box draws its twelve edges and no diagonals"
  v = view(rittai::box(20, 30, 40), :front)
  assert size(v) == 12
  assert every((e) -> layer(e) == "VIEW", v) == true
  bb = bounds(v)
  assert vector_near(bb[1], [20, 40]) == true
end

test "a table: a header, then one line per row, numbers to one decimal"
  rows = [
    {name: "leg", length: 450.04, cut_a: 0},
    {name: "rail", length: 380, cut_a: 45}
  ]
  t = table(rows, [:name, :length, :cut_a], [30, 25, 20], [0, 0], 3)
  assert size(t) == 9
  assert map((e) -> e[:s], take_n(t, 3)) == ["NAME", "LENGTH", "CUT_A"]
  assert t[4][:s] == "450"
  assert near(px(t[5][:p]), 55) == true
  # The empty case: no rows is the header alone.
  assert size(table([], [:name], [30], [0, 0], 3)) == 1
end

test "a sheet adds a frame and one title line per field"
  sh = sheet(
    [line([0, 0], [100, 0], "OUTLINE")],
    {
      part: "tray",
      revision: "A",
      material: "316L",
      notes: ["Pickle and passivate."]
    }
  )
  es = sheet_entities(sh)
  assert size(filter((e) -> layer(e) == "TEXT", es)) == 4
  assert size(filter((e) -> layer(e) == "FRAME", es)) == 1
end

test "project drops the axis a view looks along: top keeps x and y, front x and z, side y and z"
  assert project([1, 2, 3], :top) == [1, 2]
  assert project([1, 2, 3], :front) == [1, 3]
  assert project([1, 2, 3], :side) == [2, 3]
end

test "project keeps the sign and the fraction of a coordinate, and the origin stays put"
  assert project([-1.5, 0.25, -7], :top) == [-1.5, 0.25]
  assert project([-1.5, 0.25, -7], :front) == [-1.5, -7]
  assert project([-1.5, 0.25, -7], :side) == [0.25, -7]
  assert project([0, 0, 0], :side) == [0, 0]
end

test "project of a top view needs no third coordinate, and an empty point has nothing to keep"
  assert project([1, 2], :top) == [1, 2]
  assert project([], :top) == [nil, nil]
end
