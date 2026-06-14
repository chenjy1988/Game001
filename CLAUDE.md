# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目身份

Godot 4.3 stable + GDScript 实现的硬核中世纪战棋 Demo，灵感来自《Battle Brothers》，唐代边军主题。详细背景与 phase 路线图见 `README.md`，本文件只补充开发者上下文。

## 常用命令

```bash
# 在编辑器中打开项目
godot --path /Users/chaschen/Project/Game001 --editor

# 命令行直接运行主场景（res://scenes/Main.tscn）
godot --path /Users/chaschen/Project/Game001

# 无头冒烟 / 单测（日志写入 logs/，见 tools/godot_env.sh）
./tools/smoke.sh
./tools/run_tests.sh
./tools/run_sim.sh          # 4v4 AI 对战仿真（balance + invariants）
```

无 build / lint / test runner。`scripts/tools/test_*.gd` 是手写单测（TurnManager、DamageSystem 等）；`tools/run_sim.sh` 跑 `BattleSimHarness` 无头 4v4 AI 对战（`evaluating-gameplay-balance`：pass vs ai；`implementing-gameplay-invariants`：交火/胜负）。日志落 `logs/battle_sim.log`。

## 架构关键点（多文件配合才能看懂的部分）

### 启动顺序与 autoload
- **autoload 单例 `WeaponArmorDB`**（在 `project.godot` 注册，源码 `scripts/data/WeaponArmorDB.gd`）：启动时一次性从 `data/weapons.json` 与 `data/armors.json` 反序列化为 `WeaponData` / `ArmorData` 资源。**所有运行时武器/护甲查询都走 `WeaponArmorDB.get_weapon(id)` / `.get_armor(id)`**，不要绕过它直接 `load(.tres)`。
- 入口流程：`Main.tscn`（`scripts/Main.gd`，菜单）→ `scenes/battle/BattleScene.tscn`（`scripts/core/BattleScene.gd`，战斗主控）。

### 战斗调度：AP + 回合制（DOS2 风）
**设计 SoT**：`design/phase2-plan.md` § 规则要点
- 战斗按"回合"组织，**每回合所有单位按 Init 排序依次行动 1 次**——Init 只决定顺序，不决定频率。
- 单位轮到时**可以"等待"**（Q 键；延后本回合行动顺序到尚未行动的单位之后；不消耗 AP；每回合每单位限 1 次）。
- 每回合开始补满 AP（base 9）。**AP 不跨回合保留**，end_turn 时清零。
- AP 与气力（fatigue）解耦：气力不足只影响成功率，不锁普通行动。
- Haste / Slow 改 Init（影响顺序，不影响 AP）。

**当前代码状态**：`scripts/core/TurnManager.gd` 仍用旧的 CT 累加器（Tactics Ogre 风，CT_THRESHOLD=100）——这与新设计有冲突，但大多数新代码已切到正确路径。
- Phase 2 待重构：`TurnManager` → `RoundManager` 转换（优先级低，当前工作流保留兼容性）。
- 新增 AP 逻辑已在 `BattleScene.gd`、`Unit.gd` 中试验性部署。

### 伤害管线：新公式（v3 新版 + Wisdom暴击）
`scripts/core/DamageSystem.gd` 是**无状态静态工具类**（Phase 2 重构后，包含 27 项单测 PASS）。管线如下：
1. **命中率**（v3.2，`design/weapon-system.md` §6.1.1）：`Hit% = clamp((atk - final_def)/100 + hit_bonus, 5%, 95%)`；`final_def = base + dodge_pts + block_pts + def_flat`（高防惩罚后）；闪避默认 0，身轻如燕（**JP 被动**，非先天天赋）`(init−全身重)×20%`；格挡=装备 block（配盾仅盾/双持求和）。
2. **命中部位**：head ~5% / body ~95%（注意 `HEAD_HIT_CHANCE=0.25` 为历史遗留，代码优先级更新为 0.05）。
3. **穿透系数**（新）：`armor_mult`（斩/刺/砸对皮/锁/板甲的克制系数，1.0~1.5）× `weight_penetration`（武器重量驱动，0~0.4）。
4. **暴击**（新）：Wisdom 每 5 点 +1% 暴击率（crit_chance），暴击伤害 ×1.5。
5. **伤害计算**：`damage = (base_damage × armor_mult × penetration + random_roll) × (crit ? 1.5 : 1.0)`。

