#!/usr/bin/env python3
"""
gen_biome_atlas.py — 把 AI 生成的 4-grid 战场地形拼图加工成 4 张 biome 大纹理。

输入：assets/terrain/ai_raw/terrain_4grid.png  （2×2 拼图）
        左上 grass / 右上 dirt
        左下 leaf  / 右下 rocky

输出：assets/terrain/ai/atlas/
        grass.png / dirt.png / leaf.png / rocky.png   （1024×1024 RGB，seamless）

—— 设计要点（消除万花筒/对称伪影） ——

之前用 4×4 mirror tile + Godot TEXTURE_REPEAT_MIRROR 的方案存在严重副作用：
镜像在每个角点处形成 4 重对称中心，整张 atlas 出现明显的"星星/钻石"图案，
配合 atlas wrap 边界的 MIRROR 又叠加放大，肉眼能直接数出无数对称轴。

正确做法是 **让 atlas 真正无缝**，全程不依赖任何镜像，平铺即连续：
  1) Offset+Feather 法构造无缝纹理：
     - 把图像循环移位 (W/2, H/2)，原本在边缘的内容现在到了中心
     - 用平滑 alpha mask（中心 1.0、边缘 0.0）把原图与移位图混合
     - 结果：边缘像素 = 来自中心区域的内容；左右/上下边缘对应的就是同一段中心内容
     - 平铺时左边缘紧挨右边缘 = 同一段内容连续 → 无可见接缝
  2) Godot 端用 TEXTURE_REPEAT_ENABLED（普通 wrap，不是 MIRROR）
     - 没有镜像就没有对称轴，绝不出现万花筒图案

加工管线（每个 biome）：
  a) 切 quadrant + center crop 到正方形
  b) 缩到 ATLAS_SIZE×ATLAS_SIZE  ← 主体物适中（约 hex 大小）
  c) 多轮光照展平（去中心暗辐射 / 残留亮斑）
  d) 轻锐化 + 微对比度
  e) Offset+Feather 制作无缝纹理（不做任何镜像/4×4 平铺）
"""
import os
import sys
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_PATH = os.path.join(ROOT, "assets", "terrain", "ai_raw", "terrain_4grid.png")
OUT_DIR = os.path.join(ROOT, "assets", "terrain", "ai", "atlas")

ATLAS_SIZE = 1024  # 输出分辨率（也即内容尺度：1024 atlas px → 配合 uv_scale=1/256，主体物 ≈ 1 hex）

QUADRANTS = {
    "grass": (0, 0),
    "dirt":  (1, 0),
    "leaf":  (0, 1),
    "rocky": (1, 1),
}


def _flatten_lighting(img: Image.Image, blur_frac: float = 0.30) -> Image.Image:
    """单轮光照展平：用大半径模糊估计低频光照场，把整图除以光照场归一化。"""
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    blur_radius = max(img.size) * blur_frac
    light = img.convert("L").filter(ImageFilter.GaussianBlur(radius=blur_radius))
    light_arr = np.asarray(light, dtype=np.float32) / 255.0
    light_arr = np.clip(light_arr, 0.15, 1.0)
    target = float(np.asarray(img.convert("L"), dtype=np.float32).mean()) / 255.0
    factor = (target / light_arr)[:, :, None]
    out = rgb * factor
    out = np.clip(out, 0.0, 1.0)
    return Image.fromarray((out * 255.0).astype("uint8"), "RGB")


def _smooth_ramp(L: int, edge_frac: float) -> np.ndarray:
    """生成平滑 alpha：中央 1.0，两端各 edge_frac*L 长度内余弦平滑过渡到 0.0。"""
    a = np.ones(L, dtype=np.float32)
    edge = max(1, int(L * edge_frac))
    for i in range(edge):
        t = i / float(edge)  # 0 在最外缘，1 在内边界
        a[i] = 0.5 - 0.5 * np.cos(np.pi * t)  # 0→1 余弦
        a[L - 1 - i] = a[i]
    return a


