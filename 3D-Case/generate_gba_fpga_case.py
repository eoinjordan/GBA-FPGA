#!/usr/bin/env python3
"""Generate the v2 Nano 20K enclosure using estimated dimensions in millimetres.

See README.md for fit assumptions. Outputs go to an ignored build directory
unless --output is supplied; existing repository models are not overwritten.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np
import trimesh
from shapely.geometry import LinearRing, MultiPolygon, Point, Polygon, box
from shapely import constrained_delaunay_triangles
from shapely.ops import unary_union


@dataclass(frozen=True)
class CaseParameters:
    body_width: float = 194.0
    body_height: float = 110.0
    front_depth: float = 11.8
    back_depth: float = 13.2
    face_thickness: float = 2.2
    front_wall: float = 2.2
    back_wall: float = 2.5
    seam_clearance: float = 0.35

    lcd_outer_width: float = 105.5
    lcd_outer_height: float = 67.2
    lcd_thickness: float = 3.2
    lcd_active_width: float = 95.0
    lcd_active_height: float = 53.9
    lcd_center_x: float = 97.0
    lcd_center_y: float = 47.5

    dpad_center_x: float = 25.5
    dpad_center_y: float = 58.0
    dpad_overall: float = 27.2
    dpad_arm: float = 9.6

    button_a_x: float = 172.0
    button_a_y: float = 53.0
    button_b_x: float = 157.8
    button_b_y: float = 64.0
    ab_hole_diameter: float = 12.6

    select_x: float = 86.0
    start_x: float = 108.0
    start_select_y: float = 89.0
    start_select_width: float = 13.0
    start_select_height: float = 5.0

    tang_board_width: float = 76.5
    tang_board_height: float = 25.5
    cart_board_width: float = 86.0
    cart_board_height: float = 54.0

    print_clearance: float = 0.35
    screw_clearance_diameter: float = 2.8
    screw_boss_outer_diameter: float = 7.0


CASE = CaseParameters()
SEGMENTS = 20


def cubic_bezier(p0: Sequence[float], p1: Sequence[float], p2: Sequence[float], p3: Sequence[float], n: int) -> list[tuple[float, float]]:
    pts: list[tuple[float, float]] = []
    for i in range(n):
        t = i / n
        u = 1.0 - t
        x = u**3*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t**3*p3[0]
        y = u**3*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t**3*p3[1]
        pts.append((x, y))
    return pts


def gba_outline(width: float, height: float) -> Polygon:
    """Return a smooth, GBA-proportioned horizontal handheld silhouette."""
    sx = width / 194.0
    sy = height / 110.0
    pts: list[tuple[float, float]] = []
    pts += [(14*sx, 0)]
    pts += [(170*sx, 0)]
    pts += cubic_bezier((170*sx, 0), (184*sx, 0), (194*sx, 7*sy), (194*sx, 17*sy), 12)
    pts += [(194*sx, 67*sy)]
    pts += cubic_bezier((194*sx, 67*sy), (194*sx, 87*sy), (181*sx, 101*sy), (162*sx, 107*sy), 18)
    pts += cubic_bezier((162*sx, 107*sy), (143*sx, 113*sy), (119*sx, 109*sy), (97*sx, 107*sy), 18)
    pts += cubic_bezier((97*sx, 107*sy), (75*sx, 109*sy), (51*sx, 113*sy), (32*sx, 107*sy), 18)
    pts += cubic_bezier((32*sx, 107*sy), (13*sx, 101*sy), (0, 87*sy), (0, 67*sy), 18)
    pts += [(0, 17*sy)]
    pts += cubic_bezier((0, 17*sy), (0, 7*sy), (10*sx, 0), (14*sx, 0), 12)
    poly = Polygon(pts)
    if not poly.is_valid:
        poly = poly.buffer(0)
    return poly


def rounded_rect(cx: float, cy: float, width: float, height: float, radius: float, resolution: int = SEGMENTS) -> Polygon:
    radius = max(0.01, min(radius, width/2 - 0.01, height/2 - 0.01))
    core = box(cx-width/2+radius, cy-height/2+radius, cx+width/2-radius, cy+height/2-radius)
    return core.buffer(radius, resolution=resolution, join_style=1)


def capsule(cx: float, cy: float, width: float, height: float, rotation_deg: float = 0.0) -> Polygon:
    poly = rounded_rect(cx, cy, width, height, min(width, height)/2.0)
    if rotation_deg:
        from shapely.affinity import rotate
        poly = rotate(poly, rotation_deg, origin=(cx, cy))
    return poly


def cross_shape(cx: float, cy: float, overall: float, arm: float, radius: float = 0.7) -> Polygon:
    p = unary_union([
        box(cx-overall/2, cy-arm/2, cx+overall/2, cy+arm/2),
        box(cx-arm/2, cy-overall/2, cx+arm/2, cy+overall/2),
    ])
    if radius > 0:
        p = p.buffer(radius, resolution=8).buffer(-radius, resolution=8)
    return p


def polygon_signed_area(coords: Sequence[Sequence[float]]) -> float:
    a = 0.0
    for i in range(len(coords)-1):
        x0, y0 = coords[i]
        x1, y1 = coords[i+1]
        a += x0*y1 - x1*y0
    return 0.5*a


def _iter_polygons(geom) -> Iterable[Polygon]:
    if isinstance(geom, Polygon):
        yield geom
    elif isinstance(geom, MultiPolygon):
        yield from geom.geoms
    else:
        cleaned = geom.buffer(0)
        if isinstance(cleaned, Polygon):
            yield cleaned
        elif isinstance(cleaned, MultiPolygon):
            yield from cleaned.geoms


def triangulate_polygon(poly: Polygon) -> tuple[np.ndarray, np.ndarray]:
    """Triangulate a Shapely polygon, including holes, into shared 2D vertices."""
    vertex_map: dict[tuple[float, float], int] = {}
    vertices: list[tuple[float, float]] = []
    faces: list[tuple[int, int, int]] = []
    for tri in constrained_delaunay_triangles(poly).geoms:
        if tri.area < 1e-8:
            continue
        rp = tri.representative_point()
        if not poly.covers(rp):
            continue
        clipped = tri.intersection(poly)
        if clipped.area < tri.area * 0.999:
            continue
        coords = list(tri.exterior.coords)[:3]
        ids = []
        for x, y in coords:
            key = (round(float(x), 7), round(float(y), 7))
            if key not in vertex_map:
                vertex_map[key] = len(vertices)
                vertices.append((float(x), float(y)))
            ids.append(vertex_map[key])
        p0, p1, p2 = [np.array(vertices[j]) for j in ids]
        edge1, edge2 = p1-p0, p2-p0
        if edge1[0]*edge2[1] - edge1[1]*edge2[0] < 0:
            ids[1], ids[2] = ids[2], ids[1]
        faces.append(tuple(ids))
    if not faces:
        raise ValueError("Triangulation produced no faces")
    return np.array(vertices, dtype=float), np.array(faces, dtype=np.int64)


def extrude_polygon(geom, height: float, z0: float = 0.0) -> trimesh.Trimesh:
    meshes: list[trimesh.Trimesh] = []
    for poly in _iter_polygons(geom):
        v2, f2 = triangulate_polygon(poly)
        n = len(v2)
        vertices = np.vstack([
            np.column_stack([v2, np.full(n, z0)]),
            np.column_stack([v2, np.full(n, z0+height)]),
        ])
        faces: list[list[int]] = []
        faces.extend([[int(a), int(c), int(b)] for a, b, c in f2])
        faces.extend([[int(a+n), int(b+n), int(c+n)] for a, b, c in f2])

        rings = [poly.exterior, *poly.interiors]
        for ring in rings:
            coords = list(ring.coords)
            ccw = polygon_signed_area(coords) > 0
            for i in range(len(coords)-1):
                p0 = (round(float(coords[i][0]), 7), round(float(coords[i][1]), 7))
                p1 = (round(float(coords[i+1][0]), 7), round(float(coords[i+1][1]), 7))
                # Boundary coordinates are normally present in triangulation. Add them if needed.
                lookup = {(round(x,7), round(y,7)): j for j,(x,y) in enumerate(v2.tolist())}
                if p0 not in lookup or p1 not in lookup:
                    continue
                a, b = lookup[p0], lookup[p1]
                if ccw:
                    faces += [[a, b, b+n], [a, b+n, a+n]]
                else:
                    faces += [[a, b+n, b], [a, a+n, b+n]]
        mesh = trimesh.Trimesh(vertices=vertices, faces=np.asarray(faces), process=True)
        trimesh.repair.fix_normals(mesh)
        meshes.append(mesh)
    return trimesh.util.concatenate(meshes)


def ring_extrusion(outer: Polygon, inner: Polygon, height: float, z0: float) -> trimesh.Trimesh:
    return extrude_polygon(outer.difference(inner), height, z0)


def cylinder_ring(cx: float, cy: float, outer_d: float, inner_d: float, height: float, z0: float, sections: int = 48) -> trimesh.Trimesh:
    outer = Point(cx, cy).buffer(outer_d/2, resolution=sections//4)
    inner = Point(cx, cy).buffer(inner_d/2, resolution=sections//4)
    return ring_extrusion(outer, inner, height, z0)


def sample_rounded_rect(cx: float, cy: float, width: float, height: float, radius: float, per_corner: int = 16) -> np.ndarray:
    r = min(radius, width/2, height/2)
    centers = [
        (cx+width/2-r, cy+height/2-r, 0, math.pi/2),
        (cx-width/2+r, cy+height/2-r, math.pi/2, math.pi),
        (cx-width/2+r, cy-height/2+r, math.pi, 3*math.pi/2),
        (cx+width/2-r, cy-height/2+r, 3*math.pi/2, 2*math.pi),
    ]
    pts = []
    for ccx, ccy, a0, a1 in centers:
        for a in np.linspace(a0, a1, per_corner, endpoint=False):
            pts.append((ccx+r*math.cos(a), ccy+r*math.sin(a)))
    return np.asarray(pts, dtype=float)


def loft_surface(lower_xy: np.ndarray, lower_z: float, upper_xy: np.ndarray, upper_z: float, inward: bool = False) -> trimesh.Trimesh:
    if len(lower_xy) != len(upper_xy):
        raise ValueError("Loft rings must have the same number of points")
    n = len(lower_xy)
    vertices = np.vstack([
        np.column_stack([lower_xy, np.full(n, lower_z)]),
        np.column_stack([upper_xy, np.full(n, upper_z)]),
    ])
    faces = []
    for i in range(n):
        j = (i+1) % n
        if not inward:
            faces += [[i, j, j+n], [i, j+n, i+n]]
        else:
            faces += [[i, j+n, j], [i, i+n, j+n]]
    mesh = trimesh.Trimesh(vertices=vertices, faces=np.asarray(faces), process=True)
    trimesh.repair.fix_normals(mesh)
    return mesh


def bridge_rings(outer_xy: np.ndarray, outer_z: float, inner_xy: np.ndarray, inner_z: float, normal_outward: bool = True) -> trimesh.Trimesh:
    if len(outer_xy) != len(inner_xy):
        raise ValueError("Rings must have equal point counts")
    n = len(outer_xy)
    vertices = np.vstack([
        np.column_stack([outer_xy, np.full(n, outer_z)]),
        np.column_stack([inner_xy, np.full(n, inner_z)]),
    ])
    faces = []
    for i in range(n):
        j=(i+1)%n
        if normal_outward:
            faces += [[i, j, j+n], [i, j+n, i+n]]
        else:
            faces += [[i, j+n, j], [i, i+n, j+n]]
    mesh=trimesh.Trimesh(vertices=vertices, faces=np.asarray(faces), process=True)
    trimesh.repair.fix_normals(mesh)
    return mesh


def concatenate(meshes: Iterable[trimesh.Trimesh]) -> trimesh.Trimesh:
    good = [m for m in meshes if m is not None and len(m.vertices) and len(m.faces)]
    mesh = trimesh.util.concatenate(good)
    mesh.remove_unreferenced_vertices()
    return mesh


def front_shell(p: CaseParameters) -> trimesh.Trimesh:
    outer = gba_outline(p.body_width, p.body_height)
    screen = rounded_rect(p.lcd_center_x, p.lcd_center_y, p.lcd_active_width, p.lcd_active_height, 2.2)
    dpad = cross_shape(p.dpad_center_x, p.dpad_center_y, p.dpad_overall, p.dpad_arm)
    a_hole = Point(p.button_a_x, p.button_a_y).buffer(p.ab_hole_diameter/2, resolution=24)
    b_hole = Point(p.button_b_x, p.button_b_y).buffer(p.ab_hole_diameter/2, resolution=24)
    select_hole = capsule(p.select_x, p.start_select_y, p.start_select_width, p.start_select_height, -10)
    start_hole = capsule(p.start_x, p.start_select_y, p.start_select_width, p.start_select_height, -10)

    speaker_holes = []
    for row, count in enumerate((3, 4, 3)):
        y = 82.0 + row*4.0
        x0 = 164.0 - (count-1)*2.2
        for col in range(count):
            speaker_holes.append(Point(x0+col*4.4, y).buffer(0.9, resolution=12))

    face = outer.difference(unary_union([screen, dpad, a_hole, b_hole, select_hole, start_hole, *speaker_holes]))
    meshes: list[trimesh.Trimesh] = [extrude_polygon(face, p.face_thickness, 0.0)]

    inner = outer.buffer(-p.front_wall, join_style=1)
    shoulder_notches = unary_union([
        box(14, -2, 52, 5.8),
        box(p.body_width-52, -2, p.body_width-14, 5.8),
    ])
    wall = outer.difference(inner).difference(shoulder_notches)
    meshes.append(extrude_polygon(wall, p.front_depth-p.face_thickness, p.face_thickness))

    # Interlocking tongue, deliberately inset to fit the back cavity.
    lip_outer = outer.buffer(-3.0, join_style=1)
    lip_inner = outer.buffer(-4.05, join_style=1)
    meshes.append(ring_extrusion(lip_outer, lip_inner, 1.55, p.front_depth-0.4))

    # Minimal raised screen bezel on the exterior.
    bezel_outer = rounded_rect(p.lcd_center_x, p.lcd_center_y, p.lcd_active_width+4.0, p.lcd_active_height+4.0, 3.4)
    meshes.append(ring_extrusion(bezel_outer, screen, 0.55, -0.55))

    # LCD location ledge on the internal face.
    pocket_outer = rounded_rect(p.lcd_center_x, p.lcd_center_y, p.lcd_outer_width+1.0, p.lcd_outer_height+1.0, 3.0)
    pocket_inner = rounded_rect(p.lcd_center_x, p.lcd_center_y, p.lcd_outer_width-2.8, p.lcd_outer_height-2.8, 2.2)
    meshes.append(ring_extrusion(pocket_outer, pocket_inner, 1.5, p.face_thickness))

    # Button guide tubes.
    for cx, cy in [(p.button_a_x,p.button_a_y),(p.button_b_x,p.button_b_y)]:
        meshes.append(cylinder_ring(cx, cy, p.ab_hole_diameter+3.0, p.ab_hole_diameter, 2.5, p.face_thickness))
    start_outer = capsule(p.select_x, p.start_select_y, p.start_select_width+3.0, p.start_select_height+3.0, -10)
    start_inner = select_hole
    meshes.append(ring_extrusion(start_outer, start_inner, 2.0, p.face_thickness))
    sel_outer = capsule(p.start_x, p.start_select_y, p.start_select_width+3.0, p.start_select_height+3.0, -10)
    meshes.append(ring_extrusion(sel_outer, start_hole, 2.0, p.face_thickness))

    # Main shell screw bosses.
    boss_positions = [(12,18),(182,18),(9.5,80),(184.5,80),(55,101),(139,101)]
    for x,y in boss_positions:
        if outer.buffer(-3.5).contains(Point(x,y)):
            meshes.append(cylinder_ring(x,y,p.screw_boss_outer_diameter,p.screw_clearance_diameter,p.front_depth-p.face_thickness-0.7,p.face_thickness))

    # PCB support bosses based on the photographed split GBA-style boards.
    pcb_bosses = [
        (7.5,35.5),(50.0,37.5),(12.0,86.0),(48.0,87.0),  # D-pad board
        (146.0,38.0),(184.0,39.0),(148.0,84.5),(181.5,86.0), # A/B board
    ]
    for x,y in pcb_bosses:
        if outer.buffer(-2.8).contains(Point(x,y)):
            meshes.append(cylinder_ring(x,y,5.5,2.2,5.4,p.face_thickness))

    mesh = concatenate(meshes)
    mesh.metadata['name'] = 'gba_fpga_front_shell_v2'
    return mesh


def back_shell(p: CaseParameters) -> trimesh.Trimesh:
    outer = gba_outline(p.body_width, p.body_height)
    module_opening = rounded_rect(97.0, 77.0, 101.0, 57.0, 12.0)
    face = outer.difference(module_opening)
    meshes: list[trimesh.Trimesh] = [extrude_polygon(face, p.face_thickness, 0.0)]

    inner = outer.buffer(-p.back_wall, join_style=1)
    top_notches = unary_union([
        box(14, -2, 52, 6.2),
        box(p.body_width-52, -2, p.body_width-14, 6.2),
        box(53.0, -2, 141.0, 8.2),  # cartridge entry
    ])
    side_ports = unary_union([
        box(-2, 30, 5.0, 45),
        box(p.body_width-5.0, 29, p.body_width+2, 47),
    ])
    wall = outer.difference(inner).difference(top_notches).difference(side_ports)
    meshes.append(extrude_polygon(wall, p.back_depth-p.face_thickness, p.face_thickness))

    # Internal cover landing ring around the large rear service opening.
    landing_outer = rounded_rect(97.0,77.0,108.0,64.0,14.0)
    landing_inner = rounded_rect(97.0,77.0,101.7,57.7,12.2)
    meshes.append(ring_extrusion(landing_outer, landing_inner, 2.0, p.face_thickness))

    boss_positions = [(12,18),(182,18),(9.5,80),(184.5,80),(55,101),(139,101)]
    for x,y in boss_positions:
        if outer.buffer(-3.5).contains(Point(x,y)):
            meshes.append(cylinder_ring(x,y,p.screw_boss_outer_diameter,2.15,p.back_depth-p.face_thickness-0.7,p.face_thickness))

    # Rear module cover mounting bosses aligned to the external cover ears.
    for x,y in [(40.0,55.0),(154.0,55.0),(40.0,99.0),(154.0,99.0)]:
        if outer.buffer(-3.0).contains(Point(x,y)):
            meshes.append(cylinder_ring(x,y,7.0,2.2,5.5,p.face_thickness))

    # Cartridge adapter support bosses, compatible with the photographed board envelope.
    for x,y in [(55.0,16.0),(139.0,16.0),(55.0,43.5),(139.0,43.5)]:
        meshes.append(cylinder_ring(x,y,6.0,2.4,6.0,p.face_thickness))

    # Tang Nano tray attachment points below the cartridge adapter.
    for x,y in [(57.0,48.0),(137.0,48.0),(57.0,76.5),(137.0,76.5)]:
        if not module_opening.contains(Point(x,y)):
            meshes.append(cylinder_ring(x,y,6.0,2.4,5.0,p.face_thickness))

    mesh=concatenate(meshes)
    mesh.metadata['name']='gba_fpga_back_shell_v2'
    return mesh


def rear_module_cover(p: CaseParameters) -> trimesh.Trimesh:
    """Hollow sloped rear cover with a continuous, watertight shell."""
    n=24
    ob=sample_rounded_rect(0.0,0.0,109.0,65.0,14.5,n)
    osr=sample_rounded_rect(0.0,0.0,109.0,65.0,14.5,n)
    ot=sample_rounded_rect(0.0,3.0,92.0,49.0,11.0,n)
    ib=sample_rounded_rect(0.0,0.0,97.0,53.0,11.5,n)
    isr=sample_rounded_rect(0.0,0.0,97.0,53.0,11.5,n)
    it=sample_rounded_rect(0.0,3.0,87.5,44.5,9.2,n)
    rings=[(ob,0.0),(osr,2.0),(ot,7.0),(ib,0.0),(isr,2.0),(it,5.0)]
    vertices=[]
    offsets=[]
    for xy,z in rings:
        offsets.append(len(vertices))
        vertices.extend([(float(x),float(y),z) for x,y in xy])
    m=len(ob)
    faces=[]
    def connect(a:int,b:int,reverse:bool=False):
        oa,obase=offsets[a],offsets[b]
        for i in range(m):
            j=(i+1)%m
            if not reverse:
                faces.extend([[oa+i,oa+j,obase+j],[oa+i,obase+j,obase+i]])
            else:
                faces.extend([[oa+i,obase+j,oa+j],[oa+i,obase+i,obase+j]])
    connect(0,1,False)  # outer flange wall
    connect(1,2,False)  # outer slope
    connect(2,5,False)  # crown thickness
    connect(4,5,True)   # inner slope
    connect(3,4,True)   # inner flange wall
    connect(0,3,True)   # underside annular face
    shell=trimesh.Trimesh(vertices=np.asarray(vertices),faces=np.asarray(faces),process=True)
    shell.merge_vertices(merge_norm=True,merge_tex=True,digits_vertex=7)
    shell.update_faces(shell.unique_faces())
    shell.remove_unreferenced_vertices()
    trimesh.repair.fix_normals(shell)

    # External mounting ears place the holes outside the hollow bay footprint.
    ears=[]
    for x,y in [(-57.0,-22.0),(57.0,-22.0),(-57.0,22.0),(57.0,22.0)]:
        ears.append(cylinder_ring(x,y,9.0,3.0,2.0,0.0))
    mesh=concatenate([shell,*ears])
    mesh.metadata['name']='gba_fpga_sloped_rear_module_cover_v2'
    return mesh

def screen_retainer(p: CaseParameters) -> trimesh.Trimesh:
    cx,cy=0.0,0.0
    outer=rounded_rect(cx,cy,p.lcd_outer_width+4.0,p.lcd_outer_height+4.0,4.5)
    inner=rounded_rect(cx,cy,p.lcd_active_width+1.8,p.lcd_active_height+1.8,2.8)
    tabs=[]
    for x,y in [(-p.lcd_outer_width/2-5,0),(p.lcd_outer_width/2+5,0),(0,-p.lcd_outer_height/2-5),(0,p.lcd_outer_height/2+5)]:
        tabs.append(Point(x,y).buffer(5.5,resolution=16))
    shape=unary_union([outer,*tabs]).difference(inner)
    for x,y in [(-p.lcd_outer_width/2-5,0),(p.lcd_outer_width/2+5,0),(0,-p.lcd_outer_height/2-5),(0,p.lcd_outer_height/2+5)]:
        shape=shape.difference(Point(x,y).buffer(1.4,resolution=16))
    mesh=extrude_polygon(shape,1.8,0.0)
    mesh.metadata['name']='gba_fpga_lcd_retainer_v2'
    return mesh


def open_frame_tray(board_w: float, board_h: float, name: str, rail_h: float = 4.5) -> trimesh.Trimesh:
    clearance=CASE.print_clearance
    outer=rounded_rect(0,0,board_w+6.0,board_h+6.0,3.5)
    inner=rounded_rect(0,0,board_w-7.0,board_h-7.0,2.0)
    holes=[]
    for x,y in [(-(board_w+1)/2,-(board_h+1)/2),((board_w+1)/2,-(board_h+1)/2),(-(board_w+1)/2,(board_h+1)/2),((board_w+1)/2,(board_h+1)/2)]:
        holes.append(Point(x,y).buffer(1.4,resolution=16))
    base=outer.difference(inner).difference(unary_union(holes))
    meshes=[extrude_polygon(base,1.8,0.0)]

    # Low side rails, ends left open for connectors/cables.
    rail_t=2.2
    side1=box(-board_w/2-clearance-rail_t, -board_h/2-clearance, -board_w/2-clearance, board_h/2+clearance)
    side2=box(board_w/2+clearance, -board_h/2-clearance, board_w/2+clearance+rail_t, board_h/2+clearance)
    meshes += [extrude_polygon(side1,rail_h,1.8),extrude_polygon(side2,rail_h,1.8)]

    # Flexible top retaining nubs at each side.
    for x in [-board_w/2-clearance-rail_t/2,board_w/2+clearance+rail_t/2]:
        for y in [-board_h*0.28,board_h*0.28]:
            nub=rounded_rect(x,y,3.2,7.0,1.2)
            meshes.append(extrude_polygon(nub,1.2,1.8+rail_h))
    mesh=concatenate(meshes)
    mesh.metadata['name']=name
    return mesh


def button_pcb_clamp_set() -> trimesh.Trimesh:
    meshes=[]
    # Eight identical rotating clamp bars printed as a sprue-like set.
    for row in range(2):
        for col in range(4):
            cx=col*18.0
            cy=row*14.0
            bar=rounded_rect(cx,cy,14.0,5.5,2.4).difference(Point(cx-4.2,cy).buffer(1.25,resolution=16))
            meshes.append(extrude_polygon(bar,2.4,0.0))
    mesh=concatenate(meshes)
    mesh.metadata['name']='gba_fpga_button_pcb_clamp_set_v2'
    return mesh


def export_mesh(mesh: trimesh.Trimesh, out_dir: Path, stem: str) -> dict:
    paths={}
    for ext in ('stl','obj'):
        path=out_dir/f'{stem}.{ext}'
        mesh.export(path)
        paths[ext]=str(path)
    return paths


def sha256_file(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):
            h.update(chunk)
    return h.hexdigest()


def write_preview(out_dir: Path, p: CaseParameters) -> None:
    import matplotlib.pyplot as plt
    from matplotlib.patches import Polygon as MplPolygon
    from matplotlib.patches import Circle, FancyBboxPatch

    fig,axes=plt.subplots(1,2,figsize=(14,5.2))
    outer=gba_outline(p.body_width,p.body_height)
    for ax,title in zip(axes,['Front layout','Back layout']):
        xy=np.asarray(outer.exterior.coords)
        ax.add_patch(MplPolygon(xy,closed=True,fill=False,linewidth=1.5))
        ax.set_aspect('equal')
        ax.set_xlim(-6,p.body_width+6)
        ax.set_ylim(p.body_height+6,-6)
        ax.set_title(title)
        ax.set_xlabel('mm')
        ax.set_ylabel('mm')
        ax.grid(True,linewidth=0.3)
    ax=axes[0]
    ax.add_patch(FancyBboxPatch((p.lcd_center_x-p.lcd_active_width/2,p.lcd_center_y-p.lcd_active_height/2),p.lcd_active_width,p.lcd_active_height,boxstyle='round,pad=0,rounding_size=2.2',fill=False))
    dxy=np.asarray(cross_shape(p.dpad_center_x,p.dpad_center_y,p.dpad_overall,p.dpad_arm).exterior.coords)
    ax.add_patch(MplPolygon(dxy,closed=True,fill=False))
    for x,y in [(p.button_a_x,p.button_a_y),(p.button_b_x,p.button_b_y)]:
        ax.add_patch(Circle((x,y),p.ab_hole_diameter/2,fill=False))
    ax.text(p.lcd_center_x,p.lcd_center_y,'4.3-inch LCD',ha='center',va='center')
    ax=axes[1]
    mod=rounded_rect(97,77,101,57,12)
    ax.add_patch(MplPolygon(np.asarray(mod.exterior.coords),closed=True,fill=False))
    ax.add_patch(FancyBboxPatch((53,0),88,8.2,boxstyle='square,pad=0',fill=False))
    ax.text(97,77,'Sloped service cover',ha='center',va='center')
    fig.tight_layout()
    fig.savefig(out_dir/'gba_fpga_case_v2_preview.png',dpi=180)
    plt.close(fig)


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,
                        default=Path(__file__).resolve().parent.parent/'build/hardware/enclosure-v2')
    args=parser.parse_args()
    out_dir=args.output.resolve()
    out_dir.mkdir(parents=True,exist_ok=True)
    models={
        'gba_fpga_front_shell_v2':front_shell(CASE),
        'gba_fpga_back_shell_v2':back_shell(CASE),
        'gba_fpga_sloped_rear_module_cover_v2':rear_module_cover(CASE),
        'gba_fpga_lcd_retainer_v2':screen_retainer(CASE),
        'gba_fpga_tang_nano_20k_tray_v2':open_frame_tray(CASE.tang_board_width,CASE.tang_board_height,'gba_fpga_tang_nano_20k_tray_v2'),
        'gba_fpga_cartridge_adapter_tray_v2':open_frame_tray(CASE.cart_board_width,CASE.cart_board_height,'gba_fpga_cartridge_adapter_tray_v2',rail_h=5.2),
        'gba_fpga_button_pcb_clamp_set_v2':button_pcb_clamp_set(),
    }
    manifest={'parameters':asdict(CASE),'models':{}}
    for stem,mesh in models.items():
        export_mesh(mesh,out_dir,stem)
        manifest['models'][stem]={
            'watertight':bool(mesh.is_watertight),
            'vertices':int(len(mesh.vertices)),
            'faces':int(len(mesh.faces)),
            'extents_mm':[round(float(v),3) for v in mesh.extents],
            'components':int(len(mesh.split(only_watertight=False))),
        }
    write_preview(out_dir,CASE)
    with (out_dir/'model_manifest.json').open('w',encoding='utf-8') as f:
        json.dump(manifest,f,indent=2)

    checksum_lines=[]
    generated_names={f'{stem}.{extension}' for stem in models for extension in ('stl','obj')}
    generated_names.update(('model_manifest.json','gba_fpga_case_v2_preview.png'))
    for path in sorted(out_dir/name for name in generated_names):
        if path.is_file():
            checksum_lines.append(f"{sha256_file(path)}  {path.name}")
    (out_dir/'SHA256SUMS.txt').write_text('\n'.join(checksum_lines)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
