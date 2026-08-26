#!/usr/bin/env python3
"""Generate data/map_geometry.json — coastlines, per-region province cells and
road paths — from the region positions and graphs in data/regions.json.

The map data itself stays authoritative: this tool only synthesizes *shapes*
around it, deterministically (fixed seed, hash-based noise, no random module),
so re-running with the same seed reproduces the committed file byte for byte.

    python3 tools/generate_map_geometry.py            # regenerate
    python3 tools/generate_map_geometry.py --preview  # ASCII sanity view

Algorithm, all on a GRID x GRID raster of the 0-100 map space:
 1. A distance-field blob around every region position (radius scaled from
    its nearest land neighbour), roughened by seeded value noise and carved
    by sea-zone anchors, thresholded into a land mask.
 2. A Worley F2-F1 strait rule forces sea between different land-adjacency
    components, so islands can never fuse to the mainland.
 3. Repairs: every region position is stamped onto land, every land-adjacent
    pair gets a corridor if its blobs did not already touch, stray islets
    are dropped and enclosed lakes filled — the mask ends up honouring the
    adjacency graph exactly.
 4. Land cells are assigned to their nearest region (a Voronoi restricted to
    land); boundary tracing + Douglas-Peucker turns masks into polygons.
 5. Roads: a grid Dijkstra over land, noise-weighted so they meander, for
    each of the land-adjacent pairs.
"""
from __future__ import annotations

import argparse
import heapq
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

GRID = 400
WORLD = 100.0
H = WORLD / GRID

SEED = 20260825
LAND_THRESHOLD = 0.15
NOISE_AMP = 0.35            # coast raggedness, faded out over open sea
NOISE_WAVELENGTH = 5.0      # base feature size of the coast noise, world units
BLOB_SCALE = 1.0            # blob radius as a fraction of nearest-neighbour distance
BLOB_MIN, BLOB_MAX = 4.5, 13.0
ISLAND_SCALE = 0.45         # islands (no land neighbours) scale off any-region distance
ISLAND_MIN, ISLAND_MAX = 3.5, 6.5
CAPSULE_SCALE = 0.30        # land capsules along adjacency edges, radius vs length
CAPSULE_MIN, CAPSULE_MAX = 2.2, 8.0
CARVE_STRENGTH = 1.5        # sea-zone anchors push the coast back this hard
CARVE_SCALE = 0.95          # ...within this fraction of their clearance
CHANNEL_WIDTH = 1.2         # forced strait where distant provinces nearly touch
CHANNEL_MAX_HOPS = 3        # provinces further apart than this by land get one
STAMP_RADIUS = 1.6          # land disc guaranteed around every region position
CORRIDOR_RADIUS = 0.8       # half-width of a repaired land corridor
MIN_ISLET_AREA = 0.5        # square units; smaller stray islets are dropped
SIMPLIFY_CELL = 0.12
SIMPLIFY_COAST = 0.12
SIMPLIFY_ROAD = 0.30
ROAD_NOISE = 0.6            # roads pay up to this much extra per cell


# --- deterministic noise ----------------------------------------------------

def _fnv(*values: int) -> int:
    h = 0x811C9DC5
    for value in values:
        value &= 0xFFFFFFFF
        for shift in (0, 8, 16, 24):
            h ^= (value >> shift) & 0xFF
            h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def _rand01(*values: int) -> float:
    return _fnv(*values) / 4294967296.0


def _value_noise(x: float, y: float, freq: float, octave: int, seed: int) -> float:
    fx, fy = x * freq, y * freq
    ix, iy = math.floor(fx), math.floor(fy)
    tx, ty = fx - ix, fy - iy
    sx = tx * tx * (3.0 - 2.0 * tx)
    sy = ty * ty * (3.0 - 2.0 * ty)
    c00 = _rand01(ix, iy, octave, seed)
    c10 = _rand01(ix + 1, iy, octave, seed)
    c01 = _rand01(ix, iy + 1, octave, seed)
    c11 = _rand01(ix + 1, iy + 1, octave, seed)
    top = c00 * (1.0 - sx) + c10 * sx
    bottom = c01 * (1.0 - sx) + c11 * sx
    return top * (1.0 - sy) + bottom * sy


