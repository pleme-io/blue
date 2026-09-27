use("retsu")
use("kazu")
use("gyouretsu")
use("kikagaku")
use("rittai")
use("zumen")
# kakou (加工) — fabrication: folded sheet, cut tube and bent wire, from the dimensions a shop measures to the blanks, cut lists and solids it makes.
#
# Three part families, the ones a shop with shears, a manual brake, a saw and
# a TIG torch makes. Each gives the shop its instructions (a flat blank with
# bend lines, a cut length with end angles, a developed wire length) and the
# design pipeline its solid (a rittai mesh), from one description.
#
# Units: millimetres, degrees for bend and cut angles (what a shop reads),
# grams for mass. Written for nupastel docs/plans/design-pipeline.md, step 5.
#
# ── the bend relations ───────────────────────────────────────────────
# A bent sheet stretches outside the bend and compresses inside it. The
# neutral surface, which keeps its length, sits a fraction K of the thickness
# in from the inside. With A the bend angle in radians, R the inside radius
# and T the thickness:
#   bend allowance   BA   = A (R + K T)        the neutral arc's length
#   outside setback  OSSB = tan(A / 2) (R + T) mould line to bend tangent
#   bend deduction   BD   = 2 OSSB - BA        what a bend takes off the sum
#                                               of the outside dimensions
# K depends on the material, the tooling and the ratio R / T, so the default
# (0.44, a common rule of thumb for stainless air-bent at R about T) is a
# placeholder until a test bend on the shop's own brake measures it:
# kk_k_from_test_bend.

def kk_rad(deg)
  deg * pi() / 180
end

def kk_bend_allowance(angle_deg, r, t, k)
  kk_rad(angle_deg) * (r + (k * t))
end

def kk_outside_setback(angle_deg, r, t)
  tan(kk_rad(angle_deg) / 2) * (r + t)
end

def kk_bend_deduction(angle_deg, r, t, k)
  (2 * kk_outside_setback(angle_deg, r, t)) - kk_bend_allowance(angle_deg, r, t, k)
end

# K from a test bend: a coupon cut to flat_length, bent once to angle_deg on
# the shop's brake, its two outside legs measured. The legs overshoot the
# flat length by exactly one bend deduction.
def kk_k_from_test_bend(flat_length, leg1, leg2, angle_deg, r, t)
  bd = (leg1 + leg2) - flat_length
  ba = (2 * kk_outside_setback(angle_deg, r, t)) - bd
  ((ba / kk_rad(angle_deg)) - r) / t
end

# ── materials ────────────────────────────────────────────────────────

# Density in g/cm^3.
def kk_density(material)
  table = {ss316l: 7.99, ss304: 7.93, al6061: 2.70, steel: 7.85}
  d = get(table, material)
  if d == nil
    throw(error(:kakou_material, "no density for #{to_s(material)}; known: ss316l, ss304, al6061, steel"))
  end
  d
end

# ── the shop's limits ────────────────────────────────────────────────
# Rules of thumb for a manual brake, each a multiple of the thickness, and
# the sheet sizes on offer. A project replaces them with its shop's real
# limits; every one is named in the refusal it produces.

def kk_default_rules()
  {min_radius_t: 1.0, min_flange_t: 4.0, hole_bend_t: 2.5, hole_edge_t: 2.0, sheets: [[1250, 2000], [1250, 3000]], nest_gap: 5}
end

def kk_rule(rules, key)
  v = get(rules, key)
  if v == nil
    get(kk_default_rules(), key)
  else
    v
  end
end

# ── sheet parts ──────────────────────────────────────────────────────
# A sheet part is a rectangular base of outside dimensions width x depth
# (the mould lines, as a shop measures), with up to one flange on each side
# (:south is -y, :east +x, :north +y, :west -x), each bent once, upward,
# through angle_deg with an inside radius, to an outside length measured
# from the base's underside. Corners between flanges are left open for a
# TIG weld. Holes are polygons in the base, in the base's outside
# coordinates. Hems (a 180 degree fold) and flanges on flanges are refused
# for now, by name.

