#!/usr/bin/env python3
"""Generate data/map_geometry.json from data/regions.json.

Offline, stdlib-only, and fully deterministic: a fixed seed drives an FNV-1a
value-noise coastline, every iteration is ordered, and coordinates are
rounded before writing, so rerunning the tool on unchanged inputs produces a
byte-identical file. CI validates the committed output but never regenerates
it. Rerun after editing region positions or adjacency:

    python3 tools/generate_map_geometry.py

Method: each region grows a distance-field blob around its authored position;
capsules along every land adjacency guarantee the corridors between
neighbours; sea-zone anchors carve open water; and a Worley F2-F1 strait rule
forces sea along the midline between regions of *different* landmasses
(connected components of the adjacency graph), so islands never fuse with the
mainland. The resulting scalar field is sampled on a node grid, coastlines
are extracted with marching squares (interpolated for the smooth outline,
midpoint for the per-region cells so neighbouring cells share vertices), and
roads are traced with A* over land nodes so they hug the terrain and never
cross water.
"""
from __future__ import annotations

import heapq
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGIONS_PATH = ROOT / "data" / "regions.json"
OUT_PATH = ROOT / "data" / "map_geometry.json"

SEED = 20260827          # never change casually: the whole coastline moves
GRID = 400               # nodes per axis is GRID + 1
WORLD_MIN, WORLD_MAX = -2.0, 102.0
STEP = (WORLD_MAX - WORLD_MIN) / GRID

BLOB_MIN, BLOB_MAX = 1.8, 6.0    # region blob radius clamp (world units)
BLOB_SHARE = 0.62                # fraction of nearest-neighbour distance
CORRIDOR_CORE = 2.2              # land half-width along adjacency capsules
CORRIDOR_HARD = 1.0              # inner half-width no noise or strait may cut
CORRIDOR_REACH = 3.2             # capsule influence beyond the core
TRIANGLE_FILL = 0.6              # field level inside adjacency triangles
POSITION_CORE = 1.2              # land radius around a position nothing may cut
NOISE_AMP = 1.5                  # coastline wobble
STRAIT_WIDTH = 0.9               # F2-F1 band forced to sea between landmasses
CARVE_RADIUS = 4.5               # open water around sea-zone anchors
CARVE_STRENGTH = 1.2
MIN_ISLAND_NODES = 26            # smaller landmasses are noise, not islands
MAX_POND_AREA_NODES = 2200       # enclosed anchorless seas below this become land
SIMPLIFY_OUTLINE = 0.28          # Douglas-Peucker tolerances (world units)
SIMPLIFY_CELL = 0.30
SIMPLIFY_ROAD = 0.35


# --- deterministic noise ---------------------------------------------------

def _hash01(ix: int, iy: int, salt: int) -> float:
    h = 1469598103934665603
    for v in (SEED, salt, ix & 0xFFFFFFFF, iy & 0xFFFFFFFF):
        h ^= v
        h = (h * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return h / 2.0 ** 64


def _value_noise(x: float, y: float, freq: float, salt: int) -> float:
    fx, fy = x * freq, y * freq
    ix, iy = math.floor(fx), math.floor(fy)
    tx, ty = fx - ix, fy - iy
    sx = tx * tx * (3.0 - 2.0 * tx)
    sy = ty * ty * (3.0 - 2.0 * ty)
    v00 = _hash01(ix, iy, salt)
    v10 = _hash01(ix + 1, iy, salt)
    v01 = _hash01(ix, iy + 1, salt)
    v11 = _hash01(ix + 1, iy + 1, salt)
    top = v00 + (v10 - v00) * sx
    bottom = v01 + (v11 - v01) * sx
    return (top + (bottom - top) * sy) * 2.0 - 1.0


def coast_noise(x: float, y: float) -> float:
    return (0.45 * _value_noise(x, y, 0.055, 4)
            + 0.30 * _value_noise(x, y, 0.11, 1)
            + 0.15 * _value_noise(x, y, 0.22, 2)
            + 0.10 * _value_noise(x, y, 0.44, 3))


# --- small geometry helpers ------------------------------------------------

def node_xy(ix: int, iy: int) -> tuple[float, float]:
    return WORLD_MIN + ix * STEP, WORLD_MIN + iy * STEP


def seg_distance(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    vx, vy = bx - ax, by - ay
    length_sq = vx * vx + vy * vy
    if length_sq == 0.0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / length_sq))
    return math.hypot(px - (ax + t * vx), py - (ay + t * vy))