def fbm(x: float, y: float, seed: int) -> float:
    """Three octaves of value noise in [0, 1]."""
    total, amplitude, norm = 0.0, 1.0, 0.0
    freq = 1.0 / NOISE_WAVELENGTH
    for octave in range(3):
        total += amplitude * _value_noise(x, y, freq, octave, seed)
        norm += amplitude
        amplitude *= 0.5
        freq *= 2.0
    return total / norm


# --- small geometry helpers -------------------------------------------------

def simplify(points: list[tuple[float, float]], epsilon: float) -> list[tuple[float, float]]:
    """Douglas-Peucker on an open polyline."""
    if len(points) < 3:
        return list(points)
    ax, ay = points[0]
    bx, by = points[-1]
    dx, dy = bx - ax, by - ay
    length_sq = dx * dx + dy * dy
    worst, worst_dist = 0, -1.0
    for i in range(1, len(points) - 1):
        px, py = points[i]
        if length_sq < 1e-12:
            dist = math.hypot(px - ax, py - ay)
        else:
            t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_sq))
            dist = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
        if dist > worst_dist:
            worst, worst_dist = i, dist
    if worst_dist <= epsilon:
        return [points[0], points[-1]]
    left = simplify(points[: worst + 1], epsilon)
    right = simplify(points[worst:], epsilon)
    return left[:-1] + right


def simplify_ring(ring: list[tuple[float, float]], epsilon: float) -> list[tuple[float, float]]:
    """Douglas-Peucker on a closed ring (first point NOT repeated at the end).
    Anchored at the two most distant-from-centroid vertices for stability."""
    if len(ring) < 4:
        return list(ring)
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    anchor = max(range(len(ring)), key=lambda i: ((ring[i][0] - cx) ** 2 + (ring[i][1] - cy) ** 2, -i))
    rotated = ring[anchor:] + ring[:anchor]
    closed = rotated + [rotated[0]]
    out = simplify(closed, epsilon)
    if len(out) > 1 and out[0] == out[-1]:
        out = out[:-1]
    return out


def chaikin_ring(ring: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """One round of Chaikin corner cutting on a closed ring — turns the raster
    staircase into organic curves before simplification thins it."""
    out: list[tuple[float, float]] = []
    for i in range(len(ring)):
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % len(ring)]
        out.append((0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by))
        out.append((0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by))
    return out


