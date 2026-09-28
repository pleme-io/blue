use("retsu")
use("kazu")
use("gyouretsu")
use("kikagaku")
use("junjo")

# rittai (立体) — solids: poses, triangle meshes built by extrusion and sweep, their validity, volume and centroid, and STL.
#
# A point is [x, y, z]. A mesh is [vertices, faces]: each face is [i, j, k],
# indices into the vertices, wound counter-clockwise seen from OUTSIDE, so
# every normal points out and the divergence theorem gives a positive volume.
# Solids are generated rather than carved: an extrusion of a kikagaku region
# (a sheet with holes, a tube's cross-section) or a sweep of a profile along
# a path (a bent wire), because the parts they are for (folded sheet, welded
# tube, bent wire) are made that way. There are no 3D boolean operations.
#
# Units are the caller's; the design pipeline uses millimetres throughout.
# Written for nupastel docs/plans/design-pipeline.md, step 4.

# ── points and directions ────────────────────────────────────────────

def rt_x(p)
  nth(0, p)
end

def rt_y(p)
  nth(1, p)
end

def rt_z(p)
  nth(2, p)
end

# A 2-D point lifted onto the plane z.
def rt_lift(p, z)
  [px(p), py(p), z]
end

# ── rotations and poses ──────────────────────────────────────────────
# A rotation is a 3 x 3 matrix (a list of rows). A pose is [rotation,
# translation]: it maps a point p to R p + t.

def rt_rot_x(theta)
  [[1, 0, 0], [0, cos(theta), -sin(theta)], [0, sin(theta), cos(theta)]]
end

def rt_rot_y(theta)
  [[cos(theta), 0, sin(theta)], [0, 1, 0], [-sin(theta), 0, cos(theta)]]
end

def rt_rot_z(theta)
  [[cos(theta), -sin(theta), 0], [sin(theta), cos(theta), 0], [0, 0, 1]]
end

# Rotation by theta about a unit axis (Rodrigues' formula).
def rt_rot_axis(axis, theta)
  k = normalize(axis)
  kx = rt_x(k)
  ky = rt_y(k)
  kz = rt_z(k)
  kmat = [[0, -kz, ky], [kz, 0, -kx], [-ky, kx, 0]]
  madd(
    madd(identity_matrix(3), mscale(sin(theta), kmat)),
    mscale(1 - cos(theta), matmul(kmat, kmat))
  )
end

# The rotation taking unit direction a onto unit direction b by the shortest
# turn. Opposite directions have no unique shortest turn; a half-turn about
# any axis perpendicular to a is chosen.
def rt_rot_between(a, b)
  ua = normalize(a)
  ub = normalize(b)
  c = dot(ua, ub)
  if c > 0.999999999999
    identity_matrix(3)
  elsif c < -0.999999999999
    rt_rot_axis(rt_perpendicular(ua), pi())
  else
    rt_rot_axis(cross_product(ua, ub), acos(clamp(c, -1, 1)))
  end
end

# Some unit vector perpendicular to v.
def rt_perpendicular(v)
  trial = if abs(rt_x(v)) < 0.9
    [1, 0, 0]
  else
    [0, 1, 0]
  end
  normalize(cross_product(v, trial))
end

def rt_pose(rotation, translation)
  [rotation, translation]
end

def rt_pose_rotation(p)
  nth(0, p)
end

def rt_pose_translation(p)
  nth(1, p)
end

def rt_identity_pose()
  rt_pose(identity_matrix(3), [0, 0, 0])
end

def rt_translation(t)
  rt_pose(identity_matrix(3), t)
end

def rt_apply(pose, p)
  vadd(mvmul(rt_pose_rotation(pose), p), rt_pose_translation(pose))
end

# First b, then a: rt_apply(rt_compose(a, b), p) == rt_apply(a, rt_apply(b, p)).
def rt_compose(a, b)
  rt_pose(
    matmul(rt_pose_rotation(a), rt_pose_rotation(b)),
    rt_apply(a, rt_pose_translation(b))
  )
end

# The inverse pose. A rotation's inverse is its transpose.
def rt_inverse(pose)
  rt = transpose(rt_pose_rotation(pose))
  rt_pose(rt, scale(-1, mvmul(rt, rt_pose_translation(pose))))
end

# The pose that stands a part built along +z on the segment from a to b: its
# origin at a, its +z along b - a. This is how a tube member is placed.
def rt_pose_along(a, b)
  rt_pose(rt_rot_between([0, 0, 1], vsub(b, a)), a)
