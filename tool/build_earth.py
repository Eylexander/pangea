"""Builds assets/earth.jpg: NASA's Blue Marble (public domain) reprojected to the map's Equal Earth projection.

    pip install numpy pillow
    python tool/build_earth.py [dir]

[dir] must hold world.topo.bathy.200407.3x5400x2700.jpg (downloaded there if missing): Blue Marble Next Generation,
July (the least snow where most countries are), with topography and bathymetry. The output covers exactly
`EqualEarth.world` in lib/world.dart (latitudes 84 N to 58 S, Antarctica left out); pixels outside the Earth's
outline are the app's space color.
"""

import math
import os
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageEnhance

SRC = ('https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73751/'
       'world.topo.bathy.200407.3x5400x2700.jpg')
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'earth.jpg')
WIDTH = 4096
SPACE = (7, 11, 20)  # #070B14, Earth's background in the app (map.dart, MapPalette.space)

A1, A2, A3, A4 = 1.340264, -0.081106, 0.000893, 0.003796
M = math.sqrt(3) / 2


def project_y(lat):
    t = math.asin(M * math.sin(math.radians(lat)))
    return -(t * (A1 + A2 * t * t + t ** 6 * (A3 + A4 * t * t)))


def main():
    src_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
    path = os.path.join(src_dir, os.path.basename(SRC))
    if not os.path.exists(path):
        urllib.request.urlretrieve(SRC, path)
    src = np.asarray(Image.open(path).convert('RGB'), dtype=np.float32)
    sh, sw, _ = src.shape

    # Same rectangle as EqualEarth.world.
    x_max = 2 * math.sqrt(3) * math.pi / (3 * A1)
    top, bottom = project_y(84), project_y(-58)
    height = round(WIDTH * (bottom - top) / (2 * x_max))

    xs = (np.arange(WIDTH) + 0.5) / WIDTH * 2 * x_max - x_max
    ys = top + (np.arange(height) + 0.5) / height * (bottom - top)

    # Invert y → θ per row (Newton), then x → longitude per pixel.
    theta = np.empty(height)
    for i, y in enumerate(-ys):
        t = y
        for _ in range(12):
            f = t * (A1 + A2 * t * t + t ** 6 * (A3 + A4 * t * t)) - y
            t -= f / (A1 + 3 * A2 * t * t + t ** 6 * (7 * A3 + 9 * A4 * t * t))
        theta[i] = t
    t = theta[:, None]
    t2 = t * t
    t6 = t2 ** 3
    lon = xs[None, :] * 3 * (9 * A4 * t6 * t2 + 7 * A3 * t6 + 3 * A2 * t2 + A1) / (2 * math.sqrt(3) * np.cos(t))
    lat = np.arcsin(np.clip(np.sin(t) / M, -1, 1)) * np.ones_like(lon)
    lon_deg, lat_deg = np.degrees(lon), np.degrees(lat)
    inside = np.abs(lon_deg) <= 180

    # Bilinear sampling of the equirectangular source.
    u = np.clip((lon_deg + 180) / 360 * sw - 0.5, 0, sw - 1.001)
    v = np.clip((90 - lat_deg) / 180 * sh - 0.5, 0, sh - 1.001)
    u0, v0 = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = (u - u0)[..., None], (v - v0)[..., None]
    out = (src[v0, u0] * (1 - fu) * (1 - fv) + src[v0, u0 + 1] * fu * (1 - fv)
           + src[v0 + 1, u0] * (1 - fu) * fv + src[v0 + 1, u0 + 1] * fu * fv)
    out[~inside] = SPACE

    img = Image.fromarray(out.clip(0, 255).astype(np.uint8))
    # Blue Marble is dark and muted at phone sizes: a little lift.
    img = ImageEnhance.Brightness(img).enhance(1.12)
    img = ImageEnhance.Color(img).enhance(1.12)
    img.save(OUT, quality=86, optimize=True, progressive=True)
    print(f'{WIDTH}x{height}, {os.path.getsize(OUT) // 1024} KB')


if __name__ == '__main__':
    main()
