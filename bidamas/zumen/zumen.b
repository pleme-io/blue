use("retsu")
use("kazu")
use("moji")
use("gyouretsu")
use("kikagaku")
use("rittai")
use("ronri")
# zumen (図面) — technical drawings: 2-D entities on layers, sheets with a title block, feature-edge views of solids, written as DXF R12 and SVG.
#
# A drawing is data first: a list of entities, each on a layer, in the
# units of the part (millimetres in the design pipeline). The writers are
# rendered bridges (the kueri rule): DXF R12 for the cutting shop (the
# oldest version, the one every CAM program and laser controller reads), and
# SVG for people, turned into PDF or PNG by rsvg-convert at a process
# boundary. Every number is written by zu_num, to six decimals at most, so
# the same drawing always produces the same bytes and the same hash.
#
# Written for nupastel docs/plans/design-pipeline.md, step 6.

# ── numbers ──────────────────────────────────────────────────────────

# A number to at most six decimals, trailing zeros dropped, never an
# exponent, and never "-0".
def zu_num(x)
  n = round(x * 1000000)
  a = abs(n)
  whole = floor(a / 1000000)
  frac = a - (whole * 1000000)
  sign = if n < 0
    "-"
  else
    ""
  end
  if frac == 0
    "#{sign}#{to_s(whole)}"
  else
    "#{sign}#{to_s(whole)}.#{zu_trim_zeros(pad_left(to_s(frac), 6, "0"))}"
  end
end

def zu_trim_zeros(s)
  if ends_with?(s, "0")
    zu_trim_zeros(take_chars(s, length(s) - 1))
  else
    s
  end
end

# ── entities ─────────────────────────────────────────────────────────
# Each entity is a map with :kind and :layer.

def zu_line(a, b, layer)
  {kind: :line, a: a, b: b, layer: layer}
end

def zu_circle(c, r, layer)
  {kind: :circle, c: c, r: r, layer: layer}
end

# An arc counter-clockwise from a0 to a1, in degrees (DXF's convention).
def zu_arc(c, r, a0, a1, layer)
  {kind: :arc, c: c, r: r, a0: a0, a1: a1, layer: layer}
end

def zu_polyline(pts, closed, layer)
  {kind: :polyline, pts: pts, closed: closed, layer: layer}
end

def zu_text(p, height, s, layer)
  {kind: :text, p: p, h: height, s: s, layer: layer}
end

def zu_kind(e)
  get(e, :kind)
end

def zu_layer(e)
  get(e, :layer)
end

# The layers a drawing uses, each [name, DXF colour number, linetype].
# Bend lines are dashed, as a shop expects.
def zu_layers()
  [["OUTLINE", 7, "CONTINUOUS"], ["HOLES", 1, "CONTINUOUS"], ["BEND", 3, "DASHED"], ["DIM", 4, "CONTINUOUS"], ["TEXT", 7, "CONTINUOUS"], ["FRAME", 8, "CONTINUOUS"], ["VIEW", 7, "CONTINUOUS"]]
end

def zu_layer_names()
  map(fn(l) first(l) end, zu_layers())
end

# A kikagaku region as entities: the outline, and each hole.
def zu_region(r)
  concat_lists([zu_polyline(region_outline(r), true, "OUTLINE")], map(fn(h) zu_polyline(h, true, "HOLES") end, region_holes(r)))
end

# A linear dimension between a and b, drawn offset to the left of a -> b:
# two extension lines, the dimension line with tick marks, and the length
# as text to one decimal.
def zu_dim(a, b, offset, text_h)
  d = vsub(b, a)
  len = magnitude(d)
  u = scale(1.0 / len, d)
  nrm = [0 - py(u), px(u)]
  pa = vadd(a, scale(offset, nrm))
  pb = vadd(b, scale(offset, nrm))
  tick = scale(text_h * 0.4, vadd(u, nrm))
  mid = vadd(midpoint(pa, pb), scale(text_h * 0.4, nrm))
  [zu_line(a, vadd(pa, scale(text_h * 0.3, nrm)), "DIM"), zu_line(b, vadd(pb, scale(text_h * 0.3, nrm)), "DIM"), zu_line(pa, pb, "DIM"), zu_line(vsub(pa, tick), vadd(pa, tick), "DIM"), zu_line(vsub(pb, tick), vadd(pb, tick), "DIM"), zu_text(mid, text_h, zu_num(round(len * 10) / 10), "DIM")]
end

