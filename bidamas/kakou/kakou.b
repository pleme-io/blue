use(
  "gyouretsu",
  [
    :angle_between,
    :cross_product,
    :dot,
    :scale,
    :transpose,
    :vadd,
    :vdistance,
    :vector_near,
    :vsub
  ]
)

use("kazu", [:abs, :max, :near, :near_within, :square, :sum])

use(
  "kikagaku",
  [
    :arc_points,
    :boundary_gap,
    :bounding_box,
    :circle_polygon,
    :distance,
    :midpoint,
    :pi,
    :polygon_inside,
    :px,
    :py,
    :rect_polygon,
    :region,
    :region_area,
    :region_outline,
    :region_refusals,
    :regular_polygon_area
  ]
)

use(
  "retsu",
  [
    :concat_lists,
    :contains,
    :count_of,
    :find_first,
    :first,
    :flat_map,
    :index_of,
    :indexes,
    :is_empty,
    :last,
    :size
  ]
)

use("rittai")

use("zumen")

legacy_names("0.1.1", "kk")

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

def rad(deg)
  deg * pi() / 180
end

def bend_allowance(angle_deg, r, t, k)
  rad(angle_deg) * (r + k * t)
end

def outside_setback(angle_deg, r, t)
  tan(rad(angle_deg) / 2) * (r + t)
end

def bend_deduction(angle_deg, r, t, k)
  2 * outside_setback(angle_deg, r, t) - bend_allowance(angle_deg, r, t, k)
end

# K from a test bend: a coupon cut to flat_length, bent once to angle_deg on
# the shop's brake, its two outside legs measured. The legs overshoot the
# flat length by exactly one bend deduction.
def k_from_test_bend(flat_length, leg1, leg2, angle_deg, r, t)
  bd = leg1 + leg2 - flat_length
  ba = 2 * outside_setback(angle_deg, r, t) - bd
  (ba / rad(angle_deg) - r) / t
end

# ── materials ────────────────────────────────────────────────────────

# Density in g/cm^3.
def density(material)
  table = {ss316l: 7.99, ss304: 7.93, al6061: 2.7, steel: 7.85}
  d = get(table, material)
  if d == nil
    throw(
      error(
        :kakou_material,
        "no density for #{to_s(material)}; known: ss316l, ss304, al6061, steel"
      )
    )
  end
  d
end

# ── the shop's limits ────────────────────────────────────────────────
# Rules of thumb for a manual brake, each a multiple of the thickness, and
# the sheet sizes on offer. A project replaces them with its shop's real
# limits; every one is named in the refusal it produces.

def default_rules()
  {
    min_radius_t: 1.0,
    min_flange_t: 4.0,
    hole_bend_t: 2.5,
    hole_edge_t: 2.0,
    sheets: [[1250, 2000], [1250, 3000]],
    nest_gap: 5
  }
end

def rule(rules, key)
  v = get(rules, key)
  if v == nil
    get(default_rules(), key)
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

def flange(side, length, angle_deg, inside_radius)
  {side: side, length: length, angle: angle_deg, radius: inside_radius}
end

def sheet_part(spec)
  {
    name: get(spec, :name),
    material: opt(spec, :material, :ss316l),
    thickness: get(spec, :thickness),
    width: get(spec, :width),
    depth: get(spec, :depth),
    flanges: opt(spec, :flanges, []),
    holes: opt(spec, :holes, []),
    k: opt(spec, :k, 0.44),
    arc_segments: opt(spec, :arc_segments, 12)
  }
end

def opt(m, key, default)
  v = get(m, key)
  if v == nil
    default
  else
    v
  end
end

def sides()
  [:south, :east, :north, :west]
end

def flange_on(part, side)
  find_first(fn(f) get(f, :side) == side end, get(part, :flanges))
end

# The setback a flange takes off its side of the flat base; 0 unflanged.
def side_setback(part, side)
  f = flange_on(part, side)
  if f == nil
    0
  else
    outside_setback(get(f, :angle), get(f, :radius), get(part, :thickness))
  end
