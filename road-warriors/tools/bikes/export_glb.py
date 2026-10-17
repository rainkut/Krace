# Headless Blender: builds original bikes procedurally and renders rear-view lean frames (transparent PNG).
# Run: blender -b -P render_bikes.py -- <bike_id|all> <outdir> [--res=512] [--samples=48] [--only=<lean idx>]
import bpy, math, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
WHICH = argv[0] if argv else 'thunderbolt'
OUT = argv[1] if len(argv) > 1 else '/tmp/bikes'
opt = {a.split('=')[0]: a.split('=')[1] for a in argv if a.startswith('--') and '=' in a}
NORIDER = '--norider' in argv
RES, SAMPLES, ONLY = int(opt.get('--res', 512)), int(opt.get('--samples', 48)), opt.get('--only')
LEANS = list(range(-30, 31, 5))
V = Vector

def mat(name, col, metal=0.0, rough=0.5, emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*col, 1); b.inputs['Metallic'].default_value = metal; b.inputs['Roughness'].default_value = rough
    if emit:
        b.inputs['Emission Color'].default_value = (*col, 1); b.inputs['Emission Strength'].default_value = emit
    return m

class Rig:
    def __init__(s):
        s.root = bpy.data.objects.new('bike', None); bpy.context.scene.collection.objects.link(s.root)
    def fin(s, o, m, bev=0.0):
        o.data.materials.append(m); o.parent = s.root
        for p in o.data.polygons: p.use_smooth = True
        if bev:
            b = o.modifiers.new('b', 'BEVEL'); b.width = bev; b.segments = 3
        return o
    def cyl(s, p1, p2, r, m, r2=None, v=24):
        a, b = V(p1), V(p2); d = b - a
        if r2 is None: bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=v)
        else: bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=d.length, vertices=v)
        o = bpy.context.object; o.location = (a + b) / 2
        o.rotation_euler = V((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
        return s.fin(o, m)
    def sph(s, loc, sc, m, rot=(0, 0, 0)):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=36, ring_count=22, location=loc, rotation=rot)
        o = bpy.context.object; o.scale = sc; return s.fin(o, m)
    def box(s, loc, size, m, rot=(0, 0, 0), bev=0.01):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
        o = bpy.context.object; o.scale = size; return s.fin(o, m, bev / max(size))
    def torus(s, loc, major, minor, m):
        bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=64, minor_segments=18, location=loc, rotation=(0, math.pi / 2, 0))
        return s.fin(bpy.context.object, m)
    def arc(s, cy, cz, R, a0, a1, w, thick, m, taper=1.0, n=24):
        vs, fs = [], []
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n); y, z = cy + R * math.sin(a), cz + R * math.cos(a)
            ww = w / 2 * (1 - (1 - taper) * (i / n)); vs += [(-ww, y, z), (ww, y, z)]
            if i: k = 2 * i; fs.append((k - 2, k - 1, k + 1, k))
        me = bpy.data.meshes.new('arc'); me.from_pydata(vs, [], fs); me.update()
        o = bpy.data.objects.new('arc', me); bpy.context.scene.collection.objects.link(o)
        so = o.modifiers.new('s', 'SOLIDIFY'); so.thickness = thick
        return s.fin(o, m)

