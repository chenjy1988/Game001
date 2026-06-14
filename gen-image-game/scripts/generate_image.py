#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "google-genai>=1.0.0",
#     "pillow>=10.0.0",
# ]
# ///
"""
gen-image-game - 调用 Google Gemini 生图 API（文生图 / 图生图）。

基于 ~/.codebuddy/skills/nano-banana-pro 的脚本改造：
  - 新增 --model 参数，支持在 2.5-flash（便宜）和 3-pro（高质量）之间切换
  - 默认模型改为 gemini-2.5-flash-image-preview（适合小游戏素材）

用法：
    uv run generate_image.py \\
        --prompt "your image description" \\
        --filename "output.png" \\
        [--model flash|pro] \\
        [--resolution 1K|2K|4K] \\
        [--input-image path/to/ref.png] \\
        [--api-key KEY]
"""

import argparse
import os
import sys
from pathlib import Path


MODEL_MAP = {
    "flash": "gemini-2.5-flash-image",            # Nano Banana，便宜快，适合小游戏素材
    "flash2": "gemini-3.1-flash-image-preview",   # Nano Banana 2，新版 flash（预览）
    "pro": "gemini-3-pro-image-preview",          # Nano Banana Pro，高质量，适合封面/大背景
}


def get_api_key(provided_key):
    if provided_key:
        return provided_key
    return os.environ.get("GEMINI_API_KEY")


def main():
    parser = argparse.ArgumentParser(
        description="Generate game assets using Google Gemini image models"
    )
    parser.add_argument("--prompt", "-p", required=True, help="Image description/prompt")
    parser.add_argument("--filename", "-f", required=True, help="Output filename (e.g., player.png)")
    parser.add_argument("--input-image", "-i", help="Optional input image path for editing/reference")
    parser.add_argument(
        "--model", "-m",
        choices=list(MODEL_MAP.keys()),
        default="flash",
        help="Model shortcut: flash (default, Nano Banana), flash2 (Nano Banana 2, preview), or pro (Nano Banana Pro, high-quality)",
    )
    parser.add_argument(
        "--resolution", "-r",
        choices=["512", "1K", "2K", "4K"],
        default="1K",
        help="Output resolution: 512 (0.5K, flash2 only) / 1K (default) / 2K / 4K",
    )
    parser.add_argument(
        "--aspect-ratio", "-a",
        choices=[
            "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4",
            "9:16", "16:9", "21:9",
            "1:4", "4:1", "1:8", "8:1",  # flash2 only
        ],
        default="1:1",
        help="Aspect ratio: 1:1 (default), 16:9, 9:16, 3:4, 4:3 etc. See --help for full list.",
    )
    parser.add_argument("--api-key", "-k", help="Gemini API key (overrides env var)")

    args = parser.parse_args()

    api_key = get_api_key(args.api_key)
    if not api_key:
        print("Error: No API key provided.", file=sys.stderr)
        print("Please either:", file=sys.stderr)
        print("  1. Provide --api-key argument", file=sys.stderr)
        print("  2. Set GEMINI_API_KEY environment variable", file=sys.stderr)
        print("     export GEMINI_API_KEY=\"your_key\"   # add to ~/.zshrc to persist", file=sys.stderr)
        print("  Get key at: https://aistudio.google.com/app/apikey", file=sys.stderr)
        sys.exit(1)

    from google import genai
    from google.genai import types
    from PIL import Image as PILImage

    client = genai.Client(api_key=api_key)

    output_path = Path(args.filename)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    input_image = None
    output_resolution = args.resolution
    if args.input_image:
        try:
            input_image = PILImage.open(args.input_image)
            print(f"Loaded input image: {args.input_image}")

            # 自动根据输入图尺寸推断分辨率（仅在用户未显式指定时）
            if args.resolution == "1K":
                width, height = input_image.size
                max_dim = max(width, height)
                if max_dim >= 3000:
                    output_resolution = "4K"
                elif max_dim >= 1500:
                    output_resolution = "2K"
                else:
                    output_resolution = "1K"
                print(f"Auto-detected resolution: {output_resolution} (from input {width}x{height})")
        except Exception as e:
            print(f"Error loading input image: {e}", file=sys.stderr)
            sys.exit(1)

    if input_image:
        contents = [input_image, args.prompt]
    else:
        contents = args.prompt

    model_id = MODEL_MAP[args.model]
    print(f"Model: {model_id} | Size: {output_resolution} | Aspect: {args.aspect_ratio}")
    print(f"{'Editing' if input_image else 'Generating'} image...")

    try:
        response = client.models.generate_content(
            model=model_id,
            contents=contents,
            config=types.GenerateContentConfig(
                response_modalities=["TEXT", "IMAGE"],
                image_config=types.ImageConfig(
                    image_size=output_resolution,
                    aspect_ratio=args.aspect_ratio,
                ),
            ),
        )

        image_saved = False
        for part in response.parts:
            if part.text is not None:
                print(f"Model response: {part.text}")
            elif part.inline_data is not None:
                from io import BytesIO

                image_data = part.inline_data.data
                if isinstance(image_data, str):
                    import base64
                    image_data = base64.b64decode(image_data)

                image = PILImage.open(BytesIO(image_data))

                # 保持 RGBA 以支持后续透明背景处理；RGB 直接存
                if image.mode == "RGBA":
                    image.save(str(output_path), "PNG")
                elif image.mode == "RGB":
                    image.save(str(output_path), "PNG")
                else:
                    image.convert("RGB").save(str(output_path), "PNG")
                image_saved = True

        if image_saved:
            full_path = output_path.resolve()
            print(f"\nImage saved: {full_path}")
        else:
            print("Error: No image was generated in the response.", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"Error generating image: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