end

# How far the flat blank reaches past the flat base on a side: the bend
# allowance, then the flange's straight run.
def side_extension(part, side)
  f = flange_on(part, side)
  if f == nil
    0
  else
    bend_allowance(
      get(f, :angle),
      get(f, :radius),
      get(part, :thickness),
      get(part, :k)
    ) +
      flange_run(part, f)
  end
end

# The flange's straight run past its bend.
def flange_run(part, f)
  get(f, :length) -
    outside_setback(get(f, :angle), get(f, :radius), get(part, :thickness))
end

# The flat base: the outside rectangle less each flanged side's setback,
# as [x0, y0, x1, y1].
def flat_base(part)
  [
    side_setback(part, :west),
    side_setback(part, :south),
    get(part, :width) - side_setback(part, :east),
    get(part, :depth) - side_setback(part, :north)
  ]
end

# The flat blank's outline, counter-clockwise: the base with each flange's
# strip, the corners notched where two strips meet.
def blank_outline(part)
  b = flat_base(part)
  x0 = nth(0, b)
  y0 = nth(1, b)
  x1 = nth(2, b)
  y1 = nth(3, b)
  es = side_extension(part, :south)
  ee = side_extension(part, :east)
  en = side_extension(part, :north)
  ew = side_extension(part, :west)
  pts = concat_lists(
    strip([x0, y0], [x0, y0 - es], [x1, y0 - es], es),
    concat_lists(
      strip([x1, y0], [x1 + ee, y0], [x1 + ee, y1], ee),
      concat_lists(
        strip([x1, y1], [x1, y1 + en], [x0, y1 + en], en),
        strip([x0, y1], [x0 - ew, y1], [x0 - ew, y0], ew)
      )
    )
  )
  pts
end

def strip(corner, out1, out2, e)
  if e > 0
    [corner, out1, out2]
  else
    [corner]
  end
end

# The flat pattern: the blank (a kikagaku region with the holes) and the
# bend lines, each with the side, where the bend zone starts and ends, the
# centre line, the angle, the radius and the direction.
def flat_pattern(part)
  {
    blank: region(blank_outline(part), get(part, :holes)),
    bends: map(fn(f) bend_line(part, f) end, get(part, :flanges))
  }
end

def bend_line(part, f)
  b = flat_base(part)
  ba = bend_allowance(
    get(f, :angle),
    get(f, :radius),
    get(part, :thickness),
    get(part, :k)
  )
  side = get(f, :side)
  seg = base_edge(b, side)
  out = side_out(side)
  {
    side: side,
    start: seg,
    finish: map(fn(p) vadd(p, scale(ba, out)) end, seg),
    centre: map(fn(p) vadd(p, scale(ba / 2, out)) end, seg),
    angle: get(f, :angle),
    radius: get(f, :radius),
    direction: :up,
    allowance: ba
  }
end

# A side's edge of the flat base, as two 2-D points, and its outward normal.
def base_edge(b, side)
  x0 = nth(0, b)
  y0 = nth(1, b)
  x1 = nth(2, b)
  y1 = nth(3, b)
  if side == :south
    [[x0, y0], [x1, y0]]
  elsif side == :east
    [[x1, y0], [x1, y1]]
  elsif side == :north
    [[x0, y1], [x1, y1]]
  else
    [[x0, y0], [x0, y1]]
  end
end

def side_out(side)
  if side == :south
    [0, -1]
  elsif side == :east
    [1, 0]
  elsif side == :north
    [0, 1]
  else
    [-1, 0]
  end
end

def blank_size(part)
  bb = bounding_box(blank_outline(part))
  [px(nth(1, bb)) - px(nth(0, bb)), py(nth(1, bb)) - py(nth(0, bb))]
end