def kk_flange(side, length, angle_deg, inside_radius)
  {side: side, length: length, angle: angle_deg, radius: inside_radius}
end

def kk_sheet_part(spec)
  {name: get(spec, :name), material: kk_opt(spec, :material, :ss316l), thickness: get(spec, :thickness), width: get(spec, :width), depth: get(spec, :depth), flanges: kk_opt(spec, :flanges, []), holes: kk_opt(spec, :holes, []), k: kk_opt(spec, :k, 0.44), arc_segments: kk_opt(spec, :arc_segments, 12)}
end

def kk_opt(m, key, default)
  v = get(m, key)
  if v == nil
    default
  else
    v
  end
end

def kk_sides()
  [:south, :east, :north, :west]
end

def kk_flange_on(part, side)
  find_first(fn(f) get(f, :side) == side end, get(part, :flanges))
end

# The setback a flange takes off its side of the flat base; 0 unflanged.
def kk_side_setback(part, side)
  f = kk_flange_on(part, side)
  if f == nil
    0
  else
    kk_outside_setback(get(f, :angle), get(f, :radius), get(part, :thickness))
  end
end

# How far the flat blank reaches past the flat base on a side: the bend
# allowance, then the flange's straight run.
def kk_side_extension(part, side)
  f = kk_flange_on(part, side)
  if f == nil
    0
  else
    kk_bend_allowance(get(f, :angle), get(f, :radius), get(part, :thickness), get(part, :k)) + kk_flange_run(part, f)
  end
end

# The flange's straight run past its bend.
def kk_flange_run(part, f)
  get(f, :length) - kk_outside_setback(get(f, :angle), get(f, :radius), get(part, :thickness))
end

# The flat base: the outside rectangle less each flanged side's setback,
# as [x0, y0, x1, y1].
def kk_flat_base(part)
  [kk_side_setback(part, :west), kk_side_setback(part, :south), get(part, :width) - kk_side_setback(part, :east), get(part, :depth) - kk_side_setback(part, :north)]
end

# The flat blank's outline, counter-clockwise: the base with each flange's
# strip, the corners notched where two strips meet.
def kk_blank_outline(part)
  b = kk_flat_base(part)
  x0 = nth(0, b)
  y0 = nth(1, b)
  x1 = nth(2, b)
  y1 = nth(3, b)
  es = kk_side_extension(part, :south)
  ee = kk_side_extension(part, :east)
  en = kk_side_extension(part, :north)
  ew = kk_side_extension(part, :west)
  pts = concat_lists(kk_strip([x0, y0], [x0, y0 - es], [x1, y0 - es], es), concat_lists(kk_strip([x1, y0], [x1 + ee, y0], [x1 + ee, y1], ee), concat_lists(kk_strip([x1, y1], [x1, y1 + en], [x0, y1 + en], en), kk_strip([x0, y1], [x0 - ew, y1], [x0 - ew, y0], ew))))
  pts
end

def kk_strip(corner, out1, out2, e)
  if e > 0
    [corner, out1, out2]
  else
    [corner]
  end
end

# The flat pattern: the blank (a kikagaku region with the holes) and the
# bend lines, each with the side, where the bend zone starts and ends, the
# centre line, the angle, the radius and the direction.
def kk_flat_pattern(part)
  {blank: region(kk_blank_outline(part), get(part, :holes)), bends: map(fn(f) kk_bend_line(part, f) end, get(part, :flanges))}
end

def kk_bend_line(part, f)
  b = kk_flat_base(part)
  ba = kk_bend_allowance(get(f, :angle), get(f, :radius), get(part, :thickness), get(part, :k))
  side = get(f, :side)
  seg = kk_base_edge(b, side)
  out = kk_side_out(side)
  {side: side, start: seg, finish: map(fn(p) vadd(p, scale(ba, out)) end, seg), centre: map(fn(p) vadd(p, scale(ba / 2, out)) end, seg), angle: get(f, :angle), radius: get(f, :radius), direction: :up, allowance: ba}
end