**历史遗留**：旧字段 `armor_effectiveness` / `armor_penetration` 在 `WeaponData.gd` 中仍存活但**未使用**（弃用准备）。

### Hex 网格
`scripts/core/HexGrid.gd` 自己渲染（`_draw` 直接画多边形，无 TileSet），用 `AStar2D` 做寻路、BFS 做可达计算。地形采用"无缝大纹理 + 世界坐标 UV 采样"方案（2026-05 重构），多 biome 之间用 `transition/<biome>_dir<n>.png` 叠加过渡。坐标用 axial `Vector2i`，`HexCoord.gd` 是工具类。

### AI
`scripts/core/BattleAI.gd` 是**评分式静态决策器**：枚举 `(可达落点, 可攻击目标)` 笛卡尔积，按 `命中率×期望伤害 + 击杀奖励 - OA命中惩罚 - 移动惩罚 - 落点ZoC惩罚` 选最高分。返回 `{path, target, end_turn, score, reason}` 让 BattleScene 异步执行。
- **控制区（ZoC）+ 借机攻击已实装**：装备近战武器的单位威胁周围 6 格，离开敌人 ZoC 触发免费攻击。

### Stats 与运行时
`scripts/core/Stats.gd` 是 `Resource`（可直接在编辑器里配 `.tres`，支持序列化）。关键方法：
- `init_runtime(armor_weight)` 在战斗开始时调用，**护甲重量会减少 max_fatigue 并通过 `effective_initiative()` 进入 Init 排序**。
- `effective_initiative()` 返回运行时 Initiative（已考虑护甲减值）。
- `apply_damage(damage, head: bool)` 简化伤害应用。
- `melee_defense` / `ranged_defense` 是**过渡期**字段，新代码应统一使用 `defense`（见注释）。

### 战斗 UI：DOS2 风平铺式（F1/F5/F6 已完成）
`scripts/ui/CombatMenu.gd` 实装了扁平化 chip 布局（6月初重新设计）：
- **F1（字母快捷键）**：P / I / Q 三个固定左槽位。P=詳情面板切换，I=道具（占位），Q=等待。
- **HUD 行动条**（F5 新增）：中央对称三层布局：[头甲条（薄）] → [HP/气力条（厚）] → [AP 钻石 ◆◇（最小）]。所有数值标签改为 Hover 提示（中心对称）。
- **攻击/技能 chip**（F1 数字键）：数字 1~9 按钮，动态从当前武器 `weapon.attack_modes` 展开。
- **P 键详情面板**（F6）：全属性面板 toggle（内容与 HUD 冗余但用户需求）。
- 两个独立面板：HUD 面板 + 下方 Chip 面板，各自居中，宽度独立。

**F3（待做）**：攻击模式 chip 必须接入 DamageSystem（目前仅 UI 展示，无伤害系数切换）。双模式武器（剑/陌刀）的斩/刺切换仍需在此处完成。

### 单位模型与数据
`scripts/core/Unit.gd` 是游戏对象，管理状态、移动、动画。`scripts/data/` 下是数据资源：
- `WeaponData.gd` / `ArmorData.gd`：武器/护甲属性（从 JSON 反序列化）。
- `Stats.gd`：角色属性面板（HP / Head&Body Armor / AP / Fatigue / 各种技能与防御）。
- 职业系统（**未实装**）：Phase 2.5 新增 JobClass + JobDB + 武器专精系数。

## 数据驱动（重要！）

**`data/weapons.json`**（v3.1，15 件武器）和 **`data/armors.json`** 是 SoT（Single Source of Truth）。改数值**优先改 JSON**、不改 GDScript 常量。

- JSON 结构对应 `WeaponData.gd` / `ArmorData.gd` 的 `@export` 字段。
- `WeaponArmorDB._load_weapons()` / `._load_armors()` 是手写映射逻辑。
- **新增字段必须在两边都加**（JSON + `*Data.gd` @export 字段 + 映射逻辑）。