def build(P):
    r = Rig()
    chrome = mat('chrome', (0.9, 0.9, 0.92), 1.0, 0.15); black = mat('black', (0.03, 0.03, 0.035), 0.3, 0.5)
    rub = mat('rubber', (0.025, 0.025, 0.03), 0.0, 0.9); pt = mat('paint', P['paint'], 0.3, 0.25)
    acc = mat('accent', P['accent'], 0.2, 0.3); alu = mat('alu', (0.5, 0.52, 0.55), 0.9, 0.35)
    seatm = mat('seat', P.get('seat_col', (0.06, 0.05, 0.05)), 0.0, 0.6)
    tail = mat('tail', (1, 0.04, 0.02), 0, 0.3, 8.0); lamp = mat('lamp', (1, 0.95, 0.8), 0, 0.2, 5.0)
    jacket = mat('jacket', P['jacket'], 0.0, 0.7); helmet = mat('helmet', P['helmet'], 0.4, 0.2)
    pants = mat('pants', (0.07, 0.08, 0.12), 0.0, 0.8); glove = mat('glove', (0.04, 0.04, 0.04), 0.0, 0.6)
    visor = mat('visor', (0.02, 0.03, 0.05), 0.9, 0.08)
    WR, WB, TR, TRf = P['wr'], P['wb'], P['tire'], P.get('tire_f', P['tire'])
    # wheels
    for y, tw, hub in ((-WB, TR, 0.07), (WB, TRf, 0.06)):
        r.torus((0, y, WR), WR - tw, tw, rub)
        r.torus((0, y, WR), WR - 2 * tw, 0.014, chrome if P['spokes'] else alu)
        r.cyl((-hub, y, WR), (hub, y, WR), 0.065, alu)
        if P['spokes']:
            for k in range(16):
                a = k * 2 * math.pi / 16
                r.cyl((0, y, WR), (0, y + (WR - 2 * tw) * math.sin(a), WR + (WR - 2 * tw) * math.cos(a)), 0.0035, chrome, v=6)
        else:
            for k in range(5):
                a = k * 2 * math.pi / 5; rr = WR - 2 * tw
                r.cyl((0, y, WR), (0, y + rr * math.sin(a), WR + rr * math.cos(a)), 0.016, alu, v=8)
        if P.get('knobby'):
            for k in range(22):
                a = k * 2 * math.pi / 22
                r.box((0, y + (WR - 0.5 * tw) * math.sin(a), WR + (WR - 0.5 * tw) * math.cos(a)), (2 * tw * 1.1, 0.03, 0.02), rub, (a, 0, 0), 0.004)
    # fenders
    fw = P['fender_w']
    r.arc(-WB, WR, WR + 0.045, -75, P['rf_a'], fw, 0.014, pt, taper=0.8)
    r.sph((0, -WB - P['tail_len'], P['tail_z']), (0.04, 0.03, 0.04), tail)
    r.box((0, -WB - P['tail_len'] + 0.03, P['tail_z'] - 0.07), (0.16, 0.012, 0.09), acc, (0.2, 0, 0), 0.003)
    if P.get('beak'):
        r.arc(WB, WR, WR + 0.05, -10, 50, 0.11, 0.012, acc, taper=0.5)
        r.box((0, WB + 0.28, WR + 0.42), (0.14, 0.2, 0.012), acc, (-0.5, 0, 0), 0.004)
    else:
        r.arc(WB, WR, WR + 0.04, -60, 70, 0.13, 0.012, pt, taper=0.85)
    # frame/engine
    sy, sz = P['seat_pos']
    r.cyl((0, -WB + 0.1, WR), (0, 0.15, sz - 0.1), 0.022, black); r.cyl((0, 0.15, sz - 0.1), (0, WB - 0.15, WR + 0.45), 0.022, black)
    ew = P['eng_w']
    r.box((0, 0.04, 0.42), (ew, 0.38, 0.30), alu, bev=0.03); r.box((0, -0.18, 0.40), (ew + 0.05, 0.26, 0.24), alu, bev=0.03)
    if P['eng'] == 'air':
        r.cyl((0, 0.10, 0.50), (0, 0.10, 0.88), 0.095, alu)
        for k in range(7): r.cyl((0, 0.10, 0.56 + k * 0.045), (0, 0.10, 0.575 + k * 0.045), 0.125, alu)
    elif P['eng'] == 'vtwin':
        for s in (-1, 1):
            r.cyl((0.11 * s, 0.12, 0.50), (0.2 * s, 0.14, 0.8), 0.085, black)
            for k in range(6): r.cyl((0.11 * s + 0.015 * s * k, 0.12, 0.54 + k * 0.05), (0.12 * s + 0.015 * s * k, 0.12, 0.555 + k * 0.05), 0.11, alu, v=20)
    # exhaust
    ex = P['exhaust']
    if ex == 'chrome_side':
        r.cyl((0.19, 0.30, 0.34), (0.19, -0.50, 0.30), 0.036, chrome); r.cyl((0.20, -0.30, 0.31), (0.20, -1.04, 0.36), 0.075, chrome, r2=0.06)
        r.sph((0.20, -1.045, 0.36), (0.045, 0.01, 0.045), black)
    elif ex == 'dual_short':
        for s in (-1, 1):
            r.cyl((0.17 * s, 0.25, 0.30), (0.19 * s, -0.5, 0.32), 0.04, chrome); r.cyl((0.20 * s, -0.25, 0.32), (0.21 * s, -0.98, 0.40), 0.06, black, r2=0.05)
            r.sph((0.21 * s, -0.985, 0.40), (0.04, 0.01, 0.04), chrome)
    elif ex == 'upswept':
        r.cyl((0.18, 0.30, 0.34), (0.20, -0.45, 0.45), 0.034, chrome); r.cyl((0.21, -0.35, 0.50), (0.23, -0.98, 0.84), 0.065, alu, r2=0.05)
        r.sph((0.23, -0.99, 0.845), (0.045, 0.012, 0.045), black)
    elif ex == 'small':
        r.cyl((0.14, 0.25, 0.28), (0.15, -0.55, 0.30), 0.03, chrome); r.cyl((0.16, -0.3, 0.30), (0.17, -0.85, 0.36), 0.055, chrome, r2=0.045)
    elif ex == 'underseat':
        r.cyl((0.0, -0.45, 0.40), (0.0, -0.98, 0.62), 0.07, alu, r2=0.09); r.sph((0.0, -0.99, 0.625), (0.085, 0.012, 0.065), black)
    # seat + tank
    ty, tz, tsc = P['tank']
    r.sph((0, ty, tz), tsc, pt)
    r.box((0, ty + 0.02, tz + 0.02 + tsc[2] * 0.7), (0.12, tsc[1] * 1.2, 0.012), acc, bev=0.003)
    sx = P['seat_sc']; r.sph((0, sy, sz), sx, seatm)
    if P.get('pillion'): r.sph((0, sy - 0.36, sz + 0.02), (0.13, 0.17, 0.05), seatm)
    # suspension
    for s in (-1, 1):
        if P.get('twin_shock', True):
            r.cyl((0.17 * s, -WB, WR), (0.15 * s, -WB + 0.24, sz - 0.1), 0.016, chrome); r.cyl((0.17 * s, -WB + 0.04, WR + 0.08), (0.155 * s, -WB + 0.21, sz - 0.16), 0.032, black, v=16)
        fz = P['fork_top']
        r.cyl((0.085 * s, WB, WR), (0.085 * s, WB - 0.2, fz), 0.021, chrome)
        r.cyl((0.085 * s, WB - 0.12, WR + (fz - WR) * 0.55), (0.085 * s, WB - 0.2, fz + 0.04), 0.03, alu, v=16)
    if not P.get('twin_shock', True):
        r.cyl((0, -WB + 0.1, WR + 0.1), (0, -WB + 0.3, sz - 0.1), 0.03, acc, v=16)
    # bars
    by, bz, bw, bt = P['bars']
    r.cyl((-bw, by, bz), (bw, by, bz), 0.014, chrome if bt != 'clip' else black)
    for s in (-1, 1):
        if bt == 'cruiser':
            r.cyl((0.24 * s, by, bz), (bw * s, by - 0.06, bz - 0.06), 0.014, chrome)
        if bt == 'cross': r.cyl((-bw * 0.8, by, bz + 0.12), (bw * 0.8, by, bz + 0.12), 0.01, black)
        r.cyl(((bw - 0.1) * s, by - 0.01, bz - 0.01), ((bw + 0.05) * s, by - 0.02, bz - 0.02), 0.02, glove, v=14)
        r.cyl((bw * 0.9 * s, by, bz + 0.01), (bw * 0.8 * s, by - 0.03, bz + 0.1), 0.006, chrome, v=8)
        if bt != 'clip': r.sph((bw * 0.8 * s, by - 0.03, bz + 0.115), (0.04, 0.012, 0.03), chrome)
    # headlamp / fairing
    hy, hz, hr = P['lamp']
    if P.get('fairing'):
        r.sph((0, hy - 0.06, hz - 0.02), (0.21, 0.26, 0.2), pt, (0.4, 0, 0))
        r.box((0, hy - 0.2, hz + 0.2), (0.3, 0.02, 0.23), visor, (-0.6, 0, 0), 0.006)
        r.box((0, hy - 0.05, hz + 0.02), (0.32, 0.06, 0.05), acc, bev=0.01)
    else:
        r.sph((0, hy, hz), (hr, hr * 0.95, hr), chrome if P.get('chrome_lamp', True) else black); r.sph((0, hy - 0.07, hz + 0.08), (0.052, 0.012, 0.052), lamp)
    if NORIDER: return r
    # RIDER
    sh = P['rider']
    hip = V((0, sy - 0.02, sz + 0.09)); shoulder = hip + V((0, sh['fwd'], sh['h']))
    r.cyl(hip, shoulder, 0.15, jacket, r2=0.17)
    r.sph(shoulder + V((0, 0, 0.0)), (0.25, 0.1, 0.09), jacket)
    r.box(hip + V((0, -0.03, -0.01)), (0.3, 0.16, 0.14), pants, bev=0.03)
    head = shoulder + V((0, sh['fwd'] * 0.15 + 0.02, 0.2))
    r.sph(head, (0.125, 0.15, 0.135), helmet); r.sph(head + V((0, 0.07, -0.0)), (0.1, 0.1, 0.07), visor)
    r.box(head + V((0, -0.12, 0.0)), (0.11, 0.02, 0.05), acc, bev=0.005)
    py, pz = P['peg']
    for s in (-1, 1):
        grip = V((((bw - 0.02) * s), by, bz)); sho = shoulder + V((0.2 * s, 0, 0))
        elbow = (sho + grip) / 2 + V((0.07 * s, -0.04, -0.07))
        r.cyl(sho, elbow, 0.05, jacket, r2=0.045); r.cyl(elbow, grip, 0.042, jacket, r2=0.04)
        hp = hip + V((0.12 * s, 0, 0)); peg = V((0.19 * s, py, pz))
        knee = (hp + peg) / 2 + V((0.07 * s, 0.14, 0.12))
        r.cyl(hp, knee, 0.078, pants, r2=0.065); r.cyl(knee, peg + V((0, 0, 0.03)), 0.06, pants, r2=0.05)
        r.box(peg + V((0, 0.04, 0.0)), (0.09, 0.2, 0.08), black, bev=0.02)
    return r

