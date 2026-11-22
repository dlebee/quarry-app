"""Places quarry piles and props around the haul road (run after make_quarry_terrain.py).
   python3 scripts/make_site_layout.py   ->  godot/assets/models/site/{props,piles}.json"""
import json, math, random, os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))
random.seed(7)
road = json.load(open("godot/assets/models/quarry_road.json"))
RIM_R = 107.0


def near_road(x, z, m):
    return any(math.hypot(x - p[0], z - p[2]) < m for p in road)


props = [
    {"file": "office-container.glb", "at": [160, -55], "yaw": 90, "height": 2.8},
    {"file": "office-container-long.glb", "at": [170, -40], "yaw": 0, "height": 2.8},
    {"file": "portable-toilet.glb", "at": [180, -58], "yaw": 180, "height": 2.4},
    {"file": "rubble-skip.glb", "at": [140, -60], "yaw": 20, "height": 1.6},
    {"file": "material-stack.glb", "at": [135, -45], "yaw": 0, "height": 1.5},
    {"file": "container.glb", "at": [185, -20], "yaw": 90, "height": 2.6},
    {"file": "tower-crane-ground.glb", "at": [125, -85], "yaw": 30, "height": 28},
    {"file": "sign.glb", "at": [122, 14], "yaw": 90, "height": 2.2},
    {"file": "barrel.glb", "at": [176, -62], "height": 1.0},
    {"file": "barrel.glb", "at": [177, -63.5], "height": 1.0},
]
for k in range(5):
    props.append({"file": "pipe.glb", "at": [132 + k * 3.2, -30], "height": 2.2})
# Cones on the outer edge of the haul road, barriers on the drop side.
for i, p in enumerate(road[:-3]):
    if i % 3:
        continue
    r = math.hypot(p[0], p[2])
    ux, uz = p[0] / r, p[2] / r
    props.append({"file": "cone.glb", "at": [round(p[0] + ux * 7.5, 1), round(p[2] + uz * 7.5, 1)], "height": 0.9})
    if i % 9 == 0 and r < RIM_R - 5:
        props.append({"file": random.choice(["barrier-plastic.glb", "barrier-wood.glb"]),
                      "at": [round(p[0] - ux * 7.5, 1), round(p[2] - uz * 7.5, 1)],
                      "yaw": round(-math.degrees(math.atan2(uz, ux))), "height": 1.0})
# Stone piles (CC0 rock models) on the benches and the rim, away from the road.
for i in range(30):
    r = random.choice([63, 76, 89, 102, 120, 135])
    a = random.uniform(0, math.tau)
    x, z = math.cos(a) * r, math.sin(a) * r
    if near_road(x, z, 14) or (x > 110 and abs(z) < 70):
        continue
    props.append({"file": random.choice(["LP_B-Rocks_00.glb", "LP_B-Rocks_02.glb", "LP_B-Rocks_04.glb", "rocks-group.glb"]),
                  "at": [round(x, 1), round(z, 1)], "yaw": random.randint(0, 359), "height": round(random.uniform(1.5, 4.0), 1)})
json.dump(props, open("godot/assets/models/site/props.json", "w"), indent=1)

# Diggable piles: dirt, gravel and sand on the floor and the bench shelves.
spots = []
for r, n in [(18, 2), (32, 3), (45, 3), (63, 2), (76, 2), (89, 2), (102, 1)]:
    placed = 0
    for _ in range(60):
        if placed >= n:
            break
        a = random.uniform(0, math.tau)
        x, z = math.cos(a) * r, math.sin(a) * r
        if near_road(x, z, 16) or any(math.hypot(x - s[0], z - s[1]) < 18 for s in spots):
            continue
        spots.append([round(x, 1), round(z, 1), random.choice(["dirt", "dirt", "gravel", "sand"])])
        placed += 1
json.dump(spots, open("godot/assets/models/site/piles.json", "w"))
print(len(props), "props,", len(spots), "piles")
