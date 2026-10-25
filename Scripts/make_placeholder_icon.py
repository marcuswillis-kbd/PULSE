#!/usr/bin/env python3
"""Write an opaque 1024x1024 placeholder icon (no alpha channel)."""

import struct
import zlib
from pathlib import Path


def write_png(path: Path, width: int, height: int, pixel) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixel(x, y))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def icon_pixel(x: int, y: int):
    cx = cy = 512
    dx = x - cx
    dy = y - cy
    dist = (dx * dx + dy * dy) ** 0.5
    if dist < 250:
        return (12, 48, 58)
    if dist < 300:
        return (61, 220, 230)
    # A simple pulse across the middle of the disc.
    if 280 < dist < 300:
        return (61, 220, 230)
    pulse_y = 512
    if 250 <= x <= 774:
        local = (x - 512) / 262
        # Piecewise heartbeat: flat, spike up, spike down, flat.
        if -0.15 <= local < 0.0:
            pulse_y = 512 - int(180 * (local + 0.15) / 0.15)
        elif 0.0 <= local < 0.08:
            pulse_y = 332 + int(360 * local / 0.08)
        elif 0.08 <= local < 0.22:
            pulse_y = 692 - int(180 * (local - 0.08) / 0.14)
        if abs(y - pulse_y) <= 10 and dist < 248:
            return (232, 250, 252)
    return (7, 16, 24)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    targets = [
        root / "Phone/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        root / "Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    ]
    blob = None
    for target in targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        if blob is None:
            write_png(target, 1024, 1024, icon_pixel)
            blob = target.read_bytes()
        else:
            target.write_bytes(blob)
        print(target, len(blob))


if __name__ == "__main__":
    main()
