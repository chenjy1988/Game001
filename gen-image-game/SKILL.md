---
name: gen-image-game
description: 小游戏素材生成 skill，基于 Google Gemini 图像模型，专为 H5/小游戏开发提供透明背景素材、尺寸预设、风格锁定、批量生成、精灵图拼装等能力。
---

# gen-image-game - 小游戏素材生成

## ⚠️ 全局硬性约束（AI 必读，不可违反）

本 skill 只允许调用本目录下 `scripts/` 中的脚本（Google Gemini API）。

**严禁**以任何形式调用、请求、下载、安装第三方生图服务，包括但不限于：
Pollinations.ai、Stable Diffusion、DALL-E、Midjourney、HuggingFace、ComfyUI、Flux、Replicate、Automatic1111 等。

**严禁**使用 `curl` / `urllib` / `requests` / `fetch` / `wget` 绕过本 skill 的脚本直接访问任何外部生图 URL。

**严禁**用"让我最后尝试..."、"使用免费 API..."、"No API key needed" 等说辞绕过兜底。

如果用户未配置 `GEMINI_API_KEY`，**直接进入前置配置引导流程**，不得"创造性地"寻找替代方案。

---

## 前置要求（必读）

本 skill 需要 **Google Gemini API Key**。首次使用前必须完成配置：

### 1. 获取 API Key

访问 https://aistudio.google.com/app/apikey 创建 Key（Google 账号登录）。

### 2. 设置环境变量

**macOS / Linux**（推荐写入 `~/.zshrc` 持久化）：

```bash
export GEMINI_API_KEY="your_key_here"
```

**验证**：

```bash
echo $GEMINI_API_KEY   # 应输出你的 key
```

### 3. 依赖工具

- `uv`（推荐，脚本 shebang 用的是 uv run）：`curl -LsSf https://astral.sh/uv/install.sh | sh`
- 或 Python 3.10+ 手动安装：`pip install google-genai pillow rembg onnxruntime`

---

## 脚本总览

| 脚本 | 用途 |
|------|------|
| `scripts/generate_image.py` | 调用 Gemini 生成图片（文生图 / 图生图） |
| `scripts/remove_bg.py` | 用 rembg 抠除背景，输出透明 PNG |
| `scripts/assemble_spritesheet.py` | 将多张素材拼成固定网格精灵图 + 坐标 JSON |

**统一调用方式**（使用绝对路径，工作目录保持在用户项目下）：

```bash
uv run <SKILL_DIR>/scripts/<script>.py <args>
```

其中 `<SKILL_DIR>` 是本 skill 的绝对路径（例如 `.codebuddy/skills/gen-image-game`）。

---

## 模型与分辨率

### 模型选项（`--model` 参数）

| shortcut | 实际模型 ID | 显示名 | 适用 | 费用 |
|----------|-----------|--------|------|------|
| `flash`（默认） | `gemini-2.5-flash-image` | Nano Banana | 常规小游戏素材、图标、道具 | 低 |
| `flash2` | `gemini-3.1-flash-image-preview` | Nano Banana 2（预览） | 新版 flash，效果更好 | 低 |
| `pro` | `gemini-3-pro-image-preview` | Nano Banana Pro | 封面、宣传图、大背景 | 高 |

> 模型 ID 会随 Google 发版调整。若遇到 `404 model not found`，执行 `curl "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY"` 查看最新列表。

### 分辨率（`--resolution` 参数，控制像素总量）

| 值 | 说明 |
|----|------|
| `512` | ~512px（0.5K），**仅 flash2 (Gemini 3.1) 支持**，极小素材使用 |
| `1K`（默认） | ~1024px，适合素材/图标/小背景 |
| `2K` | ~2048px |
| `4K` | ~4096px，适合封面大图（仅 pro 推荐） |

### 宽高比（`--aspect-ratio` 参数，控制图片形状）