# A table as text entities, one row per line from origin downward: the
# header, then each row's cells in the given columns, each column width
# wide. Rows are maps (a cut list, a bill of materials).
def zu_table(rows, columns, widths, origin, h)
  lines = concat_lists([map(fn(c) upcase(to_s(c)) end, columns)], map(fn(r) map(fn(c) zu_cell(get(r, c)) end, columns) end, rows))
  flat_map(fn(i) zu_table_row(nth(i, lines), widths, [px(origin), py(origin) - (i * h * 1.8)], h) end, indexes(lines))
end

def zu_table_row(cells, widths, p, h)
  map(fn(j) zu_text([px(p) + sum(take_n(widths, j)), py(p)], h, nth(j, cells), "TEXT") end, indexes(cells))
end

# A cell's text: numbers to one decimal (a cut list is read at a saw), nil
# as empty, anything else as itself.
def zu_cell(v)
  if v == nil
    ""
  else
    if number?(v)
      zu_num(round(v * 10) / 10)
    else
      to_s(v)
    end
  end
end

# ── bounds ───────────────────────────────────────────────────────────

def zu_entity_points(e)
  k = zu_kind(e)
  if k == :line
    [get(e, :a), get(e, :b)]
  else
    if k == :polyline
      get(e, :pts)
    else
      if k == :circle || k == :arc
        c = get(e, :c)
        r = get(e, :r)
        [[px(c) - r, py(c) - r], [px(c) + r, py(c) + r]]
      else
        [get(e, :p), vadd(get(e, :p), [get(e, :h) * 0.6 * length(get(e, :s)), get(e, :h)])]
      end
    end
  end
end

# [[min x, min y], [max x, max y]] over every entity; nil for none.
def zu_bounds(entities)
  bounding_box(flat_map(fn(e) zu_entity_points(e) end, entities))
end

# ── sheets ───────────────────────────────────────────────────────────
# A sheet is the part's drawing: its entities and its title fields. The
# title block goes below the drawing, the width of the drawing's extent.

def zu_sheet(entities, title)
  {entities: entities, title: title}
end

def zu_title_rows(title)
  keys = [:part, :revision, :material, :thickness, :units, :source]
  concat_lists(map(fn(k) "#{upcase(to_s(k))}: #{to_s(get(title, k))}" end, filter(fn(k) get(title, k) != nil end, keys)), zu_opt_lines(get(title, :notes)))
end

def zu_opt_lines(xs)
  if xs == nil
    []
  else
    xs
  end
end

# Every entity of the sheet, the frame and title block included.
def zu_sheet_entities(sheet)
  ents = get(sheet, :entities)
  bb = zu_bounds(ents)
  lo = nth(0, bb)
  hi = nth(1, bb)
  w = max(px(hi) - px(lo), 100)
  h = 3.5
  rows = zu_title_rows(get(sheet, :title))
  top = py(lo) - 15
  texts = map(fn(i) zu_text([px(lo), top - (i * h * 1.6)], h, nth(i, rows), "TEXT") end, indexes(rows))
  bottom = top - (size(rows) * h * 1.6) - 3
  frame = zu_polyline([[px(lo) - 5, bottom], [px(lo) + w + 5, bottom], [px(lo) + w + 5, top + h + 3], [px(lo) - 5, top + h + 3]], true, "FRAME")
  concat_lists(ents, concat_lists([frame], texts))
end

# ── feature-edge views of a solid ────────────────────────────────────
# An orthographic view draws each edge where the two faces meeting at it
# turn by more than half a degree, and each boundary edge, projected onto
# the view's plane. Coplanar triangulation diagonals disappear; a
# tessellated curve shows its facets. Hidden edges are drawn too (there is
# no hidden-line removal yet).

def zu_project(p, view)
  if view == :top
    [rt_x(p), rt_y(p)]
  else
    if view == :front
      [rt_x(p), rt_z(p)]
    else
      [rt_y(p), rt_z(p)]
    end
  end
end

def zu_view(mesh, view)
  m = rt_weld(mesh)
  vs = rt_vertices(m)
  faces = rt_faces(m)
  normals = map(fn(f) rt_face_normal(m, f) end, faces)
  table = reduce(fn(acc, i) zu_edge_faces(acc, nth(i, faces), i) end, {}, indexes(faces))
  keys = zu_distinct_keys(faces)
  drawn = filter(fn(k) zu_feature?(get(table, k), normals) end, keys)
  map(fn(k) zu_edge_line(k, vs, view) end, drawn)
end

def zu_edge_key(a, b)
  "#{to_s(min(a, b))}-#{to_s(max(a, b))}"
end

def zu_edges_of(f)
  [[nth(0, f), nth(1, f)], [nth(1, f), nth(2, f)], [nth(2, f), nth(0, f)]]
end

