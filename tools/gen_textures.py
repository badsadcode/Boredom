#!/usr/bin/env python3
"""Procedural, tileable textures for BadLevel's blockout materials.

BadLevel's GLB uses 1 UV unit = 2 m, so every texture is a 2 m x 2 m tile.
256 px per tile = 128 px/m; the PS1 look samples a coarser mip on top of that.

    python3 tools/gen_textures.py            # writes assets/textures/*.png

Each material gets <name>.png (albedo) and <name>_n.png (normal, OpenGL convention).
Everything is seeded, so the output is reproducible.
"""
import os
import numpy as np
from PIL import Image

S = 256
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")


def fnoise(rng, beta=2.0, aniso=(1.0, 1.0)):
    """Tileable noise (periodic by construction). beta: higher = smoother. aniso scales
    the frequency axes: (4, 1) gives long vertical streaks."""
    f = np.fft.fft2(rng.standard_normal((S, S)))
    fy = np.fft.fftfreq(S)[:, None] * aniso[0]
    fx = np.fft.fftfreq(S)[None, :] * aniso[1]
    r = np.sqrt(fx ** 2 + fy ** 2)
    r[0, 0] = 1.0
    f = f / r ** (beta / 2.0)
    f[0, 0] = 0
    n = np.fft.ifft2(f).real
    return (n - n.mean()) / (n.std() + 1e-9)


def lines(step_y, step_x, width=2, offset=0):
    g = np.zeros((S, S))
    if step_y:
        for y in range(offset, S, step_y):
            for w in range(width):
                g[(y + w) % S, :] = 1
    if step_x:
        for x in range(offset, S, step_x):
            for w in range(width):
                g[:, (x + w) % S] = 1
    return g


def dots(step, radius, offset=0):
    yy, xx = np.mgrid[0:S, 0:S]
    d = np.zeros((S, S))
    for cy in range(offset, S, step):
        for cx in range(offset, S, step):
            dy = np.minimum(abs(yy - cy), S - abs(yy - cy))
            dx = np.minimum(abs(xx - cx), S - abs(xx - cx))
            d = np.maximum(d, (dx ** 2 + dy ** 2 <= radius ** 2).astype(float))
    return d


def blend(a, m, color, amt):
    """Mix colour into albedo `a` where mask m (0..1) is set."""
    return a * (1 - (m * amt)[..., None]) + np.array(color)[None, None, :] * (m * amt)[..., None]