# Mass from the blank: its area times the thickness is the part's volume,
# exactly for the flat and to within the neutral-axis shift at each bend.
def sheet_mass_g(part)
  region_area(get(flat_pattern(part), :blank)) *
    get(part, :thickness) *
    density(get(part, :material)) /
    1000
end

# ── the shop's drawing of a blank ────────────────────────────────────
# What the shear and the brake need: the blank's outline and holes, each
# bend's centre line dashed with its direction, angle and inside radius
# written on it, and the blank's two overall dimensions. Plain ASCII
# ("DEG"), since an R12 reader may not have a degree sign.

def blank_entities(part, text_h)
  fp = flat_pattern(part)
  blank = get(fp, :blank)
  bends = flat_map(fn(b) bend_entities(b, text_h) end, get(fp, :bends))
  bb = bounding_box(region_outline(blank))
  lo = nth(0, bb)
  hi = nth(1, bb)
  dims = concat_lists(
    zumen::dim([px(lo), py(lo)], [px(hi), py(lo)], -(3 * text_h), text_h),
    zumen::dim([px(hi), py(lo)], [px(hi), py(hi)], -(3 * text_h), text_h)
  )
  concat_lists(zumen::region(blank), concat_lists(bends, dims))
end

def bend_entities(b, text_h)
  c = get(b, :centre)
  label = "#{upcase(to_s(get(b, :direction)))} #{zumen::num(get(b, :angle))} DEG R#{zumen::num(get(b, :radius))}"
  [
    zumen::line(nth(0, c), nth(1, c), "BEND"),
    zumen::text(
      vadd(midpoint(nth(0, c), nth(1, c)), [text_h * 0.5, text_h * 0.5]),
      text_h * 0.8,
      label,
      "BEND"
    )
  ]
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
def folded_mesh(part)
  b = flat_base(part)
  t = get(part, :thickness)
  base_region = region(
    rect_polygon(
      nth(0, b),
      nth(1, b),
      nth(2, b) - nth(0, b),
      nth(3, b) - nth(1, b)
    ),
    get(part, :holes)
  )
  walls = flat_map(
    fn(f)
      rittai::extrude_wall_faces(
        base_region,
        0,
        index_of(sides(), get(f, :side))
      )
    end,
    get(part, :flanges)
  )
  base = rittai::drop_faces(rittai::extrude(base_region, t), walls)
  rittai::weld(
    rittai::merge(
      concat_lists(
        [base],
        map(fn(f) flange_mesh(part, b, f) end, get(part, :flanges))
      )
    )
  )
end

def flange_section(part, f)
  t = get(part, :thickness)
  r = get(f, :radius)
  n = get(part, :arc_segments)
  a_end = rad(get(f, :angle)) - pi() / 2
  inner = arc_points([0, t + r], r, -(pi() / 2), a_end, n)
  outer = arc_points([0, t + r], r + t, -(pi() / 2), a_end, n)
  run = flange_run(part, f)
  dir = [-sin(a_end), cos(a_end)]
  tip_in = vadd(last(inner), scale(run, dir))
  tip_out = vadd(last(outer), scale(run, dir))
  concat_lists(inner, concat_lists([tip_in, tip_out], reverse(outer)))
end

def flange_mesh(part, b, f)
  side = get(f, :side)
  seg = base_edge(b, side)
  out2 = side_out(side)
  out = [px(out2), py(out2), 0]
  up = [0, 0, 1]
  along = cross_product(out, up)
  start = if dot(
    along,
    [px(nth(1, seg)) - px(nth(0, seg)), py(nth(1, seg)) - py(nth(0, seg)), 0]
  ) >
    0
    nth(0, seg)
  else
    nth(1, seg)
  end
  len = distance(nth(0, seg), nth(1, seg))
  rot = transpose([out, up, along])
  section = region(flange_section(part, f), [])
  rittai::transform(
    rittai::pose(rot, [px(start), py(start), 0]),
    rittai::drop_faces(
      rittai::extrude(section, len),
      rittai::extrude_wall_faces(section, 0, seam_edge(section))
    )
  )