# A side's edge of the flat base, as two 2-D points, and its outward normal.
def kk_base_edge(b, side)
  x0 = nth(0, b)
  y0 = nth(1, b)
  x1 = nth(2, b)
  y1 = nth(3, b)
  if side == :south
    [[x0, y0], [x1, y0]]
  else
    if side == :east
      [[x1, y0], [x1, y1]]
    else
      if side == :north
        [[x0, y1], [x1, y1]]
      else
        [[x0, y0], [x0, y1]]
      end
    end
  end
end

def kk_side_out(side)
  if side == :south
    [0, -1]
  else
    if side == :east
      [1, 0]
    else
      if side == :north
        [0, 1]
      else
        [-1, 0]
      end
    end
  end
end

def kk_blank_size(part)
  bb = bounding_box(kk_blank_outline(part))
  [px(nth(1, bb)) - px(nth(0, bb)), py(nth(1, bb)) - py(nth(0, bb))]
end

# Mass from the blank: its area times the thickness is the part's volume,
# exactly for the flat and to within the neutral-axis shift at each bend.
def kk_sheet_mass_g(part)
  region_area(get(kk_flat_pattern(part), :blank)) * get(part, :thickness) * kk_density(get(part, :material)) / 1000
end

# ── the shop's drawing of a blank ────────────────────────────────────
# What the shear and the brake need: the blank's outline and holes, each
# bend's centre line dashed with its direction, angle and inside radius
# written on it, and the blank's two overall dimensions. Plain ASCII
# ("DEG"), since an R12 reader may not have a degree sign.

def kk_blank_entities(part, text_h)
  fp = kk_flat_pattern(part)
  blank = get(fp, :blank)
  bends = flat_map(fn(b) kk_bend_entities(b, text_h) end, get(fp, :bends))
  bb = bounding_box(region_outline(blank))
  lo = nth(0, bb)
  hi = nth(1, bb)
  dims = concat_lists(zu_dim([px(lo), py(lo)], [px(hi), py(lo)], 0 - (3 * text_h), text_h), zu_dim([px(hi), py(lo)], [px(hi), py(hi)], 0 - (3 * text_h), text_h))
  concat_lists(zu_region(blank), concat_lists(bends, dims))
end

def kk_bend_entities(b, text_h)
  c = get(b, :centre)
  label = "#{upcase(to_s(get(b, :direction)))} #{zu_num(get(b, :angle))} DEG R#{zu_num(get(b, :radius))}"
  [zu_line(nth(0, c), nth(1, c), "BEND"), zu_text(vadd(midpoint(nth(0, c), nth(1, c)), [text_h * 0.5, text_h * 0.5]), text_h * 0.8, label, "BEND")]
end

# ── the folded solid ─────────────────────────────────────────────────
# The base plate, then for each flange one solid: its cross-section (the
# bend's annular sector and the straight run) extruded along the bend line
# and stood on its edge of the base. In the cross-section's own plane, a is
# outward from the flat base's edge and b is up from the underside; the bend
# is centred at (0, T + R), so its inner arc starts on the base's top face
# and its outer arc on its underside.

# One solid, not a base with flanges resting against it: each flanged side's
# wall of the base and each flange's starting face are the same rectangle
# seen from both sides, so both are dropped and the seam welded. Left in,
# they are faces inside the solid, which rt_mesh_refusals refuses and a
# slicer or a physics engine misreads.
def kk_folded_mesh(part)
  b = kk_flat_base(part)
  t = get(part, :thickness)
  base_region = region(rect_polygon(nth(0, b), nth(1, b), nth(2, b) - nth(0, b), nth(3, b) - nth(1, b)), get(part, :holes))
  walls = flat_map(fn(f) rt_extrude_wall_faces(base_region, 0, index_of(kk_sides(), get(f, :side))) end, get(part, :flanges))
  base = rt_drop_faces(rt_extrude(base_region, t), walls)
  rt_weld(rt_merge(concat_lists([base], map(fn(f) kk_flange_mesh(part, b, f) end, get(part, :flanges)))))
end