| 值 | 形状 | 游戏场景 |
|----|------|---------|
| `1:1`（默认） | 正方形 | 图标、道具、角色半身像、精灵图素材 |
| `3:4` / `2:3` / `4:5` | 竖向 | 卡牌、竖屏手游头像 |
| `4:3` / `3:2` / `5:4` | 横向 | 常规游戏截图、小横屏背景 |
| `9:16` | 竖屏 | 抖音/快手类竖屏游戏背景、宣传图 |
| `16:9` | 宽屏 | 横屏游戏背景、PC 游戏截图 |
| `21:9` | 超宽屏 | 超宽屏横版卷轴背景 |
| `1:4` / `4:1` / `1:8` / `8:1` | 极端长条 | ⭐ 仅 `flash2` 支持，横条 UI、进度条装饰 |

> **使用惯例**：
> - 首次生成建议 `1K + 1:1` 快速预览，prompt 确定后再升高分辨率
> - 需要横版背景 → `--aspect-ratio 16:9`
> - 需要竖版手游背景 → `--aspect-ratio 9:16`
> - 卡牌类 → `--aspect-ratio 3:4`

---

## 游戏素材场景模板

AI 根据用户描述识别素材类型，套用对应的 prompt 模板、比例和尺寸：

| 素材类型 | 典型关键词 | 推荐 aspect-ratio | 推荐 resolution | 透明背景 | Prompt 补充模板 |
|---------|-----------|-------------------|----------------|---------|----------------|
| **角色**（character） | 人物、怪物、主角、敌人 | `1:1` | `1K` | 是 | `full body, centered, solid white background, game sprite` |
| **道具**（item） | 水果、宝石、钥匙、武器 | `1:1` | `1K` | 是 | `single item, centered, solid white background, game icon style` |
| **图标**（icon） | 按钮图标、能力图标 | `1:1` | `512`/`1K` | 是 | `flat icon, centered, solid white background, clean edges` |
| **卡牌**（card） | 卡牌、抽卡、角色卡 | `3:4` | `1K`/`2K` | 否 | `card illustration, ornate border, rich composition` |
| **横屏背景**（background H） | 横版场景、PC 游戏背景 | `16:9` | `1K`/`2K` | 否 | `game background, no characters, no UI elements, scenic` |
| **竖屏背景**（background V） | 手游竖屏、抖音小游戏背景 | `9:16` | `1K`/`2K` | 否 | `vertical game background, portrait orientation, no characters` |
| **横版卷轴** | 超宽屏、卷轴游戏 | `21:9` | `2K` | 否 | `panoramic game background, wide scrolling view` |
| **UI 元素** | 按钮、弹窗装饰、小 logo | `1:1` 或 `4:1` | `512`/`1K` | 是 | `UI element, flat design, clean vectors, solid white background` |

---

## 核心工作流

### 步骤 1：前置检查

```bash
# 必做：验证 GEMINI_API_KEY
echo "${GEMINI_API_KEY:-NOT_SET}"
```

如果输出 `NOT_SET`，**立即停止生图**，向用户输出前置配置引导（见"前置要求"章节），**不得**调用其他任何生图服务。

### 步骤 2：识别素材类型 & 确认风格

AI 根据用户描述判断素材类型，套用模板。

**风格锁定机制**（批量生成场景）：

- 首次生成时，AI 应询问用户风格偏好（或根据已有素材推断），记住一个 `style_suffix`，如：
  - `pixel art, 16-bit, vibrant colors`
  - `cartoon flat illustration, thick outline, pastel palette`
  - `2.5D hand-drawn, soft lighting, warm tones`
- 同一批次的所有 prompt **统一拼接** `style_suffix`，确保风格一致
- 本次会话结束前，如果用户要求"再生成一个同样风格的"，直接复用 `style_suffix`

### 步骤 3：决定输出路径

**默认规则**：

1. 如果当前工作目录在 `frontend/<game-name>/` 下 → 输出到 `frontend/<game-name>/src/assets/images/`
2. 否则 → 输出到 `./generated-images/`

用户明确指定路径（`-o` / `--output`）时以用户为准。

### 步骤 4：生成图片

