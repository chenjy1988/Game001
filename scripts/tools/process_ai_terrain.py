#!/usr/bin/env python3
"""
process_ai_terrain.py — 把 AI 生成的 4-grid 战场地形拼图切分并加工成 hex tile

输入：assets/terrain/ai_raw/terrain_4grid.png
        2×2 拼图，4 个象限分别是：
        左上 grass / 右上 dirt
        左下 leaf  / 右下 rocky

输出：assets/terrain/ai/
        grass_0..2.png       (3 张草地变体)
        dirt_0..2.png        (3 张泥地变体)
        leaf_0..2.png        (3 张枯叶变体)
        rocky_0..2.png       (3 张石砾变体)

每张输出：144×144 RGBA，pointy-top hex 形状（外接圆半径 72px），
        其余区域透明，hex 边缘有 1-2px 抗锯齿羽化。

加工管线（每个象限）：
  1) 从象限图 (≥512×512) 中随机选 3 个 256×256 子区域（保持画面有变化）
     不同子区域之间至少错开 60px，避免重复
  2) 每个子区域：旋转 / 翻转 一次随机变换（增加视觉差异）
  3) 应用色调微扰动（HSV 各 ±5%），让 3 个变体看起来"不是同一张"
  4) 缩放到 144×144（Lanczos）
  5) 应用 hex mask（pointy-top，144×144 内一个外接圆=72px 的 hex）
     边缘 1.5px alpha 渐变（消除毛边）
  6) 整体微调对比/锐化，保留细节
"""
import os
import sys
import math
import random
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_PATH = os.path.join(ROOT, "assets", "terrain", "ai_raw", "terrain_4grid.png")
OUT_DIR = os.path.join(ROOT, "assets", "terrain", "ai")

VARIANTS_PER_BIOME = 3      # 每种地形输出几张变体
TILE_SIZE = 144             # 输出尺寸（2×72：高分辨率 hex，HexGrid 以 0.5 缩放绘制保持锐利）
                            # 也可改为 72 直接匹配 HEX_SIZE=36，但放大会糊；用 144 + 缩放显示更清晰
SUB_SIZE = 256              # 从象限里随机裁出的子区域大小

# 4 象限 → biome 名映射
QUADRANTS = {
    "grass": (0, 0),    # (col, row) in 2×2
    "dirt":  (1, 0),
    "leaf":  (0, 1),
    "rocky": (1, 1),
}

SEED = 20260531


def _build_hex_mask(size: int) -> Image.Image:
    """生成 pointy-top hex mask。
    边缘几乎不羽化（仅 0.4px 防锯齿），保证相邻 hex 拼接时**没有暗缝**。
    """
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    cx = size / 2.0
    cy = size / 2.0
    # 外接圆半径稍微外扩（+0.5px），让相邻 hex 共享 1px 重叠 → 无缝
    r = size / 2.0 + 0.5
    pts = []
    for i in range(6):
        ang_deg = 60.0 * i - 30.0   # pointy-top
        ang = math.radians(ang_deg)
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    draw.polygon(pts, fill=255)
    # 极小高斯（0.4px）只为了消锯齿，不羽化 alpha
    mask = mask.filter(ImageFilter.GaussianBlur(radius=0.4))
    return mask


def _flatten_lighting(img: Image.Image) -> Image.Image:
    """
    去除"中心暗 / 角落亮"的辐射性光照渐变。

    原理：用大尺度 Gaussian blur 估计画面的低频亮度场（即"光照"），
    然后用原图除以这个场，得到亮度均匀的"反照率"图。

    这样裁出来每张 tile 内部都没有"中心暗辐射"，相邻 hex 拼接时不会出现网格状视觉边界。
    """
    import numpy as np
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    # 估计亮度场：转灰度大幅模糊（核约图宽 1/4）
    blur_radius = max(img.size) * 0.25
    light = img.convert("L").filter(ImageFilter.GaussianBlur(radius=blur_radius))
    light_arr = np.asarray(light, dtype=np.float32) / 255.0
    light_arr = np.clip(light_arr, 0.15, 1.0)   # 防除 0
    # 目标平均亮度（原图灰度均值）
    target = float(np.asarray(img.convert("L"), dtype=np.float32).mean()) / 255.0
    # 每像素 = rgb * (target / light)
    factor = (target / light_arr)[:, :, None]
    out = rgb * factor
    out = np.clip(out, 0.0, 1.0)
    return Image.fromarray((out * 255.0).astype("uint8"), "RGB")


