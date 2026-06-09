# 战斗 UI 设计（v1.1 — DOS2 风扁平化）

> **作用域**：玩家轮到我方单位行动时的输入界面。敌方/中立 AI 回合时不显示主操作菜单（只保留观战级 UI：日志、TopBar、HUD 灰化）。
>
> **配套**：[`../design.md`](../design.md) § 十二（AP + 回合制） / [`phase2-plan.md`](phase2-plan.md) F 阶段（战斗 UI）
>
> **版本变迁**：v1.0（5 大类菜单 + Hover 二级展开）→ v1.1（**DOS2 风扁平化平铺**，本文档）

---

## 一、核心交互原则

1. **平铺优于层级**：所有可执行动作直接展开为 chip，不再"先选类别再选动作"两步走
2. **数字键 1~9 直绑**：所有攻击模式、技能 chip 按出现顺序绑数字键，无需查表
3. **字母键固定槽位**：详情/道具/等待 这种与单位无关的操作绑死字母键 P/I/Q，永不变位（肌肉记忆）
4. **常驻不打断**：HUD 数据条 + chip 操作栏永远显示在屏幕底部，不弹模态框
5. **数据驱动**：chip 列表由 `weapon.attack_modes` + `unit.abilities` 动态构建，未来加新职业/能力直接占新槽位
6. **HUD 与 chip 解耦**：两者独立 panel 独立居中，技能数变化不影响 HUD 视觉位置

---

## 二、UI 总布局

```
                    [屏幕底部居中]
        ┌──────────────────────────────────────────┐
        │  ────  30/30          ────  50/50       │ ← Layer 1：头甲|身甲（细 4px）
        │  ━━━━━━━ 65/65        ━━━━━ 92/92       │ ← Layer 2：HP|气力（粗 10px）
        │              ◆◆◆◆◆◆◆◇◇                   │ ← Layer 3：AP 钻石点
        └──────────────────────────────────────────┘   HUD（透明背景，无外框）

           ┌──────────────────────────────────┐
           │ [头像] | [P][I][Q] | [1斩][2刺]  │     操作栏（深色木框）
           └──────────────────────────────────┘
```

- **HUD panel**：宽度恒定（由 `HUD_BAR_W=200` × 2 + 间距决定），永远屏幕中央
- **操作栏 panel**：宽度随技能数动态扩张（chip 多了变长），独立居中

---

## 三、操作栏组成

### 1. 头像（最左）

- 来源：`Unit.get_portrait_texture()`（Phase 1 已实装的 sprite 系统）
- 尺寸：50×50 px
- 切换单位时自动同步（`show_for_unit(unit)` 触发）
- Hover 显示单位姓名 tooltip

### 2. 固定字母键 chip（中段）

不变位、不进数字键 list，作为"全局功能键"：

| chip | 字母 | 颜色边框 | 行为 | 状态 |
|---|---|---|---|---|
| **详** | `P` | 蓝（0.55, 0.55, 0.85） | 切换详情面板（HP/AP/装备/速度/护甲...）| ✅ 已实装 |
| **物** | `I` | 绿（0.45, 0.65, 0.40） | 弹出物品 popup（v1 占位 / v2 接 Inventory） | ⏳ Phase 3 |
| **待** | `Q` | 黄（0.85, 0.78, 0.30） | 等待 — 排到本回合队尾（不消耗 AP，每回合限 1 次） | ✅ 已实装 |

**为什么用 P/I/Q 而不是设计文档原本的 W/A/S**：W/S/A 已被 wsad 相机平移占用；P/I/Q 是空闲键且都在左手食指/中指自然落点。

### 3. 动态数字键 chip（右段）

- 来源：当前单位的 `weapon.attack_modes` 列表 + 占位技能（Phase 2.5 接入 `Unit.job.abilities`）
- 数字键 1~9, 0 直绑当前 list 的第 1~10 项
- 颜色边框分组：
  - 红（0.85, 0.30, 0.25）= 攻击 chip
  - 蓝（0.30, 0.55, 0.85）= 技能 chip（Phase 2.5 解锁）
- AP 不足时自动灰化，仍可 hover 看 tooltip（用于规划下回合）

**示例**：

| 单位 | weapon | chip 列表 |
|---|---|---|
| 陌刀手 | 陌刀（slash + pierce） | `[1斩][2刺][3瞄][4暴][5穿]` |
| 长矛兵 | 长矛（pierce） | `[1刺][2瞄][3暴][4穿]` |
| 战锤兵 | 战锤（crush） | `[1砸][2瞄][3暴][4穿]` |
| 弓手 | 弓（ranged） | `[1射][2瞄][3暴][4穿]` |

> 武器伤害类型 → chip 短标签：`slash → 斩`、`pierce → 刺`、`crush → 砸`、`ranged → 射`

---

## 四、HUD 数据条（中心对称三层）

