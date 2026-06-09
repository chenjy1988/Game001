#!/usr/bin/env python3
"""
gen_transition_masks.py — 为 hex 边界 biome 混合预合成"方向过渡 tile"

输出（每个 biome × 6 个方向）：
    assets/terrain/ai/transition/<biome>_dir<idx>.png    144×144 RGBA

含义：
    把 ai/<biome>_0.png（biome 代表 tile）按"朝向方向 idx 衰减的 alpha 渐变"
    重新合成的 tile：
        - 朝向邻居那一侧 alpha = 1
        - 远离邻居方向 alpha = 0
        - hex 形状外 alpha = 0
    渲染时如果某 hex 的方向 idx 邻居 biome 不同，就在自己 tile 上面叠这张
    transition tile，从而实现"邻居 biome 渗透到自己一边"的过渡。

idx 顺序与 HexCoord.DIRECTIONS 一致：
    0: E   1: NE   2: NW   3: W   4: SW   5: SE
"""
import math
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TILE_DIR = os.path.join(ROOT, "assets", "terrain", "ai")
OUT_DIR = os.path.join(TILE_DIR, "transition")
SIZE = 144

BIOMES = ["grass", "leaf", "rocky", "dirt"]

# 每方向的单位向量（pointy-top hex 邻居中心相对偏移方向；y 屏幕向下为 +）
# 与 HexCoord.DIRECTIONS 顺序对应：E, NE, NW, W, SW, SE
SQ3_2 = math.sqrt(3.0) / 2.0
DIRS_VEC = [
    ( 1.0,            0.0   ),  # 0  E
    ( SQ3_2,         -0.5   ),  # 1  NE  (向上偏右)
    (-SQ3_2,         -0.5   ),  # 2  NW  (向上偏左)
    (-1.0,            0.0   ),  # 3  W
    (-SQ3_2,          0.5   ),  # 4  SW  (向下偏左)
    ( SQ3_2,          0.5   ),  # 5  SE  (向下偏右)
]


def _hex_mask(size: int) -> np.ndarray:
    img = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(img)
    cx = size / 2.0
    cy = size / 2.0
    r = size / 2.0 + 0.5
    pts = []
    for i in range(6):
        ang = math.radians(60.0 * i - 30.0)
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    draw.polygon(pts, fill=255)
    img = img.filter(ImageFilter.GaussianBlur(radius=0.4))
    return np.asarray(img, dtype=np.float32) / 255.0


def _direction_alpha(size: int, dx: float, dy: float) -> np.ndarray:
    """
    朝向方向 (dx, dy) 衰减的 alpha 渐变 [0, 1]。
    朝向那一侧 = 1，反向 = 0，中心 ~0.45。
    """
    cx = size / 2.0
    cy = size / 2.0
    r = size / 2.0
    ys, xs = np.indices((size, size), dtype=np.float32)
    px = (xs - cx) / r
    py = (ys - cy) / r
    norm = math.sqrt(dx * dx + dy * dy)
    udx = dx / norm
    udy = dy / norm
    proj = px * udx + py * udy   # [-1, 1]
    # 让渐变区间映射到 [-0.4, 1.0] → 0..1：朝向那一侧 alpha 强，反向几乎全 0
    a = (proj + 0.40) / 1.40
    a = np.clip(a, 0.0, 1.0)
    a = a * a * (3.0 - 2.0 * a)   # smoothstep 柔化
    return a


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    hex_a = _hex_mask(SIZE)
    out_count = 0
    for biome in BIOMES:
        src_path = os.path.join(TILE_DIR, f"{biome}_0.png")
        if not os.path.exists(src_path):
            print(f"[WARN] biome 源图不存在: {src_path}", file=sys.stderr)
            continue
        src = Image.open(src_path).convert("RGBA")
        if src.size != (SIZE, SIZE):
            src = src.resize((SIZE, SIZE), Image.LANCZOS)
        src_arr = np.asarray(src, dtype=np.float32) / 255.0    # (H, W, 4)
        for idx, (dx, dy) in enumerate(DIRS_VEC):
            dir_a = _direction_alpha(SIZE, dx, dy)
            # 最终 alpha = src 自身 alpha (= hex 形状) × 方向渐变
            final_a = src_arr[..., 3] * hex_a * dir_a
            rgba = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
            rgba[..., 0:3] = src_arr[..., 0:3]
            rgba[..., 3] = final_a
            out = (rgba * 255.0).clip(0, 255).astype(np.uint8)
            img = Image.fromarray(out, mode="RGBA")
            img.save(os.path.join(OUT_DIR, f"{biome}_dir{idx}.png"), optimize=True)
            out_count += 1
    print(f"[done] {out_count} transition tiles -> {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
