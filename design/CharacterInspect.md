# 角色检视（Character Inspect）v1.0

> **定位**：Battle Brothers 式 **全屏角色案牍**——立绘 + 属性 + 装备 + 技能 + Buff + **随身道具**。  
> **不在战斗中叠层打扰操作**；与 `UnitTooltip` 瞥视、`CombatMenu` P 轻量详情分工明确。  
> **配套**：[`combat-ui.md`](combat-ui.md) · [`status-effects.md`](status-effects.md) · [`combat-effects-system.md`](combat-effects-system.md) · [`economy-system.md`](economy-system.md) §补给

---

## 一、为什么单独做（决策记录）

| 方案 | 问题 |
|---|---|
| 战斗内 **固定 hover** 查 Buff | 挡战场、与移动/攻击抢点击；读 icon 说明时仍有操作成本 |
| 仅靠 **P 详情条** | 空间不够放装备格、Buff 表、道具栏；与底栏 HUD 冗余 |
| **双击 → 全屏检视 + Esc 回战场** ✅ | 查阅是「切模式」；Buff/道具可展开写清；不干扰本回合操控 |

**原则**：战场上只保留 **瞥视**（hover）；**深查**进 Character Inspect。

---

## 二、入口与退出

| 操作 | 条件 | 行为 |
|---|---|---|
| **双击** 地图上单位 | 仅 **我方回合**（`current_unit.faction == 0`） | 打开检视，绑定该 `Unit` |
| **Esc** | 检视已打开 | 关闭，回到战场（恢复进入前选中/高亮状态） |
| 单击 / 悬停 | 检视 **未** 打开 | **不变**——仍走 `UnitTooltip` transient hover |
| 敌方回合 | — | 双击无效（或灰显提示「观战中」） |

打开检视时：

- 战场 **输入锁定**（不响应移动/攻击 hex 点击；避免误操作）
- 底栏 `CombatMenu` **可隐藏或灰化**（实现二选一，默认隐藏减少噪音）
- **不暂停** AI 计时器（若未来有）；当前回合 AP 不自动消耗

---

## 三、与其他 UI 的分工

```
                    ┌─────────────────────────────────────┐
  hover 单位        │ UnitTooltip：HP/甲/命中预览（瞥视）   │
  双击单位          │ CharacterInspect：全量案牍（深查）    │
  P 键              │ CombatMenu 详情条：当前行动者轻量属性  │ → 长期可收敛到「仅当前单位快捷条」
  I 键              │ 行军置物架：战斗快捷用道具（6 格）      │ → 与检视「道具区」同源数据
                    └─────────────────────────────────────┘
```

| UI | 场景 | 道具 |
|---|---|---|
| **Character Inspect · 道具区** | 身上 **全部** 携带物（背包/腰囊） | 列表 + 图标 + 数量 + 说明；战斗内只读 |
| **CombatMenu · I 置物架** | 战前绑定的 **快捷栏**（最多 6） | 战斗中按 `I` 选格 → 选目标使用 |
| 关系 | 快捷栏是背包的子集引用 | 在检视里可「设为快捷」；营地可拖拽整理 |

---

## 四、版面布局（BB 风案牍）

```
┌──────────────────────────────────────────────────────────────────────────┐
│  [×] 归队 (Esc)                                    强盗头目  ·  敌方      │
├──────────────┬───────────────────────────────────────────────────────────┤
│              │  【属性】                                                  │
│   立绘       │  HP / 气力 / Init / 智识 / 暴击 / 近战 / 防御 / 移动 …     │
│  (半身/全身) │  职业 · 性格 · 士气档（H2）                                 │
│              ├───────────────────────────────────────────────────────────┤
│  阵营色框    │  【装备】          【技能】                                  │
│              │  武器 [icon]       主动 1~4（Phase 2.5+）                  │
│              │  护甲 [icon]       被动 / 反应（占位）                       │
│              │  副手 [icon]                                               │
│              ├───────────────────────────────────────────────────────────┤
│              │  【状态】 Buff / Debuff / 派生（气力档、手拙）               │
│              │  [icon] 流血   每回合 -5 HP        剩 2 回合               │
│              │  [icon] 疲劳   命中 -10%         派生                       │
│              ├───────────────────────────────────────────────────────────┤
│              │  【随身道具】                                              │
│              │  [icon] 金创药 ×2   恢复 HP …                             │
│              │  [icon] 解毒散 ×1   清除中毒 …                             │
│              │  （空槽显示「—」；重量合计 x / 负重上限）                    │
└──────────────┴───────────────────────────────────────────────────────────┘
```