def kk_flange_section(part, f)
  t = get(part, :thickness)
  r = get(f, :radius)
  n = get(part, :arc_segments)
  a_end = kk_rad(get(f, :angle)) - (pi() / 2)
  inner = arc_points([0, t + r], r, 0 - (pi() / 2), a_end, n)
  outer = arc_points([0, t + r], r + t, 0 - (pi() / 2), a_end, n)
  run = kk_flange_run(part, f)
  dir = [0 - sin(a_end), cos(a_end)]
  tip_in = vadd(last(inner), scale(run, dir))
  tip_out = vadd(last(outer), scale(run, dir))
  concat_lists(inner, concat_lists([tip_in, tip_out], reverse(outer)))
end

def kk_flange_mesh(part, b, f)
  side = get(f, :side)
  seg = kk_base_edge(b, side)
  out2 = kk_side_out(side)
  out = [px(out2), py(out2), 0]
  up = [0, 0, 1]
  along = cross_product(out, up)
  start = if dot(along, [px(nth(1, seg)) - px(nth(0, seg)), py(nth(1, seg)) - py(nth(0, seg)), 0]) > 0
    nth(0, seg)
  else
    nth(1, seg)
  end
  len = distance(nth(0, seg), nth(1, seg))
  rot = transpose([out, up, along])
  section = region(kk_flange_section(part, f), [])
  rt_transform(rt_pose(rot, [px(start), py(start), 0]), rt_drop_faces(rt_extrude(section, len), rt_extrude_wall_faces(section, 0, kk_seam_edge(section))))
end

# The section's edge on the base's side, a = 0 at both ends: where the
# flange meets the base.
def kk_seam_edge(section)
  pts = region_outline(section)
  n = size(pts)
  first(filter(fn(e) abs(px(nth(e, pts))) < 0.000001 && abs(px(nth((e + 1) % n, pts))) < 0.000001 end, range(0, n)))
end

# ── what a shop cannot make ──────────────────────────────────────────

def kk_sheet_refusals(part, rules)
  t = get(part, :thickness)
  fl = get(part, :flanges)
  shape = kk_shape_refusals(part)
  if is_empty(shape) == false
    shape
  else
    radius = map(fn(f) [:kakou_radius, "#{to_s(get(part, :name))} #{to_s(get(f, :side))}: inside radius #{to_s(get(f, :radius))} is under #{to_s(kk_rule(rules, :min_radius_t))} T = #{to_s(kk_rule(rules, :min_radius_t) * t)}"] end, filter(fn(f) get(f, :radius) < (kk_rule(rules, :min_radius_t) * t) - 0.000001 end, fl))
    flange = map(fn(f) [:kakou_flange, "#{to_s(get(part, :name))} #{to_s(get(f, :side))}: the straight run #{to_s(kk_flange_run(part, f))} is under #{to_s(kk_rule(rules, :min_flange_t))} T = #{to_s(kk_rule(rules, :min_flange_t) * t)}, too short to hold in the brake"] end, filter(fn(f) kk_flange_run(part, f) < kk_rule(rules, :min_flange_t) * t end, fl))
    concat_lists(radius, concat_lists(flange, concat_lists(kk_hole_refusals(part, rules), kk_sheet_size_refusals(part, rules))))
  end
end

def kk_shape_refusals(part)
  fl = get(part, :flanges)
  sides = map(fn(f) get(f, :side) end, fl)
  unknown = filter(fn(s) contains(kk_sides(), s) == false end, sides)
  twice = filter(fn(s) count_of(sides, s) > 1 end, kk_sides())
  angles = filter(fn(f) get(f, :angle) <= 0 || get(f, :angle) >= 180 end, fl)
  concat_lists(map(fn(s) [:kakou_unsupported, "side #{to_s(s)} is not one of south, east, north, west"] end, unknown), concat_lists(map(fn(s) [:kakou_unsupported, "two flanges on #{to_s(s)}; a flange on a flange is not supported yet"] end, twice), map(fn(f) [:kakou_unsupported, "a #{to_s(get(f, :angle))} degree bend on #{to_s(get(f, :side))}: only 0 < angle < 180 is supported; hems are not yet"] end, angles)))
end