### 视觉权重设计
| Layer | 数据 | 条粗细 | 字号 | 设计意图 |
|---|---|---|---|---|
| 1（最上） | 头甲 \| 身甲 | 4 px 细线 | 11 | 视觉次要（甲值常变化但不致命） |
| 2（中） | HP \| 气力 | 10 px 粗条 | 11 | 视觉主体（生命线 + 行动力） |
| 3（最下） | AP 钻石点 | — | 12 | 紧凑显示行动点 |

### 中心对称布局

每行两条同宽（`HUD_BAR_W = 200`），数值文本在条的**外侧**对齐：

```
[数值] ━━━━━━━━━━     ║     ━━━━━━━━━━ [数值]
   ↑ 靠右对齐                        靠左对齐 ↑
```

这样无论数据是 `30/30` 还是 `200/200`，左右两侧的数值文本都对齐到屏幕中线两侧的等距位置。

### 标签隐藏

不显示"头甲""HP""气力""AP"等文字标签——通过：
- 颜色区分（红=HP / 灰=头甲 / 蓝=身甲 / 橙=气力 / 黄=AP）
- 鼠标 hover 任意条 → tooltip 弹出"头甲" / "HP" / "AP（行动点）" 等说明

### AP 钻石点

- `◆`（U+25C6）= 满 AP 点 / `◇`（U+25C7）= 已消耗
- 每点 = 1 AP，按 `Stats.max_ap` 数量绘制
- 不显示 `9/9` 数字（钻石本身就是数量可视化）

---

## 五、键盘快捷键全表

| 键 | 行为 | 状态 |
|---|---|---|
| `1` ~ `9`, `0` | 触发当前 chip 列表第 1~10 项 | ✅ |
| `P` | 切换详情面板 | ✅ |
| `I` | 道具 popup（暂占位） | ⏳ |
| `Q` | 等待（排到队尾，每回合限 1） | ✅ |
| `Esc` | 详情打开时先关详情，否则不消费 → BattleScene 接管（取消选择） | ✅ |
| `Space` | 结束当前回合（AP 不跨回合保留，剩余 AP 清零）| ✅（BattleScene 处理） |
| `R` | 重开战斗（debug） | ✅（BattleScene 处理） |
| `WSAD` / 方向键 | 相机平移 | ✅（BattleScene 处理） |
| `Ctrl + =` / `Ctrl + -` | 缩放 | ✅（BattleScene 处理） |

---

## 六、详情面板（按 P 切换）

操作栏上方弹出，显示完整数据视图（HUD 没有的次要信息 + HUD 数据冗余）：

- **行 1**：单位姓名 + 阵营标签（友方/敌方）
- **行 2**：2×3 GridContainer
  - HP / AP / 头甲 / 身甲 / 气力 进度条（带数值标签）
  - 速度（基础 init − 疲劳 − 装备重量）
- **行 3**：武器细节（display_name / damage_base / weight / attack_modes / AP 消耗）
- **行 4**：护甲细节（display_name / 头甲 / 身甲 / 重量）
- **行 5**：提示文字 `[P] 切换详情`

> **冗余但不冲突**：HUD 是常驻概览（你随时知道 HP 还剩多少），详情是按需细查（你想看武器 base 值或速度推算）。两层信息满足 DOS2 玩家"扫一眼 + 深挖"两种节奏。

---

## 七、状态机（玩家回合）

```
        回合开始
            ↓
    ┌──────────────┐
    │   IDLE       │ ← 显示可达格 + 可击目标 + chip 全启用
    └──────────────┘
        ↓               ↓               ↓
   1~9 / chip 点击   Q / 等待 chip   Space / 结束
        ↓               ↓               ↓
   ┌────────────┐  ┌─────────┐   ┌──────────┐
   │ TARGETING  │  │ WAIT    │   │ END_TURN │
   │ （选目标）  │  │（即时） │   │ （即时） │
   └────────────┘  └─────────┘   └──────────┘
        ↓               ↓               ↓
   点击红色目标    挪到队尾       回合结束
        ↓               ↓               ↓
   执行攻击 → IDLE  IDLE（队列变更） 下回合
```

**AP 不足时**：chip 自动灰化，但仍可 hover 看 tooltip。
**等待已用过**：Q chip 灰化；`TurnManager.can_wait()` 返回 false。

---

## 八、与代码的对接点

### 8.1 节点结构（实装）

- `scripts/ui/CombatMenu.gd`（PanelContainer，`class_name CombatMenu`）
  - `_hud_panel`（透明背景）→ HUD 三层
  - `_action_panel`（深色木框）→ chip 行
- BattleScene 的 `UI` CanvasLayer 内挂载，常驻底部居中（`_update_screen_position()` 每帧定位）

### 8.2 信号

```gdscript
signal action_selected(action_id: String)
```

action_id 命名约定：
- `attack_<mode>`：例如 `attack_slash`、`attack_pierce`、`attack_crush`、`attack_ranged`
- `skill_<id>`：例如 `skill_aim_head`、`skill_all_out`、`skill_puncture`（占位）
- `wait`：等待
- `item_placeholder`：道具（占位）