```bash
uv run <SKILL_DIR>/scripts/generate_image.py \
    --prompt "<完整 prompt，含素材描述 + 模板补充 + style_suffix>" \
    --filename "<output_path>/player.png" \
    --model flash \
    --resolution 1K \
    --aspect-ratio 1:1
```

**关键参数选择建议**：

| 用户需求 | `--model` | `--resolution` | `--aspect-ratio` |
|---------|-----------|----------------|------------------|
| 常规角色/道具/图标 | `flash` | `1K` | `1:1` |
| 竖屏手游背景 | `flash` | `1K` 或 `2K` | `9:16` |
| 横屏游戏背景 | `flash` | `1K` 或 `2K` | `16:9` |
| 卡牌 | `flash` | `1K` | `3:4` |
| 游戏封面/宣传图 | `pro` | `2K` 或 `4K` | 视场景 |

**批量生成**：循环调用，保持 `--model` / `--resolution` / `--aspect-ratio` / style_suffix 一致。

**图生图**（基于已有素材扩展）：加 `--input-image path/to/ref.png`。

### 步骤 5：透明背景处理（可选）

如果素材类型是 character / item / icon / UI（表格里标记"是"的），生成时 prompt 里务必加 `solid white background`，然后：

```bash
uv run <SKILL_DIR>/scripts/remove_bg.py \
    --input <output_path>/player.png \
    --inplace
```

脚本会输出 alpha 范围，验证抠图是否成功：

- `Alpha range: (0, 255)` → ✅ 抠图成功
- `Alpha range: (255, 255)` → ⚠️ 背景未扣除（可能 prompt 没包含 "solid white background"，或主体边缘不清晰）

### 步骤 6：询问是否压缩（不主动执行）

生成完成后，**主动询问用户**：

```
已生成 N 张素材（总大小 X MB）。是否需要压缩？
（小游戏对图片大小敏感，压缩可减少加载时间）

[Y] 压缩 —— 会调用 image-compress skill
[N] 保持原样
```

用户选 Y 才 `use_skill("image-compress")` 调用，否则跳过。

### 步骤 7：（按需）拼装精灵图

**只有当用户明确要求**"拼成精灵图" / "合并成一张" / "sprite sheet" / "做成网格" 时调用：

```bash
uv run <SKILL_DIR>/scripts/assemble_spritesheet.py \
    --inputs <path>/player.png <path>/enemy.png <path>/coin.png \
    --output <path>/sprites.png \
    --cols 4 \
    --tile-size 128 \
    --names player enemy coin
```

输出 `sprites.png` + `sprites.json`（含每个 frame 的 x/y/w/h）。

> 用户只说"生成 N 张素材"时**不要**自动拼精灵图，保留独立 PNG 就好。

### 步骤 8：自动预览（硬性规则 ⚠️）

**CodeBuddy IDE 对话气泡不支持内联渲染本地图片**（Markdown `![]()`、HTML `<img>`、`file://` 均失效）。因此生成完成后，AI **必须主动让用户能看到图**，不能让用户自己去翻文件夹。

**统一做法：调用系统命令打开产物目录（macOS 用 `open`，用户可在 Finder 里用空格快速预览）。**

| 平台 | 命令 |
|------|------|
| macOS | `open <output_dir>` |
| Linux | `xdg-open <output_dir>` |
| Windows | `start <output_dir>` |

| 场景 | 行为 |
|------|------|
| **单张生成** | `open <输出目录>` —— 用户点击文件按空格即可预览 |
| **批量 ≥ 2 张** | `open <输出目录>` —— Finder 中 `⌘A` 全选后空格可轮播所有图 |
| **精灵图场景** | `open <输出目录>` —— 包含 sprites.png + 各独立 PNG + sprites.json |
| **图生图编辑** | `open <输出目录>` |

> **❌ 严禁：**
> - 让用户自己去文件夹翻
> - 只告诉路径不打开文件夹
> - 依赖对话内联图片渲染（不支持）
> - 使用 `open_result_view`（它打开在 IDE 右侧结果面板，用户可能看不到）
>
> **✅ 正确做法：** 每次生成流水结束**必须**执行一次 `open <output_dir>` 打开 Finder/文件管理器。

