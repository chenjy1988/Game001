#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "pillow>=10.0.0",
# ]
# ///
"""
assemble_spritesheet.py - 将多张素材图拼成固定网格的精灵图 + 坐标 JSON。

用法：
    uv run assemble_spritesheet.py \\
        --inputs img1.png img2.png img3.png ... \\
        --output spritesheet.png \\
        --cols 4 \\
        [--tile-size 128] \\
        [--padding 0] \\
        [--names player enemy coin ...]

输出：
    <output>.png   精灵图（RGBA）
    <output>.json  坐标数据（frames 数组，每项含 name / x / y / w / h）

JSON 格式示例：
{
  "meta": { "size": [512, 512], "cols": 4, "rows": 4, "tile_size": 128 },
  "frames": [
    { "name": "player", "x": 0,   "y": 0, "w": 128, "h": 128 },
    { "name": "enemy",  "x": 128, "y": 0, "w": 128, "h": 128 },
    ...
  ]
}
"""

import argparse
import json
import math
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Assemble sprites into a fixed grid sheet")
    parser.add_argument("--inputs", "-i", nargs="+", required=True, help="Input image paths (in order)")
    parser.add_argument("--output", "-o", required=True, help="Output spritesheet path (.png)")
    parser.add_argument("--cols", "-c", type=int, required=True, help="Number of columns in grid")
    parser.add_argument("--tile-size", "-t", type=int, default=128, help="Tile size in pixels (default: 128)")
    parser.add_argument("--padding", "-p", type=int, default=0, help="Padding between tiles in pixels")
    parser.add_argument("--names", "-n", nargs="+", help="Optional name for each frame (defaults to file stem)")
    parser.add_argument("--background", default="transparent",
                        choices=["transparent", "white"],
                        help="Background color for empty cells (default: transparent)")

    args = parser.parse_args()

    from PIL import Image

    inputs = [Path(p) for p in args.inputs]
    missing = [str(p) for p in inputs if not p.exists()]
    if missing:
        print(f"Error: input file(s) not found: {missing}", file=sys.stderr)
        sys.exit(1)

    if args.names and len(args.names) != len(inputs):
        print(
            f"Error: --names count ({len(args.names)}) must match --inputs count ({len(inputs)})",
            file=sys.stderr,
        )
        sys.exit(1)

    names = args.names if args.names else [p.stem for p in inputs]

    n = len(inputs)
    cols = args.cols
    rows = math.ceil(n / cols)
    tile = args.tile_size
    pad = args.padding

    # 每格实际占用 = tile + padding（首尾不留多余 padding）
    sheet_w = cols * tile + (cols - 1) * pad
    sheet_h = rows * tile + (rows - 1) * pad

    if args.background == "transparent":
        sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    else:
        sheet = Image.new("RGBA", (sheet_w, sheet_h), (255, 255, 255, 255))

    frames = []
    for idx, (path, name) in enumerate(zip(inputs, names)):
        col = idx % cols
        row = idx // cols
        x = col * (tile + pad)
        y = row * (tile + pad)

        img = Image.open(str(path)).convert("RGBA")
        # 等比缩放到 tile 大小，保持原始比例（不足则居中留透明）
        img.thumbnail((tile, tile), Image.LANCZOS)
        ox = x + (tile - img.width) // 2
        oy = y + (tile - img.height) // 2
        sheet.paste(img, (ox, oy), img)

        frames.append(
            {"name": name, "x": x, "y": y, "w": tile, "h": tile, "index": idx}
        )

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(str(out_path), "PNG")

    meta = {
        "size": [sheet_w, sheet_h],
        "cols": cols,
        "rows": rows,
        "tile_size": tile,
        "padding": pad,
        "count": n,
    }
    json_path = out_path.with_suffix(".json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({"meta": meta, "frames": frames}, f, ensure_ascii=False, indent=2)

    print(f"Spritesheet saved: {out_path.resolve()}")
    print(f"Coordinate JSON:   {json_path.resolve()}")
    print(f"Layout: {cols} cols x {rows} rows, tile {tile}px, total {sheet_w}x{sheet_h}")


if __name__ == "__main__":
    main()