end

# The section's edge on the base's side, a = 0 at both ends: where the
# flange meets the base.
def seam_edge(section)
  pts = region_outline(section)
  n = size(pts)
  first(
    filter(
      fn(e)
        abs(px(nth(e, pts))) < 0.000001 &&
          abs(px(nth((e + 1) % n, pts))) < 0.000001
      end,
      range(0, n)
    )
  )
end

# ── what a shop cannot make ──────────────────────────────────────────

def sheet_refusals(part, rules)
  t = get(part, :thickness)
  fl = get(part, :flanges)
  shape = shape_refusals(part)
  if is_empty(shape) == false
    shape
  else
    radius = map(
      fn(f)
        [
          :kakou_radius,
          "#{to_s(get(part, :name))} #{to_s(get(f, :side))}: inside radius #{to_s(get(f, :radius))} is under #{to_s(rule(rules, :min_radius_t))} T = #{to_s(rule(rules, :min_radius_t) * t)}"
        ]
      end,
      filter(
        fn(f) get(f, :radius) < rule(rules, :min_radius_t) * t - 0.000001 end,
        fl
      )
    )
    flange = map(
      fn(f)
        [
          :kakou_flange,
          "#{to_s(get(part, :name))} #{to_s(get(f, :side))}: the straight run #{to_s(flange_run(part, f))} is under #{to_s(rule(rules, :min_flange_t))} T = #{to_s(rule(rules, :min_flange_t) * t)}, too short to hold in the brake"
        ]
      end,
      filter(fn(f) flange_run(part, f) < rule(rules, :min_flange_t) * t end, fl)
    )
    concat_lists(
      radius,
      concat_lists(
        flange,
        concat_lists(
          hole_refusals(part, rules),
          sheet_size_refusals(part, rules)
        )
      )
    )
  end
end

def shape_refusals(part)
  fl = get(part, :flanges)
  sides = map(fn(f) get(f, :side) end, fl)
  unknown = filter(fn(s) contains(kakou::sides(), s) == false end, sides)
  twice = filter(fn(s) count_of(sides, s) > 1 end, kakou::sides())
  angles = filter(fn(f) get(f, :angle) <= 0 || get(f, :angle) >= 180 end, fl)
  concat_lists(
    map(
      fn(s)
        [
          :kakou_unsupported,
          "side #{to_s(s)} is not one of south, east, north, west"
        ]
      end,
      unknown
    ),
    concat_lists(
      map(
        fn(s)
          [
            :kakou_unsupported,
            "two flanges on #{to_s(s)}; a flange on a flange is not supported yet"
          ]
        end,
        twice
      ),
      map(
        fn(f)
          [
            :kakou_unsupported,
            "a #{to_s(get(f, :angle))} degree bend on #{to_s(get(f, :side))}: only 0 < angle < 180 is supported; hems are not yet"
          ]
        end,
        angles
      )
    )
  )
end

# Holes must sit inside the flat base, clear of each bend by hole_bend_t T
# plus the radius, and clear of each plain edge by hole_edge_t T.
def hole_refusals(part, rules)
  _t = get(part, :thickness)
  b = flat_base(part)
  base = rect_polygon(
    nth(0, b),
    nth(1, b),
    nth(2, b) - nth(0, b),
    nth(3, b) - nth(1, b)
  )
  flat_map(
    fn(i)
      one_hole_refusals(part, rules, b, base, i, nth(i, get(part, :holes)))
    end,
    indexes(get(part, :holes))
  )
end

def one_hole_refusals(part, rules, b, base, i, hole)
  _t = get(part, :thickness)
  if polygon_inside(hole, base) == false
    [
      [
        :kakou_hole,
        "#{to_s(get(part, :name))} hole #{to_s(i)} is not inside the flat base"
      ]
    ]
  else
    flat_map(
      fn(side) hole_side_refusals(part, rules, b, i, hole, side) end,
      sides()
    )
  end