# Holes must sit inside the flat base, clear of each bend by hole_bend_t T
# plus the radius, and clear of each plain edge by hole_edge_t T.
def kk_hole_refusals(part, rules)
  t = get(part, :thickness)
  b = kk_flat_base(part)
  base = rect_polygon(nth(0, b), nth(1, b), nth(2, b) - nth(0, b), nth(3, b) - nth(1, b))
  flat_map(fn(i) kk_one_hole_refusals(part, rules, b, base, i, nth(i, get(part, :holes))) end, indexes(get(part, :holes)))
end

def kk_one_hole_refusals(part, rules, b, base, i, hole)
  t = get(part, :thickness)
  if polygon_inside(hole, base) == false
    [[:kakou_hole, "#{to_s(get(part, :name))} hole #{to_s(i)} is not inside the flat base"]]
  else
    flat_map(fn(side) kk_hole_side_refusals(part, rules, b, i, hole, side) end, kk_sides())
  end
end

def kk_hole_side_refusals(part, rules, b, i, hole, side)
  t = get(part, :thickness)
  gap = boundary_gap(hole, kk_base_edge(b, side))
  f = kk_flange_on(part, side)
  if f == nil
    need = kk_rule(rules, :hole_edge_t) * t
    if gap < need
      [[:kakou_hole_edge, "#{to_s(get(part, :name))} hole #{to_s(i)} is #{to_s(gap)} from the #{to_s(side)} edge; the least is #{to_s(need)}"]]
    else
      []
    end
  else
    need = (kk_rule(rules, :hole_bend_t) * t) + get(f, :radius)
    if gap < need
      [[:kakou_hole_bend, "#{to_s(get(part, :name))} hole #{to_s(i)} is #{to_s(gap)} from the #{to_s(side)} bend; the least is #{to_s(need)}, or the hole distorts"]]
    else
      []
    end
  end
end

def kk_sheet_size_refusals(part, rules)
  s = kk_blank_size(part)
  fits = some(fn(sh) kk_fits(s, sh) end, kk_rule(rules, :sheets)) == true
  if fits
    []
  else
    [[:kakou_sheet, "#{to_s(get(part, :name))}: the blank #{to_s(px(s))} x #{to_s(py(s))} fits none of the sheets"]]
  end
end

def kk_fits(s, sheet)
  (px(s) <= px(sheet) && py(s) <= py(sheet)) || (py(s) <= px(sheet) && px(s) <= py(sheet))
end

# How many blanks of size s come from one sheet, in rows and columns with a
# gap between them, taking the better of the two orientations.
def kk_nest_count(s, sheet, gap)
  max(kk_grid(px(s), py(s), px(sheet), py(sheet), gap), kk_grid(py(s), px(s), px(sheet), py(sheet), gap))
end

def kk_grid(w, h, sw, sh, gap)
  floor((sw + gap) / (w + gap)) * floor((sh + gap) / (h + gap))
end

# ── tube ─────────────────────────────────────────────────────────────
# A tube member is a length of stock between two points, its ends cut
# square or mitred. The solid is the section extruded along the centre line
# with square ends, which is what a clearance check needs; the mitre angles
# travel on the cut list, which is what the saw needs.

def kk_square_tube(side, wall)
  {kind: :square_tube, side: side, wall: wall}
end

def kk_round_tube(od, wall)
  {kind: :round_tube, od: od, wall: wall}
end

def kk_round_bar(d)
  {kind: :round_bar, od: d, wall: nil}
end

def kk_stock_name(stock)
  k = get(stock, :kind)
  if k == :square_tube
    "tube #{to_s(get(stock, :side))}x#{to_s(get(stock, :side))}x#{to_s(get(stock, :wall))}"
  else
    if k == :round_tube
      "tube OD#{to_s(get(stock, :od))}x#{to_s(get(stock, :wall))}"
    else
      "bar D#{to_s(get(stock, :od))}"
    end
  end
end