end

# ── meshes ───────────────────────────────────────────────────────────

def rt_mesh(vertices, faces)
  [vertices, faces]
end

def rt_vertices(m)
  nth(0, m)
end

def rt_faces(m)
  nth(1, m)
end

def rt_empty_mesh()
  rt_mesh([], [])
end

# Several meshes as one, the later faces re-indexed past the earlier vertices.
def rt_merge(meshes)
  reduce(fn(acc, m) rt_merge_two(acc, m) end, rt_empty_mesh(), meshes)
end

def rt_merge_two(a, b)
  off = size(rt_vertices(a))
  rt_mesh(
    concat_lists(rt_vertices(a), rt_vertices(b)),
    concat_lists(
      rt_faces(a),
      map(fn(f) map(fn(i) i + off end, f) end, rt_faces(b))
    )
  )
end

def rt_transform(pose, m)
  rt_mesh(map(fn(p) rt_apply(pose, p) end, rt_vertices(m)), rt_faces(m))
end

def rt_translate(m, d)
  rt_transform(rt_translation(d), m)
end

def rt_face_points(m, f)
  map(fn(i) nth(i, rt_vertices(m)) end, f)
end

# The face's outward normal, unit length; zero for a degenerate face.
def rt_face_normal(m, f)
  pts = rt_face_points(m, f)
  n = cross_product(
    vsub(nth(1, pts), nth(0, pts)),
    vsub(nth(2, pts), nth(0, pts))
  )
  if is_zero_vector(n)
    [0, 0, 0]
  else
    normalize(n)
  end
end

def rt_face_area(m, f)
  pts = rt_face_points(m, f)
  magnitude(
    cross_product(
      vsub(nth(1, pts), nth(0, pts)),
      vsub(nth(2, pts), nth(0, pts))
    )
  ) /
    2
end

def rt_surface_area(m)
  sum(map(fn(f) rt_face_area(m, f) end, rt_faces(m)))
end

# ── volume and centroid ──────────────────────────────────────────────
# Each face and the origin make a tetrahedron of signed volume
# (a . (b x c)) / 6; over a closed, outward-wound mesh they sum to the
# solid's volume, and their volume-weighted centroids to its centroid.

def rt_tet_volume(pts)
  dot(nth(0, pts), cross_product(nth(1, pts), nth(2, pts))) / 6
end

def rt_volume(m)
  sum(map(fn(f) rt_tet_volume(rt_face_points(m, f)) end, rt_faces(m)))
end

def rt_centroid(m)
  v = rt_volume(m)
  moment = reduce(
    fn(acc, f) rt_centroid_term(acc, rt_face_points(m, f)) end,
    [0, 0, 0],
    rt_faces(m)
  )
  scale(1.0 / v, moment)
end

def rt_centroid_term(acc, pts)
  # A tetrahedron's centroid is the mean of its four corners, one of them the
  # origin: (a + b + c) / 4.
  vadd(
    acc,
    scale(
      rt_tet_volume(pts) / 4,
      vadd(vadd(nth(0, pts), nth(1, pts)), nth(2, pts))
    )
  )
end

# Mass from volume and density. With lengths in mm and density in g/cm^3
# (316L: 7.99), mm^3 * g/cm^3 / 1000 is grams.
def rt_mass_g(m, density_g_cm3)
  rt_volume(m) * density_g_cm3 / 1000
end

def rt_bounds(m)
  vs = rt_vertices(m)
  [
    [
      min_of(map(fn(p) rt_x(p) end, vs)),
      min_of(map(fn(p) rt_y(p) end, vs)),
      min_of(map(fn(p) rt_z(p) end, vs))
    ],
    [
      max_of(map(fn(p) rt_x(p) end, vs)),
      max_of(map(fn(p) rt_y(p) end, vs)),
      max_of(map(fn(p) rt_z(p) end, vs))
    ]
  ]
end

# ── validity ─────────────────────────────────────────────────────────
# A mesh can be written to a file and still not be a solid. These are the
# ways it fails, as [kind, why]. Empty means closed, consistently wound
# outward, and without degenerate faces.

def rt_edge_key(a, b)
  "#{to_s(a)}>#{to_s(b)}"
end