def simplify(points: list[tuple[float, float]], tolerance: float, closed: bool) -> list[tuple[float, float]]:
    """Douglas-Peucker. Closed loops are anchored at vertex 0 and at the
    vertex farthest from it, then each arc is simplified independently."""
    if len(points) < 3:
        return list(points)

    def dp(part: list[tuple[float, float]]) -> list[tuple[float, float]]:
        if len(part) < 3:
            return list(part)
        ax, ay = part[0]
        bx, by = part[-1]
        worst, worst_index = -1.0, -1
        for i in range(1, len(part) - 1):
            d = seg_distance(part[i][0], part[i][1], ax, ay, bx, by)
            if d > worst:
                worst, worst_index = d, i
        if worst <= tolerance:
            return [part[0], part[-1]]
        left = dp(part[: worst_index + 1])
        right = dp(part[worst_index:])
        return left[:-1] + right

    if not closed:
        return dp(points)
    ax, ay = points[0]
    far, far_index = -1.0, len(points) // 2
    for i, (x, y) in enumerate(points):
        d = (x - ax) ** 2 + (y - ay) ** 2
        if d > far:
            far, far_index = d, i
    first = dp(points[: far_index + 1])
    second = dp(points[far_index:] + [points[0]])
    return first[:-1] + second[:-1]


def signed_area(loop: list[tuple[float, float]]) -> float:
    total = 0.0
    for i in range(len(loop)):
        x0, y0 = loop[i]
        x1, y1 = loop[(i + 1) % len(loop)]
        total += x0 * y1 - x1 * y0
    return total / 2.0


def point_in_loop(x: float, y: float, loop: list[tuple[float, float]]) -> bool:
    inside = False
    for i in range(len(loop)):
        x0, y0 = loop[i]
        x1, y1 = loop[(i + 1) % len(loop)]
        if (y0 > y) != (y1 > y):
            cross = (x1 - x0) * (y - y0) / (y1 - y0) + x0
            if x < cross:
                inside = not inside
    return inside


def loop_centroid(loop: list[tuple[float, float]]) -> tuple[float, float]:
    area = signed_area(loop)
    if abs(area) < 1e-9:
        xs = sum(p[0] for p in loop) / len(loop)
        ys = sum(p[1] for p in loop) / len(loop)
        return xs, ys
    cx = cy = 0.0
    for i in range(len(loop)):
        x0, y0 = loop[i]
        x1, y1 = loop[(i + 1) % len(loop)]
        w = x0 * y1 - x1 * y0
        cx += (x0 + x1) * w
        cy += (y0 + y1) * w
    return cx / (6.0 * area), cy / (6.0 * area)


# --- marching squares ------------------------------------------------------

