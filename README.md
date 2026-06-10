# Game001 — Battle Brothers Demo

一个受 **《战兄弟（Battle Brothers）》** 启发的硬核中世纪战棋 Demo，唐代边军主题。

## 目标

复刻战兄弟战斗系统的核心精髓 + 唐代背景叙事：
- 基于 **Initiative（主动性）** 的动态回合序列（不区分玩家/敌人回合）
- 六边形战场 + **控制区（Zone of Control）** + 借机攻击
- **高低差** 命中加成 / 爆头概率
- **压制（Overwhelm）** 侧翼包抄机制
- **三段式伤害管线**：armor_mult 破甲 → 武器重量驱动渗透 → 攻击类型差异化
- 角色属性面板：HP / Head & Body Armor / AP / Fatigue / Morale & Resolve / Initiative / Melee & Ranged Skill & Defense / **Wisdom**
- 19 职业体系（押衙亲兵 / 陌刀手 / 跳荡 / 不良人 / 僧兵 / 弩手 / ...）
- 唐代制式武器 15 件（横刀 / 陌刀 / 长矛 / 擘张弩 / ...）
- 临时伤势 + 永久伤势 + 士气崩溃

## 技术栈

- **引擎**：Godot 4.3 stable（标准版，GDScript）
- **平台**：macOS（开发） → 可导出到 Windows / macOS / Linux / Web
- **版本控制**：Git

## 开发路线图

### Phase 1（已完成 ✅）：战斗核心 MVP
目标：能在六边形地图上选择单位、按 Initiative 顺序行动、移动、攻击、计算命中与破甲伤害。

- [x] 六边形网格（HexGrid）+ AStar 寻路 + BFS 可达计算 + 鼠标拾取与高亮
- [x] 单位（Unit）+ 属性数据类（Stats）：HP / 头身护甲 / AP / Fatigue / Resolve / Initiative / 近远战技能与防御 / Wisdom
- [x] Initiative 回合调度器（TurnManager）：动态排序，不区分玩家/敌方回合
- [x] 移动消耗 AP / Fatigue，Initiative 随疲劳实时下降
- [x] 近战攻击：命中率 = 攻击者近战技能 - 防御者有效近战防御（>45 收益递减）
- [x] 三段式伤害管线（v3 旧版，待 Phase 2 重构为 weight × 渗透公式）
- [x] 头部/身体分别命中（头部 ~5%，伤害 ×1.5）
- [x] **控制区 + 借机攻击**：装备近战武器单位威胁周围 6 格，离开敌人 ZoC 触发免费攻击
- [x] **评分式 AI（BattleAI）**：枚举可达格 × 攻击目标，按评分函数选最优行动
- [x] 单位面板 UI（HP/头身甲/AP/Fatigue 进度条）+ BBCode 战斗日志 + Initiative 排序预览
- [x] 武器/护甲 JSON 数据驱动（5 武器 + 4 护甲）

#### 操作说明

| 按键/操作 | 说明 |
|---|---|
| 左键点击友方单位 | 选中（自动选当前回合单位） |
| 左键点击蓝色高亮格 | 移动（消耗 AP/Fatigue） |
| 左键点击红色高亮敌人 | 攻击（用 weapon.attack_modes[0] 默认模式） |
| **数字键 1~9** | 触发对应攻击模式 / 技能 chip（动态从 weapon + abilities 展开） |
| **P** | 切换详情面板（HP/AP/头甲/身甲/气力 + 装备细节） |
| **I** | 道具（Phase 3+） |
| **Q** | 等待 — 排到本回合队尾（不消耗 AP，每回合限 1 次） |
| WSAD / 方向键 | 相机平移 |
| Ctrl+= / Ctrl+- | 缩放 |
| 空格 | 结束当前回合（AP 不跨回合保留） |
| R | 重开战斗（debug） |
| ESC | 取消选中 / 关闭详情 |

### Phase 2（进行中 🚧）：职业 × 战斗 Demo

**详细规划见**：[`design/phase2-plan.md`](design/phase2-plan.md)

**核心目标**：用 4 个代表性职业 + 武器系统新规则（疾风连击 / 锐意 / 残忍 / 双武器精通 / 伤势）跑出可玩战斗 Demo。