def rt_directed_edges(m)
  flat_map(
    fn(f)
      [
        rt_edge_key(nth(0, f), nth(1, f)),
        rt_edge_key(nth(1, f), nth(2, f)),
        rt_edge_key(nth(2, f), nth(0, f))
      ]
    end,
    rt_faces(m)
  )
end

def rt_mesh_refusals(m)
  n = size(rt_vertices(m))
  faces = rt_faces(m)
  if is_empty(faces)
    [[:rittai_mesh, "the mesh has no faces"]]
  else
    bad_index = filter(
      fn(f) some(fn(i) i < 0 || i >= n end, f) == true end,
      faces
    )
    if is_empty(bad_index) == false
      [
        [
          :rittai_mesh,
          "#{to_s(size(bad_index))} face(s) name a vertex that does not exist"
        ]
      ]
    else
      # Judged by POSITION, as every reader of an STL judges it: two parts
      # that touch share no vertex indices, so by index each looks closed,
      # while by position their touching faces sit inside one another.
      rt_closed_refusals(rt_weld(m))
    end
  end
end

def rt_closed_refusals(m)
  degenerate = size(
    filter(fn(f) rt_face_area(m, f) <= 0.0000000001 end, rt_faces(m))
  )
  directed = rt_directed_edges(m)
  seen = rt_count_keys(directed)
  present = rt_key_set(seen)
  doubled = size(filter(fn(kv) nth(1, kv) > 1 end, seen))
  unmatched = size(
    filter(fn(kv) get(present, rt_reverse_key(nth(0, kv))) == nil end, seen)
  )
  crowded = size(
    filter(
      fn(kv) nth(1, kv) > 2 end,
      rt_count_keys(map(fn(k) rt_undirected_key(k) end, directed))
    )
  )
  out = concat_lists(
    if crowded > 0
      [
        [
          :rittai_mesh,
          "#{to_s(crowded)} edge(s) are shared by more than two faces: not one solid (parts touching without being fused)"
        ]
      ]
    else
      []
    end,
    concat_lists(
      if degenerate > 0
        [[:rittai_mesh, "#{to_s(degenerate)} degenerate face(s)"]]
      else
        []
      end,
      concat_lists(
        if doubled > 0
          [
            [
              :rittai_mesh,
              "#{to_s(doubled)} edge(s) run the same way twice: faces wound inconsistently"
            ]
          ]
        else
          []
        end,
        if unmatched > 0
          [
            [
              :rittai_mesh,
              "#{to_s(unmatched)} edge(s) have no face on the other side: the mesh is open"
            ]
          ]
        else
          []
        end
      )
    )
  )
  if is_empty(out) && rt_volume(m) <= 0
    [[:rittai_mesh, "the volume is not positive: the faces are wound inward"]]
  else
    out
  end
end

def rt_reverse_key(k)
  parts = split(k, ">")
  "#{nth(1, parts)}>#{nth(0, parts)}"
end

# The edge regardless of direction: its two indices, lower first.
def rt_undirected_key(k)
  parts = map(fn(s) to_int(s) end, split(k, ">"))
  "#{to_s(min(nth(0, parts), nth(1, parts)))}-#{to_s(max(nth(0, parts), nth(1, parts)))}"
end

# ── welding and fusing ───────────────────────────────────────────────

# A position as a key, to a millionth of the unit: two vertices closer than
# that are one vertex.
def rt_position_key(p)
  "#{to_s(round(rt_x(p) * 1000000))},#{to_s(round(rt_y(p) * 1000000))},#{to_s(round(rt_z(p) * 1000000))}"
end

# Vertices at the same position merged into one, faces re-indexed. An
# assembly of parts that touch has a duplicate vertex at every seam; welded,
# a seam either closes (the parts were fused properly) or shows as an edge
# shared by more than two faces (they only touch).
def rt_weld(m)
  vs = rt_vertices(m)
  fin = reduce(
    fn(acc, p) rt_weld_step(acc, p) end,
    {index: {}, kept: [], count: 0, remap: []},
    vs
  )
  remap = reverse(get(fin, :remap))
  rt_mesh(
    reverse(get(fin, :kept)),
    map(fn(f) map(fn(i) nth(i, remap) end, f) end, rt_faces(m))
  )
end

