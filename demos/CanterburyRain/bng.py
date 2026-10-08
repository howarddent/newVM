"""WGS84 latitude/longitude -> British National Grid (OSGB36) easting/northing.

Shared by make_location_data.py and make_county_data.py, so the places, the
Irish/Manx context outline and the ONS county boundaries (published in BNG)
all land on the same map coordinates. Helmert datum shift WGS84 -> OSGB36
then the transverse Mercator projection on the Airy 1830 ellipsoid, after
the Ordnance Survey's "A guide to coordinate systems in Great Britain";
good to a few metres in Great Britain, and usable (if unofficial) for
Ireland, which only needs to look right on a small map.
"""
import math


def _helmert_wgs84_to_osgb36(lat, lon):
    a, b = 6378137.0, 6356752.3141                  # WGS84
    e2 = 1 - (b * b) / (a * a)
    phi, lam = math.radians(lat), math.radians(lon)
    nu = a / math.sqrt(1 - e2 * math.sin(phi) ** 2)
    x = nu * math.cos(phi) * math.cos(lam)
    y = nu * math.cos(phi) * math.sin(lam)
    z = (1 - e2) * nu * math.sin(phi)
    tx, ty, tz = -446.448, 125.157, -542.060
    s = 20.4894e-6
    rx, ry, rz = (math.radians(v / 3600) for v in (-0.1502, -0.2470, -0.8421))
    x2 = tx + (1 + s) * x - rz * y + ry * z
    y2 = ty + rz * x + (1 + s) * y - rx * z
    z2 = tz - ry * x + rx * y + (1 + s) * z
    a, b = 6377563.396, 6356256.909                 # Airy 1830
    e2 = 1 - (b * b) / (a * a)
    p = math.hypot(x2, y2)
    phi = math.atan2(z2, p * (1 - e2))
    for _ in range(10):
        nu = a / math.sqrt(1 - e2 * math.sin(phi) ** 2)
        phi = math.atan2(z2 + e2 * nu * math.sin(phi), p)
    return phi, math.atan2(y2, x2)


def to_bng(lat, lon):
    phi, lam = _helmert_wgs84_to_osgb36(lat, lon)
    a, b = 6377563.396, 6356256.909
    F0 = 0.9996012717
    phi0, lam0 = math.radians(49), math.radians(-2)
    N0, E0 = -100000, 400000
    e2 = 1 - (b * b) / (a * a)
    n = (a - b) / (a + b)
    s, c = math.sin(phi), math.cos(phi)
    nu = a * F0 / math.sqrt(1 - e2 * s * s)
    rho = a * F0 * (1 - e2) / (1 - e2 * s * s) ** 1.5
    eta2 = nu / rho - 1
    dphi, sphi = phi - phi0, phi + phi0
    M = b * F0 * ((1 + n + 1.25 * n * n + 1.25 * n ** 3) * dphi
                  - (3 * n + 3 * n * n + 21 / 8 * n ** 3) * math.sin(dphi) * math.cos(sphi)
                  + (15 / 8 * n * n + 15 / 8 * n ** 3) * math.sin(2 * dphi) * math.cos(2 * sphi)
                  - 35 / 24 * n ** 3 * math.sin(3 * dphi) * math.cos(3 * sphi))
    t = math.tan(phi)
    I = M + N0
    II = nu / 2 * s * c
    III = nu / 24 * s * c ** 3 * (5 - t * t + 9 * eta2)
    IIIA = nu / 720 * s * c ** 5 * (61 - 58 * t * t + t ** 4)
    IV = nu * c
    V = nu / 6 * c ** 3 * (nu / rho - t * t)
    VI = nu / 120 * c ** 5 * (5 - 18 * t * t + t ** 4 + 14 * eta2 - 58 * t * t * eta2)
    dl = lam - lam0
    N = I + II * dl ** 2 + III * dl ** 4 + IIIA * dl ** 6
    E = E0 + IV * dl + V * dl ** 3 + VI * dl ** 5
    return E, N


if __name__ == '__main__':
    # OS worked example: 52 39' 27.2531"N, 1 43' 4.5177"E (OSGB36) -> E 651409.903, N 313177.270
    # Checked here via WGS84 inputs for Canterbury against ONS-style values instead:
    print(to_bng(51.27904, 1.07992))