def normal_from_height(h, strength=1.0):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.dstack([-dx * strength, dy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def save(name, albedo, height, nstrength=2.0):
    a = np.clip(albedo, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))
    n = normal_from_height(height, nstrength)
    Image.fromarray((np.clip(n, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_n.png"))


def grime(rng, a, amount=0.35):
    m = np.clip(fnoise(rng, 3.0) * 0.7 - 0.25, 0, 1)
    return blend(a, m, (0.12, 0.11, 0.09), amount)


# --------------------------------------------------------------------------- textures

def floor_tex(rng):
    a = np.ones((S, S, 3)) * np.array([0.50, 0.49, 0.46])
    a += (0.05 * fnoise(rng, 2.0) + 0.035 * fnoise(rng, 0.7))[..., None]
    half = S // 2
    for sy in range(2):                       # 1 m slabs with their own tint
        for sx in range(2):
            a[sy * half:(sy + 1) * half, sx * half:(sx + 1) * half] += rng.uniform(-0.04, 0.04)
    h = 0.5 * fnoise(rng, 2.2) + 0.5 * fnoise(rng, 0.8)
    grout = lines(half, half, 3)
    a = blend(a, grout, (0.14, 0.13, 0.12), 0.7)
    h -= 2.5 * grout
    a = grime(rng, a)
    m = np.clip(fnoise(rng, 3.5) * 1.1 - 1.2, 0, 1)         # a few oil stains
    a = blend(a, m, (0.05, 0.05, 0.05), 0.8)
    return a, h


def wall_tex(rng):
    a = np.ones((S, S, 3)) * np.array([0.74, 0.74, 0.71])
    a += (0.035 * fnoise(rng, 2.0) + 0.03 * fnoise(rng, 0.6))[..., None]
    streak = fnoise(rng, 2.5, (5, 1))                         # rain / dirt streaks
    a = blend(a, np.clip(streak * 0.5 - 0.1, 0, 1), (0.2, 0.19, 0.16), 0.55)
    h = 0.5 * fnoise(rng, 1.5) + 0.3 * fnoise(rng, 0.6)
    seam = lines(S, S // 2, 3)                                # 1 m wide panels, 2 m tall
    a = blend(a, seam, (0.18, 0.18, 0.17), 0.8)
    h -= 3.0 * seam
    bolts = dots(S // 4, 3, 8) * (1 - seam)
    a = blend(a, bolts, (0.32, 0.32, 0.32), 0.9)
    h += 1.5 * bolts
    return grime(rng, a, 0.25), h


def ceiling_tex(rng):
    a = np.ones((S, S, 3)) * np.array([0.60, 0.60, 0.58])
    a += (0.03 * fnoise(rng, 2.0) + 0.04 * fnoise(rng, 0.5))[..., None]
    tile = S // 4                                             # 0.5 m acoustic tiles
    grid = lines(tile, tile, 3)
    perf = dots(S // 16, 1, 4) * (1 - grid)
    a = blend(a, grid, (0.22, 0.22, 0.21), 0.85)
    a = blend(a, perf, (0.25, 0.25, 0.24), 0.7)
    h = 0.3 * fnoise(rng, 1.0) - 2.5 * grid - 1.0 * perf
    return grime(rng, a, 0.4), h


def door_tex(rng, color):
    steel = np.array([0.42, 0.44, 0.47])
    a = np.ones((S, S, 3)) * steel
    a += (0.04 * fnoise(rng, 2.0) + 0.03 * fnoise(rng, 0.6))[..., None]
    h = 0.4 * fnoise(rng, 1.2)
    yy, xx = np.mgrid[0:S, 0:S]
    edge = np.minimum(np.minimum(xx, S - 1 - xx), np.minimum(yy, S - 1 - yy))
    panel = (edge > 18).astype(float)                         # inset coloured plate
    a = blend(a, panel, color, 0.9)
    inner = (edge > 26).astype(float) * (edge < 30)
    h += 2.0 * panel - 2.0 * inner
    a = blend(a, inner, tuple(c * 0.55 for c in color), 0.7)
    chev = ((xx + yy) // 16 % 2).astype(float) * ((edge > 44) & (edge < 62)).astype(float)
    a = blend(a, chev, (0.95, 0.8, 0.1), 0.55)                # faint hazard band
    rivets = dots(S // 4, 3, 6) * (1 - panel)
    a = blend(a, rivets, (0.62, 0.63, 0.65), 0.9)
    h += 2.0 * rivets
    a = grime(rng, a, 0.3)
    return a, h


def secret_tex(rng):
    a, h = wall_tex(rng)
    yy, xx = np.mgrid[0:S, 0:S]
    edge = np.minimum(np.minimum(xx, S - 1 - xx), np.minimum(yy, S - 1 - yy))
    seam = ((edge > 10) & (edge < 14)).astype(float)          # a faint outline: for the observant
    a = blend(a, seam, (0.3, 0.28, 0.32), 0.7)
    a = blend(a, np.clip(fnoise(rng, 2.0) * 0.4, 0, 1), (0.35, 0.3, 0.42), 0.35)
    return a, h - 1.5 * seam


def lift_tex(rng):
    a = np.ones((S, S, 3)) * np.array([0.78, 0.62, 0.15])
    a += (0.05 * fnoise(rng, 2.0))[..., None]
    yy, xx = np.mgrid[0:S, 0:S]
    d1 = (((xx + yy) % 32) < 6).astype(float)                 # diamond plate
    d2 = (((xx - yy) % 32) < 6).astype(float)
    plate = np.clip(d1 + d2, 0, 1)
    a = blend(a, plate, (0.45, 0.35, 0.06), 0.6)
    h = 2.5 * plate + 0.3 * fnoise(rng, 1.0)
    return grime(rng, a, 0.35), h


def ladder_tex(rng):
    a = np.ones((S, S, 3)) * np.array([0.48, 0.30, 0.17])
    a += (0.05 * fnoise(rng, 1.5, (1, 6)) + 0.03 * fnoise(rng, 0.6))[..., None]
    plank = lines(S // 4, 0, 3)
    a = blend(a, plank, (0.1, 0.06, 0.03), 0.8)
    rust = np.clip(fnoise(rng, 2.5) * 0.7 - 0.1, 0, 1)
    a = blend(a, rust, (0.55, 0.25, 0.08), 0.4)
    return a, 0.5 * fnoise(rng, 1.0, (1, 5)) - 2.0 * plank


TEXTURES = {
    "floor": floor_tex, "wall": wall_tex, "ceiling": ceiling_tex,
    "door_red": lambda r: door_tex(r, (0.74, 0.12, 0.10)),
    "door_blue": lambda r: door_tex(r, (0.14, 0.30, 0.78)),
    "secret": secret_tex, "lift": lift_tex, "ladder": ladder_tex,
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i, (name, fn) in enumerate(TEXTURES.items()):
        rng = np.random.default_rng(1000 + i)
        a, h = fn(rng)
        save(name, a, h)
        print("wrote", name)
    # contact sheet (2x2 tiling of each) for a quick look
    names = list(TEXTURES)
    sheet = Image.new("RGB", (S * 2 * 4, S * 2 * 2))
    for i, n in enumerate(names):
        t = Image.open(os.path.join(OUT, n + ".png")).convert("RGB")
        for ty in range(2):
            for tx in range(2):
                sheet.paste(t, ((i % 4) * S * 2 + tx * S, (i // 4) * S * 2 + ty * S))
    sheet = sheet.resize((sheet.width // 2, sheet.height // 2))
    sheet.save(os.path.join(os.path.dirname(__file__), "..", "docs", "textures_sheet.png"))