def rt_weld_step(acc, p)
  k = rt_position_key(p)
  at = get(get(acc, :index), k)
  if at == nil
    n = get(acc, :count)
    {
      index: assoc(get(acc, :index), k, n),
      kept: concat_lists([p], get(acc, :kept)),
      count: n + 1,
      remap: concat_lists([n], get(acc, :remap))
    }
  else
    {
      index: get(acc, :index),
      kept: get(acc, :kept),
      count: get(acc, :count),
      remap: concat_lists([at], get(acc, :remap))
    }
  end
end

# The mesh without the faces at the given positions in its face list.
def rt_drop_faces(m, drop)
  rt_mesh(
    rt_vertices(m),
    map(
      fn(i) nth(i, rt_faces(m)) end,
      filter(fn(i) contains(drop, i) == false end, indexes(rt_faces(m)))
    )
  )
end

# rt_extrude's face order is a contract: the side walls come first, two
# triangles per loop edge, loop by loop (the outline, then each hole) and
# edge by edge from each loop's first point; then the top cap, then the
# bottom. These are the two wall faces of edge e of loop l, the edge from
# point e to point e + 1, for a caller fusing a part onto that wall.
def rt_extrude_wall_faces(r, l, e)
  sizes = concat_lists(
    [size(region_outline(r))],
    map(fn(h) size(h) end, region_holes(r))
  )
  before = sum(take_n(sizes, l))
  [2 * (before + e), 2 * (before + e) + 1]
end

# [key, count] for each distinct key.
def rt_count_keys(keys)
  table = reduce(
    fn(acc, k) assoc(acc, k, rt_count_of(acc, k) + 1) end,
    {},
    keys
  )
  map(fn(k) [k, get(table, k)] end, rt_distinct(keys, table))
end

def rt_count_of(table, k)
  v = get(table, k)
  if v == nil
    0
  else
    v
  end
end

def rt_distinct(keys, table)
  reverse(
    get(
      reduce(
        fn(acc, k) rt_distinct_step(acc, k) end,
        {seen: {}, out: []},
        keys
      ),
      :out
    )
  )
end

def rt_distinct_step(acc, k)
  if get(get(acc, :seen), k) == nil
    {
      seen: assoc(get(acc, :seen), k, true),
      out: concat_lists([k], get(acc, :out))
    }
  else
    acc
  end
end

def rt_key_set(pairs)
  reduce(fn(acc, kv) assoc(acc, nth(0, kv), true) end, {}, pairs)
end

# ── triangulating a polygon with holes ───────────────────────────────
# Ear clipping. Holes are first joined to the outline by a bridge to a
# vertex the hole can see, making one polygon that doubles back along each
# bridge; that polygon is then clipped one convex ear at a time. The result
# is triangles as index triples into the region's points: the outline's
# first, then each hole's, in order.

# All of a region's points, outline first, and each loop's index range.
def rt_region_points(r)
  concat_lists(region_outline(r), flat_map(fn(h) h end, region_holes(r)))
end

def rt_region_loops(r)
  sizes = concat_lists(
    [size(region_outline(r))],
    map(fn(h) size(h) end, region_holes(r))
  )
  starts = reverse(
    get(
      reduce(
        fn(acc, s)
          {
            next: get(acc, :next) + s,
            out: concat_lists([get(acc, :next)], get(acc, :out))
          }
        end,
        {next: 0, out: []},
        sizes
      ),
      :out
    )
  )
  map(
    fn(i) range(nth(i, starts), nth(i, starts) + nth(i, sizes)) end,
    indexes(sizes)
  )
end

# Triangles for a region, or a refusal. Each triangle is counter-clockwise.
def rt_triangulate(r)
  pts = rt_region_points(r)
  loops = rt_region_loops(r)
  holes = sort_by(
    fn(l) -max_of(map(fn(i) px(nth(i, pts)) end, l)) end,
    rest(loops)
  )
  merged = reduce(
    fn(poly, h) rt_bridge(pts, poly, h, holes) end,
    first(loops),
    holes
  )
  rt_ear_clip(pts, merged)
end

# Join hole h into polygon poly (both lists of point indices): from the
# hole's rightmost vertex, a bridge to the nearest polygon vertex the
# segment reaches without crossing any edge.
def rt_bridge(pts, poly, h, holes)
  m = rt_rightmost(pts, h)
  cands = sort_by(fn(i) distance_squared(nth(i, pts), nth(m, pts)) end, poly)
  edges = concat_lists(
    rt_index_edges(poly),
    flat_map(fn(l) rt_index_edges(l) end, holes)
  )
  p = find_first(fn(i) rt_visible(pts, m, i, edges) end, cands)
  at = index_of(poly, p)
  k = index_of(h, m)
  around = concat_lists(drop_n(h, k), take_n(h, k))
  concat_lists(
    take_n(poly, at + 1),
    concat_lists(around, concat_lists([m, p], drop_n(poly, at + 1)))
  )