def _make_seamless(img: Image.Image, feather_frac: float = 0.25) -> Image.Image:
    """
    分轴 1D Offset+Feather 法做无缝纹理（no mirror、no seam leak）。

    背景：早期版本用 2D 外积 alpha = ax(x)*ay(y)，结果在 (y=H/2, x=0) 这类
    "shifted 自身 seam 与 alpha=0 重合"的位置，shifted 内部 seam 直接泄露到
    输出，atlas 中央 row 511↔512 出现 ~19/255 的横向跳变 → 屏幕上一条水平线。

    正确做法：分轴两次 1D 处理，每次只 roll 一个轴，shifted 的 seam 始终落在
    alpha=1 的区域里，永远不会泄露。

    步骤：
      Step 1（水平方向无缝化）：
        shifted_h = roll(arr, W/2, axis=1)  ← 只 x shift，y 不变
        alpha_x   = 1 在中心 50% 列，余弦渐降到 0 在最外列
        out1 = arr * alpha_x + shifted_h * (1 - alpha_x)
        - shifted_h 的 seam 在 x=W/2 这一列，那里 alpha_x=1 → seam 完全屏蔽
        - 左右边缘 alpha_x=0 → 输出 = shifted_h[edge] = arr 的中央相邻列
          → 左右边缘对应原图相邻像素 → 平铺时 wrap 处连续
        - 垂直方向 (y) 完全没动，y 边缘原来啥样还啥样

      Step 2（垂直方向无缝化）：
        shifted_v = roll(out1, H/2, axis=0)  ← 只 y shift
        alpha_y   = 1 在中心 50% 行，余弦渐降到 0 在最外行
        out2 = out1 * alpha_y + shifted_v * (1 - alpha_y)
        - 同理 shifted_v 的 seam 在 y=H/2 行，那里 alpha_y=1 → seam 屏蔽
        - 上下边缘 alpha_y=0 → 输出 = out1 的中央相邻行 → 上下 wrap 连续
        - 不影响 x 方向无缝（step 2 不在 x 方向 shift）

    最终四个边缘都无缝、内部无任何 seam 泄露。
    """
    arr = np.asarray(img, dtype=np.float32)
    H, W = arr.shape[:2]

    # Step 1：水平无缝
    shifted_h = np.roll(arr, W // 2, axis=1)
    ax = _smooth_ramp(W, feather_frac)[None, :, None]   # (1, W, 1)
    out1 = arr * ax + shifted_h * (1.0 - ax)

    # Step 2：垂直无缝
    shifted_v = np.roll(out1, H // 2, axis=0)
    ay = _smooth_ramp(H, feather_frac)[:, None, None]   # (H, 1, 1)
    out2 = out1 * ay + shifted_v * (1.0 - ay)

    out = np.clip(out2, 0.0, 255.0).astype(np.uint8)
    return Image.fromarray(out, "RGB")


def _process_biome(quad: Image.Image) -> Image.Image:
    # 1) center crop 取 1:1 区域
    qw, qh = quad.size
    side = min(qw, qh)
    cx, cy = qw // 2, qh // 2
    flat = quad.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2))
    # 2) 缩到 ATLAS_SIZE
    flat = flat.resize((ATLAS_SIZE, ATLAS_SIZE), Image.LANCZOS)
    # 3) 光照展平：第 1 轮去大尺度光照，第 2 轮去残留中尺度亮斑
    flat = _flatten_lighting(flat, blur_frac=0.35)
    flat = _flatten_lighting(flat, blur_frac=0.18)
    # 4) 轻锐化
    flat = flat.filter(ImageFilter.UnsharpMask(radius=1.0, percent=60, threshold=2))
    # 5) 微提对比度
    flat = ImageEnhance.Contrast(flat).enhance(1.05)
    # 6) Offset+Feather 做无缝（不做任何镜像/平铺）
    flat = _make_seamless(flat, feather_frac=0.25)
    return flat


def main() -> int:
    if not os.path.exists(SRC_PATH):
        print(f"[ERR] 原图不存在: {SRC_PATH}", file=sys.stderr)
        return 1
    src = Image.open(SRC_PATH).convert("RGB")
    sw, sh = src.size
    print(f"[input] {SRC_PATH}  {sw}×{sh}")

    half_w, half_h = sw // 2, sh // 2
    os.makedirs(OUT_DIR, exist_ok=True)

    for name, (col, row) in QUADRANTS.items():
        x0 = col * half_w
        y0 = row * half_h
        quad = src.crop((x0, y0, x0 + half_w, y0 + half_h))
        atlas = _process_biome(quad)
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        atlas.save(out_path, optimize=True)
        print(f"  -> {out_path}  ({ATLAS_SIZE}×{ATLAS_SIZE}, seamless via offset+feather)")

    print(f"[done] 4 atlases written to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
