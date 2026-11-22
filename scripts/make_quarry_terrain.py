# Builds the quarry map in Blender and exports it for Godot.
#   Blender -b -P scripts/make_quarry_terrain.py -- <out_dir> [<blend_dir>]
# Open-pit quarry: terraced benches down to a flat floor, a haul ramp from the floor up to the
# work yard on the east rim, grass and hills beyond. Writes quarry_terrain.glb and quarry_heights.bin
# (int32 N, float32 size, then N*N float32 heights; row = z, col = x, Godot axes).
import bpy, bmesh, math, struct, sys, os
from mathutils import noise, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["."]
out = args[0]
blend_dir = args[1] if len(args) > 1 else out
os.makedirs(out, exist_ok=True)
os.makedirs(blend_dir, exist_ok=True)

SIZE = 400.0
N = 241
HALF = SIZE / 2

FLOOR = -28.0
FLOOR_R = 55.0
BENCH_H = 7.0      # 4 benches of 7 m = 28 m deep
BENCH_W = 10.0     # flat shelf
WALL_W = 3.0       # steep face
BENCHES = 4
RIM_R = FLOOR_R + BENCHES * (BENCH_W + WALL_W)   # 107
ROAD_W = 14.0      # haul road width
TURNS = 0.7        # the road spirals down the pit wall this many times
# Haul road: winds down the benches from the east rim (angle 0) to the pit floor.
ROAD = []
for i in range(361):
    t = i / 360.0                       # 0 = floor end, 1 = rim end
    ang = -TURNS * 2 * math.pi * (1 - t)
    r = (FLOOR_R - 6) + ((RIM_R + 8) - (FLOOR_R - 6)) * t
    ROAD.append((math.cos(ang) * r, math.sin(ang) * r, FLOOR + (0.0 - FLOOR) * t))
# Yard road from the rim exit to the crusher dump spot (flat, just painted).
YARD = [(RIM_R + 8, 0.0), (128, 6), (145, 16), (160, 28)]


def fbm(x, y, oct=4):
    s, a, f = 0.0, 1.0, 1.0
    for _ in range(oct):
        s += a * noise.noise(Vector((x * f, y * f, 3.1)))
        a *= 0.5
        f *= 2.0
    return s


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def seg_dist(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz + 1e-9)))
    return math.hypot(px - ax - dx * t, pz - az - dz * t), t


def road_at(x, z):
    """(distance to road centre, road height there)."""
    best, hy = 1e9, 0.0
    for i in range(0, len(ROAD) - 1):
        a, b = ROAD[i], ROAD[i + 1]
        if abs(a[0] - x) > 30 and abs(b[0] - x) > 30:
            continue
        d, t = seg_dist(x, z, a[0], a[1], b[0], b[1])
        if d < best:
            best, hy = d, a[2] + (b[2] - a[2]) * t
    return best, hy


def yard_road(x, z):
    return min(seg_dist(x, z, *YARD[i], *YARD[i + 1])[0] for i in range(len(YARD) - 1))