end

def rt_rightmost(pts, loop)
  reduce(
    fn(best, i)
      if px(nth(i, pts)) > px(nth(best, pts))
        i
      else
        best
      end
    end,
    first(loop),
    loop
  )
end

def rt_index_edges(loop)
  n = size(loop)
  map(fn(j) [nth(j, loop), nth((j + 1) % n, loop)] end, range(0, n))
end

# The segment from vertex m to vertex p crosses no edge except at its ends.
def rt_visible(pts, m, p, edges)
  a = nth(m, pts)
  b = nth(p, pts)
  some(fn(e) rt_blocks(pts, e, m, p, a, b) end, edges) != true
end

def rt_blocks(pts, e, m, p, a, b)
  i = nth(0, e)
  j = nth(1, e)
  if i == m || j == m || i == p || j == p
    false
  else
    segments_intersect(a, b, nth(i, pts), nth(j, pts))
  end
end

def rt_ear_clip(pts, poly)
  n = size(poly)
  fin = reduce(
    fn(acc, step) rt_clip_step(pts, acc) end,
    {poly: poly, tris: [], stuck: false},
    range(0, n)
  )
  if get(fin, :stuck) || size(get(fin, :poly)) > 0
    {
      triangles: reverse(get(fin, :tris)),
      refusals: [
        [
          :rittai_triangulation,
          "no ear left with #{to_s(size(get(fin, :poly)))} vertices remaining; the region is not simple"
        ]
      ]
    }
  else
    {triangles: reverse(get(fin, :tris)), refusals: []}
  end
end

def rt_clip_step(pts, acc)
  poly = get(acc, :poly)
  if get(acc, :stuck) || size(poly) == 0
    acc
  elsif size(poly) == 3
    {poly: [], tris: concat_lists([poly], get(acc, :tris)), stuck: false}
  else
    ears = filter(fn(k) rt_is_ear(pts, poly, k) end, indexes(poly))
    if is_empty(ears)
      flat = filter(fn(k) rt_turn(pts, poly, k) == 0 end, indexes(poly))
      if is_empty(flat)
        {poly: poly, tris: get(acc, :tris), stuck: true}
      else
        {
          poly: remove_at(poly, first(flat)),
          tris: get(acc, :tris),
          stuck: false
        }
      end
    else
      k = first(ears)
      n = size(poly)
      tri = [nth((k + n - 1) % n, poly), nth(k, poly), nth((k + 1) % n, poly)]
      {
        poly: remove_at(poly, k),
        tris: concat_lists([tri], get(acc, :tris)),
        stuck: false
      }
    end
  end
end

# The sign of the turn at position k: 1 convex (counter-clockwise), -1
# reflex, 0 straight.
def rt_turn(pts, poly, k)
  n = size(poly)
  c = cross(
    nth(nth((k + n - 1) % n, poly), pts),
    nth(nth(k, poly), pts),
    nth(nth((k + 1) % n, poly), pts)
  )
  if c > 0.0000000001
    1
  elsif c < -0.0000000001
    -1
  else
    0
  end
end

# A convex corner whose triangle holds no other vertex of the polygon. A
# vertex at the same place as a corner (the two ends of a bridge) does not
# count as inside.
def rt_is_ear(pts, poly, k)
  if rt_turn(pts, poly, k) != 1
    false
  else
    n = size(poly)
    a = nth(nth((k + n - 1) % n, poly), pts)
    b = nth(nth(k, poly), pts)
    c = nth(nth((k + 1) % n, poly), pts)
    some(fn(j) rt_blocks_ear(pts, poly, j, a, b, c) end, indexes(poly)) != true
  end
end

def rt_blocks_ear(pts, poly, j, a, b, c)
  q = nth(nth(j, poly), pts)
  if near(distance_squared(q, a), 0) ||
    near(distance_squared(q, b), 0) ||
    near(distance_squared(q, c), 0)
    false
  else
    cross(a, b, q) >= 0 && cross(b, c, q) >= 0 && cross(c, a, q) >= 0
  end
end

# ── solids ───────────────────────────────────────────────────────────