### 步骤 9：反馈结果

清晰告知：

- ✅ 生成的文件清单（绝对路径）
- 📐 每张图的尺寸与格式（PNG / RGBA / RGB）
- 🎨 使用的 style_suffix（批量场景）
- 💡 后续建议（例如"如需在 Phaser 中使用精灵图，请按 sprites.json 的 frames 坐标加载"）

---

## 错误处理

| 问题 | 处理方式 |
|------|---------|
| `GEMINI_API_KEY` 未设置 | **立即停止**，输出前置配置引导。禁止走任何替代方案 |
| `quota / 403 / permission` 错误 | 提示用户检查 Key 是否有效、配额是否充足 |
| rembg 首次下载模型慢 | 告知用户首次下载 ~170MB，后续本地缓存 |
| `uv` 未安装 | 提示用户 `curl -LsSf https://astral.sh/uv/install.sh | sh` 或用 python 手装依赖 |
| 生成图片质量差 | 建议切 `--model pro` + 拉高 `--resolution` |
| 透明背景没扣干净 | 检查 prompt 是否包含 `solid white background`，主体是否居中且边缘清晰 |

---

## 交互示例

### 示例 1：单张角色素材

```
用户：帮我生成一个像素风格的战士角色，用在小游戏里

AI：
1. 识别：素材类型=character，需透明背景
2. 询问风格（如无明确偏好，推荐 pixel art, 16-bit）
3. 调 generate_image.py：
   --prompt "A warrior character, armor, sword, full body, centered,
             solid white background, game sprite, pixel art, 16-bit, vibrant colors"
   --filename "frontend/<game>/src/assets/images/warrior.png"
   --model flash --resolution 1K
4. 调 remove_bg.py --inplace 抠透明背景
5. 验证 alpha range
6. 询问是否压缩
7. 输出结果
```

### 示例 2：批量生成 + 风格锁定

```
用户：帮我生成 6 个水果素材（苹果、香蕉、橙子、草莓、葡萄、西瓜），透明背景，用在消除游戏里

AI：
1. 识别：素材类型=item × 6，需透明背景
2. 确认风格 → style_suffix = "cartoon flat illustration, thick outline, vibrant colors"
3. 循环 6 次：
   for fruit in [apple, banana, orange, strawberry, grape, watermelon]:
       generate_image.py --prompt "<fruit>, single item, centered,
                                   solid white background, game icon style,
                                   <style_suffix>"
                         --filename "assets/images/<fruit>.png"
                         --model flash --resolution 1K
4. 对每张调 remove_bg.py
5. 询问是否拼成精灵图（用户说"不用，分开就行"）→ 跳过
6. 询问是否压缩
7. 输出 6 个独立 PNG 清单
```

### 示例 3：基于已有素材扩展

```
用户：我已经有一个战士角色图 warrior.png，帮我做一个同风格的法师角色

AI：
1. 识别：图生图场景
2. 调 generate_image.py：
   --prompt "A mage character with staff, robe, keep the same art style"
   --input-image warrior.png
   --filename "mage.png"
   --model flash
3. 透明背景处理
4. 输出
```

---

## 最佳实践

1. **prompt 三段式**：`<主体描述>, <模板补充>, <style_suffix>`
2. **批量生成锁 style_suffix**：保持视觉一致性
3. **1K 先试**：prompt 不确定时先 1K 预览，确定后再 4K 出终稿
4. **透明背景必须 prompt + rembg 双保险**：单靠 Gemini 输出不稳定
5. **精灵图按需生成**：用户没说要拼，就保留独立 PNG
6. **永远不要伪造**：GEMINI_API_KEY 未配置时停下来引导，禁止绕过

---

## 目录结构

```
gen-image-game/
├── SKILL.md                         # 本文档
└── scripts/
    ├── generate_image.py            # Gemini 生图主脚本
    ├── remove_bg.py                 # rembg 透明背景处理
    └── assemble_spritesheet.py      # 精灵图拼装（按需）
```