end

def hole_side_refusals(part, rules, b, i, hole, side)
  t = get(part, :thickness)
  gap = boundary_gap(hole, base_edge(b, side))
  f = flange_on(part, side)
  if f == nil
    need = rule(rules, :hole_edge_t) * t
    if gap < need
      [
        [
          :kakou_hole_edge,
          "#{to_s(get(part, :name))} hole #{to_s(i)} is #{to_s(gap)} from the #{to_s(side)} edge; the least is #{to_s(need)}"
        ]
      ]
    else
      []
    end
  else
    need = rule(rules, :hole_bend_t) * t + get(f, :radius)
    if gap < need
      [
        [
          :kakou_hole_bend,
          "#{to_s(get(part, :name))} hole #{to_s(i)} is #{to_s(gap)} from the #{to_s(side)} bend; the least is #{to_s(need)}, or the hole distorts"
        ]
      ]
    else
      []
    end
  end
end

def sheet_size_refusals(part, rules)
  s = blank_size(part)
  fits = some(fn(sh) kakou::fits(s, sh) end, rule(rules, :sheets)) == true
  if fits
    []
  else
    [
      [
        :kakou_sheet,
        "#{to_s(get(part, :name))}: the blank #{to_s(px(s))} x #{to_s(py(s))} fits none of the sheets"
      ]
    ]
  end
end

def fits(s, sheet)
  px(s) <= px(sheet) && py(s) <= py(sheet) ||
    py(s) <= px(sheet) && px(s) <= py(sheet)
end

# How many blanks of size s come from one sheet, in rows and columns with a
# gap between them, taking the better of the two orientations.
def nest_count(s, sheet, gap)
  max(
    grid(px(s), py(s), px(sheet), py(sheet), gap),
    grid(py(s), px(s), px(sheet), py(sheet), gap)
  )
end

def grid(w, h, sw, sh, gap)
  floor((sw + gap) / (w + gap)) * floor((sh + gap) / (h + gap))
end

# ── tube ─────────────────────────────────────────────────────────────
# A tube member is a length of stock between two points, its ends cut
# square or mitred. The solid is the section extruded along the centre line
# with square ends, which is what a clearance check needs; the mitre angles
# travel on the cut list, which is what the saw needs.

def square_tube(side, wall)
  {kind: :square_tube, side: side, wall: wall}
end

def round_tube(od, wall)
  {kind: :round_tube, od: od, wall: wall}
end

def round_bar(d)
  {kind: :round_bar, od: d, wall: nil}
end

def stock_name(stock)
  k = get(stock, :kind)
  if k == :square_tube
    "tube #{to_s(get(stock, :side))}x#{to_s(get(stock, :side))}x#{to_s(get(stock, :wall))}"
  elsif k == :round_tube
    "tube OD#{to_s(get(stock, :od))}x#{to_s(get(stock, :wall))}"
  else
    "bar D#{to_s(get(stock, :od))}"
  end
end

# The stock's cross-section as a kikagaku region, centred on the origin.
def section(stock, n)
  k = get(stock, :kind)
  if k == :square_tube
    s = get(stock, :side)
    w = get(stock, :wall)
    region(
      rect_polygon(-(s / 2), -(s / 2), s, s),
      [rect_polygon(w - s / 2, w - s / 2, s - 2 * w, s - 2 * w)]
    )
  elsif k == :round_tube
    region(
      circle_polygon([0, 0], get(stock, :od) / 2, n),
      [circle_polygon([0, 0], get(stock, :od) / 2 - get(stock, :wall), n)]
    )
  else
    region(circle_polygon([0, 0], get(stock, :od) / 2, n), [])
  end
end

def tube_member(name, stock, a, b, cut_a_deg, cut_b_deg)
  {
    name: name,
    stock: stock,
    from: a,
    to: b,
    cut_a: cut_a_deg,
    cut_b: cut_b_deg,
    material: :ss316l
  }
