#!/usr/bin/env python3
"""Draw the Repost Sweep app icon. Standard library only."""

import math
import struct
import zlib
from pathlib import Path


WIDTH = 1024
HEIGHT = 1024
CYAN = (37 / 255, 244 / 255, 238 / 255)
PINK = (254 / 255, 44 / 255, 85 / 255)
WHITE = (1, 1, 1)


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


def blend(buffer, x, y, red, green, blue, alpha, width=WIDTH):
    if x < 0 or y < 0 or x >= width or y >= width or alpha <= 0:
        return
    index = (y * width + x) * 4
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


def fill_disc(buffer, cx, cy, radius, color, softness=1.6, width=WIDTH):
    red, green, blue = color
    min_x = max(0, int(cx - radius - softness - 2))
    max_x = min(width - 1, int(cx + radius + softness + 2))
    min_y = max(0, int(cy - radius - softness - 2))
    max_y = min(width - 1, int(cy + radius + softness + 2))
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            distance = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            alpha = max(0.0, min(1.0, (radius + softness - distance) / (softness * 2)))
            if alpha:
                blend(buffer, x, y, red, green, blue, alpha, width)


def stroke_arc(buffer, cx, cy, radius, start, end, thickness, color, steps=90):
    for step in range(steps + 1):
        angle = start + (end - start) * (step / steps)
        fill_disc(
            buffer,
            cx + math.cos(angle) * radius,
            cy + math.sin(angle) * radius,
            thickness / 2,
            color,
            softness=1.3,
        )


def fill_triangle(buffer, points, color):
    ordered = list(points)
    area = (
        ordered[0][0] * (ordered[1][1] - ordered[2][1])
        + ordered[1][0] * (ordered[2][1] - ordered[0][1])
        + ordered[2][0] * (ordered[0][1] - ordered[1][1])
    )
    if area < 0:
        ordered[1], ordered[2] = ordered[2], ordered[1]

    def edge(a, b, x, y):
        return (x - a[0]) * (b[1] - a[1]) - (y - a[1]) * (b[0] - a[0])

    min_x = max(0, int(min(p[0] for p in ordered) - 2))
    max_x = min(WIDTH - 1, int(max(p[0] for p in ordered) + 2))
    min_y = max(0, int(min(p[1] for p in ordered) - 2))
    max_y = min(HEIGHT - 1, int(max(p[1] for p in ordered) + 2))
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            px, py = x + 0.5, y + 0.5
            if edge(ordered[1], ordered[2], px, py) >= 0 and edge(ordered[2], ordered[0], px, py) >= 0 and edge(ordered[0], ordered[1], px, py) >= 0:
                blend(buffer, x, y, *color, 1)


def arrow_head(buffer, cx, cy, radius, angle, color, size=86):
    tip_x = cx + math.cos(angle) * radius
    tip_y = cy + math.sin(angle) * radius
    tangent = angle + math.pi / 2
    points = [
        (tip_x + math.cos(tangent) * size, tip_y + math.sin(tangent) * size),
        (tip_x + math.cos(angle - 0.7) * 36, tip_y + math.sin(angle - 0.7) * 36),
        (tip_x + math.cos(angle + 0.7) * 36, tip_y + math.sin(angle + 0.7) * 36),
    ]
    fill_triangle(buffer, points, color)


def stroke_line(buffer, x0, y0, x1, y1, thickness, color):
    length = max(1.0, math.hypot(x1 - x0, y1 - y0))
    steps = int(length / 3)
    for step in range(steps + 1):
        t = step / steps
        fill_disc(buffer, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, thickness / 2, color, softness=1.2)


def draw_master():
    buffer = bytearray(WIDTH * HEIGHT * 4)
    for index in range(0, len(buffer), 4):
        buffer[index + 3] = 255
    fill_disc(buffer, 280, 760, 280, CYAN, softness=180)
    # The glow discs are opaque; knock them back by painting black over most of the canvas.
    # Draw the glows first with low alpha instead.
    buffer = bytearray(WIDTH * HEIGHT * 4)
    for index in range(0, len(buffer), 4):
        buffer[index + 3] = 255
    for y in range(HEIGHT):
        for x in range(WIDTH):
            cyan_d = math.hypot(x - 250, y - 780) / 420
            pink_d = math.hypot(x - 790, y - 240) / 420
            glow = max(0.0, 0.22 - cyan_d * 0.22) + max(0.0, 0.20 - pink_d * 0.20)
            if glow:
                red = int(min(255, 37 * glow * 3))
                green = int(min(255, 20 * glow))
                blue = int(min(255, 40 * glow))
                buffer[(y * WIDTH + x) * 4] = red
                buffer[(y * WIDTH + x) * 4 + 1] = green
                buffer[(y * WIDTH + x) * 4 + 2] = blue

    center = 512
    radius = 250
    stroke_arc(buffer, center, center, radius, math.radians(200), math.radians(20), 58, CYAN, steps=110)
    stroke_arc(buffer, center + 18, center + 10, radius, math.radians(20), math.radians(200), 58, PINK, steps=110)
    arrow_head(buffer, center, center, radius, math.radians(20), CYAN)
    arrow_head(buffer, center + 18, center + 10, radius, math.radians(200), PINK)
    stroke_line(buffer, 390, 390, 640, 640, 54, WHITE)
    stroke_line(buffer, 640, 390, 390, 640, 54, WHITE)
    return buffer


def downscale(source, size):
    output = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            sx = min(WIDTH - 1, int((x + 0.5) * WIDTH / size))
            sy = min(HEIGHT - 1, int((y + 0.5) * HEIGHT / size))
            start = (sy * WIDTH + sx) * 4
            dest = (y * size + x) * 4
            output[dest : dest + 4] = source[start : start + 4]
    return output


def main():
    master = draw_master()
    folder = Path(__file__).resolve().parents[1] / "RepostSweep" / "Assets.xcassets" / "AppIcon.appiconset"
    folder.mkdir(parents=True, exist_ok=True)
    sizes = {
        "AppIcon.png": 1024,
        "Icon-20.png": 20,
        "Icon-20@2x.png": 40,
        "Icon-20@3x.png": 60,
        "Icon-29.png": 29,
        "Icon-29@2x.png": 58,
        "Icon-29@3x.png": 87,
        "Icon-40.png": 40,
        "Icon-40@2x.png": 80,
        "Icon-40@3x.png": 120,
        "Icon-60@2x.png": 120,
        "Icon-60@3x.png": 180,
        "Icon-76.png": 76,
        "Icon-76@2x.png": 152,
        "Icon-83.5@2x.png": 167,
    }
    for name, size in sizes.items():
        pixels = master if size == 1024 else downscale(master, size)
        path = folder / name
        write_png(path, size, size, bytes(pixels))
        print(path)


if __name__ == "__main__":
    main()