#### 设计层（已落地 ✅）
- [x] **武器系统 v3.1**：攻击类型 + weight × 渗透公式 + 疾风连击 + 双武器精通规则（[`design/weapon-system.md`](design/weapon-system.md)）
- [x] **职业系统 v1.3**：19 职业 + Wisdom→暴击 + 锐意/残忍/疾风连击（[`design/class-system.md`](design/class-system.md)）
- [x] **状态系统**：临时伤势触发新规则（≥10% HP + HP 状态分档修正 + cap 75%）（[`design/status-effects.md`](design/status-effects.md)）
- [x] **武器数据**：15 件武器 weight 校准对齐 BB 0~16 范围（[`data/weapons.json`](data/weapons.json)）
- [x] **战斗 UI 设计**：DOS2 风扁平化平铺（头像 + 字母键 P/I/Q + 数字键 1~9 + 中心对称 HUD）（[`design/combat-ui.md`](design/combat-ui.md)）

#### 代码层进度（v1.3，与 [`design/phase2-todo.md`](design/phase2-todo.md) 同步）

> 具体职业能力（疾风连击 / 全力一击 / 碎甲 / 双武器精通 / 锐意 / 残忍 / 伤势）放到 **Phase 2.5（能力专题）** 单独推进，避免战斗系统底盘还没稳就先做花活。

- [x] **A. DamageSystem 重构** — 9 步管线 + Wisdom→暴击 + weight×渗透 + 27 项单测 PASS
- [x] **E. 行动调度重构** — CT 累加 → AP+回合制+Init 排序+等待机制（不消耗 AP / 每回合限 1 次）+ 22 项单测 PASS
- [x] **F1/F5/F6. 战斗 UI 主体** — CombatMenu（头像 + 字母键 + 数字键 chip）+ HUD（中心对称三层）+ 详情面板（P 切换）
- [ ] **B. 4 职业数据** — 跳荡 / 陌刀手 / 不良人 / 押衙亲兵（JobClass + JobDB + 武器专精系数）
- [ ] **C. Ability 框架** — Ability 基类 + BasicAttack 数据驱动
- [ ] **D. 4v4 Demo + UI 收尾** — BattleScene 升级 + 战斗预览 + 战斗日志 v2 + TopBar 升级
- [ ] **F3. 攻击模式对接** — chip 选"斩/刺"真正切换 armor_mult/hp_mult/base_pen 系数
- [ ] **F4. 道具 popup 占位** — 按 I 弹槽位（Phase 3 接入 Unit.inventory）

### Phase 3：角色养成（未启动）
- [ ] 经验 / JP / 升级 / 转职树
- [ ] 词条系统（武器 / 护甲）
- [ ] 永久伤势
- [ ] 弩手抵近射击 + 上弦机制
- [ ] 僧兵棒打七寸 + 念力护体
- [ ] 方士战兵方术系统

### Phase 4：战略层（未启动）
- [ ] 营地 / 招募 / 退役
- [ ] 城镇与动态物价
- [ ] 故事节点 / 任务系统
- [ ] 长线 campaign

## 项目结构

