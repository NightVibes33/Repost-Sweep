#!/usr/bin/env python3
"""Draw the Repost Sweep app icon. Standard library only."""

import math
import struct
import zlib
from pathlib import Path


WIDTH = 1024
HEIGHT = 1024


def write_png(path, width, height, rgba):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    rows = []
    stride = width * 4
    for y in range(height):
        rows.append(b"\x00" + rgba[y * stride : (y + 1) * stride])
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def blend(buffer, x, y, red, green, blue, alpha):
    if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT or alpha <= 0:
        return
    index = (y * WIDTH + x) * 4
    dst_a = buffer[index + 3] / 255
    src_a = max(0.0, min(1.0, alpha))
    out_a = src_a + dst_a * (1 - src_a)
    if out_a <= 0:
        return
    for channel, value in enumerate((red, green, blue)):
        dst = buffer[index + channel] / 255
        out = (value * src_a + dst * dst_a * (1 - src_a)) / out_a
        buffer[index + channel] = int(max(0, min(255, round(out * 255))))
    buffer[index + 3] = int(max(0, min(255, round(out_a * 255))))


def fill_disc(buffer, cx, cy, radius, color, softness=1.4):
    red, green, blue = color
    min_x = max(0, int(cx - radius - softness - 2))
    max_x = min(WIDTH - 1, int(cx + radius + softness + 2))
    min_y = max(0, int(cy - radius - softness - 2))
    max_y = min(HEIGHT - 1, int(cy + radius + softness + 2))
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            distance = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            alpha = max(0.0, min(1.0, (radius + softness - distance) / (softness * 2)))
            if alpha:
                blend(buffer, x, y, red, green, blue, alpha)


def main():
    buffer = bytearray(WIDTH * HEIGHT * 4)
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        red = int(16 + (28 - 16) * t)
        green = int(20 + (34 - 20) * t)
        blue = int(18 + (28 - 18) * t)
        row = y * WIDTH * 4
        for x in range(WIDTH):
            buffer[row + x * 4] = red
            buffer[row + x * 4 + 1] = green
            buffer[row + x * 4 + 2] = blue
            buffer[row + x * 4 + 3] = 255

    accent = (214 / 255, 242 / 255, 92 / 255)
    ink = (20 / 255, 32 / 255, 8 / 255)

    # Chartreuse sweep: a thick open ring with an arrow head.
    center_x, center_y = 512, 530
    ring_radius = 250
    stroke = 54
    start = math.radians(125)
    end = math.radians(400)
    steps = 140
    for step in range(steps + 1):
        angle = start + (end - start) * (step / steps)
        fill_disc(
            buffer,
            center_x + math.cos(angle) * ring_radius,
            center_y + math.sin(angle) * ring_radius,
            stroke / 2,
            accent,
            softness=1.2,
        )

    # Arrow head at the end of the sweep.
    tip_angle = end
    tip_x = center_x + math.cos(tip_angle) * ring_radius
    tip_y = center_y + math.sin(tip_angle) * ring_radius
    tangent = tip_angle + math.pi / 2
    head = 78
    left = tip_angle - 0.55
    right = tip_angle + 0.9
    points = [
        (tip_x + math.cos(tangent) * head, tip_y + math.sin(tangent) * head),
        (tip_x + math.cos(left) * stroke, tip_y + math.sin(left) * stroke),
        (tip_x + math.cos(right) * stroke, tip_y + math.sin(right) * stroke),
    ]
    min_x = max(0, int(min(p[0] for p in points) - 4))
    max_x = min(WIDTH - 1, int(max(p[0] for p in points) + 4))
    min_y = max(0, int(min(p[1] for p in points) - 4))
    max_y = min(HEIGHT - 1, int(max(p[1] for p in points) + 4))

    area = (
        points[0][0] * (points[1][1] - points[2][1])
        + points[1][0] * (points[2][1] - points[0][1])
        + points[2][0] * (points[0][1] - points[1][1])
    )
    if area < 0:
        points[1], points[2] = points[2], points[1]

    def edge(a, b, x, y):
        return (x - a[0]) * (b[1] - a[1]) - (y - a[1]) * (b[0] - a[0])

    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            px, py = x + 0.5, y + 0.5
            w0 = edge(points[1], points[2], px, py)
            w1 = edge(points[2], points[0], px, py)
            w2 = edge(points[0], points[1], px, py)
            if w0 >= 0 and w1 >= 0 and w2 >= 0:
                blend(buffer, x, y, *accent, 1)

    # Inner ink dot so the mark reads at small sizes.
    fill_disc(buffer, 512, 530, 46, ink, softness=1.3)
    fill_disc(buffer, 512, 530, 22, accent, softness=1.2)

    destination = Path(__file__).resolve().parents[1] / "RepostSweep" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    write_png(destination, WIDTH, HEIGHT, bytes(buffer))
    print(destination)


if __name__ == "__main__":
    main()