# A kikagaku region extruded from z = 0 to z = h: a sheet part's blank, or a
# tube's cross-section run out to its length.
def rt_extrude(r, h)
  pts = rt_region_points(r)
  n = size(pts)
  tri = rt_triangulate(r)
  if is_empty(get(tri, :refusals)) == false
    throw(error(:rittai_triangulation, rt_why_of(get(tri, :refusals))))
  end
  bottom = map(fn(p) rt_lift(p, 0) end, pts)
  top = map(fn(p) rt_lift(p, h) end, pts)
  sides = flat_map(fn(l) rt_loop_sides(l, n) end, rt_region_loops(r))
  caps_top = map(fn(t) map(fn(i) i + n end, t) end, get(tri, :triangles))
  caps_bottom = map(fn(t) reverse(t) end, get(tri, :triangles))
  rt_mesh(
    concat_lists(bottom, top),
    concat_lists(sides, concat_lists(caps_top, caps_bottom))
  )
end

def rt_why_of(refusals)
  join(map(fn(r) nth(1, r) end, refusals), "; ")
end

# The two side triangles of each edge a -> b of a loop, facing out: bottom
# a, bottom b, top b, then bottom a, top b, top a.
def rt_loop_sides(loop, n)
  flat_map(
    fn(e)
      [
        [nth(0, e), nth(1, e), nth(1, e) + n],
        [nth(0, e), nth(1, e) + n, nth(0, e) + n]
      ]
    end,
    rt_index_edges(loop)
  )
end

def rt_box(w, d, h)
  rt_extrude(region(rect_polygon(0, 0, w, d), []), h)
end

# A cylinder of radius r and height h along +z, its base a regular n-gon.
def rt_cylinder(r, h, n)
  rt_extrude(region(circle_polygon([0, 0], r, n), []), h)
end

# A profile (a simple polygon, counter-clockwise in its own xy plane) swept
# along a path of 3-D points, with a mitred joint at each interior point: the
# shape of a bent wire or rod. The profile's x axis starts along a normal to
# the first segment and is carried round each bend without twisting.
def rt_sweep(profile, path)
  prof = ccw_polygon(profile)
  frames = rt_sweep_frames(path)
  rings = map(fn(i) rt_ring(prof, path, frames, i) end, indexes(path))
  np = size(prof)
  verts = flat_map(fn(ring) ring end, rings)
  walls = flat_map(fn(s) rt_ring_walls(s, np) end, range(0, size(path) - 1))
  tri = rt_triangulate(region(prof, []))
  last_base = (size(path) - 1) * np
  start_cap = map(fn(t) reverse(t) end, get(tri, :triangles))
  end_cap = map(fn(t) map(fn(i) i + last_base end, t) end, get(tri, :triangles))
  rt_mesh(verts, concat_lists(walls, concat_lists(start_cap, end_cap)))
end

def rt_segment_dir(path, i)
  normalize(vsub(nth(i + 1, path), nth(i, path)))
end

# [normal, binormal] for each segment, carried by the rotation between
# consecutive segment directions (parallel transport).
def rt_sweep_frames(path)
  t0 = rt_segment_dir(path, 0)
  n0 = rt_perpendicular(t0)
  first_frame = [n0, cross_product(t0, n0)]
  reverse(
    reduce(
      fn(acc, i) rt_transport(path, acc, i) end,
      [first_frame],
      range(1, size(path) - 1)
    )
  )
end

def rt_transport(path, acc, i)
  prev = first(acc)
  r = rt_rot_between(rt_segment_dir(path, i - 1), rt_segment_dir(path, i))
  concat_lists([[mvmul(r, nth(0, prev)), mvmul(r, nth(1, prev))]], acc)
end

# The profile placed at path point i: on the end planes at the two ends,
# and on the mitre plane (normal along the sum of the two directions) at a
# joint, reached along the incoming direction.
def rt_ring(prof, path, frames, i)
  last_seg = size(path) - 2
  seg = min(i, last_seg)
  frame = nth(seg, frames)
  if i == 0 || i == size(path) - 1
    map(
      fn(q)
        vadd(
          nth(i, path),
          vadd(scale(px(q), nth(0, frame)), scale(py(q), nth(1, frame)))
        )
      end,
      prof
    )
  else
    tin = rt_segment_dir(path, i - 1)
    tout = rt_segment_dir(path, i)
    mitre = normalize(vadd(tin, tout))
    fin = nth(i - 1, frames)
    map(
      fn(q)
        rt_onto_mitre(
          nth(i, path),
          vadd(scale(px(q), nth(0, fin)), scale(py(q), nth(1, fin))),
          tin,
          mitre
        )
      end,
      prof
    )
  end
