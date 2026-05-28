# Game001 — Battle Brothers Demo

一个受 **《战兄弟（Battle Brothers）》** 启发的硬核中世纪战棋 Demo。

## 目标

复刻战兄弟战斗系统的核心精髓：
- 基于 **Initiative（主动性）** 的动态回合序列（不区分玩家/敌人回合）
- 六边形战场 + **控制区（Zone of Control）** + 借机攻击
- **高低差** 命中加成 / 爆头概率
- **压制（Overwhelm）** 侧翼包抄机制
- **破甲 → 穿甲 → 剩余护甲 10% 抵消** 三段式伤害管线
- 角色属性面板：HP / Head & Body Armor / AP / Fatigue / Morale & Resolve / Initiative / Melee & Ranged Skill & Defense
- 背景与天赋星级（Backgrounds & Talents）成长机制

## 技术栈

- **引擎**：Godot 4.3 stable（标准版，GDScript）
- **平台**：macOS（开发） → 可导出到 Windows / macOS / Linux / Web
- **版本控制**：Git

## 开发路线图

### Phase 1（已完成 ✅）：战斗核心 MVP
目标：能在六边形地图上选择单位、按 Initiative 顺序行动、移动、攻击、计算命中与破甲伤害。

- [x] 六边形网格（HexGrid）+ AStar 寻路 + BFS 可达计算 + 鼠标拾取与高亮
- [x] 单位（Unit）+ 属性数据类（Stats）：HP / 头身护甲 / AP / Fatigue / Resolve / Initiative / 近远战技能与防御
- [x] Initiative 回合调度器（TurnManager）：动态排序，不区分玩家/敌方回合
- [x] 移动消耗 AP / Fatigue，Initiative 随疲劳实时下降
- [x] 近战攻击：命中率 = 攻击者近战技能 - 防御者有效近战防御（>45 收益递减）
- [x] 三段式伤害管线：基础 → 对甲效率（破甲）→ 穿甲（直击 HP）→ 剩余护甲 10% 抵消
- [x] 头部/身体分别命中（头部 ~5%，伤害 ×1.5）
- [x] 单位面板 UI（HP/头身甲/AP/Fatigue 进度条）+ BBCode 战斗日志
- [x] 顶部 Initiative 排序预览
- [x] 简单 AI（敌方追击 + 攻击）
- [x] 武器/护甲 JSON 数据驱动（5 武器 + 4 护甲）

#### 操作说明

| 按键/操作 | 说明 |
|---|---|
| 左键点击友方单位 | 选中（自动选当前回合单位） |
| 左键点击蓝色高亮格 | 移动（消耗 AP/Fatigue） |
| 左键点击红色高亮敌人 | 攻击 |
| 空格 | 结束当前回合 |
| R | 重开战斗 |
| ESC | 取消选中 |

### Phase 2：拟真战斗
- [ ] 控制区 + 借机攻击（Zone of Control）
- [ ] 高低差（Elevation）
- [ ] 压制（Overwhelm）
- [ ] 士气/决心系统（六级士气状态）
- [ ] 简单 AI（敌方单位行动）

### Phase 3：角色养成
- [ ] 背景（Backgrounds）+ 天赋星级（1-3 stars）
- [ ] 升级加点 + 11 级软上限 + 老兵等级
- [ ] 永久创伤（Hitpoints 归零后果）

### Phase 4：战略层
- [ ] 城镇与动态物价
- [ ] 修理与倒卖（工具/T2 T3 武器利润法则）
- [ ] 剥甲战术（Puncture / 匕首穿刺）

## 项目结构

```
Game001/
├── project.godot              # Godot 项目入口
├── icon.svg                   # 项目图标（占位）
├── assets/                    # 美术资源（暂用占位色块）
│   ├── sprites/
│   ├── tiles/
│   └── fonts/
├── scenes/                    # 场景 .tscn
│   ├── Main.tscn              # 入口场景
│   ├── battle/
│   │   ├── BattleScene.tscn   # 战斗主场景
│   │   ├── HexGrid.tscn       # 六边形战场
│   │   └── Unit.tscn          # 单位 prefab
│   └── ui/
│       └── UnitPanel.tscn     # 单位属性面板
├── scripts/
│   ├── core/
│   │   ├── Stats.gd           # 属性数据类
│   │   ├── Unit.gd            # 单位逻辑
│   │   ├── TurnManager.gd     # Initiative 调度
│   │   ├── HexGrid.gd         # 六边形网格 + 寻路
│   │   ├── DamageSystem.gd    # 伤害管线
│   │   └── ZoneOfControl.gd   # 控制区
│   ├── data/
│   │   └── Backgrounds.gd     # 背景与天赋
│   └── ui/
│       └── UnitPanel.gd
└── data/                      # 数据驱动配置
    ├── weapons.json
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

推荐安装 VS Code 扩展 **godot-tools**，提供 GDScript 语法高亮、跳转、调试。

```bash
code --install-extension geequlim.godot-tools
```

在 Godot 编辑器：`Editor → Editor Settings → Text Editor → External` 勾选 Use External Editor，
Exec Path 填 `/usr/local/bin/code`，Exec Flags 填 `{project} --goto {file}:{line}:{col}`。

## 设计理念参考

- 战斗：高度拟真的中世纪战斗模拟，每个数值都可被玩家理解和反推
- 数值：硬核但不劝退，暴露完整公式给玩家
- 节奏：回合制但战术深度高，单场战斗可持续 10-20 回合