def _crop_random_subregion(quadrant_img: Image.Image, rng: random.Random,
                           used_centers: list) -> Image.Image:
    """
    从象限图随机裁一块 SUB_SIZE×SUB_SIZE 区域，保证与已有裁切中心至少错开 60px。
    """
    qw, qh = quadrant_img.size
    if qw < SUB_SIZE or qh < SUB_SIZE:
        # 象限太小，直接返回 resize 后的整张
        return quadrant_img.resize((SUB_SIZE, SUB_SIZE), Image.LANCZOS)
    for _ in range(40):
        cx = rng.randint(SUB_SIZE // 2, qw - SUB_SIZE // 2)
        cy = rng.randint(SUB_SIZE // 2, qh - SUB_SIZE // 2)
        ok = True
        for (ux, uy) in used_centers:
            if (cx - ux) ** 2 + (cy - uy) ** 2 < 60 * 60:
                ok = False
                break
        if ok:
            used_centers.append((cx, cy))
            return quadrant_img.crop((
                cx - SUB_SIZE // 2, cy - SUB_SIZE // 2,
                cx + SUB_SIZE // 2, cy + SUB_SIZE // 2,
            ))
    # 多次失败，随便返回一个
    cx = rng.randint(SUB_SIZE // 2, qw - SUB_SIZE // 2)
    cy = rng.randint(SUB_SIZE // 2, qh - SUB_SIZE // 2)
    used_centers.append((cx, cy))
    return quadrant_img.crop((
        cx - SUB_SIZE // 2, cy - SUB_SIZE // 2,
        cx + SUB_SIZE // 2, cy + SUB_SIZE // 2,
    ))


def _rand_transform(img: Image.Image, rng: random.Random) -> Image.Image:
    """随机旋转 0/90/180/270 + 50% 概率水平翻转"""
    rot = rng.choice([0, 90, 180, 270])
    if rot:
        img = img.rotate(rot, expand=False)
    if rng.random() < 0.5:
        img = ImageOps.mirror(img)
    return img


def _color_jitter(img: Image.Image, rng: random.Random) -> Image.Image:
    """色调微扰：亮度/饱和/对比度各 ±8%"""
    img = ImageEnhance.Brightness(img).enhance(1.0 + rng.uniform(-0.08, 0.08))
    img = ImageEnhance.Color(img).enhance(1.0 + rng.uniform(-0.08, 0.08))
    img = ImageEnhance.Contrast(img).enhance(1.0 + rng.uniform(-0.08, 0.08))
    return img


def _process_one_tile(sub: Image.Image, hex_mask: Image.Image,
                      rng: random.Random) -> Image.Image:
    """SUB_SIZE 子图 → 144×144 hex RGBA tile"""
    # 1) 随机变换（增加视觉差异）
    sub = _rand_transform(sub, rng)
    # 2) 色调微扰
    sub = _color_jitter(sub, rng)
    # 3) 缩放到 TILE_SIZE
    sub = sub.resize((TILE_SIZE, TILE_SIZE), Image.LANCZOS)
    # 4) 轻微锐化以保留细节（缩放往往会糊化）
    sub = sub.filter(ImageFilter.UnsharpMask(radius=1.0, percent=80, threshold=2))
    # 5) 转 RGBA + 应用 hex mask
    if sub.mode != "RGBA":
        sub = sub.convert("RGBA")
    out = Image.new("RGBA", (TILE_SIZE, TILE_SIZE), (0, 0, 0, 0))
    out.paste(sub, (0, 0), mask=hex_mask)
    return out


def main() -> int:
    if not os.path.exists(SRC_PATH):
        print(f"[ERR] 原图不存在: {SRC_PATH}", file=sys.stderr)
        print(f"     请先把 4-grid 拼图保存到该路径", file=sys.stderr)
        return 1
    src = Image.open(SRC_PATH).convert("RGB")
    sw, sh = src.size
    print(f"[input] {SRC_PATH}  {sw}×{sh}")

    # 切成 4 象限，并对每个象限做"亮度均衡"
    # （AI 生成图常有"中心暗 / 边缘亮"的辐射光照，会让 hex tile 拼接时显出网格）
    half_w, half_h = sw // 2, sh // 2
    quadrants = {}
    for name, (col, row) in QUADRANTS.items():
        x0 = col * half_w
        y0 = row * half_h
        quad = src.crop((x0, y0, x0 + half_w, y0 + half_h))
        quad = _flatten_lighting(quad)
        quadrants[name] = quad

    # 准备 hex mask
    hex_mask = _build_hex_mask(TILE_SIZE)

    os.makedirs(OUT_DIR, exist_ok=True)

    rng = random.Random(SEED)
    out_count = 0
    for biome, quad in quadrants.items():
        used_centers = []
        for i in range(VARIANTS_PER_BIOME):
            sub = _crop_random_subregion(quad, rng, used_centers)
            tile = _process_one_tile(sub, hex_mask, rng)
            out_path = os.path.join(OUT_DIR, f"{biome}_{i}.png")
            tile.save(out_path, optimize=True)
            out_count += 1
            print(f"  -> {out_path}")
    print(f"[done] {out_count} tiles written to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
