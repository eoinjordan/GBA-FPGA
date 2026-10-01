#!/usr/bin/env python3
"""Generate a compact GBA-style prototype with interchangeable FPGA cradles.

The default LCD outer envelope is provisional. Mechanical adapters provide
no electrical routing. See README.md before printing or selecting hardware.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from shapely.affinity import scale
from shapely.geometry import LineString, Point, box
from shapely.ops import nearest_points, unary_union
import trimesh

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import generate_gba_fpga_case as outline_library


def rounded(cx, cy, width, height, radius=1.5):
    return outline_library.rounded_rect(cx, cy, width, height, radius, resolution=12)


def disk(cx, cy, radius):
    return Point(cx, cy).buffer(radius, quad_segs=16)


def extrude(polygon, depth, z=0):
    mesh = trimesh.creation.extrude_polygon(polygon, depth, engine='earcut')
    mesh.apply_translation((0, 0, z))
    return mesh


def fused(meshes):
    return trimesh.boolean.union(meshes, engine='manifold', check_volume=True)


def cut(mesh, cutters):
    return trimesh.boolean.difference([mesh, *cutters], engine='manifold', check_volume=True)


def bolt_points(p):
    w, h = p['body_width'], p['body_height']
    return [(7.5, 17), (w-7.5, 17), (9, h-20), (w-9, h-20),
            (w*.32, h-7), (w*.68, h-7)]


def adapter_points(p):
    cx, cy = p['body_width']/2, p['board_center_y']
    hx, hy = p['adapter_hole_spacing_x']/2, p['adapter_hole_spacing_y']/2
    return [(cx+x, cy+y) for x in (-hx, hx) for y in (-hy, hy)]


def lcd_points(p):
    cx, cy = p['body_width']/2, p['lcd_center_y']
    return [(cx-p['lcd_outer_width']/2-4, cy), (cx+p['lcd_outer_width']/2+4, cy),
            (cx, cy-p['lcd_outer_height']/2-4), (cx, cy+p['lcd_outer_height']/2+4)]


def outline(p):
    shape = outline_library.gba_outline(p['body_width'], p['body_height'])
    # The older outline's curved grips exceed the nominal height slightly.
    return scale(shape, xfact=1, yfact=p['body_height']/(shape.bounds[3]-shape.bounds[1]),
                 origin=(0, 0))


def front_shell(p):
    shape = outline(p)
    cx = p['body_width']/2
    panel_cutout = rounded(cx, p['lcd_center_y'], p['lcd_outer_width']+2,
                          p['lcd_outer_height']+2, 2)
    control_holes = [outline_library.cross_shape(*p['dpad_center'],
                         p['dpad_size'], p['dpad_arm'], .65),
                     disk(*p['a_center'], p['ab_hole_diameter']/2),
                     disk(*p['b_center'], p['ab_hole_diameter']/2),
                     outline_library.capsule(*p['select_center'], 11.5, 4.2, -15),
                     outline_library.capsule(*p['start_center'], 11.5, 4.2, -15)]
    face = extrude(shape.difference(unary_union([panel_cutout, *control_holes])), p['face'])
    walls = extrude(shape.difference(shape.buffer(-p['wall'])),
                    p['front_depth']-p['face']+.2, p['face']-.2)
    # Bosses overlap the face; union produces connected solids.
    bosses = [extrude(disk(x, y, 3.1), p['front_depth']-p['face']+.2,
                      p['face']-.2) for x, y in [*bolt_points(p), *lcd_points(p)]]
    shell = fused([face, walls, *bosses])
    pilots = [extrude(disk(x, y, 1.05), p['front_depth']-p['face']+.1,
                     p['face']+.2) for x, y in [*bolt_points(p), *lcd_points(p)]]
    # Shoulder pockets accept independently fitted levers or existing controls.
    shoulder_cuts = [extrude(box(x-12, -3, x+12, 4.2), p['front_depth']-3.2, 3.3)
                     for x in (19, p['body_width']-19)]
    return cut(shell, [*pilots, *shoulder_cuts])


def back_shell(p):
    shape = outline(p)
    floor = extrude(shape, p['face'])
    wall = extrude(shape.difference(shape.buffer(-p['wall'])),
                   p['back_depth']-p['face']+.2, p['face']-.2)
    bosses = [extrude(disk(x, y, 3.1), p['back_depth']-p['face']+.2,
                      p['face']-.2) for x, y in bolt_points(p)]
    adapter_bosses = [extrude(disk(x, y, 3.1), 3.4, p['face']-.2)
                     for x, y in adapter_points(p)]
    shell = fused([floor, wall, *bosses, *adapter_bosses])
    cutters = [extrude(disk(x, y, 1.4), p['back_depth']+2, -1)
               for x, y in bolt_points(p)]
    cutters += [extrude(disk(x, y, 2.7), 1.3, -.01) for x, y in bolt_points(p)]
    cutters += [extrude(disk(x, y, 1.05), 3.3, p['face']+.2)
                for x, y in adapter_points(p)]
    # A common top service opening avoids assuming either board's connector positions.
    cutters += [extrude(box(p['body_width']/2-15, -3, p['body_width']/2+15, 3), 8, 4)]
    return cut(shell, cutters)


def bezel(p):
    cx, cy = p['body_width']/2, p['lcd_center_y']
    visible = rounded(cx, cy, p['lcd_visible_width'], p['lcd_visible_height'], 1)
    lip = rounded(cx, cy, p['lcd_outer_width']+6, p['lcd_outer_height']+6, 2.5)
    seat = rounded(cx, cy, p['lcd_outer_width']+2-2*p['clearance'],
                    p['lcd_outer_height']+2-2*p['clearance'], 2)
    return fused([extrude(lip.difference(visible), 1),
                  extrude(seat.difference(visible), p['face']+1.1, .9)])


def lcd_retainer(p):
    # A separate flat retainer permits shims instead of forcing a panel thickness.
    cx, cy = 0, 0
    outer = rounded(cx, cy, p['lcd_outer_width']+4, p['lcd_outer_height']+4, 2)
    inner = rounded(cx, cy, p['lcd_visible_width']+2, p['lcd_visible_height']+2, 1)
    cx, cy = p['body_width']/2, p['lcd_center_y']
    locations = [(x-cx, y-cy) for x, y in lcd_points(p)]
    tabs = [disk(x, y, 3.5) for x, y in locations]
    holes = [disk(x, y, 1.4) for x, y in locations]
    return extrude(unary_union([outer, *tabs]).difference(unary_union([inner, *holes])), 1.4)


def adapter(p, board_width, board_height):
    # Board edges, mounting holes and component keep-outs must be checked physically.
    width, height, c = p['adapter_width'], p['adapter_height'], p['clearance']
    plate = rounded(0, 0, width, height, 3)
    opening = rounded(0, 0, board_width-8, board_height-8, 2)
    holes = [disk(x, y, 1.4) for x in (-p['adapter_hole_spacing_x']/2,
                                      p['adapter_hole_spacing_x']/2)
             for y in (-p['adapter_hole_spacing_y']/2, p['adapter_hole_spacing_y']/2)]
    # Slots allow cable ties away from the chip, without inventing PCB hole coordinates.
    tie_slots = [rounded(x, y, 6, 2.2, .5)
                 for x in (-board_width/2+5, board_width/2-5)
                 for y in (-board_height/2-3, board_height/2+3)]
    base = extrude(plate.difference(unary_union([opening, *holes, *tie_slots])), 1.8)
    pads = [extrude(box(x-2, y-2, x+2, y+2), 2.1, 1.6)
            for x in (-board_width/2+2, board_width/2-2)
            for y in (-board_height/2+2, board_height/2-2)]
    rails = [extrude(box(x-1, -board_height/2+3, x+1, board_height/2-3), 3.6, 1.6)
             for x in (-board_width/2-c-1, board_width/2+c+1)]
    return fused([base, *pads, *rails])


def spacer(p):
    shape = outline(p)
    ring = shape.difference(shape.buffer(-p['wall']))
    pads = [disk(x, y, 3.1) for x, y in bolt_points(p)]
    bridges = [LineString([(x, y), nearest_points(Point(x, y), shape.exterior)[1].coords[0]])
               .buffer(2.5) for x, y in bolt_points(p)]
    holes = [disk(x, y, 1.4) for x, y in bolt_points(p)]
    mesh = fused([extrude(part, p['spacer_depth']) for part in [ring, *pads, *bridges]])
    mesh = trimesh.boolean.intersection([mesh, extrude(shape, p['spacer_depth'])], engine='manifold')
    return cut(mesh, [extrude(hole, p['spacer_depth']+2, -1) for hole in holes])


def control_clamps():
    parts = []
    for x in (0, 16, 32, 48):
        for y in (0, 12):
            bar = rounded(x, y, 12, 4.5, 1.5).difference(disk(x-3.3, y, 1.1))
            parts.append(extrude(bar, 2))
    return trimesh.util.concatenate(parts)


def validate_parameters(p):
    if not all(isinstance(v, (int, float)) and v > 0 for v in p.values()
               if not isinstance(v, list)):
        raise ValueError('Dimensions must be positive numbers')
    if p['lcd_visible_width'] >= p['lcd_outer_width'] or p['lcd_visible_height'] >= p['lcd_outer_height']:
        raise ValueError('LCD visible window must fit within the outer envelope')
    if p['lcd_outer_width'] > 72 or p['lcd_outer_height'] > 53:
        raise ValueError('This compact control layout needs a panel envelope no larger than 72 x 53 mm')
    if p['face']+p['lcd_thickness']+1.4 > p['front_depth']:
        raise ValueError('Panel plus face and retainer exceeds front depth')
    for key in ('nano20k', 'som60k'):
        if p[key+'_width']+8 > p['adapter_width'] or p[key+'_height']+8 > p['adapter_height']:
            raise ValueError(f'{key} exceeds the adapter envelope')
    cx, cy = p['body_width']/2, p['lcd_center_y']
    cutouts = [rounded(cx, cy, p['lcd_outer_width']+2, p['lcd_outer_height']+2, 2),
               outline_library.cross_shape(*p['dpad_center'], p['dpad_size'], p['dpad_arm'], .65),
               disk(*p['a_center'], p['ab_hole_diameter']/2),
               disk(*p['b_center'], p['ab_hole_diameter']/2),
               outline_library.capsule(*p['select_center'], 11.5, 4.2, -15),
               outline_library.capsule(*p['start_center'], 11.5, 4.2, -15)]
    inner = outline(p).buffer(-p['wall'])
    if not all(inner.covers(hole) for hole in cutouts):
        raise ValueError('Display or controls intersect the perimeter wall')
    for i, hole in enumerate(cutouts):
        if any(hole.distance(other)<1.0 for other in cutouts[i+1:]):
            raise ValueError('Display and control openings need at least 1 mm separation')


def preview(models, p, destination):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection
    fig = plt.figure(figsize=(12, 6))
    ax = fig.add_subplot(121, projection='3d')
    for name, color in (('compact_front_shell', '#6954a2'), ('compact_display_bezel', '#292b38')):
        mesh = models[name]
        if name=='compact_display_bezel':
            mesh=mesh.copy(); mesh.apply_translation((0,0,-1))
        ax.add_collection3d(Poly3DCollection(mesh.triangles, facecolors=color,
                                            edgecolors='none', alpha=1))
    ax.set_xlim(0, p['body_width']); ax.set_ylim(0, p['body_height']); ax.set_zlim(0, 15)
    ax.set_box_aspect((p['body_width'], p['body_height'], 15))
    ax.view_init(elev=-65, azim=-90); ax.set_axis_off()
    ax.set_title('Compact front and replaceable bezel')
    ax2 = fig.add_subplot(122)
    shape = outline(p)
    x, y = shape.exterior.xy
    ax2.fill(x, y, color='#6954a2', alpha=.12)
    ax2.plot(x, y, color='#6954a2')
    from matplotlib.patches import Rectangle, Circle, Polygon
    cx, cy = p['body_width']/2, p['lcd_center_y']
    ax2.add_patch(Rectangle((cx-p['lcd_visible_width']/2, cy-p['lcd_visible_height']/2),
                            p['lcd_visible_width'], p['lcd_visible_height'], color='#343947'))
    dp = outline_library.cross_shape(*p['dpad_center'], p['dpad_size'], p['dpad_arm'], .65)
    ax2.add_patch(Polygon(list(dp.exterior.coords), color='#292b38'))
    for x, y in (p['a_center'], p['b_center']):
        ax2.add_patch(Circle((x, y), p['ab_hole_diameter']/2, color='#9b175c'))
    for x, y in (p['start_center'], p['select_center']):
        ax2.add_patch(Rectangle((x-5.75, y-2.1), 11.5, 4.2, angle=-15, color='#292b38'))
    ax2.set_aspect('equal'); ax2.invert_yaxis(); ax2.set_xlabel('mm'); ax2.set_ylabel('mm')
    ax2.set_title('144.5 x 82 mm reference silhouette')
    fig.tight_layout(); fig.savefig(destination, dpi=160); plt.close(fig)


def main():
    root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parameters', type=Path, default=root/'parameters.json')
    parser.add_argument('--output', type=Path, default=root.parents[1]/'build/hardware/enclosure-compact')
    args = parser.parse_args()
    p = json.loads(args.parameters.read_text(encoding='utf-8'))
    validate_parameters(p)
    models = {
        'compact_front_shell': front_shell(p),
        'compact_back_shell': back_shell(p),
        'compact_display_bezel': bezel(p),
        'compact_lcd_retainer': lcd_retainer(p),
        'compact_adapter_nano20k': adapter(p, p['nano20k_width'], p['nano20k_height']),
        'compact_adapter_mega60k_som': adapter(p, p['som60k_width'], p['som60k_height']),
        'compact_rear_spacer_8mm': spacer(p),
        'compact_button_pcb_clamps': control_clamps(),
    }
    destination = args.output.resolve(); destination.mkdir(parents=True, exist_ok=True)
    manifest = {'units': 'mm', 'fit_status': 'prototype-unmeasured', 'parameters': p, 'models': {}}
    for name, mesh in models.items():
        path = destination/(name+'.stl'); mesh.export(path)
        # Check the serialized geometry, not just the in-memory mesh.
        exported = trimesh.load_mesh(path)
        components = len(exported.split(only_watertight=False))
        expected_components = 8 if name=='compact_button_pcb_clamps' else 1
        if not exported.is_watertight or not exported.is_winding_consistent or components!=expected_components:
            raise RuntimeError(f'{name} fails exported mesh validation: {components} components')
        if not np.isfinite(exported.vertices).all() or exported.volume <= 0:
            raise RuntimeError(f'{name} has invalid vertices or volume')
        manifest['models'][name] = {'watertight': bool(exported.is_watertight),
            'winding_consistent': bool(exported.is_winding_consistent), 'components': components,
            'faces': len(exported.faces), 'extents_mm': exported.extents.round(3).tolist(),
            'volume_mm3': round(float(exported.volume), 3),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    preview(models, p, destination/'compact_preview.png')
    (destination/'model_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
