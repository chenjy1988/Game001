#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "rembg>=2.0.50",
#     "onnxruntime>=1.17.0",
#     "pillow>=10.0.0",
# ]
# ///
"""
remove_bg.py - 使用 rembg 抠除图片背景，输出透明 PNG。

用法：
    uv run remove_bg.py --input in.png [--output out.png] [--inplace]

参数说明：
    --input     必填，输入图片路径
    --output    输出路径。不指定则在原文件同目录输出 <原名>-transparent.png
    --inplace   直接覆盖原文件（和 --output 互斥）
"""

import argparse
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Remove image background using rembg")
    parser.add_argument("--input", "-i", required=True, help="Input image path")
    parser.add_argument("--output", "-o", help="Output image path (default: <name>-transparent.png)")
    parser.add_argument("--inplace", action="store_true", help="Overwrite input file")

    args = parser.parse_args()

    if args.output and args.inplace:
        print("Error: --output and --inplace are mutually exclusive", file=sys.stderr)
        sys.exit(1)

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    if args.inplace:
        output_path = input_path
    elif args.output:
        output_path = Path(args.output)
    else:
        output_path = input_path.with_name(f"{input_path.stem}-transparent.png")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    # 延迟导入（rembg 首次加载很慢，先做参数校验）
    from rembg import remove
    from PIL import Image

    print(f"Input:  {input_path}")
    print(f"Output: {output_path}")
    print("Removing background (first run may download model ~170MB, please wait)...")

    try:
        img = Image.open(str(input_path))
        result = remove(img)

        # 确保是 RGBA
        if result.mode != "RGBA":
            result = result.convert("RGBA")

        result.save(str(output_path), "PNG")

        # 简单校验
        alpha = result.split()[3]
        alpha_min, alpha_max = alpha.getextrema()
        print(f"\nDone. Mode: {result.mode}, Size: {result.size}, Alpha range: ({alpha_min}, {alpha_max})")
        if alpha_max == 255 and alpha_min < 255:
            print("[OK] Image has transparent regions.")
        elif alpha_min == 255:
            print("[WARN] No transparent region detected. Background removal may have failed.")
        else:
            print("[WARN] Unexpected alpha range, please check manually.")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