end

def member_length(m)
  vdistance(get(m, :from), get(m, :to))
end

def member_mesh(m, n)
  rittai::transform(
    rittai::pose_along(get(m, :from), get(m, :to)),
    rittai::extrude(section(get(m, :stock), n), member_length(m))
  )
end

# The section's area is exact for the square tube; a round tube's is its
# tessellation's, so its mass comes out a hair under the true one.
def member_mass_g(m, n)
  region_area(section(get(m, :stock), n)) *
    member_length(m) *
    density(get(m, :material)) /
    1000
end

# One cut-list row per member.
def cut_list(members)
  map(
    fn(m)
      {
        name: get(m, :name),
        stock: stock_name(get(m, :stock)),
        length: member_length(m),
        cut_a: get(m, :cut_a),
        cut_b: get(m, :cut_b)
      }
    end,
    members
  )
end

# ── wire ─────────────────────────────────────────────────────────────
# A wire is a round bar bent along a path of points, each corner bent to a
# centre-line radius. Its developed length (what is cut before bending) is
# the path's length less, at each corner of turn theta, 2 r tan(theta / 2)
# for the straight it no longer runs, plus r theta for the arc it does.

def wire(name, d, path, bend_radius)
  {name: name, d: d, path: path, radius: bend_radius, material: :ss316l}
end

def turn(path, i)
  angle_between(
    vsub(nth(i, path), nth(i - 1, path)),
    vsub(nth(i + 1, path), nth(i, path))
  )
end

def wire_length(w)
  path = get(w, :path)
  r = get(w, :radius)
  straight = sum(
    map(
      fn(i) vdistance(nth(i, path), nth(i + 1, path)) end,
      range(0, size(path) - 1)
    )
  )
  corners = map(fn(i) turn(path, i) end, range(1, size(path) - 1))
  straight - sum(map(fn(th) 2 * r * tan(th / 2) - r * th end, corners))
end

def wire_mesh(w, n)
  rittai::sweep(circle_polygon([0, 0], get(w, :d) / 2, n), get(w, :path))
end

def wire_refusals(w)
  if get(w, :radius) < get(w, :d)
    [
      [
        :kakou_radius,
        "#{to_s(get(w, :name))}: a bend radius #{to_s(get(w, :radius))} under the wire's diameter #{to_s(get(w, :d))} cracks or kinks it"
      ]
    ]
  else
    []
  end
end

# ── tests ────────────────────────────────────────────────────────────

def tray()
  sheet_part(
    {
      name: "tray",
      thickness: 1.5,
      width: 300,
      depth: 200,
      flanges: map(
        fn(s) flange(s, 40, 90, 1.5) end,
        [:south, :east, :north, :west]
      ),
      holes: [circle_polygon([150, 100], 10, 24)],
      k: 0.44
    }
  )
end

test "the bend relations, checked by hand"
  # 90 degrees, R = 1.5, T = 1.5, K = 0.44:
  #   BA   = (pi / 2)(1.5 + 0.66) = 3.392920...
  #   OSSB = tan(45)(1.5 + 1.5)   = 3
  #   BD   = 6 - 3.392920         = 2.607080
  assert near(bend_allowance(90, 1.5, 1.5, 0.44), 3.392920065876977) == true
  assert near(outside_setback(90, 1.5, 1.5), 3) == true
  assert near(bend_deduction(90, 1.5, 1.5, 0.44), 2.607079934123023) == true
  # The empty case: a zero-degree bend allows and deducts nothing.
  assert near(bend_allowance(0, 1.5, 1.5, 0.44), 0) == true
end

test "a test bend gives back the K that made it"
  # An identity: bend a 100 mm coupon at K = 0.40; its legs sum to 100 + BD.
  bd = bend_deduction(90, 1.5, 1.5, 0.4)
  assert near(
    k_from_test_bend(100, 50 + bd / 2, 50 + bd / 2, 90, 1.5, 1.5),
    0.4
  ) ==
    true