def marching_squares(sample, iso: float, interpolated: bool) -> list[list[tuple[float, float]]]:
    """Extract closed iso-contours from a (GRID+1)^2 node field. `sample`
    maps (ix, iy) -> float. Segment endpoints live on lattice edges and are
    chained by exact edge identity, so loops close without float matching.
    Midpoint mode (interpolated=False) puts every crossing at the edge
    centre, which makes touching contours from different masks share
    vertices exactly."""

    def edge_point(ix0: int, iy0: int, ix1: int, iy1: int) -> tuple[float, float]:
        x0, y0 = node_xy(ix0, iy0)
        x1, y1 = node_xy(ix1, iy1)
        if not interpolated:
            return (x0 + x1) / 2.0, (y0 + y1) / 2.0
        v0 = sample(ix0, iy0)
        v1 = sample(ix1, iy1)
        t = 0.5 if v1 == v0 else max(0.04, min(0.96, (iso - v0) / (v1 - v0)))
        return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t

    # An edge id is (min_node, "h"|"v"): the lattice edge a crossing sits on.
    segments: list[tuple[tuple, tuple]] = []
    for iy in range(GRID):
        for ix in range(GRID):
            corners = (sample(ix, iy), sample(ix + 1, iy),
                       sample(ix + 1, iy + 1), sample(ix, iy + 1))
            case = ((1 if corners[0] > iso else 0)
                    | (2 if corners[1] > iso else 0)
                    | (4 if corners[2] > iso else 0)
                    | (8 if corners[3] > iso else 0))
            if case in (0, 15):
                continue
            top = ((ix, iy), "h")
            right = ((ix + 1, iy), "v")
            bottom = ((ix, iy + 1), "h")
            left = ((ix, iy), "v")
            table = {
                1: [(left, top)], 2: [(top, right)], 3: [(left, right)],
                4: [(right, bottom)], 6: [(top, bottom)], 7: [(left, bottom)],
                8: [(bottom, left)], 9: [(bottom, top)], 11: [(bottom, right)],
                12: [(right, left)], 13: [(right, top)], 14: [(top, left)],
            }
            if case == 5:
                centre = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
                table[5] = [(left, top), (right, bottom)] if centre > iso \
                    else [(left, bottom), (right, top)]
                pairs = table[5]
            elif case == 10:
                centre = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
                pairs = [(top, right), (bottom, left)] if centre > iso \
                    else [(top, left), (bottom, right)]
            else:
                pairs = table[case]
            segments.extend(pairs)

    coords: dict[tuple, tuple[float, float]] = {}

    def coord_of(edge_id: tuple) -> tuple[float, float]:
        if edge_id not in coords:
            (ix, iy), kind = edge_id
            if kind == "h":
                coords[edge_id] = edge_point(ix, iy, ix + 1, iy)
            else:
                coords[edge_id] = edge_point(ix, iy, ix, iy + 1)
        return coords[edge_id]

    links: dict[tuple, list[tuple]] = {}
    for a, b in segments:
        links.setdefault(a, []).append(b)
        links.setdefault(b, []).append(a)

    # Every crossing point sits on one lattice edge and joins exactly two
    # segments, so loops chain uniquely; marking both directions of each
    # traversed pair emits every loop exactly once.
    visited: set[tuple[tuple, tuple]] = set()
    loops: list[list[tuple[float, float]]] = []
    for start in sorted(links):
        for first in sorted(links[start]):
            if (start, first) in visited:
                continue
            loop_ids = [start]
            previous, current = start, first
            visited.add((start, first))
            visited.add((first, start))
            closed = True
            while current != start:
                loop_ids.append(current)
                nexts = [n for n in sorted(links.get(current, [])) if n != previous]
                if not nexts:
                    closed = False  # cannot happen on a sealed field
                    break
                visited.add((current, nexts[0]))
                visited.add((nexts[0], current))
                previous, current = current, nexts[0]
            if closed and len(loop_ids) >= 3:
                loops.append([coord_of(e) for e in loop_ids])
    return loops


# --- main ------------------------------------------------------------------

