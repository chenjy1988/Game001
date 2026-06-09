#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "pillow>=10.0",
#   "rembg>=2.0.50",
#   "onnxruntime>=1.16",
#   "numpy<2",
# ]
# ///
"""
对 assets/ 下的素材做后处理：
1. 角色/武器/护甲/盾  -> 居中裁 1:1 -> rembg 抠透明 -> 缩放到目标尺寸 -> RGBA PNG
2. 头像 portrait_*    -> 居中裁 3:4 -> 缩放到 768x1024 -> 保持 RGB（带背景）
3. 战场 battlefield_* -> 直接缩放到 2048x1152 -> RGB
原图保留不动，输出到 assets/processed/。
"""
from __future__ import annotations
import sys
from pathlib import Path
from io import BytesIO

from PIL import Image
from rembg import remove, new_session

ROOT = Path("/Users/chaschen/Project/Game001/assets")
OUT = ROOT / "processed"
OUT.mkdir(parents=True, exist_ok=True)

# 分类规则：(目标比例 W:H, 目标尺寸 (w,h), 是否抠透明)
CHARACTER_FILES = ["warrior", "bandit", "boss_orc"]
WEAPON_FILES = ["short_sword", "sword", "war_hammer", "dagger", "spear", "battle_axe"]
ARMOR_FILES = ["armor_cloth", "armor_leather", "armor_mail", "armor_plate", "shield_round"]

# 用户指示：取 sword（即 sword.png 当作短剑），跳过 short_sword.png
SKIP = {"short_sword"}

PORTRAITS = ["portrait_warrior", "portrait_bandit", "portrait_boss_orc"]
BACKGROUNDS = ["battlefield_grass"]


def crop_center(img: Image.Image, ratio_w: int, ratio_h: int) -> Image.Image:
    """按目标宽高比从中心裁剪。"""
    w, h = img.size
    target_ratio = ratio_w / ratio_h
    cur_ratio = w / h
    if cur_ratio > target_ratio:
        # 太宽，裁宽
        new_w = int(h * target_ratio)
        x0 = (w - new_w) // 2
        return img.crop((x0, 0, x0 + new_w, h))
    else:
        # 太高，裁高
        new_h = int(w / target_ratio)
        y0 = (h - new_h) // 2
        return img.crop((0, y0, w, y0 + new_h))


def remove_bg_rgba(img: Image.Image, session) -> Image.Image:
    """使用 rembg 抠图，返回 RGBA。"""
    buf = BytesIO()
    img.save(buf, format="PNG")
    out_bytes = remove(buf.getvalue(), session=session)
    out = Image.open(BytesIO(out_bytes)).convert("RGBA")
    return out


def process_cutout(name: str, target_size: tuple[int, int], session) -> str | None:
    """通用：1:1 裁切 -> 抠透明 -> 缩放。"""
    src = ROOT / f"{name}.png"
    if not src.exists():
        return f"  ⏭  {name}.png 不存在，跳过"
    img = Image.open(src).convert("RGB")
    img = crop_center(img, 1, 1)
    img = remove_bg_rgba(img, session)
    # 抠完后再缩放到目标
    img = img.resize(target_size, Image.LANCZOS)
    dst = OUT / f"{name}.png"
    img.save(dst, "PNG", optimize=True)
    # 校验 alpha 范围
    alpha = img.getchannel("A")
    a_min, a_max = alpha.getextrema()
    return f"  ✅ {name}.png  -> {dst.relative_to(ROOT.parent)}  ({target_size[0]}x{target_size[1]} RGBA, alpha {a_min}-{a_max})"


def process_portrait(name: str) -> str:
    src = ROOT / f"{name}.png"
    if not src.exists():
        return f"  ⏭  {name}.png 不存在，跳过"
    img = Image.open(src).convert("RGB")
    img = crop_center(img, 3, 4)
    img = img.resize((768, 1024), Image.LANCZOS)
    dst = OUT / f"{name}.png"
    img.save(dst, "PNG", optimize=True)
    return f"  ✅ {name}.png  -> {dst.relative_to(ROOT.parent)}  (768x1024 RGB)"


def process_background(name: str) -> str:
    src = ROOT / f"{name}.png"
    if not src.exists():
        return f"  ⏭  {name}.png 不存在，跳过"
    img = Image.open(src).convert("RGB")
    img = crop_center(img, 16, 9)
    img = img.resize((2048, 1152), Image.LANCZOS)
    dst = OUT / f"{name}.png"
    img.save(dst, "PNG", optimize=True)
    return f"  ✅ {name}.png  -> {dst.relative_to(ROOT.parent)}  (2048x1152 RGB)"


def main():
    print(f"输出目录：{OUT}\n")

    print("⏳ 加载 rembg 模型 (首次会下载 ~170MB)...")
    session = new_session("u2net")
    print("✅ 模型就绪\n")

    # 1) 角色 -> 1024x1024 RGBA
    print("【1/4】角色 sprite (1024x1024 RGBA)")
    for n in CHARACTER_FILES:
        if n in SKIP:
            print(f"  ⏭  {n}.png 用户跳过")
            continue
        print(process_cutout(n, (1024, 1024), session))

    # 2) 武器 -> 512x512 RGBA
    print("\n【2/4】武器 (512x512 RGBA)")
    for n in WEAPON_FILES:
        if n in SKIP:
            print(f"  ⏭  {n}.png 用户跳过 (用 sword.png 替代)")
            continue
        print(process_cutout(n, (512, 512), session))

    # 3) 护甲/盾 -> 512x512 RGBA
    print("\n【3/4】护甲与盾 (512x512 RGBA)")
    for n in ARMOR_FILES:
        if n in SKIP:
            continue
        print(process_cutout(n, (512, 512), session))

    # 4) 头像 -> 768x1024 RGB
    print("\n【4/4】头像 (768x1024 RGB)")
    for n in PORTRAITS:
        print(process_portrait(n))

    # 5) 战场 -> 2048x1152 RGB
    print("\n【+】战场背景 (2048x1152 RGB)")
    for n in BACKGROUNDS:
        print(process_background(n))

    print("\n🎉 全部完成。原图未改动，输出在 assets/processed/")


if __name__ == "__main__":
    main()
