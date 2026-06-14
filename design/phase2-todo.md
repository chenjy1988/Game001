# Phase 2 Todo 清单（v2.0 聚焦版）

> **配套文档**：[`phase2-plan.md`](phase2-plan.md) v1.2
> **范围**：战斗系统重构 + 4 职业数据 + Ability 框架 + UI 升级（4 周）
> **不在本期**：具体职业能力（推到 Phase 2.5）
>
> **使用说明**：
> - 进行中的项标记 `[ ]` → `[~]`（in_progress）
> - 完成后改为 `[x]`
> - 同时同步 IDE Todo 面板（保持双向一致）

---

## 0. 开发周期全景（项目整体定位）

### 0.1 SRPG 项目生命周期对照

| 阶段 | 名称 | 核心目标 | 工业标准 | 本项目对应 |
|---|---|---|---|---|
| Pre-Production | 立项 / 设计 | 题材 + USP + 玩法骨架 + 数值蓝图 | 2-3 个月 | ✅ 已完成（`design.md` + `design/*` 共 10+ 篇基线） |
| **Phase 1** | 战斗核心 MVP | 一个能动的战斗循环（hex + 单位 + 命中 + 伤害 + AI） | 1-2 个月 | ✅ 已完成 |
| **Phase 2** | 战斗系统 v3.1 | 武器 / 职业 / Ability 框架 / 4v4 Demo / 战斗 UI | 4 周 | 🚧 **进行中**（MVP 可玩验证阶段） |
| **Phase 2.5** | 能力专题 | 7 个职业能力 + 被动池 + 伤势系统 | 3-4 周 | ⏳ 未启动 |
| **Phase 3** | 角色养成 | EXP / JP / 升级 / 转职树 / 词条 / 永久伤势 / 19 职业（见 [**J 段**](#j-经验养成phase-3)） | 2-3 个月 | ⏳ 未启动 |
| **Phase 4** | 战略层 | 大地图 / 营地 / 招募 / 经济 / 任务 / Campaign | 3-4 个月 | ⏳ 未启动 |
| Phase 5 | 内容生产 | 主线 12-15 章 + 支线 + 美术资源 + 配音 | 6-12 个月 | ⏳ 未启动 |
| Phase 6 | Polish + QA | 平衡调优 / Bug / 多平台导出 / 本地化 | 2-3 个月 | ⏳ 未启动 |
| Phase 7 | 发行 + DLC | EA → 1.0 → DLC 长尾 | 持续 | ⏳ 未启动 |

### 0.2 当前定位

**Phase 2（战斗系统重构 + UI 升级）Week 3-4**，核心战斗循环与战斗 UI **代码侧已收尾**；四职体感 / 4v4 时长等 **定性验收并入 P1.5 数值仿真**（与 AI 重构、`run_sim` 批量一并做，§0.4）。

**已落地**：
- ✅ A 段 DamageSystem v3.1（9 步管线 + Wisdom 暴击 + weight × 渗透，26/27 单测；T5 陌刀均值历史偏差待调）
- ✅ E 段 行动调度（AP+回合制+Init 排序+等待，22 单测）
- ✅ F 段 CombatMenu（DOS2 风扁平化 + HUD + F4 行军置物架 + 攻击模式对接）
- ✅ B 段 4 职业数据（`jobs.json`：**跳荡/枪手/奇兵/斥候**，以 JSON 为准）
- ✅ G 段 先发制人 + 行动条（仅 G7 文档补录待做）

**Phase 2 期间额外 polish（原 todo 外）**：
- ✅ 战场迷雾、战斗日志面板（展开/折叠 + 滚底）
- ✅ TopBar 头像悬停 + 时间轴 hover
- ✅ 程序化战斗音效（`CombatAudio` autoload）
- ✅ 视觉色板（`CombatPalette`）+ 打击感抛光（HitEffect / 受击动画）
- ✅ 夹击 v3 + 单位朝向（开战初始化 / 移动 / 攻击）+ `design.md` §九 同步
- ✅ 无头测试 `tools/smoke.sh` / `run_tests.sh`
- ✅ 4v4 对战仿真 `tools/run_sim.sh`（`BattleSimHarness` + `scenes/tools/BattleSim.tscn`）

### 0.3 推进顺序（MVP 可玩验证路径，优先于全量 Phase 2）

```
Week A（可玩闭环）：
  D1  4v4 标准阵容（jobs.json 四职 + 敌方精英重甲）
  D2  SidePanel 武器数值 + UnitTooltip 命中预览（期望伤害搁置）
  D4  TopBar 职业缩写 + 气力档位 + 智识/暴击（icon 像素图后置）✅
  ~~手打定性验收~~ → 并入 P1.5（`run_sim` + 遥测，§0.4）

Week B（Phase 2 收尾）：
  ~~D5 手打验收~~ → ✅ 合并至 P1.5 仿真环节（与数值调参同批验证）
  C1  Ability 框架（Phase 2.5 前补，非 MVP 阻塞）
  ~~D3 日志公式 toggle~~（暂缓，保持现状）
```

### 0.4 数值与平衡策略（决策记录，2026-06-12）

> **结论**：职业 / 武器 JSON **暂不手调**；等 **AI 系统重构完成** 后，用 **仿真实验** 收集数据，再判断数值与技能是否超标。

**为什么先 AI、后数值**

| 现状 | 后果 |
|---|---|
| 旧 `BattleAI` 一次出整条 plan，行为不稳定 | `run_sim` 胜率 / 时长 / 死亡分布噪声大 |
| 手打 + 凭感觉改 `jobs.json` / `weapons.json` | 无法区分「数值问题」还是「AI 弱智」 |

**验证链路**（SoT：[`ai-system.md`](ai-system.md) + `tools/run_sim.sh`）

```
① AI 重构落地（原子 Action / 独立 RNG / WorldView / 行为日志）
        ↓
② BattleSimHarness 接新 AI + 结构化遥测
   （回合数、击杀顺序、AP 利用、行为分、seed）
        ↓
③ 固定 4v4 阵容 × N 种子（建议 100~500 局）汇总指标
        ↓
④ 据此判断职业/武器 JSON 是否偏（胜率畸高、重甲局拖太久等）
        ↓
⑤ Phase 2.5 技能 / 能力：同一 harness 做「仅普攻 vs +技能」A/B
        ↓
⑥ 确认超标后再改数值或砍技能
```

**现阶段允许 / 禁止**

| ✅ 允许 | ❌ 禁止（至 ① 完成前） |
|---|---|
| UI 可读性（智识、暴击、命中预览） | 手调 `data/jobs.json` / `data/weapons.json` 追体感 |
| 手打记 **hypothesis**（如「打不动重甲」） | 凭手打结论直接改职业设计 |
| 仿真脚本预留 seed / archetype / disposition 字段 | Phase 2.5 能力数值大改 |
| Bug 修复、公式与单测对齐文档 | 以「技能太强」为由提前砍未实装能力 |

手打发现的体感问题记入验收清单或本地 `balance-notes`（可选），**标注为待仿真验证**，不直接落 JSON。

### 0.5 风险提示

1. **职业名以 `jobs.json` 为准**：`phase2-plan` 旧名（陌刀手/不良人/押衙亲兵）仅作远期参考，验收清单已同步。
2. **C1 非 MVP 阻塞**：普攻已通；Ability 框架在 Phase 2.5 加能力前落地即可。
3. **D3 暂缓**：当前折叠/展开 + 精简日志已够用；详细公式 toggle 不做，待试玩/仿真后再定。
4. **期望伤害预览**：用户明确不要（波动大）；D2 验收只要求命中率 + 围攻提示。
5. **数值调参门禁**：见 §0.4；Agent / 开发者改 JSON 前须 AI 仿真链路可用。

---

## A. DamageSystem 重构（Week 1）✅ 完成

- [x] **A1** — `WeaponData.gd` 加新字段（`damage_base: int` / `weight: int` / `attack_modes: Array[String]` / `head_chance` / `two_handed` / `block_value`），data/weapons.json schema 已对齐；旧字段（damage_min/max/armor_effectiveness/armor_penetration）deprecated 但保留 1 个版本
- [x] **A2** — `DamageSystem.gd` 按 weapon-system.md § 6.1 重写 9 步流程：
  1. 命中检定
  2. 部位判定（头 25% / 身 75%）
  3. 暴击 roll
  4. base × 气力档位 × 精通 × 词条 × DG
  5. 加法叠加（头部 +0.5 / 暴击 +0.5）
  6~7. 攻击类型（armor_mult）+ `final_damage` 加法倍率
  8. HP 分配：透甲 = 实际扣甲 × 渗透率；击穿后 = (final − 实际扣甲) × hp_mult（见 weapon-system.md § 4.2.4）
  9. 隐藏气力消耗
- [x] **A3** — 暴击率公式落地：`5 + max(0, wisdom-40)*0.2`，软上限 50%
- [x] **A4** — 单元测试 `scripts/tools/test_damage_system.gd`：陌刀手 vs 重甲（Slash 普攻）/ 跳荡 + 长矛 vs 中甲（Pierce 普攻）期望与文档 § 6.4 对齐，27 项 PASS

**Week 1 deliverable**：✅ 单元测试跑通，公式与文档一致。

---

## B. 4 职业数据 + 武器专精（Week 2）

- [x] **B1** — `scripts/core/JobClass.gd`（Resource）+ `data/jobs.json`：4 职业（跳荡/枪手/奇兵/斥候）+ `JobDB.gd` autoload 注册完毕；与设计文档职业名不同，以当前 JSON 为准
- [x] **B2** — `JobClass.fixed_stats()`（中值，调试用）+ `BattleScene._create_unit_from_job()` 接入 JobDB；友方 4 单位按职业生成，`unit.job` 已注入
- [x] **B3** — 武器专精（方案 A）：`Unit.attack_target()` 填入 `mastery_dmg`：在武器池内 1.0，否则 0.9（手拙）；命中惩罚 -10% 已在 `calculate_hit_chance` 实装；`job == null` 的单位不受影响
- [x] **命中 v3.2** — `weapon-system.md` §6.1.1：`final_def` 合成（闪避/格挡 1:1 进防御点、高防惩罚在合成后）、一次掷骰、miss 按 roll 区间归因；`ignore_dodge` / `ignore_block` / `block_mult` options 占位；士气 `def_mult` stub；`test_damage_system.gd` T_def/T_penalty/T_miss_attrib/T_ignore 全绿
- [x] **格挡/闪避规则落地** — `block_pts`：配盾仅盾 / 双持求和 / 主手固定值（不含 defense）；`dodge_pts` 默认 0；**身轻如燕**（JP 被动）`(init−全身重)×20%`；`data/shields.json` + `Unit.shield/offhand_weapon`；文档同步 `design.md` §四/§六、`class-system.md` §11（Trait≠JP，见 personality-system §一）

**Week 2 deliverable**：4 职业能正确生成 + 普攻数值因专精梯度而拉开差距。

---

## C. Ability 调度框架（Week 2 末）— P1，MVP 不阻塞

- [x] **C1** — Ability 框架（[`ability-system.md`](ability-system.md)）
  + 基类：`Targeting` / `Kind` / `resolve_targets()` / `gather_effect_specs()` / `AbilityEffectSpec`
  + 敌我 buff·debuff 统一 `apply_effect_specs()` → `Unit.apply_effect_spec()`（J0 接 CombatEffect）
  + `BasicAttack`（ATTACK）+ `AbilityLibrary`；单测 `test_ability_framework.gd`
  + 先发制人/吐纳仍走 `Unit.use_ability_*`（Phase 2.5 迁入 UTILITY 子类）

**Week 2 末 deliverable**：能力调度框架就绪，Phase 2.5 加能力时无需改战斗主流程。
**MVP 说明**：`Unit.attack_target()` → `BasicAttack.apply()`；职业技能 Ability 待 Phase 2.5。

---

## D. UI 升级 + 4v4 Demo（Week 3-4）⭐ MVP 重点

- [x] **D1** — BattleScene._spawn_units() 4v4（以 `jobs.json` 为准）：
  - 友方：跳荡 / 枪手 / 奇兵 / 斥候 各 1（`_create_unit_from_job`）
  - 敌方：杂兵 ×3 + 1 精英重甲（`plate_armor`，Body≈280）

- [x] **D2** — **单位面板 + 战斗预览**（期望伤害项搁置）：
  - [x] SidePanel：职业名 + Wisdom + 暴击率
  - [x] SidePanel：武器 base / weight / 渗透率（主模式）
  - [x] UnitTooltip：命中率 + 围攻加成（悬停敌人）
  - [—] 期望伤害分解（**用户搁置**，不做）

- [—] **D3** — **战斗日志 v2**（**暂缓**；当前折叠/展开 + 精简行已够用，不做详细公式 toggle）：
  ```
  （远期）多行 BBCode 公式展开 — 待试玩/仿真反馈后再排
  ```

- [x] **D4** — **TopBar 升级**（TopBar.gd）：
  - [x] 头像下职业缩写（文字 badge，像素 icon 后置）
  - [x] 气力档位色条（满 / 中 / 低 / 力竭）
  - [x] Wisdom 数值（TopBar 头像 tooltip + UnitTooltip 悬停卡 + 攻击预览暴击行）
  - [ ] 职业像素 icon（`generating-dot-assets`，后置）

- [x] **D5** — 验收策略（2026-06-12 更新）：**不单独手打 P0**；§305–327 体感项与 §0.4 数值门禁 **合并至 P1.5**（AI M0~M1 → `run_sim` 批量 → 遥测 + hypothesis 记录 → 再定是否改 JSON）

**Week 3 deliverable**：✅ 4v4 场景可开、战斗日志结构化输出。
**Week 4 deliverable**：✅ UI 升级（CombatMenu F 段 + D2/D4）完成；体感验收改 P1.5 仿真门禁。

---

## E. 行动调度重构（Week 1，与 A 并行）✅ 完成

> **背景**：design.md § 十二 已切到 AP + 回合制 + Init 排序 + 等待机制 + AP 不跨回合保留，旧 CT 累加调度已废弃。

- [x] **E1** — `TurnManager.gd` 改造：CT 累加 → 每回合按 `Stats.effective_initiative()` 排序的固定调度。
  * 删掉 `_ct: Dictionary` / `CT_THRESHOLD` / 仿真 tick 逻辑
  * 回合开始时一次性排出 `_turn_queue: Array[Unit]`，按队首推进
  * 回合定义回归"每个活着的单位行动 1 次"——快单位本回合不再多动一次
- [x] **E2** — 实装"等待"机制：`wait_current()` 第一次把当前单位挪到本回合 `_turn_queue` 末尾；第二次（已等待过）视为 `end_turn()`。
  * 不消耗 AP（`is_resumed_from_wait` 跳过 start_turn 重置）；**首次等待 +5 气力**（`TurnManager.WAIT_FATIGUE_COST`，抑制无意义拖延）
  * 每回合每单位仅可「延后顺序」1 次；第二次 Q = 结束回合
  * `can_wait()` 提供给 UI 判定（已等待过仍 true，tooltip 切换）；CombatMenu 绑定 `Sp` / `Q` 结束回合
- [x] **E3** — AP 不跨回合保留：每回合开始重置 `stats.ap = stats.max_ap`；end_turn 直接清零本回合剩余
- [x] **E4** — `get_turn_order_preview()` 简化：返回 `本回合剩余队列 + 下回合预览队列`，TopBar 同步刷新
- [x] **E5** — 兼容性扫描：`BattleAI.gd` / `Unit.gd` / `BattleScene.gd` 全部读队列状态而非 CT；`effective_initiative()` 保留作为排序依据
- [x] **E6** — 单元测试 `scripts/tools/test_turn_scheduler.gd`：22 项 PASS（队列排序 / 等待 / AP 重置 / Haste/Slow 影响顺序）

**E 阶段 deliverable**：✅ 旧 5v5 demo 在新调度下正常打完，TopBar 显示 Init 排序的本/下回合队列。

---

## G. 先发制人技能系统 + 行动条排序重构（Week 3）

> **核心设计**：增加通用高级技能"先发制人"，驱动气力在战斗排序中的影响权重，并重构行动条以支持 Init + Fatigue 联合排序、Hover 预演、以及最近 2 回合的可视化。

- [x] **G1** — `scripts/core/TurnScheduler.gd`（新文件，全局排序工具）：
  * `calculate_turn_order(units, include_fatigue_modifier)` — 按 Init + 气力比例排序
    - Init 差距 > 5 时直接按 Init 排（忽略气力）
    - Init 差距 ≤ 5 时，加权公式：`score = init + (fatigue_ratio × 5)`
    - 例：Init 相同但气力不同 → 气力充沛者优先
  * `generate_timeline_preview(units, current_round, rounds_to_show)` — 生成最近 N 回合的行动顺序预览（返回包含 round / order / unit / y_position 的字典数组）
  * `preview_with_preempt_bonus(units, activating_unit, bonus_initiative, rounds_to_show)` — 虚拟应用 +40 Init，显示激活单位的新顺序位置
  * 测试：至少 5 项单测覆盖 Init 大于/小于 5、气力比例影响、先发制人超车等场景 ✅ 5 项单测完成

- [x] **G2** — `scripts/core/Unit.gd` 补充方法：
  * `get_fatigue_ratio() -> float` — 返回气力百分比（0.0~1.0）
  * `use_ability_preempt() -> bool` — 技能执行：扣 1 AP + 20/32 气力，设置 `preempt_active = true` + `preempt_initiative_bonus = 40`
  * 新属性：`preempt_active: bool` / `preempt_initiative_bonus: int` / `is_wearing_heavy_armor() -> bool`（用于判断气力消耗 ×1.6）
  * `reset_turn_effects()` — 每回合开始时清除先发制人加值
  * `effective_initiative()` 改造：考虑临时加值 `+ (preempt_initiative_bonus if preempt_active else 0)`
  ✅ 实装完成，TurnScheduler 已集成 preempt_initiative_bonus 支持

- [x] **G3** — `scripts/ui/TopBar.gd` 滚动式无缝时间轴（实现优于原设计）：
  * 实现方案：本回合 + 下回合**合并为单行无缝长链**，用金黄色竖线分隔，比原"双行"设计更紧凑、更接近 Battle Brothers 风格
  * `set_current_unit(unit, round_num, round_0_order, round_1_order)` — 接收双回合队列 ✅
  * `_build_portrait_containers()` — 渲染合并的时间轴 + 金色分隔符 ✅
  * `_on_ability_preview_requested(ability_id, unit)` — 接收 CombatMenu 信号，调用 `TurnScheduler.preview_with_preempt_bonus()` 渲染下回合超车位置 ✅
  * `_on_ability_preview_cancelled()` — 恢复显示当前行动条 ✅
  * `_on_unit_hovered/unhovered` — 鼠标悬停某单位时，时间轴对应头像显示绿色↑箭头 + 边框高亮 ✅
  * 翻页按钮（>12 单位时出现）— 每次平移 3 格 ✅
  * 信号连接：CombatMenu.ability_preview_requested/cancelled + BattleScene.unit_hovered/unhovered ✅

- [x] **G4** — TopBar 内部 `PortraitItem` 类（替代独立 PortraitBubble.gd）：
  * `_init(u: Unit)` — 关联单位 + 自动生成头像 ✅
  * `show_arrow()/hide_arrow()` — 鼠标悬停时绿色↑箭头 + 边框高亮 ✅
  * `show_boost()` — 先发制人预览：绿色边框（+40 文字标签按设计极简化去掉了）✅
  * 设计调整：原"上升 Tween 动画 + +40 文字"被刻意去掉，保留干练的绿色边框 + ↑ 箭头

- [x] **G5** — `scripts/ui/CombatMenu.gd` 补充 Hover 信号：
  * 新增信号：`signal ability_preview_requested(ability_id: String, unit: Unit)`
  * 新增信号：`signal ability_preview_cancelled()`
  * 先发制人 chip（E 键）的 mouse_entered/exited 发出预览信号
  * 点击释放技能：调用 `current_unit.use_ability_preempt()`，成功后调用 `TopBar.refresh_timeline()` 并 `_end_current_turn()`；失败显示错误提示
  * ✅ 实装完成，先发制人 chip 已接入伤害系统，预览信号已在 BattleScene 中连接

- [x] **G6** — `scenes/ui/TopBar.tscn` 场景结构（采用单行滚动方案，原双行设计废弃）：
  * 实际实现：单行 HeaderPortraitContainer，本/下回合用金色 ColorRect 分隔符（4×48 px）
  * 翻页按钮（PageButton）支持 12 头像翻页，避免长队列挤压视觉
  * **作废**：原"Round0Container + Round1Container 双行 + HSeparator"方案——单行更接近 BB / DOS2 风格

- [x] **G7** — `design/class-system.md § 5.4` 补充 **先发制人** / **吐纳调息**（⭐ 已实装行 + E/T 键 + TopBar 预演说明）

**G 阶段 deliverable**（Week 3）：
- 行动条支持 Init + Fatigue 联合排序，气力充沛度影响同等 Init 的单位顺序
- Hover 先发制人能实时预览激活单位的新顺序（绿色特效标记）
- TopBar 显示 2 回合完整行动顺序，玩家能预测战场节奏
- 先发制人技能可正常释放，应用 +40 Init 加值，下回合生效后自动清除

---

## F. 战斗 UI（CombatMenu）（Week 2-3）⭐ 部分完成

> **背景**：UI 设计经过多轮迭代后从"5 大类菜单 + Hover 二级展开"切换到 **DOS2 风扁平化平铺**——所有动作直接展开为 chip，固定字母键 + 数字键直绑，无 hover 子菜单。详见 [`combat-ui.md`](combat-ui.md)。

- [x] **F1** — `scripts/ui/CombatMenu.gd`（PanelContainer，常驻 BattleScene 底部居中）：
  * 操作栏顺序：`[头像] | [P 详 / I 物 / Q 待] | [1~9 攻击/技能 chip]`
  * 头像左侧：`Unit.get_portrait_texture()` 自动同步当前单位
  * 字母键固定槽（不变位）：`P` 详情切换 / `I` 道具（Phase 3 占位）/ `Q` 等待
  * 数字键 1~9 直绑：动态从 `weapon.attack_modes` 展开（"斩/刺/砸/射"）+ 占位技能 chip
  * AP 不足时攻击 chip 自动灰化；`TurnManager.can_wait()` 控制 Q 可用（已等待过仍可用，文案切为结束回合）
  * Esc：详情打开时先关详情，否则不消费让 BattleScene 处理
- [x] **F5** — DOS2 风 HUD 数值条（操作栏上方独立 panel，与 chip 长度解耦）：
  * 三层中心对称结构：`[头甲|身甲]` 细条 → `[HP|气力]` 粗条 → `AP 钻石点`
  * 数值标签靠最左/最右（中心对称），无文字标签（hover 显示 tooltip）
  * AP 用 `◆`（满）/ `◇`（空）字符，每点 = 1 AP
  * HUD 与 chip 拆成两个独立 panel：HUD 宽度恒定居中，chip 宽度随技能数变化
- [x] **F6** — 详情面板（按 P 切换）：
  * 完整数据视图：HP / AP / 头甲 / 身甲 / 气力进度条 + 速度 + 武器 + 护甲细节
  * 与 HUD 数据冗余但不冲突（HUD 是常驻概览，详情是按需细查）
- [x] **F3** — 攻击模式与伤害管线对接（让 chip 真正影响伤害）：
  * BattleScene 加 `_pending_attack_mode: String` ✅ 完成
  * CombatMenu emit `attack_<mode>` → BattleScene 存 mode + 提示 ✅ 完成
  * `Unit.attack_target(target, mode)` 透传到 `DamageSystem.execute_attack(..., {"mode": mode})` ✅ 完成
  * 玩家未主动选 chip → 默认用 `weapon.attack_modes[0]` ✅ 完成
  * 双模式武器（剑 / 陌刀）选 chip 后伤害系数（armor_mult / hp_mult / base_pen）正确切换 ✅ 完成（DamageSystem 已支持）
- [x] **F4** — 行军置物架（`I` 键横向抽屉 + 羊皮纸 hover tooltip）：
  * 操作栏正上方滑出 6 格 chip（与攻/先/息同款 60×50）；`Unit.inventory` stub；选槽 → `item_<id>` 选目标（Phase 3 占位）
  * 数字键 **不**绑道具（与技能分轨，见 combat-ui.md §十）

> **作废**（旧设计已废弃）：
> ~~F2 Hover 自动展开 + 二级菜单~~ — 切到平铺式后不再需要

- [ ] **F7 / CI0** — **Character Inspect**（[`CharacterInspect.md`](CharacterInspect.md)）：
  * 我方回合 **双击**单位 → 全屏案牍（立绘 + 属性 + 装备只读 + 技能/Buff/道具占位）
  * **Esc** 回战场；hover `UnitTooltip` 不变
  * 道具区对接 `Unit.inventory` + `data/items.json`（Phase 3 CI2）；与 `I` 置物架快捷栏分轨

**F 阶段当前状态**：✅ F1–F6 完成；**F7 Character Inspect** 待排。

---

## 验收清单（并入 P1.5 数值仿真，2026-06-12）

> **D5 ✅**：下列体感项 **不单独手打 P0**；与 §0.4 一起在 **AI 重构后 `run_sim` 批量 + 遥测** 环节验收（记录 hypothesis，通过前禁止手调 JSON）。  
> 战斗日志 / UI 可读性项可在仿真回放或抽样手打中顺带确认。

**P1.5 仿真门禁**（原 P0 体感，合并验证）：

- [—] **跳荡体感**：跳荡 + 横刀/中甲，正面承伤命中率 → sim 命中率分布
- [—] **枪手长矛体感**：枪手 + 长矛，对中轻甲破甲/穿透 → sim 护甲伤害曲线
- [—] **奇兵机动体感**：奇兵 Init + 轻甲，绕侧/夹击 → sim 站位/夹击触发率
- [—] **斥候 Wisdom 体感**：斥候 vs 枪手暴击率差 → sim 暴击统计
- [—] **4v4 打完一场**：友 4 vs 敌 4，回合数 / 时长分布 → `run_sim` 汇总
- [—] **战斗日志可读**：命中/夹击/围攻/暴击标签（仿真抽样或日志导出检查）
- [x] **战斗预览**：悬停敌人显示命中率 + 围攻（不含期望伤害）
- [x] **TopBar**：Init 排序 + 职业缩写 + 气力档位 + 悬停智识/暴击
- [—] **Wisdom 暴击梯度**：斥候（Wis 50+）vs 枪手（Wis 20+）→ P1.5 sim 暴击率对比
- [x] **等待机制可用**：Q 第一次排到本回合队尾；已等待过再按 Q 结束回合（剩余 AP 作废）；`can_wait()` 两种状态均可用
- [x] **AP 不跨回合**：本回合剩余 AP > 0 时 end_turn，下回合开始 AP 重置 max_ap（不叠加）
- [x] **战斗菜单数字键直触**：1~9 单键即可触发对应攻击/技能 chip，无需鼠标
- [x] **战斗菜单字母键固定**：P=详情切换 / I=道具 / Q=等待，肌肉记忆位置不变
- [x] **HUD 数值条常驻**：HP / 头甲 / 身甲 / 气力 / AP 永远显示在屏幕底部居中，与 chip 长度解耦
- [x] **二级菜单数据正确**：~~（旧设计废弃）~~ → 改为：双模式武器（剑/陌刀）按 1/2 切换斩/刺时，伤害系数确实切换 ✅ 已在 test_attack_mode.gd 验证
- [—] **现有 Phase 1 战斗 demo 不被破坏**：旧场景启动 → P1.5 前 smoke 抽测

---

## 进度速览

| 阶段 | 任务数 | 已完成 | 进行中 | 待办 | 优先级 |
|---|---|---|---|---|---|
| A. DamageSystem 重构 | 4 | 4 | 0 | 0 | — |
| B. 4 职业数据 | 3 | 3 | 0 | 0 | — |
| C. Ability 框架 | 1 | 1 | 0 | 0 | — |
| D. UI + Demo | 5 | 4 | 0 | 1（D4 像素 icon 后置） | — |
| E. 行动调度重构 | 6 | 6 | 0 | 0 | — |
| F. 战斗 UI（CombatMenu） | 5 | 5 | 0 | 0 | — |
| G. 先发制人 + 行动条 | 7 | 7 | 0 | 0 | — |
| I. AI 战斗决策（P1.5） | 5 | 3 | 2 | 0 | **下一焦点：I3 门禁 + I4 统一评分** |
| H. 外显 + 士气 | 3 | 0 | 0 | 3 | P2.5 |
| J. CombatEffect 容器 | 6 | 0 | 0 | 6 | P2.5 |
| K. 经验/养成（Phase 3） | 5 | 0 | 0 | 5 | Phase 3 |
| **总计** | **49** | **33** | **1** | **15** | — |

**本期里程碑**：
- ✅ Week 1–2：DamageSystem + 调度 + CombatMenu + 4 职业
- ✅ Week 3：先发制人 + 行动条 + 音效/色板/夹击/朝向 polish
- ✅ **Phase 2 代码收尾**：D1–D4 + F1–F6 + C1 + E/G 全段；D5 体感 **并入 P1.5**
- 🚧 **P1.5（进行中）**：I0–I2 ✅ → **I3 门禁已接线**（镜像 sim FAIL 直至达标）→ 修 AI / 调 JSON

**剩余任务路径图**：

```
P0 MVP（可玩闭环）：✅ 已完成（代码 + UI）

P1 Phase 2 后置：
  D3 暂缓 · D4 像素 icon 后置 · C1 ✅ · G7 ✅

P1.5 平衡 + 体感验收（**进行中**，§0.4）：
  I0–I2 ✅（`logs/battle_sim_telemetry.json`）
  → I3 §十四 门禁达标 + hypothesis → 再动 JSON / 技能数值

P3 Phase 3 养成（AI + 2.5 之后）：
  J0~J4 EXP/JP 池 + 战斗结算 + 升级加点（economy-system.md）

P2 后置：
  TopBar 像素 icon · generating-dot-assets

P2.5 战斗表现 + 状态系统：
  H1 头顶外显 ∥ J0 容器骨架（M0）
  H3 状态飘字（Buff/Debuff 脚下上浮）∥ J1 施加时触发
  H2 士气设计 → J4 MoraleEffect（M3）
  J0 → J1 时效 debuff → J2 DoT → J3 性格钩子 / J5 Trait（远期）

P3 Phase 3 养成：
  K0 数据骨架 → K1 EXP/JP 分配 → K2 升级加点 → K3 JP/转职 → K4 战斗结算 UI
```

---

## I. AI 战斗决策重构（P1.5）— **下一焦点**

> **设计 SoT**：[`ai-system.md`](ai-system.md) v1.2 §5.1（统一决策评估）· §十三  
> **门禁**：§0.4 — **AI 仿真链路可用前禁止手调** `jobs.json` / `weapons.json`

- [x] **I0 — M0 骨架**（2026-06-12）：
  - `AIAgent` + `WorldView` + 独立 RNG；7 Behavior（含 Retreat/Advance/Disengage/Defend）
  - `AIAction` + `SimExecutor` / `SceneExecutor`；`data/ai_config.json`
  - `BattleScene` / `BattleSimHarness` 已接新 Agent；`BattleAI.gd` 过渡期并存
  - 行为修补：贴脸不脱战、Retreat 走完整路径、Engage 走+打、散兵门控、Wait 禁空等

- [x] **I1 — M1 倾向接入**（2026-06-12）：
  - `AIProfile`（archetype × disposition × 士气档 × 气力档）
  - `ArchetypeDB` + `DispositionDB`（autoload）；`FactionBrain` 阵营快照
  - spawn 设 `ai_archetype_id` / `ai_disposition_id`；`debug.log_decisions` 可开

- [x] **I2 — Harness 遥测**（2026-06-12）：
  - `Telemetry`：行为计数、交火率、站桩率、AP 利用、`kill_order`
  - `BattleSimHarness.aggregate()`；`battle_sim_scene` 打印 + `logs/battle_sim_telemetry.json`
  - 默认 12 局 CI；`SIM_GAMES=48` 扩批；§十四 指标 **WARN 基线**（达标门禁 → I3）
  - **24 局基线**（2026-06-12）：交火率 ~60%、站桩率 ~54%、均回合 ~25、友胜 23/24（阵容不对称）
  - ⏳ 镜像阵容 A/B、倾向对比（berserk vs cautious）→ I3

- [~] **I3 — P1.5 数值门禁**（2026-06-12 进行中）：
  - ✅ `data/sim_lineups.json` 镜像 4v4；`BattleSimHarness.run(lineup, enemy_disposition)`
  - ✅ `check_i3_gates()`（含 AP 利用率 ≥60%）/ `check_disposition_delta()`；`battle_sim_scene` 三套 sim + §十四 FAIL（`SIM_I3_STRICT=1`）
  - ✅ 输出 `logs/balance_hypothesis.md`（未达标项 + 禁止改 JSON 提醒）
  - ✅ **残 AP / OA 修补**（2026-06）：setup 门控、OA 三层（命中×冲击/己方甲/掉甲）、defer、Wait 恢复 margin、薄 Move→End；单测 T31–T38，**93 PASS**
  - ⏳ 镜像/§十四 **当前未达标**（基线 EXP-015：交火 73.7%、站桩 13.9%、中位回合 25.5）→ 先 I4 + sim 回归，达标后再动 JSON
  - ⏳ 验收清单体感项改 sim 断言（hypothesis 已占位）

- [ ] **I4 — 统一决策评估框架**（2026-06 规划，**非移形/换位特例**）：
  - 目标：Attack / Move / Wait / **任意 Ability** 同池比 **净效用**；技能选 id+target 由通用 `AbilityScorer.project()` 投影落点/state，读 `abilities.json` movement/effects
  - 共享：`oa_utility_penalty`、`best_ap_spend_utility`、机会成本；TELEPORT/SWAP 仅因「免 OA + 落点兑现」胜出，无残 AP 硬加分
  - 规划文件：`scripts/ai/scoring/action_scorer.gd`（见 `ai-system.md` §5.1）
  - 验收：移形/换位/推撞/嘲讽不需改 `behavior_ability.gd` 内 per-id 分支；新增 JSON 技能仅配 `ai_hint` + movement spec 即可入池；单测覆盖「包夹→技能」「换打→顶 OA Move」

- [ ] **I5 — 决策可观测 + 回归**：
  - `[AI]` 日志：`setup / oa / nd0→nd1 / ability_id`（`debug.log_decisions`）
  - `./tools/run_ai_experiment.sh` 镜像回归，追加 EXP-016+，对比 EXP-015

**I 段 deliverable**：原子 Action AI 替代 plan 式 `BattleAI`；`run_sim` 成为平衡 SoT；**I4** 后 Ability 与 Move 同标准竞争。

**依赖**：无（Phase 2 战斗核已齐）；**阻塞** Phase 2.5 能力数值与 JSON 手调。

---

## H. 单位外显 + 士气（Phase 2.5 起）— P2

> **设计基线**：[`status-effects.md`](status-effects.md)（Buff 8 / Debuff 14+气力三档 / 士气 **5 档** / 临时伤势）· `design.md` §十一  
> **状态/Buff 运行时架构**：见 [**J 段**](#j-combateffect-容器bb-skillcontainer-借鉴phase-25) + [`combat-effects-system.md`](combat-effects-system.md)

- [ ] **H1** — **头顶血条 + 甲量外显**（World Space，单位模型上方）：
  - HP 条（现有 `Unit._draw` 细条增强或拆为独立 `UnitOverheadBar` 节点）
  - 头甲 / 身甲条或合并甲条（薄条叠在 HP 下方；数值变化时 tween）
  - 仅可见单位显示（战争迷雾：未探索格隐藏或灰化）
  - 与底部 HUD / SidePanel 数据同源，不重复维护两套 Stats

- [ ] **H2** — **士气外显 + 士气系统设计**：
  - 设计 SoT：补齐 `Stats.morale_tier`（振奋 / 稳定 / 动摇 / **惊惧** / 崩溃）与 Resolve 检定流程（见 status-effects.md §三；防御修正为 **%**）
  - 触发器 MVP：友军死亡波及、HP&lt;25%、杀敌升级（至少 3 条可手打验证）
  - UI：头顶 icon 或色标 + CombatMenu/Tooltip 档位文字；与 H1 外显层共用挂载点
  - 战斗日志：士气变化一行 BBCode（`【动摇】张三 士气下降`）
  - **实现落点**：士气档位由 **J4 `MoraleEffect`** 写入容器 fold 链，不在 `DamageSystem` 散落 `if morale`

- [ ] **H3** — **状态飘字外显**（World Space，单位脚下向上飘）：
  - 触发：获得/刷新 **Buff**、**Debuff**（及可选：士气档位变化、DoT tick 轻提示）时，从单位脚点生成短文案并 tween 上移 + 淡出
  - 文案：`data/effects.json` / `status-effects.md` 显示名（例：`【眩晕】`、`【流血】`、`【振奋】`）；友方偏金绿、敌方 debuff 偏红紫（`CombatPalette`）
  - 表现：不挡点击（`mouse_filter` ignore）；同单位短时间同 ID 可合并或队列，避免满屏
  - **数据同源**：监听 `CombatEffectContainer.add` / `Unit.apply_effect_spec()`（**J1** 落地后接真数据）；可先 stub 一条验证动画
  - 与 H1 头顶条、J1 状态 icon **互补**（飘字 = 瞬间反馈，icon = 持续状态）

**H 阶段 deliverable**：战场上能一眼读到 HP/甲/士气档位；状态施加有脚下飘字反馈。

**依赖**：H1 与 H2 可并行；H2 → **J4**（士气进容器）；**H3** 与 **J1** 并行（动画可先 stub，效果名随 J1 接入）。

---

## J. CombatEffect 容器（BB SkillContainer 借鉴，Phase 2.5）

> **架构 SoT**：[`combat-effects-system.md`](combat-effects-system.md) v1.0  
> **原则**：多实例存储 + 有序 fold → `EffectiveCombatStats` 快照；性格**结算钩子**不进容器（[`personality-system.md`](personality-system.md) §2.2）。

- [ ] **J0 — M0 骨架**（可与 DamageSystem 小改并行，**不阻塞** Phase 2 MVP）：
  - `EffectiveCombatStats.gd` + `CombatEffectContainer.gd` + `DerivedEffects.gd`（气力档、手拙等无实例规则）
  - `Unit.get_effect_container()` / `get_effective_stats()`；`DamageSystem` 改读 fold 结果（与现 `CombatModifier` 数值一致）
  - `CombatModifier.gd` 标记 `@deprecated`，保留兼容转发
  - 单测 `scripts/tools/test_combat_effects.gd`：fold 顺序 / 气力档+手拙 parity / rebuild 重入

- [ ] **J1 — M1 时效 Debuff**：
  - `effects/CombatEffect.gd` 基类 + `TimedEffect.gd` + `EffectDB.gd` + `data/effects.json`
  - 首期 3 个：`disarmed` / `dazed`（眩晕 skip_turn）/ `slow`（迟缓 Init）
  - `Unit.get_status_for_ui()`；头顶或侧边 icon（最多 4 + `+N`）；施加时触发 **H3** 脚下飘字
  - 叠加规则：同 ID 非 stacking → `on_refresh`；`turns_remaining` 在 `notify_turn_ended` 递减

- [ ] **J2 — M2 DoT + 回合调度**：
  - `DotEffect.gd`（流血 / 燃烧 / 轻毒）；`on_turn_end_tick` 扣血
  - `BattleScene` / `TurnManager` 接 `effect_container.notify_turn_ended()` + 战斗开始/结束清理（`removed_after_battle`）
  - 单测：stacking 流血 ×2、战斗结束清临时 effect

- [ ] **J3 — M2.5 性格双轨**（与 [`personality-system.md`](personality-system.md) 验收并行）：
  - **结算钩子**仍走 `PersonalityDB.apply_combat_hooks()`（好色 / 贪财），**不**注册为 CombatEffect
  - 可选：`personalities.json` 的 `stat_mods` 走 `TraitEffect` 子类
  - 验收：sim 断言性格不进 AI 乘数链；钩子必有 BattleLog

- [ ] **J4 — M3 士气 + 临时伤势**（**依赖 H2**）：
  - `MoraleEffect.gd`：五档士气修正进 fold（命中 % / 防御 % / can_counter / can_oa）
  - `PermanentInjuryEffect.gd` 骨架 + `data/injuries.json` 占位（战斗内触发规则见 status-effects.md）
  - 情境 fold：`build_for_attack` / `build_for_defense` / `build_for_being_hit`（蓄力、破甲消耗型 passive 预留）

- [ ] **J5 — M4 天赋 + 被动**（Phase 3 前置，本期可只做接口）：
  - `TraitEffect.gd` + `PassiveEffect.gd`；`class-system.md` 被动注册进容器
  - 先发制人 / 吐纳等 `Unit` 字段待 **C1 Ability** 稳定后迁入 Effect（`on_turn_ended` 清除）

**J 阶段 deliverable**：Buff/Debuff/士气/伤势统一走容器；`DamageSystem` 只读快照；UI 状态栏与战斗修正同源。

**依赖**：J0 → J1 → J2；H2 → J4；J3 与 J1 可并行；J5 依赖 C1。

---

## Phase 2.5 占位（本期不做）

完成 v1.2 之后回到能力专题 + **J 段容器**（见上），不在本 Phase 2 周计划内：

```
▢ J0–J2  CombatEffect 容器 + 首批 debuff/DoT（combat-effects-system.md）
▢ H1–H3  头顶外显 + 士气 + **状态飘字**（Buff/Debuff 脚下上浮）；J4 MoraleEffect
▢ J3     性格钩子（好色/贪财，personality-system.md）
▢ 全力一击 / 瞄头 / 横扫千军
▢ **暗箭伤人**（步弓主动，`ignore_dodge`）+ **弓箭命中加成** JP/技能（`hit_bonus`；与 `bow_mastery`/鹰眼分轨）
▢ 穿心刺 + 疾风连击
▢ **借势合击**（通用 JP 被动：低 Melee + 友军围攻 → 命中抢救，§5.4.1）
▢ **持盾护卫**（§5.12 盾牌技：屏卫 / 荷盾，AP 4）
▢ **镇阵**（高级阵线技：−50% HP 伤 + 禁移 + 免疫位移，§5.3.1）
▢ **身法精通**（通用 JP 被动：位移技能 AP -1 + 气力 ×0.8，§5.4.3）
▢ **承锋纳气**（设想：受击回气，§5.4.2 — 未必实装）
▢ 双武器精通副手追击
▢ 碎甲 / 击晕
▢ 锐意 / 背刺 / 残忍 被动池（→ J5 PassiveEffect）
```

预估 3-4 周。**前置条件**：C1 Ability 框架必须先落地，否则每个能力都要改 `Unit.attack_target()`，4 个能力后失控；J0 可与 C1 并行。

---

## K. 经验/养成（Phase 3）

> **设计 SoT**：[`economy-system.md`](economy-system.md) §二（EXP/JP 固定池）· [`class-system.md`](class-system.md)（职业 / JP 技能）  
> **前置**：P1.5 AI 仿真 + Phase 2.5 能力框架稳定后再动数值；Phase 2 仅预留字段（`economy-system.md` §十）

- [ ] **K0 — 数据骨架**：
  - `Unit` / `Stats`：`exp`、`jp`、`level` 字段；`EconomyManager` autoload 占位
  - 关卡 `battle_exp_pool` / `battle_jp_pool`（固定池，不可 grind）
  - 验收：战斗结束可读写 exp/jp，不影响 Phase 2 战斗流程

- [ ] **K1 — EXP/JP 分配**：
  - 击杀 60% / 辅助 30% / 全队 10%（§2.4）；等级差惩罚与新兵加成
  - JP 按职业分轨积累（`class-system.md`）
  - 验收：单测 + 一场 4v4 结算账目与池总量守恒

- [ ] **K2 — 双模式升级成长**：
  - 战役选项：`growth_fixed`（职业表 + 天赋定向，**凹点对升级无效**）| `growth_random`（天赋加权随机 + FE 演出，**允许凹点**）
  - **待确定**：属性天赋是否学 BB **★～★★★** 等级（§4.5.2）；随机模式是否加「战斗显性保底」
  - UI：`LevelUpScene` 立绘 + 属性增量（两模式共用）
  - 验收：固定模式同级同角色可复现；随机模式 100 次 sim 天赋倾向可测 + 读档可 reroll

- [ ] **K3 — JP 与转职**：
  - 职业技能解锁 / Trait 消耗 JP；单角色一生 JP 上限 ~3000（§2.3）
  - 转职：**本职 + 池内武器专精 + 通用** 保留；旧艺与池外专精卸载；旧艺空载 UI 红色 `!`（§5.3.2）
  - 验收：JP 消耗后技能在战斗中可用（接 Ability 框架）

- [ ] **K4 — 战斗结算 UI**：
  - 战后羊皮纸：每人 EXP/JP 明细 + 池剩余
  - 与 Camp / 招募入口预留（Phase 4）

**K 段 deliverable**：固定池养成闭环；死亡归零 EXP/JP（§2.3）。

**依赖**：**I 段**（AI 仿真）→ Phase 2.5 能力 → **K0** 可并行预留字段。

---

## Phase 3 起步预告（远期）

完成 Phase 2 + Phase 2.5 + **K 段** 后进入：

```
▢ 角色背景 + 性别 + 属性天赋（1～3，★等级待定）+ Trait + **成长模式**（固定/随机）
▢ 19 职业全量铺开（当前 4 职业 → 19 职业）
▢ 武器/护甲词条系统
▢ 永久伤势（HP=0 → 重伤判定）
▢ 道士 / 僧兵 / 方士战兵 Wisdom 系职业能力
▢ Camp / 招募 / 工资（economy-system §三~五，Phase 4 深化）
▢ **NPC 培养**（花资源解锁能力 + 特色事件，`camp-meta-systems.md` §二）
▢ 据点建造（**可选 / 可能不做**，`camp-meta-systems.md` §三；优先合同改写据点状态）
```

预估 2-3 个月（K 段为核心首期）。

---

**文档版本**：v2.0
**创建时间**：2026-06-05（v1.0）/ … / 2026-06-12 F4 ✅ + D5 体感并入 P1.5（v1.9）/ 2026-06-12 新增 **I 段 AI P1.5** + **K 段经验养成**；CombatEffect 段改 **J**（v2.0）
**配套**：[`phase2-plan.md`](phase2-plan.md) v1.2 + [`combat-ui.md`](combat-ui.md) + [`status-effects.md`](status-effects.md) + [`combat-effects-system.md`](combat-effects-system.md) + [`ai-system.md`](ai-system.md) + [`economy-system.md`](economy-system.md)
**IDE Todo 同步**：I0–I5（AI）· H1–H3 · J0–J5 · K0–K4