end

def rt_onto_mitre(joint, offset, tin, mitre)
  vadd(joint, vsub(offset, scale(dot(offset, mitre) / dot(tin, mitre), tin)))
end

def rt_ring_walls(s, np)
  a0 = s * np
  b0 = (s + 1) * np
  flat_map(
    fn(k)
      [
        [a0 + k, a0 + (k + 1) % np, b0 + (k + 1) % np],
        [a0 + k, b0 + (k + 1) % np, b0 + k]
      ]
    end,
    range(0, np)
  )
end

# ── STL ──────────────────────────────────────────────────────────────

def rt_point_text(p)
  "#{to_s(rt_x(p))} #{to_s(rt_y(p))} #{to_s(rt_z(p))}"
end

# ASCII STL: one facet per face, its normal included.
def rt_stl(m, name)
  facets = map(fn(f) rt_stl_facet(m, f) end, rt_faces(m))
  "solid #{name}\n#{join(facets, "")}endsolid #{name}\n"
end

def rt_stl_facet(m, f)
  pts = rt_face_points(m, f)
  "facet normal #{rt_point_text(rt_face_normal(m, f))}\n outer loop\n  vertex #{rt_point_text(nth(0, pts))}\n  vertex #{rt_point_text(nth(1, pts))}\n  vertex #{rt_point_text(nth(2, pts))}\n endloop\nendfacet\n"
end

# ── tests ────────────────────────────────────────────────────────────

test "a box: closed, outward, its volume, surface and centroid"
  b = rt_box(20, 30, 40)
  assert is_empty(rt_mesh_refusals(b)) == true
  assert near(rt_volume(b), 24000) == true
  assert near(rt_surface_area(b), 2 * (20 * 30 + 20 * 40 + 30 * 40)) == true
  assert vector_near(rt_centroid(b), [10, 15, 20]) == true
  assert size(rt_faces(b)) == 12
end

test "a drilled plate extrudes to its region's area times its thickness"
  hole = circle_polygon([25, 25], 10, 32)
  plate = region(
    rect_polygon(0, 0, 100, 50),
    [hole, circle_polygon([75, 25], 8, 24)]
  )
  m = rt_extrude(plate, 1.5)
  assert is_empty(rt_mesh_refusals(m)) == true
  # Independently checkable: region_area uses the shoelace; the volume is
  # summed from tetrahedra over the triangulation and the walls.
  assert near_within(rt_volume(m), region_area(plate) * 1.5, 0.0001) == true
  # Ear clipping gives n + 2h - 2 triangles for n points and h holes.
  tri = rt_triangulate(plate)
  assert size(get(tri, :triangles)) == 4 + 32 + 24 + 2 * 2 - 2
  # The triangles tile the region exactly.
  pts = rt_region_points(plate)
  assert near_within(
    sum(
      map(
        fn(t)
          triangle_area(
            nth(nth(0, t), pts),
            nth(nth(1, t), pts),
            nth(nth(2, t), pts)
          )
        end,
        get(tri, :triangles)
      )
    ),
    region_area(plate),
    0.0001
  ) ==
    true
end

test "a non-convex outline triangulates and extrudes"
  ell = region([[0, 0], [30, 0], [30, 10], [10, 10], [10, 30], [0, 30]], [])
  m = rt_extrude(ell, 2)
  assert is_empty(rt_mesh_refusals(m)) == true
  assert near(rt_volume(m), 500 * 2) == true
end

test "a cylinder's volume is its regular polygon's area times its height"
  c = rt_cylinder(5, 10, 48)
  assert is_empty(rt_mesh_refusals(c)) == true
  assert near(rt_volume(c), regular_polygon_area(5, 48) * 10) == true
  assert vector_near(rt_centroid(c), [0, 0, 5]) == true
end