### 8.3 BattleScene 路由

```gdscript
func _on_combat_menu_action(action_id: String) -> void:
    if action_id == "wait": return  # CombatMenu 已自处理
    if action_id.begins_with("attack_"):
        var mode := action_id.substr("attack_".length())
        # F3 待办：把 mode 透传到 _player_attack(unit, target, mode)
    if action_id.begins_with("skill_"): _log_hint("（Phase 2.5）")
    if action_id.begins_with("item_"): _log_hint("（Phase 3）")
```

### 8.4 数据来源（运行时）

- 攻击模式列表 → 当前 `Unit.weapon.attack_modes`
- 技能列表 → `Unit.job.abilities`（**待 B/C 阶段实装 JobClass + Ability 框架**，目前为占位字符串）
- 道具列表 → `Unit.inventory`（**Phase 3 实装**，目前为空数组）
- 头像 → `Unit.get_portrait_texture()`（Phase 1 已实装）

---

## 九、F3 待办：攻击模式对接伤害管线

> CombatMenu 已经把 chip 选择 emit 为 `attack_<mode>`，但 BattleScene 当前只打 hint log，没把 mode 透传到 `DamageSystem.execute_attack`。

**实施步骤（约 50 行）**：

1. `BattleScene.gd` 新增 `_pending_attack_mode: String = ""`
2. `_on_combat_menu_action("attack_xxx")` → 解析 mode 存到 `_pending_attack_mode`
3. `_player_attack(unit, target)` 改签名为 `_player_attack(unit, target, mode: String = "")`
4. `Unit.attack_target(target, mode: String = "")` 透传给 DamageSystem
5. `DamageSystem.execute_attack(attacker, target, options: Dictionary)` 已支持 `options.mode`，直接用
6. 玩家未主动选 chip → 默认 `mode = weapon.attack_modes[0]`
7. 攻击后清空 `_pending_attack_mode`

**收益**：双模式武器（**剑** / **陌刀**）按 1/2 切换斩/刺时，伤害系数（armor_mult / hp_mult / base_pen）真正切换：
- 选斩：`armor_mult=1.0, hp_mult=1.0, base_pen=0.10`（克皮甲）
- 选刺：`armor_mult=0.7, hp_mult=1.0, base_pen=0.15`（克锁甲，破甲率最高）

单模式武器（长矛/战锤等）chip 选择无差别——这是设计预期（后续靠 Phase 2.5 的"全力一击/瞄头"等能力扩展模式）。

---

## 十、F4 待办：道具 popup 占位

> 道具系统设计在 Phase 3 才完整落地。CombatMenu 的 `I` 字母键 chip 当前是 disabled 状态，需要给一个轻量级 popup 占位结构，避免后续接入时大改。

**v1（Phase 3 入口）**：
- 按 `I` 不直接触发动作，而是在 chip 行上方弹出一个 popup（沿用之前删掉的子菜单逻辑）
- popup 内 4~6 个槽位（纵向列表 chip）
- 槽位先 stub 空数组（`Unit.inventory` 待 Phase 3 实装）
- 选定槽位 → 进入 `TARGETING` 状态（与攻击 chip 同路径）→ 选目标格 → 触发

**v2（演化为自定义快捷栏）**：
- 战前界面允许玩家把高频物品（药水/投掷）拖到数字键 6/7/8/9
- 战斗中数字键直触，不必每次开 popup
- 等同 DOS2 hotbar 行为

**为什么 v1 走 popup 而不是直接铺到数字键栏**：
- 数字键 1~5 已被攻击/技能占满，物品再挤进去会 1~9 不够分配
- popup 模型的 `I` 键语义保持稳定（永远是"打开物品"），v1 → v2 演化时玩家肌肉记忆不变

---

## 十一、视觉风格

- **配色**：唐风深色木框（边框 0.62, 0.50, 0.32）+ 暖光描边，与 `BattleLog` 风格一致
- **字体**：Godot 默认字体（中文支持），字号梯度：装饰 9 / 数据 11 / chip 主字 18
- **AP 钻石**：黄色 `Color(0.95, 0.85, 0.30)`
- **chip 边框**：按 kind 染色（红/蓝/绿/黄）形成视觉分组
- **HUD**：透明背景（无外框），降低视觉噪音；只靠条本身的颜色 + 边框区分

---

## 十二、Phase 2.5+ 待补充（暂不做）

- 攻击模式 chip 的 hover 预览（命中率 / 期望伤害实时计算）
- 技能 chip 解锁后的 weapon_filter / job_filter（不擅长的技能不显示）
- 自定义快捷键（玩家可在设置里改 P/I/Q）
- 手柄支持（左摇杆方向选 chip / A 键确认 / B 键取消）
- 多人单位选择/批量指令（Tab 循环单位）
- 战斗结束时 HUD 平滑淡出动画