def zu_edge_faces(acc, f, i)
  reduce(fn(t, e) zu_add_face(t, zu_edge_key(nth(0, e), nth(1, e)), i) end, acc, zu_edges_of(f))
end

def zu_add_face(t, k, i)
  prev = get(t, k)
  if prev == nil
    assoc(t, k, [i])
  else
    assoc(t, k, concat_lists(prev, [i]))
  end
end

def zu_distinct_keys(faces)
  get(reduce(fn(acc, f) reduce(fn(a2, e) zu_note_key(a2, zu_edge_key(nth(0, e), nth(1, e))) end, acc, zu_edges_of(f)) end, {seen: {}, keys: []}, faces), :keys)
end

def zu_note_key(acc, k)
  if get(get(acc, :seen), k) == nil
    {seen: assoc(get(acc, :seen), k, true), keys: concat_lists([k], get(acc, :keys))}
  else
    acc
  end
end

def zu_feature?(fs, normals)
  if size(fs) != 2
    true
  else
    dot(nth(nth(0, fs), normals), nth(nth(1, fs), normals)) < 0.99996
  end
end

def zu_edge_line(k, vs, view)
  ij = map(fn(s) to_int(s) end, split(k, "-"))
  zu_line(zu_project(nth(nth(0, ij), vs), view), zu_project(nth(nth(1, ij), vs), view), "VIEW")
end

# ── DXF R12 ──────────────────────────────────────────────────────────
# Group code, then value, one per line. HEADER names the version (AC1009 is
# R12) and the extents; TABLES declares the line types and layers every
# entity names; ENTITIES holds the drawing. A polyline is POLYLINE, its
# VERTEXes and SEQEND, R12's only polyline.

def zu_dxf_pairs(pairs)
  join(map(fn(p) "#{to_s(nth(0, p))}\n#{to_s(nth(1, p))}\n" end, pairs), "")
end

def zu_dxf(entities)
  bb = if is_empty(entities)
    [[0, 0], [0, 0]]
  else
    zu_bounds(entities)
  end
  header = [[0, "SECTION"], [2, "HEADER"], [9, "$ACADVER"], [1, "AC1009"], [9, "$EXTMIN"], [10, zu_num(px(nth(0, bb)))], [20, zu_num(py(nth(0, bb)))], [9, "$EXTMAX"], [10, zu_num(px(nth(1, bb)))], [20, zu_num(py(nth(1, bb)))], [0, "ENDSEC"]]
  ltypes = [[0, "TABLE"], [2, "LTYPE"], [70, 2], [0, "LTYPE"], [2, "CONTINUOUS"], [70, 0], [3, "Solid line"], [72, 65], [73, 0], [40, "0.0"], [0, "LTYPE"], [2, "DASHED"], [70, 0], [3, "Dashed __ __ __"], [72, 65], [73, 2], [40, "6.0"], [49, "4.0"], [49, "-2.0"], [0, "ENDTAB"]]
  layers = concat_lists([[0, "TABLE"], [2, "LAYER"], [70, size(zu_layers())]], concat_lists(flat_map(fn(l) [[0, "LAYER"], [2, nth(0, l)], [70, 0], [62, nth(1, l)], [6, nth(2, l)]] end, zu_layers()), [[0, "ENDTAB"]]))
  tables = concat_lists([[0, "SECTION"], [2, "TABLES"]], concat_lists(ltypes, concat_lists(layers, [[0, "ENDSEC"]])))
  body = concat_lists([[0, "SECTION"], [2, "ENTITIES"]], concat_lists(flat_map(fn(e) zu_dxf_entity(e) end, entities), [[0, "ENDSEC"], [0, "EOF"]]))
  zu_dxf_pairs(concat_lists(header, concat_lists(tables, body)))
end

def zu_xy(code, p)
  [[code, zu_num(px(p))], [code + 10, zu_num(py(p))], [code + 20, "0"]]
end

def zu_dxf_entity(e)
  k = zu_kind(e)
  l = [8, zu_layer(e)]
  if k == :line
    concat_lists([[0, "LINE"], l], concat_lists(zu_xy(10, get(e, :a)), zu_xy(11, get(e, :b))))
  else
    if k == :circle
      concat_lists([[0, "CIRCLE"], l], concat_lists(zu_xy(10, get(e, :c)), [[40, zu_num(get(e, :r))]]))
    else
      if k == :arc
        concat_lists([[0, "ARC"], l], concat_lists(zu_xy(10, get(e, :c)), [[40, zu_num(get(e, :r))], [50, zu_num(get(e, :a0))], [51, zu_num(get(e, :a1))]]))
      else
        if k == :polyline
          flag = if get(e, :closed)
            1
          else
            0
          end
          concat_lists([[0, "POLYLINE"], l, [66, 1], [70, flag], [10, "0"], [20, "0"], [30, "0"]], concat_lists(flat_map(fn(p) concat_lists([[0, "VERTEX"], l], zu_xy(10, p)) end, get(e, :pts)), [[0, "SEQEND"], l]))
        else
          concat_lists([[0, "TEXT"], l], concat_lists(zu_xy(10, get(e, :p)), [[40, zu_num(get(e, :h))], [1, get(e, :s)]]))
        end
      end
    end
  end