# The stock's cross-section as a kikagaku region, centred on the origin.
def kk_section(stock, n)
  k = get(stock, :kind)
  if k == :square_tube
    s = get(stock, :side)
    w = get(stock, :wall)
    region(rect_polygon(0 - (s / 2), 0 - (s / 2), s, s), [rect_polygon(w - (s / 2), w - (s / 2), s - (2 * w), s - (2 * w))])
  else
    if k == :round_tube
      region(circle_polygon([0, 0], get(stock, :od) / 2, n), [circle_polygon([0, 0], (get(stock, :od) / 2) - get(stock, :wall), n)])
    else
      region(circle_polygon([0, 0], get(stock, :od) / 2, n), [])
    end
  end
end

def kk_tube_member(name, stock, a, b, cut_a_deg, cut_b_deg)
  {name: name, stock: stock, from: a, to: b, cut_a: cut_a_deg, cut_b: cut_b_deg, material: :ss316l}
end

def kk_member_length(m)
  vdistance(get(m, :from), get(m, :to))
end

def kk_member_mesh(m, n)
  rt_transform(rt_pose_along(get(m, :from), get(m, :to)), rt_extrude(kk_section(get(m, :stock), n), kk_member_length(m)))
end

# The section's area is exact for the square tube; a round tube's is its
# tessellation's, so its mass comes out a hair under the true one.
def kk_member_mass_g(m, n)
  region_area(kk_section(get(m, :stock), n)) * kk_member_length(m) * kk_density(get(m, :material)) / 1000
end

# One cut-list row per member.
def kk_cut_list(members)
  map(fn(m) {name: get(m, :name), stock: kk_stock_name(get(m, :stock)), length: kk_member_length(m), cut_a: get(m, :cut_a), cut_b: get(m, :cut_b)} end, members)
end

# ── wire ─────────────────────────────────────────────────────────────
# A wire is a round bar bent along a path of points, each corner bent to a
# centre-line radius. Its developed length (what is cut before bending) is
# the path's length less, at each corner of turn theta, 2 r tan(theta / 2)
# for the straight it no longer runs, plus r theta for the arc it does.

def kk_wire(name, d, path, bend_radius)
  {name: name, d: d, path: path, radius: bend_radius, material: :ss316l}
end

def kk_turn(path, i)
  angle_between(vsub(nth(i, path), nth(i - 1, path)), vsub(nth(i + 1, path), nth(i, path)))
end

def kk_wire_length(w)
  path = get(w, :path)
  r = get(w, :radius)
  straight = sum(map(fn(i) vdistance(nth(i, path), nth(i + 1, path)) end, range(0, size(path) - 1)))
  corners = map(fn(i) kk_turn(path, i) end, range(1, size(path) - 1))
  straight - sum(map(fn(th) (2 * r * tan(th / 2)) - (r * th) end, corners))
end

def kk_wire_mesh(w, n)
  rt_sweep(circle_polygon([0, 0], get(w, :d) / 2, n), get(w, :path))
end

def kk_wire_refusals(w)
  if get(w, :radius) < get(w, :d)
    [[:kakou_radius, "#{to_s(get(w, :name))}: a bend radius #{to_s(get(w, :radius))} under the wire's diameter #{to_s(get(w, :d))} cracks or kinks it"]]
  else
    []
  end
end

# ── tests ────────────────────────────────────────────────────────────

def kk_tray()
  kk_sheet_part({name: "tray", thickness: 1.5, width: 300, depth: 200, flanges: map(fn(s) kk_flange(s, 40, 90, 1.5) end, [:south, :east, :north, :west]), holes: [circle_polygon([150, 100], 10, 24)], k: 0.44})
end

test "the bend relations, checked by hand"
  # 90 degrees, R = 1.5, T = 1.5, K = 0.44:
  #   BA   = (pi / 2)(1.5 + 0.66) = 3.392920...
  #   OSSB = tan(45)(1.5 + 1.5)   = 3
  #   BD   = 6 - 3.392920         = 2.607080
  assert near(kk_bend_allowance(90, 1.5, 1.5, 0.44), 3.392920065876977) == true
  assert near(kk_outside_setback(90, 1.5, 1.5), 3) == true
  assert near(kk_bend_deduction(90, 1.5, 1.5, 0.44), 2.607079934123023) == true
  # The empty case: a zero-degree bend allows and deducts nothing.
  assert near(kk_bend_allowance(0, 1.5, 1.5, 0.44), 0) == true