test "poses: rotation, composition, inverse, and standing a part on a segment"
  q = [1, 2, 3]
  p = rt_pose(rt_rot_z(pi() / 2), [10, 0, 0])
  assert vector_near(rt_apply(p, [1, 0, 0]), [10, 1, 0]) == true
  assert vector_near(rt_apply(rt_inverse(p), rt_apply(p, q)), q) == true
  assert vector_near(rt_apply(rt_compose(p, rt_inverse(p)), q), q) == true
  assert vector_near(
    mvmul(rt_rot_axis([0, 0, 1], pi() / 2), [1, 0, 0]),
    [0, 1, 0]
  ) ==
    true
  assert is_orthogonal(rt_rot_axis([1, 2, 3], 0.7)) == true
  along = rt_pose_along([0, 0, 0], [0, 100, 0])
  assert vector_near(rt_apply(along, [0, 0, 100]), [0, 100, 0]) == true
  assert vector_near(
    mvmul(rt_rot_between([0, 0, 1], [0, 0, -1]), [0, 0, 1]),
    [0, 0, -1]
  ) ==
    true
  # A transformed solid keeps its volume and moves its centroid.
  b = rt_transform(p, rt_box(2, 2, 2))
  assert near(rt_volume(b), 8) == true
  assert vector_near(rt_centroid(b), rt_apply(p, [1, 1, 1])) == true
end

test "a swept wire: straight, then mitred round a corner"
  sq = rect_polygon(-1, -1, 2, 2)
  straight = rt_sweep(sq, [[0, 0, 0], [0, 0, 50]])
  assert is_empty(rt_mesh_refusals(straight)) == true
  assert near(rt_volume(straight), 4 * 50) == true
  # Round a right angle with a mitred joint, the volume is the profile area
  # times the centreline length: the two wedges of the mitre cancel.
  ell = rt_sweep(
    circle_polygon([0, 0], 1, 16),
    [[0, 0, 0], [0, 0, 40], [30, 0, 40]]
  )
  assert is_empty(rt_mesh_refusals(ell)) == true
  assert near_within(
    rt_volume(ell),
    regular_polygon_area(1, 16) * 70,
    0.000001
  ) ==
    true
end

test "broken meshes are refused, each for its own reason"
  b = rt_box(1, 1, 1)
  # The controls: a face removed (open), one face flipped (inconsistent),
  # every face flipped (inward), an index out of range, and no faces at all.
  open = rt_mesh(rt_vertices(b), rest(rt_faces(b)))
  assert size(rt_mesh_refusals(open)) >= 1
  flipped = rt_mesh(
    rt_vertices(b),
    concat_lists([reverse(first(rt_faces(b)))], rest(rt_faces(b)))
  )
  assert size(rt_mesh_refusals(flipped)) >= 1
  inward = rt_mesh(rt_vertices(b), map(fn(f) reverse(f) end, rt_faces(b)))
  assert map(fn(r) nth(1, r) end, rt_mesh_refusals(inward)) ==
    ["the volume is not positive: the faces are wound inward"]
  assert size(rt_mesh_refusals(rt_mesh(rt_vertices(b), [[0, 1, 99]]))) == 1
  assert size(rt_mesh_refusals(rt_empty_mesh())) == 1
end

test "parts that only touch are refused; fused, they are one solid"
  # Two unit boxes side by side. Merged, each is closed by its own indices,
  # and the check still refuses them: by position, the shared face at x = 1
  # is inside the solid. This is how a folded sheet part first failed a
  # second reader (trimesh) while passing an index-only check.
  r = region(rect_polygon(0, 0, 1, 1), [])
  a = rt_extrude(r, 1)
  b = rt_translate(rt_extrude(r, 1), [1, 0, 0])
  touching = rt_merge([a, b])
  assert is_empty(rt_mesh_refusals(touching)) == false
  # Fused: drop a's east wall (edge 1) and b's west wall (edge 3), then weld.
  fused = rt_weld(
    rt_merge(
      [
        rt_drop_faces(a, rt_extrude_wall_faces(r, 0, 1)),
        rt_drop_faces(b, rt_extrude_wall_faces(r, 0, 3))
      ]
    )
  )
  assert is_empty(rt_mesh_refusals(fused)) == true
  assert near(rt_volume(fused), 2) == true
  # Welding merges only what coincides: a box welded is the same box.
  assert size(rt_vertices(rt_weld(a))) == 8
end

test "STL: one facet per face, with outward normals"
  s = rt_stl(rt_box(1, 1, 1), "cube")
  assert starts_with?(s, "solid cube\n") == true
  assert ends_with?(s, "endsolid cube\n") == true
  assert size(
    filter(fn(l) starts_with?(l, "facet normal") end, split(s, "\n"))
  ) ==
    12
end