def pit(r):
    if r <= FLOOR_R:
        return FLOOR
    d = r - FLOOR_R
    k = int(d // (BENCH_W + WALL_W))
    if k >= BENCHES:
        return 0.0
    f = d - k * (BENCH_W + WALL_W)
    base = FLOOR + k * BENCH_H
    if f < WALL_W:
        return base + BENCH_H * smooth(0.0, WALL_W, f)
    return base + BENCH_H


def ramp_h(x):
    t = (x - RAMP_X0) / (RAMP_X1 - RAMP_X0)
    return FLOOR + (0.0 - FLOOR) * max(0.0, min(1.0, t))


def height(x, z):
    r = math.hypot(x, z)
    # Rough, uneven benches: wobble the radius so the walls aren't perfect circles.
    rr = r + 4.0 * fbm(x * 0.025, z * 0.025, 3)
    h = pit(rr)
    if rr > RIM_R:
        h = 0.0 + 14.0 * smooth(RIM_R + 50, HALF, r) * (0.6 + 0.4 * fbm(x * 0.01, z * 0.01)) \
            + 0.4 * fbm(x * 0.05, z * 0.05)
    if r < RIM_R + 20:
        d, rh = road_at(x, z)
        blend = 1.0 - smooth(ROAD_W / 2, ROAD_W / 2 + 5.0, d)
        if blend > 0:
            h = h + (rh - h) * blend
    if r < RIM_R:
        h += 0.25 * fbm(x * 0.08, z * 0.08, 2)
    return h


def color(x, z, h, slope):
    r = math.hypot(x, z)
    v = 0.5 + 0.5 * fbm(x * 0.07, z * 0.07, 2)
    gravel = (0.62 + 0.06 * v, 0.58 + 0.05 * v, 0.52)
    stone = (0.80, 0.62 + 0.05 * v, 0.42)
    face = (0.66, 0.46, 0.30)
    road = (0.47, 0.40, 0.33)
    grass = (0.38 + 0.1 * v, 0.62 + 0.08 * v, 0.24)

    def mix(a, b, t):
        return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

    c = mix(gravel, stone, smooth(-26, -5, h))
    c = mix(c, face, smooth(0.25, 0.6, slope))
    yard = mix(road, grass, smooth(RIM_R + 25, RIM_R + 55, r))
    c = mix(c, yard, smooth(RIM_R - 2, RIM_R + 4, r))
    if math.hypot(x, z) < RIM_R + 20 and road_at(x, z)[0] < ROAD_W / 2:
        c = (0.55, 0.36, 0.16)          # road mask colour (the shader turns this into dirt road)
    elif yard_road(x, z) < 6.0:
        c = (0.55, 0.36, 0.16)
    return c


bpy.ops.wm.read_factory_settings(use_empty=True)
heights = [[height(-HALF + SIZE * i / (N - 1), -HALF + SIZE * j / (N - 1)) for i in range(N)] for j in range(N)]

mesh = bpy.data.meshes.new("QuarryTerrain")
bm = bmesh.new()
step = SIZE / (N - 1)
verts = [bm.verts.new((-HALF + step * i, HALF - step * j, heights[j][i])) for j in range(N) for i in range(N)]
bm.verts.ensure_lookup_table()
col_layer = bm.loops.layers.color.new("Col")
for j in range(N - 1):
    for i in range(N - 1):
        a, b, c, d = j * N + i, j * N + i + 1, (j + 1) * N + i + 1, (j + 1) * N + i
        bm.faces.new((verts[a], verts[d], verts[c], verts[b]))
bm.normal_update()
for f in bm.faces:
    for loop in f.loops:
        v = loop.vert
        slope = 1.0 - max(0.0, v.normal.z)
        rr, gg, bb = color(v.co.x, -v.co.y, v.co.z, slope * 3.0)
        loop[col_layer] = (rr, gg, bb, 1.0)
bm.to_mesh(mesh)
bm.free()
for poly in mesh.polygons:
    poly.use_smooth = True
mesh.color_attributes.active_color_name = "Col"
mesh.color_attributes.render_color_index = 0
obj = bpy.data.objects.new("QuarryTerrain", mesh)
bpy.context.scene.collection.objects.link(obj)
mat = bpy.data.materials.new("Ground")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes.get("Principled BSDF")
attr = nt.nodes.new("ShaderNodeVertexColor")
attr.layer_name = "Col"
nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 1.0
mesh.materials.append(mat)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(blend_dir, "quarry_terrain.blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "quarry_terrain.glb"), export_format="GLB",
                          export_yup=True, export_vertex_color="NAME", export_vertex_color_name="Col", export_all_vertex_colors=False, export_apply=True)
with open(os.path.join(out, "quarry_heights.bin"), "wb") as fh:
    fh.write(struct.pack("<if", N, SIZE))
    for row in heights:
        fh.write(struct.pack("<%df" % N, *row))
import json
with open(os.path.join(out, "quarry_road.json"), "w") as fh:
    json.dump([[round(p[0], 2), round(p[2], 2), round(p[1], 2)] for p in ROAD[::6]] + [[x, 0.0, z] for x, z in YARD[1:]], fh)
print("TERRAIN OK", min(min(r) for r in heights), max(max(r) for r in heights))