end

test "a test bend gives back the K that made it"
  # An identity: bend a 100 mm coupon at K = 0.40; its legs sum to 100 + BD.
  bd = kk_bend_deduction(90, 1.5, 1.5, 0.40)
  assert near(kk_k_from_test_bend(100, 50 + (bd / 2), 50 + (bd / 2), 90, 1.5, 1.5), 0.40) == true
end

test "a U channel's flat length is the sum of its outside legs less two bend deductions"
  # Hand-computed: a 100 x 40 base (outside) with 30 mm flanges on south and
  # north is 30 + 40 + 30 - 2 BD across, and 100 along.
  u = kk_sheet_part({name: "u", thickness: 1.5, width: 100, depth: 40, flanges: [kk_flange(:south, 30, 90, 1.5), kk_flange(:north, 30, 90, 1.5)], k: 0.44})
  s = kk_blank_size(u)
  assert near(px(s), 100) == true
  assert near(py(s), 100 - (2 * kk_bend_deduction(90, 1.5, 1.5, 0.44))) == true
  # No flanges: the blank is the part.
  flat = kk_sheet_part({name: "flat", thickness: 1.5, width: 100, depth: 40})
  assert vector_near(kk_blank_size(flat), [100, 40]) == true
end

test "a tray's folded solid is closed, and its volume adds up by parts"
  tray = kk_tray()
  m = kk_folded_mesh(tray)
  assert is_empty(rt_mesh_refusals(m)) == true
  # Independently: the base plate is its flat area times T; each flange is
  # the polygonal annular sector (n/2) sin(A/n) ((R+T)^2 - R^2) plus its
  # straight run times T, over the bend line's length.
  b = kk_flat_base(tray)
  bw = nth(2, b) - nth(0, b)
  bd = nth(3, b) - nth(1, b)
  base_v = ((bw * bd) - regular_polygon_area(10, 24)) * 1.5
  sector = (12 / 2.0) * sin((pi() / 2) / 12) * (square(3.0) - square(1.5))
  run = 40 - 3
  flange_v = (2 * bw * (sector + (run * 1.5))) + (2 * bd * (sector + (run * 1.5)))
  assert near_within(rt_volume(m), base_v + flange_v, 0.001) == true
  # The folded part stands 40 high and 300 x 200 outside: its bounding box
  # is the outside dimensions.
  bb = rt_bounds(m)
  assert vector_near(vsub(nth(1, bb), nth(0, bb)), [300, 200, 40]) == true
end

test "a flat pattern: the blank's outline, its bend lines, and its mass"
  tray = kk_tray()
  fp = kk_flat_pattern(tray)
  assert size(get(fp, :bends)) == 4
  assert is_empty(region_refusals(get(fp, :blank))) == true
  # 316L at 7.99 g/cm^3: the blank's area times 1.5 mm.
  assert near(kk_sheet_mass_g(tray), region_area(get(fp, :blank)) * 1.5 * 7.99 / 1000) == true
  # Each bend's zone is one bend allowance wide.
  bl = first(get(fp, :bends))
  assert near(vdistance(first(get(bl, :start)), first(get(bl, :finish))), kk_bend_allowance(90, 1.5, 1.5, 0.44)) == true
end

test "a blank's drawing: outline, holes, one labelled bend line per flange, two dimensions"
  es = kk_blank_entities(kk_tray(), 3.5)
  assert size(filter(fn(e) zu_layer(e) == "OUTLINE" end, es)) == 1
  assert size(filter(fn(e) zu_layer(e) == "HOLES" end, es)) == 1
  bend_lines = filter(fn(e) zu_layer(e) == "BEND" && zu_kind(e) == :line end, es)
  assert size(bend_lines) == 4
  assert contains(map(fn(e) get(e, :s) end, filter(fn(e) zu_kind(e) == :text end, es)), "UP 90 DEG R1.5") == true
  # The dimensions read the blank's size, to one decimal.
  s = kk_blank_size(kk_tray())
  texts = map(fn(e) get(e, :s) end, filter(fn(e) zu_layer(e) == "DIM" && zu_kind(e) == :text end, es))
  assert texts == [zu_num(round(px(s) * 10) / 10), zu_num(round(py(s) * 10) / 10)]