- **立绘**：`Unit.get_portrait_texture()` 大图；无资源时 fallback 战斗 sprite 放大
- **装备**：与 `Unit.weapon` / `Unit.armor` / 副手（未来）只读展示；数值 hover 展开渗透/重量
- **技能**：已学 `Ability` / 职业主动；未实装显示锁定占位
- **状态**：`Unit.get_status_for_ui()`（J 段容器）；每条 **名称 + impact 一行 + 回合**；icon 可 hover 展开长说明
- **随身道具**：`Unit.inventory`（见 §五）

视觉：唐风案牍（直角、熟纸底、铁包边）——**独立 Scene**，不与战场 UI 混用失败过的平铺纹理方案。

---

## 五、数据模型（SoT）

### 5.1 装备 / 属性

| 字段 | 来源 |
|---|---|
| Stats 全表 | `Unit.stats` |
| 武器/护甲 | `WeaponArmorDB` via `Unit.weapon` / `Unit.armor` |
| 职业 | `Unit.job` → `JobDB` |
| 性格 / 倾向 | `personality_id` / `disposition_id`（敌军战法，只读展示） |

### 5.2 状态（Buff / Debuff）

| 层级 | 来源 |
|---|---|
| 实例效果 | `CombatEffectContainer` → `data/effects.json` |
| 派生（气力档、手拙） | `DerivedEffects` / `get_active_debuffs()`，带「派生」标签 |

### 5.3 随身道具

**战斗单位携带物**，与营地仓库区分：

```gdscript
# Unit.gd（演进目标，Phase 3 前可为 stub）
var inventory: Array = []   # Array[ItemStack] 或 Dictionary 序列化
# ItemStack: { item_id: String, count: int, slot: int }
```

| 概念 | 说明 |
|---|---|
| **背包（inventory）** | 本场战斗身上携带的全部道具；检视 **道具区** 完整列出 |
| **快捷栏（quick_bar）** | 6 格，CombatMenu `I` 置物架；引用 `item_id`，不重复占背包格 |
| **重量** | 计入 `Stats` 负重：`武器 + 护甲 + Σ item.weight × count`（见 `class-system.md` 负重） |
| **数据表** | `data/items.json`（Phase 3 SoT，结构对齐 `economy-system.md` 补给定价） |

**战斗内检视**：道具只读；**使用**仍走 `I` 置物架 → 选目标（不在这屏直接点「使用」，避免与 Esc 回战场逻辑纠缠）。  
**营地检视**：同一 `CharacterInspect` 组件，开启 `editable` 模式：换装、拖动物品、整理快捷栏。

---

## 六、实现落点

| 组件 | 路径（建议） |
|---|---|
| 场景 | `scenes/ui/CharacterInspect.tscn` |
| 脚本 | `scripts/ui/CharacterInspect.gd` |
| 绑定 API | `CharacterInspect.open(unit: Unit, mode: InspectMode)` |
| 战场接线 | `BattleScene` 双击检测 → `open(READONLY)`；`ui_cancel` → `close()` |

**双击检测**：hex 层 400ms 内同格第二次点击；**不**触发移动/攻击单点逻辑。

---

## 七、分期

| 阶段 | 内容 | 验收 |
|---|---|---|
| **CI0**（Phase 2.x） | 壳子：立绘 + 属性 + 装备只读 + Esc | 双击友/敌/队友可开可关 |
| **CI1**（J1 后） | 状态区接 `effects.json` + icon + 说明行 | 与容器数据一致 |
| **CI2**（Phase 3） | 道具区接 `items.json` + `Unit.inventory`；重量行 | 与 `I` 置物架同源 |
| **CI3**（营地） | `editable`：换装、背包整理、快捷栏绑定 | 与战斗只读版共用 Scene |

---

## 八、不在本期

- 检视内直接发动攻击 / 移动
- 战斗内改装备（仅营地 `editable`）
- 替换 `UnitTooltip` hover（瞥视保留）
- 战斗内固定 pin hover（已否决，见 §一）

---

## 九、交叉引用

| 文档 | 关系 |
|---|---|
| [`combat-ui.md`](combat-ui.md) §十 | `I` 置物架与快捷栏 |
| [`phase2-todo.md`](phase2-todo.md) | 可增 **F7 / CI0** 任务项 |
| [`combat-effects-system.md`](combat-effects-system.md) | Buff 列表数据源 |
| [`status-effects.md`](status-effects.md) | 效果文案与档位 |
| [`economy-system.md`](economy-system.md) | 道具经济、补给品类 |
| [`personality-system.md`](personality-system.md) | 性格展示（只读） |

---

**文档版本**：v1.0  
**最后更新**：2026-06-12