def chaikin_line(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Chaikin corner cutting on an open polyline, endpoints pinned."""
    if len(points) < 3:
        return list(points)
    out = [points[0]]
    for i in range(len(points) - 1):
        ax, ay = points[i]
        bx, by = points[i + 1]
        out.append((0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by))
        out.append((0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by))
    out.append(points[-1])
    return out


def ring_area(ring: list[tuple[float, float]]) -> float:
    """Signed shoelace area (y grows southward, so sign is orientation only)."""
    total = 0.0
    for i in range(len(ring)):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % len(ring)]
        total += x1 * y2 - x2 * y1
    return total / 2.0


# --- mask -> polygons -------------------------------------------------------

def trace_boundaries(cells: set[int]) -> list[list[tuple[float, float]]]:
    """Directed boundary edges of a cell set, chained into closed loops with
    land kept on the left; at saddle corners the sharpest right turn wins so
    diagonally-touching blobs stay separate rings."""
    edges: dict[tuple[int, int], list[tuple[int, int]]] = {}

    def add(start: tuple[int, int], end: tuple[int, int]) -> None:
        edges.setdefault(start, []).append(end)

    for idx in cells:
        j, i = divmod(idx, GRID)
        if j == 0 or (idx - GRID) not in cells:      # north edge, walk west
            add((i + 1, j), (i, j))
        if j == GRID - 1 or (idx + GRID) not in cells:  # south edge, walk east
            add((i, j + 1), (i + 1, j + 1))
        if i == 0 or (idx - 1) not in cells:         # west edge, walk south
            add((i, j), (i, j + 1))
        if i == GRID - 1 or (idx + 1) not in cells:  # east edge, walk north
            add((i + 1, j + 1), (i + 1, j))

    loops: list[list[tuple[float, float]]] = []
    while edges:
        start = min(edges)
        loop_corners = [start]
        current = start
        incoming = (0, 0)
        while True:
            options = edges[current]
            if len(options) == 1:
                chosen = options[0]
            else:
                # Prefer the rightmost turn relative to the incoming direction.
                def turn_rank(candidate: tuple[int, int]) -> tuple[float, tuple[int, int]]:
                    dx, dy = candidate[0] - current[0], candidate[1] - current[1]
                    cross = incoming[0] * dy - incoming[1] * dx
                    dot = incoming[0] * dx + incoming[1] * dy
                    return (math.atan2(cross, dot), candidate)
                chosen = min(options, key=turn_rank)
            options.remove(chosen)
            if not options:
                del edges[current]
            incoming = (chosen[0] - current[0], chosen[1] - current[1])
            current = chosen
            if current == start:
                break
            loop_corners.append(current)
        loops.append([(x * H, y * H) for x, y in loop_corners])
    return loops


# --- main pipeline ----------------------------------------------------------

def build(seed: int, preview: bool) -> dict:
    regions_doc = json.loads((ROOT / "data" / "regions.json").read_text())
    regions = sorted(regions_doc["regions"], key=lambda r: r["id"])
    sea_zones = regions_doc.get("sea_zones", [])
    ids = [r["id"] for r in regions]
    index_of = {rid: k for k, rid in enumerate(ids)}
    pos = [(float(r["position"]["x"]), float(r["position"]["y"])) for r in regions]
    adjacency = [[index_of[n] for n in r.get("adjacent", []) if n in index_of] for r in regions]
    pairs = sorted({tuple(sorted((k, n))) for k, neighbours in enumerate(adjacency) for n in neighbours})

    # Land components of the adjacency graph (islands are their own).
    group = list(range(len(regions)))

    def find(k: int) -> int:
        while group[k] != k:
            group[k] = group[group[k]]
            k = group[k]
        return k

    for a, b in pairs:
        group[find(a)] = find(b)
    group = [find(k) for k in range(len(regions))]

    # All-pairs BFS hop counts over land adjacency (-1 = unreachable): the
    # strait rule below separates provinces that are near in space but far by
    # land — if you cannot march there in a few days, water lies between.
    hops = [[-1] * len(regions) for _ in regions]
    for origin in range(len(regions)):
        hops[origin][origin] = 0
        frontier = [origin]
        while frontier:
            nxt = []
            for k in frontier:
                for n in adjacency[k]:
                    if hops[origin][n] < 0:
                        hops[origin][n] = hops[origin][k] + 1
                        nxt.append(n)
            frontier = nxt

    # Blob radii from nearest neighbours; lone islands scale off the nearest
    # region of any kind and stay deliberately smaller than mainland blobs.
    radii = []
    for k in range(len(regions)):
        near = [math.dist(pos[k], pos[n]) for n in adjacency[k]]
        if near:
            radii.append(max(BLOB_MIN, min(BLOB_MAX, BLOB_SCALE * min(near))))
        else:
            nearest_any = min(math.dist(pos[k], pos[n]) for n in range(len(regions)) if n != k)
            radii.append(max(ISLAND_MIN, min(ISLAND_MAX, ISLAND_SCALE * nearest_any)))

    total = GRID * GRID
    field = [0.0] * total
    for k, (px, py) in enumerate(pos):
        radius = radii[k]
        i0 = max(0, int((px - radius) / H))
        i1 = min(GRID - 1, int((px + radius) / H))
        j0 = max(0, int((py - radius) / H))
        j1 = min(GRID - 1, int((py + radius) / H))
        inv = 1.0 / radius
        for j in range(j0, j1 + 1):
            cy = (j + 0.5) * H
            row = j * GRID
            for i in range(i0, i1 + 1):
                cx = (i + 0.5) * H
                t = math.hypot(cx - px, cy - py) * inv
                if t < 1.0:
                    # Metaball union: falloffs SUM, so chains of provinces
                    # merge into continents instead of beaded archipelagos.
                    field[row + i] += (1.0 - t) * (1.0 - t)

    # Land capsules along every adjacency edge: the continent is the graph
    # made flesh — solid along the marching routes, bays where no road runs.
    for a, b in pairs:
        ax, ay = pos[a]
        bx, by = pos[b]
        ex, ey = bx - ax, by - ay
        length_sq = ex * ex + ey * ey
        radius = max(CAPSULE_MIN, min(CAPSULE_MAX, CAPSULE_SCALE * math.sqrt(length_sq)))
        i0 = max(0, int((min(ax, bx) - radius) / H))
        i1 = min(GRID - 1, int((max(ax, bx) + radius) / H))
        j0 = max(0, int((min(ay, by) - radius) / H))
        j1 = min(GRID - 1, int((max(ay, by) + radius) / H))
        inv = 1.0 / radius
        for j in range(j0, j1 + 1):
            cy = (j + 0.5) * H
            row = j * GRID
            for i in range(i0, i1 + 1):
                cx = (i + 0.5) * H
                t = 0.0 if length_sq < 1e-12 else max(0.0, min(1.0, ((cx - ax) * ex + (cy - ay) * ey) / length_sq))
                d = math.hypot(cx - (ax + t * ex), cy - (ay + t * ey)) * inv
                if d < 1.0:
                    field[row + i] += (1.0 - d) * (1.0 - d)

    # Sea-zone anchors carve gulfs and open water — as points, and as capsules
    # along the sea-zone adjacency graph so elongated seas (an Adriatic, an
    # Aegean) stay open water down their whole length.
    carve = [0.0] * total
    anchors: dict[str, tuple[float, float]] = {}
    clearances: dict[str, float] = {}
    for zone in sea_zones:
        anchor = zone.get("position")
        if not anchor:
            continue
        zx, zy = float(anchor["x"]), float(anchor["y"])
        anchors[zone["id"]] = (zx, zy)
        clearances[zone["id"]] = min(math.hypot(zx - px, zy - py) for px, py in pos)

    def carve_capsule(ax: float, ay: float, bx: float, by: float, radius: float) -> None:
        ex, ey = bx - ax, by - ay
        length_sq = ex * ex + ey * ey
        i0 = max(0, int((min(ax, bx) - radius) / H))
        i1 = min(GRID - 1, int((max(ax, bx) + radius) / H))
        j0 = max(0, int((min(ay, by) - radius) / H))
        j1 = min(GRID - 1, int((max(ay, by) + radius) / H))
        inv = 1.0 / radius
        for j in range(j0, j1 + 1):
            cy = (j + 0.5) * H
            row = j * GRID
            for i in range(i0, i1 + 1):
                cx = (i + 0.5) * H
                t = 0.0 if length_sq < 1e-12 else max(0.0, min(1.0, ((cx - ax) * ex + (cy - ay) * ey) / length_sq))
                d = math.hypot(cx - (ax + t * ex), cy - (ay + t * ey)) * inv
                if d < 1.0:
                    f = (1.0 - d) * (1.0 - d)
                    if f > carve[row + i]:
                        carve[row + i] = f

    for zone_id, (zx, zy) in anchors.items():
        carve_capsule(zx, zy, zx, zy, max(2.0, CARVE_SCALE * clearances[zone_id]))
    carved_lanes = set()
    for zone in sea_zones:
        if zone["id"] not in anchors:
            continue
        for other in zone.get("adjacent", []):
            if other not in anchors:
                continue
            lane = tuple(sorted((zone["id"], other)))
            if lane in carved_lanes:
                continue
            carved_lanes.add(lane)
            ax, ay = anchors[zone["id"]]
            bx, by = anchors[other]
            radius = max(2.0, CARVE_SCALE * min(clearances[zone["id"]], clearances[other]))
            carve_capsule(ax, ay, bx, by, radius)

    # Threshold with coast noise (faded away from any blob, so the open sea
    # stays clean of speckles).
    land = bytearray(total)
    for j in range(GRID):
        cy = (j + 0.5) * H
        row = j * GRID
        for i in range(GRID):
            idx = row + i
            base = field[idx]
            if base <= 0.0:
                continue
            cx = (i + 0.5) * H
            noise = (2.0 * fbm(cx, cy, seed) - 1.0) * NOISE_AMP * min(1.0, base / 0.3)
            if base + noise - CARVE_STRENGTH * carve[idx] > LAND_THRESHOLD:
                land[idx] = 1

    # Worley strait rule: sea is forced where two different land components
    # nearly meet, so islands can never fuse to the mainland.
    nearest = [-1] * total
    for j in range(GRID):
        cy = (j + 0.5) * H
        row = j * GRID
        for i in range(GRID):
            idx = row + i
            if not land[idx]:
                continue
            cx = (i + 0.5) * H
            d1, d2, r1, r2 = 1e18, 1e18, -1, -1
            for k, (px, py) in enumerate(pos):
                d = math.hypot(cx - px, cy - py)
                if d < d1:
                    d2, r2 = d1, r1
                    d1, r1 = d, k
                elif d < d2:
                    d2, r2 = d, k
            nearest[idx] = r1
            if r2 >= 0 and (d2 - d1) < CHANNEL_WIDTH:
                between = hops[r1][r2]
                if between < 0 or between > CHANNEL_MAX_HOPS:
                    land[idx] = 0
                    nearest[idx] = -1

    def stamp(px: float, py: float, radius: float) -> None:
        i0 = max(0, int((px - radius) / H))
        i1 = min(GRID - 1, int((px + radius) / H))
        j0 = max(0, int((py - radius) / H))
        j1 = min(GRID - 1, int((py + radius) / H))
        for j in range(j0, j1 + 1):
            cy = (j + 0.5) * H
            for i in range(i0, i1 + 1):
                cx = (i + 0.5) * H
                if math.hypot(cx - px, cy - py) <= radius:
                    idx = j * GRID + i
                    if not land[idx]:
                        land[idx] = 1
                        nearest[idx] = -1

    # Every region position must stand on land.
    for k, (px, py) in enumerate(pos):
        stamp(px, py, STAMP_RADIUS)

    def cell_of(px: float, py: float) -> int:
        i = max(0, min(GRID - 1, int(px / H)))
        j = max(0, min(GRID - 1, int(py / H)))
        return j * GRID + i

    def connected(a: int, b: int) -> bool:
        start, goal = cell_of(*pos[a]), cell_of(*pos[b])
        seen = bytearray(total)
        seen[start] = 1
        frontier = [start]
        while frontier:
            nxt = []
            for idx in frontier:
                if idx == goal:
                    return True
                j, i = divmod(idx, GRID)
                for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ni, nj = i + di, j + dj
                    if 0 <= ni < GRID and 0 <= nj < GRID:
                        nidx = nj * GRID + ni
                        if land[nidx] and not seen[nidx]:
                            seen[nidx] = 1
                            nxt.append(nidx)
            frontier = nxt
        return False

    # Corridor repair: every land adjacency must be walkable on the mask.
    corridors = 0
    for a, b in pairs:
        if connected(a, b):
            continue
        corridors += 1
        ax, ay = pos[a]
        bx, by = pos[b]
        steps = max(2, int(math.dist(pos[a], pos[b]) / (H * 2)))
        for s in range(steps + 1):
            t = s / steps
            stamp(ax + (bx - ax) * t, ay + (by - ay) * t, CORRIDOR_RADIUS)
        assert connected(a, b), f"corridor failed for {ids[a]}-{ids[b]}"

    # Drop stray islets, fill enclosed lakes: 4-connected component sweeps.
    keep_cells = {cell_of(px, py) for px, py in pos}
    labels = [0] * total
    next_label = 0
    component_cells: list[list[int]] = []
    for idx in range(total):
        if not land[idx] or labels[idx]:
            continue
        next_label += 1
        members = [idx]
        labels[idx] = next_label
        queue = [idx]
        while queue:
            cur = queue.pop()
            j, i = divmod(cur, GRID)
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ni, nj = i + di, j + dj
                if 0 <= ni < GRID and 0 <= nj < GRID:
                    nidx = nj * GRID + ni
                    if land[nidx] and not labels[nidx]:
                        labels[nidx] = next_label
                        members.append(nidx)
                        queue.append(nidx)
        component_cells.append(members)
    min_cells = int(MIN_ISLET_AREA / (H * H))
    for members in component_cells:
        if len(members) < min_cells and not any(m in keep_cells for m in members):
            for m in members:
                land[m] = 0
                nearest[m] = -1

    # Lakes: sea unreachable from the map border becomes land.
    outside = bytearray(total)
    border = [idx for idx in range(total)
              if (idx < GRID or idx >= total - GRID or idx % GRID in (0, GRID - 1)) and not land[idx]]
    for idx in border:
        outside[idx] = 1
    frontier = border
    while frontier:
        nxt = []
        for idx in frontier:
            j, i = divmod(idx, GRID)
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ni, nj = i + di, j + dj
                if 0 <= ni < GRID and 0 <= nj < GRID:
                    nidx = nj * GRID + ni
                    if not land[nidx] and not outside[nidx]:
                        outside[nidx] = 1
                        nxt.append(nidx)
        frontier = nxt
    for idx in range(total):
        if not land[idx] and not outside[idx]:
            land[idx] = 1
            nearest[idx] = -1

    # Final assignment: every land cell belongs to its nearest region.
    for idx in range(total):
        if land[idx] and nearest[idx] < 0:
            j, i = divmod(idx, GRID)
            cx, cy = (i + 0.5) * H, (j + 0.5) * H
            best_k, best_d = -1, 1e18
            for k, (px, py) in enumerate(pos):
                d = math.hypot(cx - px, cy - py)
                if d < best_d:
                    best_d, best_k = d, k
            nearest[idx] = best_k

    # Region polygons.
    region_cells: list[set[int]] = [set() for _ in regions]
    for idx in range(total):
        if land[idx]:
            region_cells[nearest[idx]].add(idx)
    cells_out = []
    for k, rid in enumerate(ids):
        loops = trace_boundaries(region_cells[k])
        polygons = []
        for loop in loops:
            # Outer rings trace negative shoelace under land-on-left, y-down;
            # positive rings are holes (another region enclosed) — skip them,
            # the enclosed region fills that space itself.
            if ring_area(loop) >= 0:
                continue
            simplified = simplify_ring(chaikin_ring(chaikin_ring(loop)), SIMPLIFY_CELL)
            if len(simplified) >= 3 and abs(ring_area(simplified)) >= 0.05:
                polygons.append(simplified)
        # Label anchor: the deepest-inland cell of the region.
        depth = {idx: 0 for idx in region_cells[k]}
        frontier = [idx for idx in region_cells[k] if _touches_outside(idx, region_cells[k])]
        level = 0
        seen = set(frontier)
        while frontier:
            level += 1
            nxt = []
            for idx in frontier:
                j, i = divmod(idx, GRID)
                for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ni, nj = i + di, j + dj
                    nidx = nj * GRID + ni
                    if 0 <= ni < GRID and 0 <= nj < GRID and nidx in region_cells[k] and nidx not in seen:
                        seen.add(nidx)
                        depth[nidx] = level
                        nxt.append(nidx)
            frontier = nxt
        if depth:
            anchor_idx = max(sorted(depth), key=lambda idx: depth[idx])
            aj, ai = divmod(anchor_idx, GRID)
            label = ((ai + 0.5) * H, (aj + 0.5) * H)
        else:
            label = pos[k]
        cells_out.append({"region": rid, "polygons": polygons, "label": label})

    # Landmass outlines (coastline strokes).
    landmasses = []
    all_land = {idx for idx in range(total) if land[idx]}
    for loop in trace_boundaries(all_land):
        simplified = simplify_ring(chaikin_ring(chaikin_ring(loop)), SIMPLIFY_COAST)
        if len(simplified) >= 3 and abs(ring_area(simplified)) >= MIN_ISLET_AREA:
            landmasses.append(simplified)
    landmasses.sort(key=lambda ring: (-abs(ring_area(ring)), ring[0][1], ring[0][0]))

    # Roads: noise-weighted Dijkstra over land for every adjacency.
    edges_out = []
    for a, b in pairs:
        path = _road(land, pos[a], pos[b], seed)
        assert path is not None, f"no road for {ids[a]}-{ids[b]}"
        polyline = [pos[a]] + chaikin_line(simplify(path, SIMPLIFY_ROAD))[1:-1] + [pos[b]]
        edges_out.append({"a": ids[a], "b": ids[b], "path": polyline})

    if preview:
        _preview(land, pos, ids)
        area = sum(land) * H * H
        print(f"\nland {100.0 * sum(land) / total:.1f}% ({area:.0f} sq units), "
              f"{len(landmasses)} landmasses, {corridors} corridors stamped")

    def rounded(points):
        return [[round(x, 2), round(y, 2)] for x, y in points]

    return {
        "meta": {"seed": seed, "grid": GRID, "world_size": int(WORLD),
                 "tool": "generate_map_geometry.py/1"},
        "landmasses": [{"id": f"landmass_{n}", "outline": rounded(ring)}
                       for n, ring in enumerate(landmasses)],
        "cells": [{"region": c["region"],
                   "polygons": [rounded(p) for p in c["polygons"]],
                   "label": [round(c["label"][0], 2), round(c["label"][1], 2)]}
                  for c in cells_out],
        "edges": [{"a": e["a"], "b": e["b"], "path": rounded(e["path"])}
                  for e in edges_out],
    }


def _touches_outside(idx: int, cells: set[int]) -> bool:
    j, i = divmod(idx, GRID)
    for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ni, nj = i + di, j + dj
        if not (0 <= ni < GRID and 0 <= nj < GRID) or (nj * GRID + ni) not in cells:
            return True
    return False


def _road(land: bytearray, start: tuple[float, float], goal: tuple[float, float],
          seed: int) -> list[tuple[float, float]] | None:
    total = GRID * GRID

    def cell_of(px: float, py: float) -> int:
        i = max(0, min(GRID - 1, int(px / H)))
        j = max(0, min(GRID - 1, int(py / H)))
        return j * GRID + i

    start_idx, goal_idx = cell_of(*start), cell_of(*goal)
    dist = {start_idx: 0.0}
    prev: dict[int, int] = {}
    heap = [(0.0, start_idx % GRID, start_idx // GRID)]
    moves = ((1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
             (1, 1, math.sqrt(2)), (1, -1, math.sqrt(2)),
             (-1, 1, math.sqrt(2)), (-1, -1, math.sqrt(2)))
    while heap:
        d, i, j = heapq.heappop(heap)
        idx = j * GRID + i
        if idx == goal_idx:
            break
        if d > dist.get(idx, 1e18) + 1e-12:
            continue
        for di, dj, step in moves:
            ni, nj = i + di, j + dj
            if not (0 <= ni < GRID and 0 <= nj < GRID):
                continue
            nidx = nj * GRID + ni
            if not land[nidx]:
                continue
            cx, cy = (ni + 0.5) * H, (nj + 0.5) * H
            cost = d + step * (1.0 + ROAD_NOISE * fbm(cx, cy, seed + 1))
            if cost < dist.get(nidx, 1e18) - 1e-12:
                dist[nidx] = cost
                prev[nidx] = idx
                heapq.heappush(heap, (cost, ni, nj))
    if goal_idx not in dist:
        return None
    chain = [goal_idx]
    while chain[-1] != start_idx:
        chain.append(prev[chain[-1]])
    chain.reverse()
    return [((idx % GRID + 0.5) * H, (idx // GRID + 0.5) * H) for idx in chain]


def _preview(land: bytearray, pos: list[tuple[float, float]], ids: list[str]) -> None:
    cols, rows = 110, 46
    marks = {}
    for k, (px, py) in enumerate(pos):
        marks[(int(px / WORLD * cols), int(py / WORLD * rows))] = ids[k][0].upper()
    for row in range(rows):
        line = []
        for col in range(cols):
            if (col, row) in marks:
                line.append(marks[(col, row)])
                continue
            i = int((col + 0.5) / cols * GRID)
            j = int((row + 0.5) / rows * GRID)
            line.append("#" if land[j * GRID + i] else "·")
        print("".join(line))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--preview", action="store_true", help="print an ASCII map")
    parser.add_argument("--dry-run", action="store_true", help="build but do not write")
    args = parser.parse_args()

    document = build(args.seed, args.preview)
    out_path = ROOT / "data" / "map_geometry.json"
    if not args.dry_run:
        out_path.write_text(json.dumps(document, sort_keys=True) + "\n")
        size = out_path.stat().st_size
        print(f"wrote {out_path} ({size / 1024:.0f} KiB, seed {args.seed})")


if __name__ == "__main__":
    main()