def main() -> int:
    document = json.loads(REGIONS_PATH.read_text())
    regions = document["regions"]
    zones = document["sea_zones"]
    ids = [r["id"] for r in regions]
    index_of = {rid: i for i, rid in enumerate(ids)}
    px = [float(r["position"]["x"]) for r in regions]
    py = [float(r["position"]["y"]) for r in regions]

    # Landmass components over land adjacency.
    component = list(range(len(regions)))

    def find(i: int) -> int:
        while component[i] != i:
            component[i] = component[component[i]]
            i = component[i]
        return i

    adjacency_pairs: list[tuple[int, int]] = []
    for r in regions:
        a = index_of[r["id"]]
        for neighbour in r["adjacent"]:
            b = index_of[neighbour]
            if a < b:
                adjacency_pairs.append((a, b))
            component[find(a)] = find(b)
    component = [find(i) for i in range(len(regions))]
    adjacency_pairs.sort()

    # Blob radius per region from nearest-neighbour spacing.
    radius = []
    for i in range(len(regions)):
        nearest = min(math.hypot(px[i] - px[j], py[i] - py[j])
                      for j in range(len(regions)) if j != i)
        radius.append(max(BLOB_MIN, min(BLOB_MAX, BLOB_SHARE * nearest)))

    nodes = GRID + 1
    base = [[-4.0] * nodes for _ in range(nodes)]

    def touch_box(x0: float, y0: float, x1: float, y1: float, margin: float):
        ix0 = max(0, int((min(x0, x1) - margin - WORLD_MIN) / STEP))
        ix1 = min(GRID, int((max(x0, x1) + margin - WORLD_MIN) / STEP) + 1)
        iy0 = max(0, int((min(y0, y1) - margin - WORLD_MIN) / STEP))
        iy1 = min(GRID, int((max(y0, y1) + margin - WORLD_MIN) / STEP) + 1)
        return ix0, ix1, iy0, iy1

    hardcore = [[-4.0] * nodes for _ in range(nodes)]
    for i in range(len(regions)):
        reach = radius[i] + NOISE_AMP + 1.0
        ix0, ix1, iy0, iy1 = touch_box(px[i], py[i], px[i], py[i], reach)
        for iy in range(iy0, iy1 + 1):
            y = WORLD_MIN + iy * STEP
            row = base[iy]
            core_row = hardcore[iy]
            for ix in range(ix0, ix1 + 1):
                x = WORLD_MIN + ix * STEP
                d = math.hypot(x - px[i], y - py[i])
                value = radius[i] - d
                if value > row[ix]:
                    row[ix] = value
                if POSITION_CORE - d > core_row[ix]:
                    core_row[ix] = POSITION_CORE - d

    corridor = [[-4.0] * nodes for _ in range(nodes)]
    for a, b in adjacency_pairs:
        ix0, ix1, iy0, iy1 = touch_box(px[a], py[a], px[b], py[b], CORRIDOR_REACH + 0.5)
        for iy in range(iy0, iy1 + 1):
            y = WORLD_MIN + iy * STEP
            row = corridor[iy]
            base_row = base[iy]
            for ix in range(ix0, ix1 + 1):
                x = WORLD_MIN + ix * STEP
                d = seg_distance(x, y, px[a], py[a], px[b], py[b])
                value = CORRIDOR_CORE - d
                if value > row[ix]:
                    row[ix] = value
                if value > base_row[ix]:
                    base_row[ix] = value  # corridors are coastline too

    # Adjacency triangles (three regions all pairwise adjacent) are compact
    # patches of solid interior land — this is what turns a net of blobs and
    # isthmuses into continents. Sea gulfs survive because no adjacency
    # crosses them, so no triangle can span them either.
    adjacency_set = set(adjacency_pairs)
    for a, b in adjacency_pairs:
        for c in range(max(a, b) + 1, len(regions)):
            if (a, c) in adjacency_set and (b, c) in adjacency_set:
                ix0, ix1, iy0, iy1 = touch_box(
                    min(px[a], px[b], px[c]), min(py[a], py[b], py[c]),
                    max(px[a], px[b], px[c]), max(py[a], py[b], py[c]), 0.3)
                d0x, d0y = px[b] - px[a], py[b] - py[a]
                d1x, d1y = px[c] - px[a], py[c] - py[a]
                denominator = d0x * d1y - d1x * d0y
                if abs(denominator) < 1e-9:
                    continue
                for iy in range(iy0, iy1 + 1):
                    y = WORLD_MIN + iy * STEP
                    base_row = base[iy]
                    for ix in range(ix0, ix1 + 1):
                        if base_row[ix] >= TRIANGLE_FILL:
                            continue
                        x = WORLD_MIN + ix * STEP
                        wx, wy = x - px[a], y - py[a]
                        u = (wx * d1y - d1x * wy) / denominator
                        v = (d0x * wy - wx * d0y) / denominator
                        if u >= -0.02 and v >= -0.02 and u + v <= 1.02:
                            base_row[ix] = TRIANGLE_FILL

    carve = [[0.0] * nodes for _ in range(nodes)]
    for zone in zones:
        position = zone.get("position")
        if not position:
            continue
        zx, zy = float(position["x"]), float(position["y"])
        ix0, ix1, iy0, iy1 = touch_box(zx, zy, zx, zy, CARVE_RADIUS)
        for iy in range(iy0, iy1 + 1):
            y = WORLD_MIN + iy * STEP
            row = carve[iy]
            for ix in range(ix0, ix1 + 1):
                x = WORLD_MIN + ix * STEP
                d = math.hypot(x - zx, y - zy)
                if d < CARVE_RADIUS:
                    value = CARVE_STRENGTH * (1.0 - d / CARVE_RADIUS)
                    if value > row[ix]:
                        row[ix] = value

    # Final scalar field + nearest-region assignment where it matters.
    field = [[-4.0] * nodes for _ in range(nodes)]
    nearest = [[-1] * nodes for _ in range(nodes)]
    for iy in range(nodes):
        y = WORLD_MIN + iy * STEP
        for ix in range(nodes):
            value = base[iy][ix]
            if value > -2.5:
                value = value + NOISE_AMP * coast_noise(*node_xy(ix, iy)) - carve[iy][ix]
            if value > -1.5 or corridor[iy][ix] > -1.0:
                x = WORLD_MIN + ix * STEP
                best = second = 1e18
                best_i = second_i = -1
                for i in range(len(regions)):
                    d = (x - px[i]) ** 2 + (y - py[i]) ** 2
                    if d < best:
                        second, second_i = best, best_i
                        best, best_i = d, i
                    elif d < second:
                        second, second_i = d, i
                nearest[iy][ix] = best_i
                if (second_i >= 0 and component[best_i] != component[second_i]
                        and math.sqrt(second) - math.sqrt(best) < STRAIT_WIDTH):
                    value = min(value, -0.6)  # strait between landmasses
            hard = corridor[iy][ix] - (CORRIDOR_CORE - CORRIDOR_HARD)
            if hardcore[iy][ix] > hard:
                hard = hardcore[iy][ix]
            if hard > 0.0:
                value = max(value, min(0.5, hard))  # nothing may cut a core
            field[iy][ix] = value

    # The outermost node ring is always sea, so every contour closes inside
    # the grid instead of running off the edge as an open chain.
    for i in range(nodes):
        field[0][i] = min(field[0][i], -0.3)
        field[GRID][i] = min(field[GRID][i], -0.3)
        field[i][0] = min(field[i][0], -0.3)
        field[i][GRID] = min(field[i][GRID], -0.3)

    land = [[field[iy][ix] > 0.0 for ix in range(nodes)] for iy in range(nodes)]

    # Noise leaves speckle islets; drown any land component too small to be a
    # real island unless it holds a region position (field and mask both, so
    # outlines, cells and roads all agree).
    position_nodes = {(round((px[i] - WORLD_MIN) / STEP), round((py[i] - WORLD_MIN) / STEP))
                      for i in range(len(regions))}
    seen = [[False] * nodes for _ in range(nodes)]
    for start_y in range(nodes):
        for start_x in range(nodes):
            if not land[start_y][start_x] or seen[start_y][start_x]:
                continue
            stack = [(start_x, start_y)]
            seen[start_y][start_x] = True
            patch = []
            keep = False
            while stack:
                cx, cy = stack.pop()
                patch.append((cx, cy))
                if (cx, cy) in position_nodes:
                    keep = True
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    mx, my = cx + dx, cy + dy
                    if 0 <= mx <= GRID and 0 <= my <= GRID \
                            and land[my][mx] and not seen[my][mx]:
                        seen[my][mx] = True
                        stack.append((mx, my))
            if not keep and len(patch) < MIN_ISLAND_NODES:
                for cx, cy in patch:
                    land[cy][cx] = False
                    field[cy][cx] = -0.2

    # Continental interiors trap "ponds": sea pockets the adjacency graph
    # encircles without crossing (mid-Gaul, inner Anatolia). A sea component
    # that never reaches the map border, holds no sea-zone anchor, and is
    # small becomes land; real enclosed seas keep their anchors and size.
    anchor_nodes = set()
    for zone in zones:
        position = zone.get("position")
        if position:
            anchor_nodes.add((round((float(position["x"]) - WORLD_MIN) / STEP),
                              round((float(position["y"]) - WORLD_MIN) / STEP)))
    sea_seen = [[False] * nodes for _ in range(nodes)]
    for start_y in range(nodes):
        for start_x in range(nodes):
            if land[start_y][start_x] or sea_seen[start_y][start_x]:
                continue
            stack = [(start_x, start_y)]
            sea_seen[start_y][start_x] = True
            patch = []
            keep = False
            while stack:
                cx, cy = stack.pop()
                patch.append((cx, cy))
                if cx in (0, GRID) or cy in (0, GRID) or (cx, cy) in anchor_nodes:
                    keep = True
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    mx, my = cx + dx, cy + dy
                    if 0 <= mx <= GRID and 0 <= my <= GRID \
                            and not land[my][mx] and not sea_seen[my][mx]:
                        sea_seen[my][mx] = True
                        stack.append((mx, my))
            if not keep and len(patch) < MAX_POND_AREA_NODES:
                for cx, cy in patch:
                    land[cy][cx] = True
                    field[cy][cx] = 0.25

    # Cell ownership is geodesic, not Euclidean: a multi-source Dijkstra over
    # land nodes from every region position. Water blocks the flood, so a
    # region can never own a scrap of the far shore of a strait the way a
    # straight-line Voronoi does.
    owner_grid = [[-1] * nodes for _ in range(nodes)]
    flood: list[tuple[float, int, int, int]] = []
    for i in range(len(regions)):
        ix = round((px[i] - WORLD_MIN) / STEP)
        iy = round((py[i] - WORLD_MIN) / STEP)
        heapq.heappush(flood, (0.0, i, ix, iy))
    flood_cost = {}
    diagonal = math.sqrt(2.0)
    while flood:
        cost, i, ix, iy = heapq.heappop(flood)
        if flood_cost.get((ix, iy), 1e18) < cost:
            continue
        owner_grid[iy][ix] = i
        for dx, dy in ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)):
            mx, my = ix + dx, iy + dy
            if not (0 <= mx <= GRID and 0 <= my <= GRID) or not land[my][mx]:
                continue
            step = diagonal if dx and dy else 1.0
            candidate = cost + step
            if candidate < flood_cost.get((mx, my), 1e18) - 1e-9:
                flood_cost[(mx, my)] = candidate
                heapq.heappush(flood, (candidate, i, mx, my))
    nearest = owner_grid

    # Every region's own node must be land and owned by itself.
    for i, rid in enumerate(ids):
        ix = round((px[i] - WORLD_MIN) / STEP)
        iy = round((py[i] - WORLD_MIN) / STEP)
        if not land[iy][ix]:
            print(f"ERROR: {rid}: position node fell into the sea — tune constants", file=sys.stderr)
            return 1
        if nearest[iy][ix] != i:
            print(f"ERROR: {rid}: position node owned by {ids[nearest[iy][ix]]}", file=sys.stderr)
            return 1

    # --- landmass outlines -------------------------------------------------
    raw_loops = marching_squares(lambda ix, iy: field[iy][ix], 0.0, True)
    loops = []
    for loop in raw_loops:
        slim = simplify(loop, SIMPLIFY_OUTLINE, True)
        if len(slim) >= 3 and abs(signed_area(slim)) > 0.15:
            loops.append(slim)
    loops.sort(key=lambda lp: -abs(signed_area(lp)))
    landmasses = []
    hole_of: dict[int, int] = {}
    for i, loop in enumerate(loops):
        depth = 0
        parent = -1
        x, y = loop[0]
        for j in range(i):
            if point_in_loop(x, y, loops[j]):
                depth += 1
                if parent == -1 or point_in_loop(loops[j][0][0], loops[j][0][1], loops[parent]):
                    parent = j
        if depth % 2 == 0:
            hole_of[i] = -1
            landmasses.append({"outline": loop, "holes": []})
        else:
            hole_of[i] = parent
    outline_index = {}
    count = 0
    for i, loop in enumerate(loops):
        if hole_of.get(i) == -1:
            outline_index[i] = count
            count += 1
    for i, loop in enumerate(loops):
        parent = hole_of.get(i, -1)
        if parent != -1 and parent in outline_index:
            landmasses[outline_index[parent]]["holes"].append(loop)

    # --- per-region cells --------------------------------------------------
    cells = []
    for i, rid in enumerate(ids):
        def cell_sample(ix: int, iy: int, i=i) -> float:
            return 1.0 if land[iy][ix] and nearest[iy][ix] == i else 0.0

        polygons = []
        raw = marching_squares(cell_sample, 0.5, False)
        raw.sort(key=lambda lp: -abs(signed_area(lp)))
        keep = []
        for loop in raw:
            x, y = loop[0]
            depth = sum(1 for other in keep if point_in_loop(x, y, other))
            if depth % 2 == 0:  # holes in a cell are sea; drop them
                keep.append(loop)
        for loop in keep:
            slim = simplify(loop, SIMPLIFY_CELL, True)
            if len(slim) >= 3 and abs(signed_area(slim)) > 0.1:
                polygons.append(slim)
        if not polygons:
            print(f"ERROR: {rid}: no cell polygon survived — tune constants", file=sys.stderr)
            return 1
        label = loop_centroid(max(polygons, key=lambda lp: abs(signed_area(lp))))
        if not any(point_in_loop(label[0], label[1], lp) for lp in polygons):
            label = (px[i], py[i])
        cells.append({"region": rid, "label": label, "polygons": polygons})

    # --- roads: A* over land nodes ------------------------------------------
    def astar(a: int, b: int):
        start = (round((px[a] - WORLD_MIN) / STEP), round((py[a] - WORLD_MIN) / STEP))
        goal = (round((px[b] - WORLD_MIN) / STEP), round((py[b] - WORLD_MIN) / STEP))
        open_heap = [(0.0, start)]
        best_cost = {start: 0.0}
        came: dict[tuple, tuple] = {}
        moves = [(-1, -1, math.sqrt(2)), (0, -1, 1.0), (1, -1, math.sqrt(2)),
                 (-1, 0, 1.0), (1, 0, 1.0),
                 (-1, 1, math.sqrt(2)), (0, 1, 1.0), (1, 1, math.sqrt(2))]
        while open_heap:
            _, current = heapq.heappop(open_heap)
            if current == goal:
                path = [current]
                while current in came:
                    current = came[current]
                    path.append(current)
                path.reverse()
                return path
            cx, cy = current
            for dx, dy, cost in moves:
                nx, ny = cx + dx, cy + dy
                if not (0 <= nx <= GRID and 0 <= ny <= GRID) or not land[ny][nx]:
                    continue
                candidate = best_cost[current] + cost
                if candidate < best_cost.get((nx, ny), 1e18) - 1e-9:
                    best_cost[(nx, ny)] = candidate
                    came[(nx, ny)] = current
                    priority = candidate + math.hypot(nx - goal[0], ny - goal[1])
                    heapq.heappush(open_heap, (priority, (nx, ny)))
        return None

    edges = []
    for a, b in adjacency_pairs:
        node_path = astar(a, b)
        if node_path is None:
            print(f"ERROR: no land route {ids[a]} -> {ids[b]} — corridor severed", file=sys.stderr)
            return 1
        points = [node_xy(ix, iy) for ix, iy in node_path]
        slim = simplify(points, SIMPLIFY_ROAD, False)
        slim[0] = (px[a], py[a])
        slim[-1] = (px[b], py[b])
        edges.append({"a": ids[a], "b": ids[b], "path": slim})

    # --- write, rounded and sorted, byte-stable -----------------------------
    def rounded(points):
        out = []
        for x, y in points:
            p = [round(x + 0.0, 2) + 0.0, round(y + 0.0, 2) + 0.0]
            if not out or out[-1] != p:
                out.append(p)
        if len(out) > 1 and out[0] == out[-1]:
            out.pop()
        return out

    payload = {
        "$schema": "../schemas/map_geometry.schema.json",
        "meta": {
            "bounds": {"max": WORLD_MAX, "min": WORLD_MIN},
            "generator": "tools/generate_map_geometry.py",
            "grid": GRID,
            "seed": SEED,
        },
        "landmasses": [
            {"outline": rounded(m["outline"]),
             "holes": [rounded(h) for h in m["holes"] if len(rounded(h)) >= 3]}
            for m in landmasses if len(rounded(m["outline"])) >= 3
        ],
        "cells": [
            {"region": c["region"],
             "label": [round(c["label"][0], 2) + 0.0, round(c["label"][1], 2) + 0.0],
             "polygons": [p for p in (rounded(lp) for lp in c["polygons"]) if len(p) >= 3]}
            for c in cells
        ],
        "edges": [{"a": e["a"], "b": e["b"], "path": rounded(e["path"])} for e in edges],
    }
    OUT_PATH.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
    total_points = sum(len(c["polygons"][0]) for c in payload["cells"])
    print(f"wrote {OUT_PATH.name}: {len(payload['landmasses'])} landmasses, "
          f"{len(payload['cells'])} cells, {len(payload['edges'])} edges "
          f"({OUT_PATH.stat().st_size // 1024} KiB, ~{total_points} cell points)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