end

test "the shop's limits refuse, each naming its rule"
  rules = kk_default_rules()
  assert is_empty(kk_sheet_refusals(kk_tray(), rules)) == true
  tight = kk_sheet_part({name: "tight", thickness: 1.5, width: 100, depth: 100, flanges: [kk_flange(:south, 40, 90, 0.5)]})
  assert map(fn(r) nth(0, r) end, kk_sheet_refusals(tight, rules)) == [:kakou_radius]
  stub = kk_sheet_part({name: "stub", thickness: 1.5, width: 100, depth: 100, flanges: [kk_flange(:south, 6, 90, 1.5)]})
  assert map(fn(r) nth(0, r) end, kk_sheet_refusals(stub, rules)) == [:kakou_flange]
  near_bend = kk_sheet_part({name: "nb", thickness: 1.5, width: 100, depth: 100, flanges: [kk_flange(:south, 40, 90, 1.5)], holes: [circle_polygon([50, 8], 3, 16)]})
  assert map(fn(r) nth(0, r) end, kk_sheet_refusals(near_bend, rules)) == [:kakou_hole_bend]
  near_edge = kk_sheet_part({name: "ne", thickness: 1.5, width: 100, depth: 100, holes: [circle_polygon([50, 4], 3, 16)]})
  assert map(fn(r) nth(0, r) end, kk_sheet_refusals(near_edge, rules)) == [:kakou_hole_edge]
  huge = kk_sheet_part({name: "huge", thickness: 1.5, width: 1400, depth: 2500})
  assert map(fn(r) nth(0, r) end, kk_sheet_refusals(huge, rules)) == [:kakou_sheet]
  hem = kk_sheet_part({name: "hem", thickness: 1.0, width: 100, depth: 100, flanges: [kk_flange(:north, 10, 180, 1.0)]})
  assert map(fn(r) nth(0, r) end, kk_sheet_refusals(hem, rules)) == [:kakou_unsupported]
end

test "nesting counts blanks per sheet in the better orientation"
  assert kk_nest_count([300, 200], [1250, 2000], 5) == 36
  assert kk_nest_count([2100, 100], [1250, 2000], 5) == 0
end

test "a tube member: its cut list, its solid, its mass"
  st = kk_square_tube(30, 1.2)
  m = kk_tube_member("post", st, [0, 0, 0], [0, 0, 600], 0, 45)
  row = first(kk_cut_list([m]))
  assert get(row, :stock) == "tube 30x30x1.2"
  assert near(get(row, :length), 600) == true
  mesh = kk_member_mesh(m, 16)
  assert is_empty(rt_mesh_refusals(mesh)) == true
  # Section 30^2 - 27.6^2 = 138.24 mm^2, times 600, is 82944 mm^3.
  assert near(rt_volume(mesh), 82944) == true
  assert near(kk_member_mass_g(m, 16), 82944 * 7.99 / 1000) == true
end

test "a bent wire: its developed length by hand, and a refused radius"
  # An L of legs 100 and 100 bent at r = 5: 200 - 2(5)tan(45) + 5(pi/2).
  w = kk_wire("hook", 3, [[0, 0, 0], [0, 0, 100], [100, 0, 100]], 5)
  assert near(kk_wire_length(w), 200 - 10 + (5 * pi() / 2)) == true
  # The empty case: a straight wire's developed length is its length.
  assert near(kk_wire_length(kk_wire("rod", 3, [[0, 0, 0], [0, 0, 80]], 5)), 80) == true
  assert is_empty(rt_mesh_refusals(kk_wire_mesh(w, 12))) == true
  assert map(fn(r) nth(0, r) end, kk_wire_refusals(kk_wire("kink", 3, [[0, 0, 0], [0, 0, 10], [10, 0, 10]], 1))) == [:kakou_radius]
end
