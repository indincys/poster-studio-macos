#!/usr/bin/env python3

import struct
import sys
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
TYPE_BY_SIZE = {
    16: b"icp4",
    32: b"icp5",
    64: b"icp6",
    128: b"ic07",
    256: b"ic08",
    512: b"ic09",
    1024: b"ic10",
}


def read_png_size(path: Path) -> int:
    data = path.read_bytes()
    if data[:8] != PNG_SIGNATURE:
        raise ValueError(f"{path} is not a PNG")
    width = struct.unpack(">I", data[16:20])[0]
    height = struct.unpack(">I", data[20:24])[0]
    if width != height:
        raise ValueError(f"{path} is not square")
    return width


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: build_icns.py <output.icns> <png> [<png> ...]", file=sys.stderr)
        return 1

    output = Path(sys.argv[1])
    chunks: list[tuple[int, bytes]] = []

    for raw_path in sys.argv[2:]:
        path = Path(raw_path)
        size = read_png_size(path)
        icon_type = TYPE_BY_SIZE.get(size)
        if icon_type is None:
            raise ValueError(f"Unsupported PNG size for ICNS: {size} ({path})")
        data = path.read_bytes()
        chunk = icon_type + struct.pack(">I", len(data) + 8) + data
        chunks.append((size, chunk))

    chunks.sort(key=lambda item: item[0])
    body = b"".join(chunk for _, chunk in chunks)
    output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