end

# ── SVG ──────────────────────────────────────────────────────────────
# Drawing units map one to one onto the SVG's user units, with y flipped
# (SVG's y runs down) and a margin. Width and height are stated in mm, so a
# printer or rsvg-convert keeps the scale 1:1.

def zu_svg_escape(s)
  replace(replace(replace(replace(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "\"", "&quot;")
end

def zu_svg_style(layer)
  if layer == "BEND"
    "stroke=\"#1a7f37\" stroke-width=\"0.35\" stroke-dasharray=\"4 2\" fill=\"none\""
  else
    if layer == "HOLES"
      "stroke=\"#cf222e\" stroke-width=\"0.5\" fill=\"none\""
    else
      if layer == "DIM" || layer == "FRAME"
        "stroke=\"#57606a\" stroke-width=\"0.25\" fill=\"none\""
      else
        "stroke=\"#1f2328\" stroke-width=\"0.5\" fill=\"none\""
      end
    end
  end
end

def zu_svg(entities, margin)
  bb = zu_bounds(entities)
  x0 = px(nth(0, bb)) - margin
  y1 = py(nth(1, bb)) + margin
  w = (px(nth(1, bb)) - px(nth(0, bb))) + (2 * margin)
  h = (py(nth(1, bb)) - py(nth(0, bb))) + (2 * margin)
  body = join(map(fn(e) zu_svg_entity(e, x0, y1) end, entities), "\n")
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{zu_num(w)}mm\" height=\"#{zu_num(h)}mm\" viewBox=\"0 0 #{zu_num(w)} #{zu_num(h)}\">\n<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n#{body}\n</svg>\n"
end

def zu_sx(p, x0)
  zu_num(px(p) - x0)
end

def zu_sy(p, y1)
  zu_num(y1 - py(p))
end

def zu_svg_entity(e, x0, y1)
  k = zu_kind(e)
  st = zu_svg_style(zu_layer(e))
  if k == :line
    "<line x1=\"#{zu_sx(get(e, :a), x0)}\" y1=\"#{zu_sy(get(e, :a), y1)}\" x2=\"#{zu_sx(get(e, :b), x0)}\" y2=\"#{zu_sy(get(e, :b), y1)}\" #{st}/>"
  else
    if k == :circle
      "<circle cx=\"#{zu_sx(get(e, :c), x0)}\" cy=\"#{zu_sy(get(e, :c), y1)}\" r=\"#{zu_num(get(e, :r))}\" #{st}/>"
    else
      if k == :polyline
        tag = if get(e, :closed)
          "polygon"
        else
          "polyline"
        end
        "<#{tag} points=\"#{join(map(fn(p) "#{zu_sx(p, x0)},#{zu_sy(p, y1)}" end, get(e, :pts)), " ")}\" #{st}/>"
      else
        if k == :arc
          zu_svg_arc(e, x0, y1, st)
        else
          "<text x=\"#{zu_sx(get(e, :p), x0)}\" y=\"#{zu_sy(get(e, :p), y1)}\" font-family=\"sans-serif\" font-size=\"#{zu_num(get(e, :h))}\" fill=\"#1f2328\">#{zu_svg_escape(get(e, :s))}</text>"
        end
      end
    end
  end
end

def zu_svg_arc(e, x0, y1, st)
  c = get(e, :c)
  r = get(e, :r)
  a0 = radians(get(e, :a0))
  a1 = radians(get(e, :a1))
  p0 = [px(c) + (r * cos(a0)), py(c) + (r * sin(a0))]
  p1 = [px(c) + (r * cos(a1)), py(c) + (r * sin(a1))]
  sweep = mod_positive(get(e, :a1) - get(e, :a0), 360)
  large = if sweep > 180
    1
  else
    0
  end
  "<path d=\"M #{zu_sx(p0, x0)} #{zu_sy(p0, y1)} A #{zu_num(r)} #{zu_num(r)} 0 #{to_s(large)} 0 #{zu_sx(p1, x0)} #{zu_sy(p1, y1)}\" #{st}/>"
end

# ── tests ────────────────────────────────────────────────────────────

# How many (0, kind) pairs the DXF text holds: group code 0 starts a
# record, so this counts records of that kind and not the same word used as a
# layer name or a value.
def zu_count(text, kind)
  ls = split(text, "\n")
  size(filter(fn(i) nth(i, ls) == "0" && nth(i + 1, ls) == kind end, filter(fn(i) i % 2 == 0 end, range(0, size(ls) - 1))))
end

test "numbers: six decimals at most, no exponent, no negative zero"
  assert zu_num(2) == "2"
  assert zu_num(1.5) == "1.5"
  assert zu_num(1.0 / 3) == "0.333333"
  assert zu_num(0 - 2.25) == "-2.25"
  assert zu_num(0.0000000001) == "0"
  assert zu_num(0 - 0.0000000001) == "0"
  # A value that prints with an exponent by default does not here.
  assert zu_num(123456789.125) == "123456789.125"
end

test "an empty drawing is still a whole DXF"
  d = zu_dxf([])
  assert starts_with?(d, "0\nSECTION\n2\nHEADER\n") == true
  assert ends_with?(d, "0\nEOF\n") == true
  assert zu_count(d, "ENDSEC") == 3
  assert zu_count(d, "LAYER") == size(zu_layers())
end

test "every entity is written once, of its own kind, on a declared layer"
  plate = region(rect_polygon(0, 0, 100, 50), [circle_polygon([25, 25], 5, 16)])
  ents = concat_lists(zu_region(plate), concat_lists([zu_line([0, 60], [100, 60], "BEND"), zu_circle([75, 25], 4, "HOLES"), zu_arc([50, 25], 10, 0, 90, "OUTLINE"), zu_text([0, -10], 3.5, "TRAY & <PAN>", "TEXT")], zu_dim([0, 0], [100, 0], -8, 3.5)))
  d = zu_dxf(ents)
  # An identity: counts in the text equal counts in the list.
  assert zu_count(d, "POLYLINE") == 2
  assert zu_count(d, "VERTEX") == 4 + 16
  assert zu_count(d, "SEQEND") == 2
  assert zu_count(d, "LINE") == 1 + 5
  assert zu_count(d, "CIRCLE") == 1
  assert zu_count(d, "ARC") == 1
  assert zu_count(d, "TEXT") == 2
  # Every layer named on an entity is declared in the table.
  assert every(fn(e) contains(zu_layer_names(), zu_layer(e)) end, ents) == true
  # The dimension reads the length it measures.
  assert get(last(zu_dim([0, 0], [100, 0], -8, 3.5)), :s) == "100"
end

test "SVG: y is flipped, the scale is 1:1 in mm, text is escaped"
  s = zu_svg([zu_line([0, 0], [100, 50], "OUTLINE"), zu_text([0, 0], 3, "a<b", "TEXT")], 10)
  assert starts_with?(s, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120mm\"") == true
  # (0, 0) is 10 in from the left and 10 up from the bottom of a 70 high box.
  assert includes(s, "x1=\"10\" y1=\"60\" x2=\"110\" y2=\"10\"") == true
  assert includes(s, "a&lt;b") == true
end

test "a view of a box draws its twelve edges and no diagonals"
  v = zu_view(rt_box(20, 30, 40), :front)
  assert size(v) == 12
  assert every(fn(e) zu_layer(e) == "VIEW" end, v) == true
  bb = zu_bounds(v)
  assert vector_near(nth(1, bb), [20, 40]) == true
end

test "a table: a header, then one line per row, numbers to one decimal"
  rows = [{name: "leg", length: 450.04, cut_a: 0}, {name: "rail", length: 380, cut_a: 45}]
  t = zu_table(rows, [:name, :length, :cut_a], [30, 25, 20], [0, 0], 3)
  assert size(t) == 9
  assert map(fn(e) get(e, :s) end, take_n(t, 3)) == ["NAME", "LENGTH", "CUT_A"]
  assert get(nth(4, t), :s) == "450"
  assert near(px(get(nth(5, t), :p)), 55) == true
  # The empty case: no rows is the header alone.
  assert size(zu_table([], [:name], [30], [0, 0], 3)) == 1
end

test "a sheet adds a frame and one title line per field"
  sh = zu_sheet([zu_line([0, 0], [100, 0], "OUTLINE")], {part: "tray", revision: "A", material: "316L", notes: ["Pickle and passivate."]})
  es = zu_sheet_entities(sh)
  assert size(filter(fn(e) zu_layer(e) == "TEXT" end, es)) == 4
  assert size(filter(fn(e) zu_layer(e) == "FRAME" end, es)) == 1
end
