#!/usr/bin/env python3
"""
gen_terrain_grass.py — 生成一张 512×512 无缝可平铺的写实草地纹理

输出：assets/terrain/terrain_grass_seamless.png

设计要点（要让它跟战兄弟"分辨率等级"匹配）：
  • 高频细节：多层叠加的小尺度噪声（模拟草叶）
  • 中频结构：中等尺度噪声形成草丛、深浅区
  • 低频偏置：极少量大尺度变化，避免整张同一颜色
  • 局部泥点：alpha 混合的暗棕色斑（不规则）
  • 颜色：photo 风的暖黄绿（不是绘画风的冷蓝绿）
  • 无缝：所有噪声层使用 wrap-around，平铺边界严格连续

实现：
  numpy + PIL，无外部噪声库依赖。用 random_seed + bilinear upscale
  从低分辨率噪声放大获得"软斑块"，多频率叠加得到 fractal noise。
  关键 trick：低分辨率噪声本身就是 wrap（生成时把第 N 列复制到第 0 列），
  upscale 后再 mod 一下，就保证 512×512 边界完全无缝。
"""
import os
import sys
import numpy as np
from PIL import Image

OUT_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", "assets", "terrain", "terrain_grass_seamless.png"
)
SIZE = 512
SEED = 20260531


def _seamless_value_noise(size: int, freq: int, rng: np.random.Generator) -> np.ndarray:
    """
    生成 size×size 的 wrap-around value noise。
    freq: 控制低分辨率网格大小（freq×freq 个噪声点，bilinear 上采样到 size）。
    返回 [0, 1] 浮点数组。
    """
    # 在 freq×freq 网格上生成随机值；为保证无缝，把第 0 行/列再复制到第 freq 行/列
    grid = rng.random((freq + 1, freq + 1)).astype(np.float32)
    grid[-1, :] = grid[0, :]
    grid[:, -1] = grid[:, 0]
    # bilinear upscale 到 size×size
    img = Image.fromarray((grid * 255).astype(np.uint8))
    img = img.resize((size + 1, size + 1), Image.BILINEAR)
    arr = np.asarray(img, dtype=np.float32) / 255.0
    return arr[:size, :size]   # 取无缝部分


def _fractal(size: int, octaves: int, base_freq: int, persistence: float,
             rng: np.random.Generator) -> np.ndarray:
    """多频叠加（每层频率 ×2，振幅 × persistence）"""
    total = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        f = base_freq * (2 ** o)
        if f > size:
            break
        n = _seamless_value_noise(size, f, rng)
        total += n * amp
        norm += amp
        amp *= persistence
    total /= norm
    # 重新规范到 [0, 1]
    lo, hi = total.min(), total.max()
    if hi > lo:
        total = (total - lo) / (hi - lo)
    return total


def _grass_color_map(low: np.ndarray, mid: np.ndarray, hi: np.ndarray) -> np.ndarray:
    """把 3 层噪声映射到 RGB（photo 风暖黄绿草地）"""
    h, w = low.shape
    # 主色：暖黄绿（基于 mid 噪声做 lerp）
    # 草尖（亮）：偏黄绿；草根（暗）：偏深绿/橄榄
    bright = np.array([0.55, 0.62, 0.32])   # 亮草
    dark   = np.array([0.22, 0.28, 0.12])   # 暗草根
    olive  = np.array([0.36, 0.40, 0.18])   # 橄榄
    t_mid = mid[:, :, None]
    rgb = bright * t_mid + dark * (1.0 - t_mid)
    # 用 low 噪声引入大面积冷暖偏移（让画面非死板）
    offset = (low[:, :, None] - 0.5) * 0.10
    rgb = rgb + offset
    # 高频细节：用 hi 噪声叠加亮度（模拟草叶光斑）
    detail = (hi[:, :, None] - 0.5) * 0.30
    rgb = rgb + detail
    # olive 局部偏色（按 mid 中段强化）
    olive_mask = (np.abs(mid - 0.5) < 0.08)[:, :, None].astype(np.float32) * 0.25
    rgb = rgb * (1.0 - olive_mask) + olive * olive_mask
    return np.clip(rgb, 0.0, 1.0)


def _add_dirt_patches(rgb: np.ndarray, dirt_mask: np.ndarray) -> np.ndarray:
    """在 dirt_mask > 阈值的位置混入暗棕泥点"""
    dirt_color = np.array([0.34, 0.25, 0.16])   # 暗棕
    dirt_dark  = np.array([0.22, 0.16, 0.10])   # 极暗棕（中心）
    # 阈值与混合强度
    t = np.clip((dirt_mask - 0.65) / 0.30, 0.0, 1.0)   # 0.65~0.95 渐变
    t_strong = np.clip((dirt_mask - 0.78) / 0.20, 0.0, 1.0)
    t = t[:, :, None]
    t_strong = t_strong[:, :, None]
    rgb = rgb * (1.0 - t) + dirt_color * t
    rgb = rgb * (1.0 - t_strong) + dirt_dark * t_strong
    return rgb


def _add_grass_blades(rgb: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """在表面上撒上一些"草叶"高光像素（极小高频细节）"""
    h, w, _ = rgb.shape
    # 概率撒点（每像素 ~0.8% 命中）
    mask = rng.random((h, w)) < 0.008
    # 命中的像素亮度提升、偏黄绿
    blade = np.array([0.78, 0.85, 0.45])
    for c in range(3):
        rgb[..., c] = np.where(mask, blade[c], rgb[..., c])
    # 再撒一些"花"（极少量红/白点，<0.05%）
    flower_mask = rng.random((h, w)) < 0.0005
    flower_red = np.array([0.78, 0.20, 0.18])
    flower_white = rng.random((h, w)) > 0.5   # 一半白一半红
    for c in range(3):
        col = np.where(flower_white, [0.92, 0.92, 0.85][c], flower_red[c])
        rgb[..., c] = np.where(flower_mask, col, rgb[..., c])
    return rgb


def _vignette_seamless(rgb: np.ndarray) -> np.ndarray:
    """因为是 tile，不能加普通暗角；但可以做轻微"湿润感"全图色调"""
    # 整体降饱和一点，提一点蓝紫做"野草地阴影"感
    avg = rgb.mean(axis=2, keepdims=True)
    rgb = rgb * 0.92 + avg * 0.08
    # 整体压一点暗（避免太亮，跟人物贴图色调匹配）
    rgb = rgb * 0.92
    return np.clip(rgb, 0.0, 1.0)


def main() -> int:
    rng = np.random.default_rng(SEED)
    # 多层无缝噪声
    low  = _fractal(SIZE, octaves=3, base_freq=2,  persistence=0.55, rng=rng)
    mid  = _fractal(SIZE, octaves=4, base_freq=8,  persistence=0.55, rng=rng)
    hi   = _fractal(SIZE, octaves=4, base_freq=32, persistence=0.50, rng=rng)
    dirt = _fractal(SIZE, octaves=3, base_freq=4,  persistence=0.55, rng=rng)
    # 颜色合成
    rgb = _grass_color_map(low, mid, hi)
    rgb = _add_dirt_patches(rgb, dirt)
    rgb = _add_grass_blades(rgb, rng)
    rgb = _vignette_seamless(rgb)
    # 输出
    out = (rgb * 255.0).astype(np.uint8)
    img = Image.fromarray(out, mode="RGB")
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    img.save(OUT_PATH, optimize=True)
    print(f"[gen_terrain_grass] saved -> {OUT_PATH}  ({SIZE}x{SIZE})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