典型武器对象示例：
```json
{
  "id": "jian",
  "name": "横刀",
  "damage_base": 42,
  "weight": 2.5,
  "attack_modes": [
    { "id": "slash", "armor_mult": 1.2, "hp_mult": 1.0 },
    { "id": "pierce", "armor_mult": 0.8, "hp_mult": 1.2 }
  ]
}
```

## 代码与设计文档的脱节概览

`design/` 是 **knowledge baseline**（优先于代码）。当前版本差异表：

| 文档（新） | 代码状态 | 优先级 |
|---|---|---|
| `design/phase2-plan.md` v1.2：DamageSystem 新公式 + Wisdom暴击 + 4职业 + Ability 框架 | ✅ DamageSystem 已重构+27单测 / ❌ 职业系统未实装 | Phase 2 Week 1~2 |
| `design/weapon-system.md` v3.1：attack_modes + armor_mult + weight×渗透 | ✅ 数据结构完成 / 🟡 UI 接入待做（F3） | 依赖 F3 完成 |
| `design/class-system.md` v1.3：19 职业 + 武器专精 + 被动技能 | ❌ 完全未实装 | Phase 2.5（能力专题） |
| `design/status-effects.md`：临时伤势触发 | ❌ 完全未实装 | Phase 2.5 |
| `design/combat-ui.md` v1.0：战斗菜单设计 | ✅ 已落地扁平化方案（vs 原设计 5 级菜单） | ✅ 完成 |

**修代码前必读 `design/phase2-plan.md`** — 它列出"本期做什么 / 推迟什么 / 不做什么"。明确推迟到 Phase 2.5 的能力：疾风连击、全力一击、双武器精通、碎甲、被动效果等。

## 文档阅读优先级

出现冲突时，优先读后面的：
1. `design/phase2-plan.md`（v1.2 本期范围 & 决策记录）
2. `design/phase2-todo.md`（任务清单与接收标准）
3. `design/weapon-system.md`（v3.1 武器/伤害规则）
4. `design/class-system.md`（v1.3 职业数据）
5. `design/combat-ui.md`（v1.0 UI 设计，已部分推翻）
6. `design/status-effects.md`（状态系统）
7. `README.md`（顶层概览）
8. `design.md`（索引性文档）
9. `design/references/`（Battle Brothers / FFT / DO2 调研）

## 常见修改模式

### 调整伤害/属性数值
→ 改 `data/weapons.json` 或 `data/armors.json`，**不要** 改 GDScript 常量。

### 添加新武器
1. 在 `data/weapons.json` 新增条目
2. 在 `WeaponData.gd` @export 章节补充字段（如有新属性）
3. 在 `WeaponArmorDB._load_weapons()` 新增映射行
4. 测试：在编辑器中加载 WeaponArmorDB，验证 `get_weapon("new_id")` 返回正确对象

### 修改战斗 UI（CombatMenu）
- 单位面板布局改动 → 修改 `_make_hud_unit()` / `_build_hud_section()` 等方法
- Chip 按钮逻辑 → 修改 `_build_action_bar_layout()` / `_on_chip_selected()`
- 字母快捷键 → 改 `_on_input_event()` 或对应的信号监听
- 注意：HUD 和 Chip 面板是两个独立的 PanelContainer，各自居中

### 调试伤害计算
→ 创建新的 `scripts/tools/test_damage_new_issue.gd`，或在 `test_damage_system.gd` 添加单测用例。在编辑器里加挂到某个 Scene 或用 godot CLI 跑。

## 当前活跃的待做项

按 `design/phase2-todo.md` 跟踪：
- **F3：攻击模式接入**（从 CombatMenu chip 切换到 DamageSystem 伤害系数）— 需要 `_pending_attack_mode` + `Unit.attack_target(target, mode)` 改造
- **B/C：职业系统 + Ability 框架**（JobClass + JobDB + 4 Demo 职业数据）— Phase 2.5 延迟
- **D：4v4 Demo 场景与 TopBar 升级**（BattleScene 配置 + 单位配置数据表）— 设计已稳定，实装待排期

## 全局开发约定（来自用户私有规则）

- 回答用中文，尽量精简 token。
- 简单文件/git 命令直接执行，不要过度规划。
- 调用 MCP 时不要打日志，但 SQL 要先打印出来。
- 查表分区数据用 `wedata_mcp` 的 `show rowcount extended <tablename>`。