```
Game001/
├── project.godot              # Godot 项目入口
├── icon.svg                   # 项目图标（占位）
├── README.md                  # 本文档
├── design.md                  # 顶层设计概要
├── design/                    # 详细设计文档（核心知识基线）
│   ├── weapon-system.md       # 武器系统（v3.1）⭐
│   ├── class-system.md        # 职业系统（v1.3）⭐
│   ├── status-effects.md      # 状态/伤势系统
│   ├── boss-mechanics.md      # Boss 机制
│   ├── terrain-system.md      # 地形系统
│   ├── economy-system.md      # 经济系统
│   ├── art-pipeline.md        # 美术管线
│   ├── phase2-plan.md         # Phase 2 推进计划 ⭐
│   └── references/            # 调研资料（BB 各系统机制）
├── assets/                    # 美术资源
├── scenes/
│   ├── Main.tscn
│   └── battle/
│       └── BattleScene.tscn   # 战斗主场景
├── scripts/
│   ├── core/
│   │   ├── Stats.gd           # 属性数据类（含 wisdom）
│   │   ├── Unit.gd            # 单位逻辑
│   │   ├── TurnManager.gd     # AP+回合制 调度（v3：Init 排序+等待+AP 不跨回合）
│   │   ├── HexGrid.gd         # 六边形网格 + 寻路
│   │   ├── DamageSystem.gd    # 伤害管线 v3.1（9 步 + Wisdom 暴击 + weight×渗透）
│   │   ├── BattleAI.gd        # 评分式 AI
│   │   ├── BattleScene.gd     # 战斗主控
│   │   ├── WeaponData.gd      # 武器数据（v3.1：damage_base/weight/attack_modes）
│   │   ├── ArmorData.gd       # 护甲数据
│   │   └── HexCoord.gd        # 六边形坐标工具
│   ├── data/
│   │   └── WeaponArmorDB.gd   # 武器/护甲数据库（autoload）
│   ├── effects/
│   ├── tools/
│   │   ├── test_damage_system.gd   # DamageSystem v3.1 自检（27 PASS）
│   │   └── test_turn_scheduler.gd  # AP+回合制+等待 自检（22 PASS）
│   └── ui/
│       ├── CombatMenu.gd      # 战斗菜单（DOS2 风扁平化 + HUD 中心对称） ⭐
│       ├── SidePanel.gd       # 单位面板
│       ├── TopBar.gd          # 顶部 Initiative 预览
│       └── UnitTooltip.gd
└── data/
	├── weapons.json           # 15 件武器（v3.1）
	└── armors.json
```

## 启动开发

### 1. 打开项目

```bash
godot --path /Users/chaschen/Project/Game001 --editor
```

或直接打开 Godot.app，在项目管理器中导入 `project.godot`。

### 2. 运行

在 Godot 编辑器内按 **F5** 运行主场景；或命令行：

```bash
godot --path /Users/chaschen/Project/Game001
```

### 3. VS Code 编辑（可选）

推荐安装 VS Code 扩展 **godot-tools**：

```bash
code --install-extension geequlim.godot-tools
```

在 Godot 编辑器：`Editor → Editor Settings → Text Editor → External` 勾选 Use External Editor，
Exec Path 填 `/usr/local/bin/code`，Exec Flags 填 `{project} --goto {file}:{line}:{col}`。

## 设计理念

- **战斗**：高度拟真的中世纪战斗模拟，每个数值都可被玩家理解和反推
- **数值**：硬核但不劝退，暴露完整公式给玩家
- **节奏**：回合制但战术深度高，单场战斗 10-20 回合
- **职业**：19 个差异化职业，没有"纯辅助"或"纯治疗"——所有职业都是战斗员
- **武器**：15 件唐代制式武器，weight 0~16 拉开差距，**重型利器靠动能透甲**
- **build**：神装 + 高 Wisdom + 锐意 + 疾风连击 = 刺客 80% 概率秒中甲后排
- **伤势**：临时伤势让"打完这场要回营地养伤"成为玩家的真实战略选择

## 关键文档索引

| 文档 | 内容 | 版本 |
|---|---|---|
| [`design.md`](design.md) | 顶层设计概要 | — |
| [`design/weapon-system.md`](design/weapon-system.md) | 武器系统：攻击类型 / 渗透公式 / 职业能力 / 双武器精通 | v3.1 |
| [`design/class-system.md`](design/class-system.md) | 职业系统：19 职业属性面板 + Wisdom 作用 + 专属能力 | v1.3 |
| [`design/status-effects.md`](design/status-effects.md) | 状态系统：伤势触发 + 士气崩溃 | — |
| [`design/combat-ui.md`](design/combat-ui.md) | 战斗 UI：DOS2 风扁平化（头像 + P/I/Q 字母键 + 1~9 数字键 + 中心对称 HUD） | v1.1 |
| [`design/phase2-plan.md`](design/phase2-plan.md) | **Phase 2 推进计划**（4 大支柱 / 4 周节奏 / 验收清单） | v1.2 |
| [`design/phase2-todo.md`](design/phase2-todo.md) | **Phase 2 实操 Todo**（24 项可勾选清单，与 IDE Todo 双向同步） | v1.3 |
| [`design/references/`](design/references/) | BB 系统调研资料（武器/护甲/伤势/AI 等） | — |