BIKES = {
    'thunderbolt': dict(paint=(0.05, 0.28, 0.17), accent=(0.85, 0.78, 0.55), jacket=(0.35, 0.22, 0.1), helmet=(0.9, 0.85, 0.7),
        wr=0.33, wb=0.72, tire=0.07, spokes=True, fender_w=0.17, rf_a=45, tail_len=0.34, tail_z=0.50, eng='air', eng_w=0.26, exhaust='chrome_side',
        seat_pos=(-0.17, 0.82), seat_col=(0.16, 0.05, 0.05), seat_sc=(0.17, 0.30, 0.055), pillion=False, tank=(0.30, 0.93, (0.175, 0.31, 0.15)),
        fork_top=0.98, bars=(0.50, 1.10, 0.36, 'cruiser'), lamp=(0.62, 0.99, 0.125), peg=(-0.05, 0.28),
        rider=dict(fwd=0.04, h=0.58)),
    'nightbreaker': dict(paint=(0.04, 0.05, 0.09), accent=(0.9, 0.42, 0.12), jacket=(0.08, 0.08, 0.09), helmet=(0.05, 0.05, 0.06), seat_col=(0.04, 0.03, 0.03),
        wr=0.30, wb=0.76, tire=0.115, tire_f=0.06, spokes=False, fender_w=0.24, rf_a=55, tail_len=0.36, tail_z=0.44, eng='vtwin', eng_w=0.30, exhaust='dual_short',
        seat_pos=(-0.2, 0.68), seat_sc=(0.17, 0.34, 0.05), tank=(0.28, 0.82, (0.17, 0.30, 0.12)),
        fork_top=0.88, bars=(0.48, 0.97, 0.34, 'cruiser'), lamp=(0.64, 0.86, 0.11), peg=(0.22, 0.26),
        rider=dict(fwd=-0.06, h=0.56)),
    'scrambler': dict(paint=(0.9, 0.38, 0.05), accent=(0.1, 0.1, 0.1), jacket=(0.6, 0.55, 0.4), helmet=(0.85, 0.85, 0.82),
        wr=0.38, wb=0.74, tire=0.075, spokes=True, knobby=True, fender_w=0.16, rf_a=40, tail_len=0.36, tail_z=0.66, eng='air', eng_w=0.24, exhaust='upswept',
        seat_pos=(-0.15, 0.92), seat_sc=(0.15, 0.38, 0.05), tank=(0.28, 1.04, (0.15, 0.27, 0.13)), beak=True,
        fork_top=1.10, bars=(0.40, 1.22, 0.38, 'cross'), lamp=(0.54, 1.08, 0.1), chrome_lamp=False, peg=(-0.12, 0.34),
        rider=dict(fwd=0.08, h=0.6)),
    'commuter': dict(paint=(0.75, 0.1, 0.1), accent=(0.95, 0.95, 0.95), jacket=(0.2, 0.35, 0.55), helmet=(0.95, 0.75, 0.1),
        wr=0.27, wb=0.58, tire=0.055, spokes=False, fender_w=0.14, rf_a=45, tail_len=0.3, tail_z=0.46, eng='plain', eng_w=0.2, exhaust='small',
        seat_pos=(-0.14, 0.76), seat_sc=(0.15, 0.30, 0.05), pillion=True, tank=(0.18, 0.86, (0.14, 0.2, 0.11)), twin_shock=True,
        fork_top=0.9, bars=(0.40, 1.02, 0.3, 'flat'), lamp=(0.50, 0.96, 0.09), peg=(-0.02, 0.26),
        rider=dict(fwd=0.0, h=0.56)),
    'streak': dict(paint=(0.95, 0.8, 0.05), accent=(0.1, 0.2, 0.7), jacket=(0.1, 0.2, 0.7), helmet=(0.95, 0.95, 0.95),
        wr=0.30, wb=0.70, tire=0.095, tire_f=0.06, spokes=False, fender_w=0.2, rf_a=40, tail_len=0.52, tail_z=0.72, eng='plain', eng_w=0.28, exhaust='underseat',
        seat_pos=(-0.30, 0.78), seat_sc=(0.14, 0.26, 0.04), tank=(0.20, 0.92, (0.16, 0.30, 0.12)), twin_shock=False, fairing=True,
        fork_top=0.86, bars=(0.40, 0.95, 0.24, 'clip'), lamp=(0.62, 0.94, 0.1), peg=(-0.28, 0.40),
        rider=dict(fwd=0.2, h=0.46)),
}

def export(name, P):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rig = build(P)
    rig.root.rotation_euler = (0, 0, 0)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + '.glb'), export_format='GLB', export_apply=True, export_yup=True)

for n in (BIKES if WHICH == 'all' else [WHICH]):
    export(n, BIKES[n]); print('done', n)