end

test "a U channel's flat length is the sum of its outside legs less two bend deductions"
  # Hand-computed: a 100 x 40 base (outside) with 30 mm flanges on south and
  # north is 30 + 40 + 30 - 2 BD across, and 100 along.
  u = sheet_part(
    {
      name: "u",
      thickness: 1.5,
      width: 100,
      depth: 40,
      flanges: [flange(:south, 30, 90, 1.5), flange(:north, 30, 90, 1.5)],
      k: 0.44
    }
  )
  s = blank_size(u)
  assert near(px(s), 100) == true
  assert near(py(s), 100 - 2 * bend_deduction(90, 1.5, 1.5, 0.44)) == true
  # No flanges: the blank is the part.
  flat = sheet_part({name: "flat", thickness: 1.5, width: 100, depth: 40})
  assert vector_near(blank_size(flat), [100, 40]) == true
end

test "a tray's folded solid is closed, and its volume adds up by parts"
  tray = kakou::tray()
  m = folded_mesh(tray)
  assert is_empty(rittai::mesh_refusals(m)) == true
  # Independently: the base plate is its flat area times T; each flange is
  # the polygonal annular sector (n/2) sin(A/n) ((R+T)^2 - R^2) plus its
  # straight run times T, over the bend line's length.
  b = flat_base(tray)
  bw = nth(2, b) - nth(0, b)
  bd = nth(3, b) - nth(1, b)
  base_v = (bw * bd - regular_polygon_area(10, 24)) * 1.5
  sector = 12 / 2.0 * sin(pi() / 2 / 12) * (square(3.0) - square(1.5))
  run = 40 - 3
  flange_v = 2 * bw * (sector + run * 1.5) + 2 * bd * (sector + run * 1.5)
  assert near_within(rittai::volume(m), base_v + flange_v, 0.001) == true
  # The folded part stands 40 high and 300 x 200 outside: its bounding box
  # is the outside dimensions.
  bb = rittai::bounds(m)
  assert vector_near(vsub(nth(1, bb), nth(0, bb)), [300, 200, 40]) == true
end

test "a flat pattern: the blank's outline, its bend lines, and its mass"
  tray = kakou::tray()
  fp = flat_pattern(tray)
  assert size(get(fp, :bends)) == 4
  assert is_empty(region_refusals(get(fp, :blank))) == true
  # 316L at 7.99 g/cm^3: the blank's area times 1.5 mm.
  assert near(
    sheet_mass_g(tray),
    region_area(get(fp, :blank)) * 1.5 * 7.99 / 1000
  ) ==
    true
  # Each bend's zone is one bend allowance wide.
  bl = first(get(fp, :bends))
  assert near(
    vdistance(first(get(bl, :start)), first(get(bl, :finish))),
    bend_allowance(90, 1.5, 1.5, 0.44)
  ) ==
    true
end

test "a blank's drawing: outline, holes, one labelled bend line per flange, two dimensions"
  es = blank_entities(tray(), 3.5)
  assert size(filter(fn(e) zumen::layer(e) == "OUTLINE" end, es)) == 1
  assert size(filter(fn(e) zumen::layer(e) == "HOLES" end, es)) == 1
  bend_lines = filter(
    fn(e) zumen::layer(e) == "BEND" && zumen::kind(e) == :line end,
    es
  )
  assert size(bend_lines) == 4
  assert contains(
    map(fn(e) get(e, :s) end, filter(fn(e) zumen::kind(e) == :text end, es)),
    "UP 90 DEG R1.5"
  ) ==
    true
  # The dimensions read the blank's size, to one decimal.
  s = blank_size(tray())
  texts = map(
    fn(e) get(e, :s) end,
    filter(fn(e) zumen::layer(e) == "DIM" && zumen::kind(e) == :text end, es)
  )
  assert texts ==
    [zumen::num(round(px(s) * 10) / 10), zumen::num(round(py(s) * 10) / 10)]
end

test "the shop's limits refuse, each naming its rule"
  rules = default_rules()
  assert is_empty(sheet_refusals(tray(), rules)) == true
  tight = sheet_part(
    {
      name: "tight",
      thickness: 1.5,
      width: 100,
      depth: 100,
      flanges: [flange(:south, 40, 90, 0.5)]
    }
  )
  assert map(fn(r) nth(0, r) end, sheet_refusals(tight, rules)) ==
    [:kakou_radius]
  stub = sheet_part(
    {
      name: "stub",
      thickness: 1.5,
      width: 100,
      depth: 100,
      flanges: [flange(:south, 6, 90, 1.5)]
    }
  )
  assert map(fn(r) nth(0, r) end, sheet_refusals(stub, rules)) ==
    [:kakou_flange]
  near_bend = sheet_part(
    {
      name: "nb",
      thickness: 1.5,
      width: 100,
      depth: 100,
      flanges: [flange(:south, 40, 90, 1.5)],
      holes: [circle_polygon([50, 8], 3, 16)]
    }
  )
  assert map(fn(r) nth(0, r) end, sheet_refusals(near_bend, rules)) ==
    [:kakou_hole_bend]
  near_edge = sheet_part(
    {
      name: "ne",
      thickness: 1.5,
      width: 100,
      depth: 100,
      holes: [circle_polygon([50, 4], 3, 16)]
    }
  )
  assert map(fn(r) nth(0, r) end, sheet_refusals(near_edge, rules)) ==
    [:kakou_hole_edge]
  huge = sheet_part({name: "huge", thickness: 1.5, width: 1400, depth: 2500})
  assert map(fn(r) nth(0, r) end, sheet_refusals(huge, rules)) == [:kakou_sheet]
  hem = sheet_part(
    {
      name: "hem",
      thickness: 1.0,
      width: 100,
      depth: 100,
      flanges: [flange(:north, 10, 180, 1.0)]
    }
  )
  assert map(fn(r) nth(0, r) end, sheet_refusals(hem, rules)) ==
    [:kakou_unsupported]
end

test "nesting counts blanks per sheet in the better orientation"
  assert nest_count([300, 200], [1250, 2000], 5) == 36
  assert nest_count([2100, 100], [1250, 2000], 5) == 0
end

test "a tube member: its cut list, its solid, its mass"
  st = square_tube(30, 1.2)
  m = tube_member("post", st, [0, 0, 0], [0, 0, 600], 0, 45)
  row = first(cut_list([m]))
  assert get(row, :stock) == "tube 30x30x1.2"
  assert near(get(row, :length), 600) == true
  mesh = member_mesh(m, 16)
  assert is_empty(rittai::mesh_refusals(mesh)) == true
  # Section 30^2 - 27.6^2 = 138.24 mm^2, times 600, is 82944 mm^3.
  assert near(rittai::volume(mesh), 82944) == true
  assert near(member_mass_g(m, 16), 82944 * 7.99 / 1000) == true
end

test "a bent wire: its developed length by hand, and a refused radius"
  # An L of legs 100 and 100 bent at r = 5: 200 - 2(5)tan(45) + 5(pi/2).
  w = wire("hook", 3, [[0, 0, 0], [0, 0, 100], [100, 0, 100]], 5)
  assert near(wire_length(w), 200 - 10 + 5 * pi() / 2) == true
  # The empty case: a straight wire's developed length is its length.
  assert near(wire_length(wire("rod", 3, [[0, 0, 0], [0, 0, 80]], 5)), 80) ==
    true
  assert is_empty(rittai::mesh_refusals(wire_mesh(w, 12))) == true
  assert map(
    fn(r) nth(0, r) end,
    wire_refusals(wire("kink", 3, [[0, 0, 0], [0, 0, 10], [10, 0, 10]], 1))
  ) ==
    [:kakou_radius]
end
