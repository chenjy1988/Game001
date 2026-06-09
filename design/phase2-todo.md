# Phase 2 Todo 清单（v1.2 聚焦版）

> **配套文档**：[`phase2-plan.md`](phase2-plan.md) v1.2
> **范围**：战斗系统重构 + 4 职业数据 + Ability 框架 + UI 升级（4 周）
> **不在本期**：具体职业能力（推到 Phase 2.5）
>
> **使用说明**：
> - 进行中的项标记 `[ ]` → `[~]`（in_progress）
> - 完成后改为 `[x]`
> - 同时同步 IDE Todo 面板（保持双向一致）

---

## A. DamageSystem 重构（Week 1）✅ 完成

- [x] **A1** — `WeaponData.gd` 加新字段（`damage_base: int` / `weight: int` / `attack_modes: Array[String]` / `head_chance` / `two_handed` / `block_value`），data/weapons.json schema 已对齐；旧字段（damage_min/max/armor_effectiveness/armor_penetration）deprecated 但保留 1 个版本
- [x] **A2** — `DamageSystem.gd` 按 weapon-system.md § 6.1 重写 9 步流程：
  1. 命中检定
  2. 部位判定（头 25% / 身 75%）
  3. 暴击 roll
  4. base × 气力档位 × 精通 × 词条 × DG
  5. 加法叠加（头部 +0.5 / 暴击 +0.5）
  6. 攻击类型分配（armor_mult + weight × 渗透）
  7. 渗透 HP = damage × 基础率 × weight_modifier（暴击翻倍）
  8. 隐藏气力消耗
- [x] **A3** — 暴击率公式落地：`5 + max(0, wisdom-40)*0.2`，软上限 50%
- [x] **A4** — 单元测试 `scripts/tools/test_damage_system.gd`：陌刀手 vs 重甲（Slash 普攻）/ 跳荡 + 长矛 vs 中甲（Pierce 普攻）期望与文档 § 6.4 对齐，27 项 PASS

**Week 1 deliverable**：✅ 单元测试跑通，公式与文档一致。

---

## B. 4 职业数据 + 武器专精（Week 2）

- [ ] **B1** — `scripts/core/data/JobClass.gd`（Resource）+ `data/jobs.json`：4 职业属性面板（HP/Init/Melee/Defense/Resolve/Wisdom/AP/Move/武器专精表）—— 跳荡 / 陌刀手 / 不良人 / 押衙亲兵
- [ ] **B2** — `JobDB.gd`（autoload）+ Unit.gd 接入 `job: JobClass` 字段，按职业 stats 范围 randomize 生成
- [ ] **B3** — 武器专精系数应用到 DamageSystem：伤害 × 系数（不擅 0.9 / 合格 1.0 / 擅长 1.10 / 精通 1.20）/ AP × 系数 / 精通暴击 +5

**Week 2 deliverable**：4 职业能正确生成 + 普攻数值因专精梯度而拉开差距。

---

## C. Ability 调度框架（Week 2 末）

- [ ] **C1** — `scripts/core/abilities/Ability.gd` 基类（Resource）：id / display_name / ap_cost / stamina_cost_extra / weapon_filter / mutex_group / `apply(attacker, target) -> AttackResult`
  + `BasicAttack`（普攻）实现，作为基类的第一个具体能力
  + 4 职业普攻全部走 Ability.apply() 路径，数据驱动

**Week 2 末 deliverable**：能力调度框架就绪，Phase 2.5 加能力时无需改战斗主流程。

---

## D. UI 升级 + 4v4 Demo（Week 3-4）⭐ 本期重点

- [ ] **D1** — BattleScene._spawn_units() 按 JobClass 生成 4v4：
  - 友方：4 职业各 1（跳荡 / 陌刀手 / 不良人 / 押衙亲兵）
  - 敌方：4 单位（杂兵 ×3 + 1 精英带重甲 Body 200）

- [ ] **D2** — **单位面板增强**（SidePanel.gd）：
  - 显示职业名 + 武器类型 + base damage / weight / 实际渗透值
  - 显示 Wisdom + 当前暴击率
  - **战斗预览面板**：鼠标悬停敌人时显示
    * 命中率（带 Overwhelm 修正）
    * 期望伤害分解（base × 气力档 × 精通 × 词条）
    * 期望 Body / HP 损失分配

- [ ] **D3** — **战斗日志 v2**（BBCode 多行结构化）：
  ```
  陌刀手挥出陌刀（Slash 模式）
    命中率 75%（roll 42）→ 命中身体
    base 75 × 1.20（精通）× 1.00（满气力）× 1.05（利刃）= 94.5
    armor_mult 1.0 → Body -94.5（破甲）
    渗透 0.10 × 2.67（weight 14）= 0.267 → HP -25.2
  ```
  - 默认精简版 + 可点开详细版（玩家可 toggle）

- [ ] **D4** — **TopBar 升级**（TopBar.gd）：
  - Initiative 排序预览显示职业 icon
  - 当前气力档位指示（满 / 中 / 低 / 力竭）
  - Wisdom 数值显示

- [ ] **D5** — 验收清单（见下文 § 验收）

**Week 3 deliverable**：4v4 战斗能正常打完一场，战斗日志结构化输出。
**Week 4 deliverable**：UI 升级完成，验收清单全绿，可对外展示。

---

## E. 行动调度重构（Week 1，与 A 并行）✅ 完成

> **背景**：design.md § 十二 已切到 AP + 回合制 + Init 排序 + 等待机制 + AP 不跨回合保留，旧 CT 累加调度已废弃。

- [x] **E1** — `TurnManager.gd` 改造：CT 累加 → 每回合按 `Stats.effective_initiative()` 排序的固定调度。
  * 删掉 `_ct: Dictionary` / `CT_THRESHOLD` / 仿真 tick 逻辑
  * 回合开始时一次性排出 `_turn_queue: Array[Unit]`，按队首推进
  * 回合定义回归"每个活着的单位行动 1 次"——快单位本回合不再多动一次
- [x] **E2** — 实装"等待"机制：`wait_current()` 把当前单位挪到本回合 `_turn_queue` 末尾。
  * 不消耗 AP（`is_resumed_from_wait` 跳过 start_turn 重置）
  * 每回合每单位限 1 次（`_waited_this_round: Dictionary`）
  * `can_wait()` 提供给 UI 判定；CombatMenu 绑定 `Q` 触发
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

- [ ] **G7** — 在 `design/class-system.md § 5.4 通用技能表` 中新增技能条目：
  ```
  | 先发制人 | 1 | 150 | 消耗当前气力 20（重甲 ×1.6 = 32）。下大回合 Initiative +40（仅排序）。Hover 时 TopBar 显示下回合预估顺位，确认释放后生效 |
  ```

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
  * AP 不足时攻击 chip 自动灰化；TurnManager.can_wait() 控制等待 chip 灰化
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
- [ ] **F4** — 道具 popup 占位（按 I 弹出 4~6 槽位）：
  * 当前 I 仅 emit `item_placeholder` log；改为弹出 popup（沿用之前删掉的子菜单逻辑）
  * 槽位先 stub 空数组（`Unit.inventory` 待 Phase 3 实装后接入）
  * 占用 ~80 行 popup 代码

> **作废**（旧设计已废弃）：
> ~~F2 Hover 自动展开 + 二级菜单~~ — 切到平铺式后不再需要

**F 阶段当前状态**：✅ F1/F3/F5/F6 完成；⏳ F4 等道具系统设计完善后实装。

---

## 验收清单（Week 4 末）

战斗 Demo 必须能复现以下场景，每项需在战斗日志 + UI 上可观察：

- [ ] **跳荡盾防体感**：跳荡 + 团牌（base_block 25）正面被攻击，hit_chance 显著降低（30-40%）
- [ ] **陌刀手 Slash 普攻人马俱碎**：陌刀 weight 14 → 渗透 0.267，普攻命中重甲 → Body -75 / HP -20
- [ ] **陌刀手 Pierce 普攻**：渗透 0.40，戳穿要害体感强
- [ ] **不良人高频体感**：双匕首 AP 3，9 AP 一回合 3 次普攻
- [ ] **押衙破甲快**：单手锤 Crush armor_mult 1.5，普攻 1 击 Body -50（vs 跳荡 -42）
- [ ] **战斗日志可读**：从 base 到 HP 的完整公式链路在日志中清晰呈现
- [ ] **战斗预览**：鼠标悬停敌人时显示命中率 + 期望伤害（基础值，不含 buff/debuff）
- [ ] **TopBar Initiative**：所有单位按 Init 排序，显示职业 icon + 气力档位
- [ ] **Wisdom 暴击梯度**：陌刀手 Wisdom 30（暴击 +0）vs 不良人 Wisdom 60（暴击 +4）数值反映正确
- [x] **等待机制可用**：选中单位按 Q 后挪到本回合队尾，行动顺序更新；每回合限 1 次，二次按下置灰
- [x] **AP 不跨回合**：本回合剩余 AP > 0 时 end_turn，下回合开始 AP 重置 max_ap（不叠加）
- [x] **战斗菜单数字键直触**：1~9 单键即可触发对应攻击/技能 chip，无需鼠标
- [x] **战斗菜单字母键固定**：P=详情切换 / I=道具 / Q=等待，肌肉记忆位置不变
- [x] **HUD 数值条常驻**：HP / 头甲 / 身甲 / 气力 / AP 永远显示在屏幕底部居中，与 chip 长度解耦
- [x] **二级菜单数据正确**：~~（旧设计废弃）~~ → 改为：双模式武器（剑/陌刀）按 1/2 切换斩/刺时，伤害系数确实切换 ✅ 已在 test_attack_mode.gd 验证
- [ ] **现有 Phase 1 战斗 demo 不被破坏**：旧 5 单位场景仍可启动（向后兼容）

---

## 进度速览

| 阶段 | 任务数 | 已完成 | 进行中 | 待办 |
|---|---|---|---|---|
| A. DamageSystem 重构 | 4 | 4 | 0 | 0 |
| B. 4 职业数据 | 3 | 0 | 0 | 3 |
| C. Ability 框架 | 1 | 0 | 0 | 1 |
| D. UI + Demo | 5 | 0 | 0 | 5 |
| E. 行动调度重构 | 6 | 6 | 0 | 0 |
| F. 战斗 UI（CombatMenu） | 5 | 5 | 0 | 0 |
| G. 先发制人 + 行动条 | 7 | 6 | 0 | 1（仅 G7 文档） |
| **总计** | **31** | **21** | **0** | **10** |

**本期里程碑**：
- ✅ Week 1：DamageSystem v3.1 + 行动调度（AP+回合制+等待）落地，49 项测试通过
- ✅ Week 2 部分：CombatMenu 完成（DOS2 风扁平化 + HUD 中心对称 + 攻击模式对接）
- 🚧 待办：4 职业 + Ability 框架 + 道具 popup + 4v4 demo

---

## Phase 2.5 占位（本期不做）

完成 v1.2 之后回到能力专题，不在本 todo 文档范围内：

```
▢ 全力一击 / 瞄头 / 横扫千军
▢ 穿心刺 + 疾风连击
▢ 双武器精通副手追击
▢ 碎甲 / 击晕
▢ 锐意 / 背刺 / 残忍 被动池
▢ 临时伤势触发系统
```

---

**文档版本**：v1.3
**创建时间**：2026-06-05（v1.0）/ 2026-06-06 加入 E 段行动调度重构（v1.1）/ 2026-06-06 加入 F 段战斗 UI（v1.2）/ 2026-06-06 A+E 完成 / F 部分完成 / F 切换为 DOS2 平铺设计（v1.3）
**配套**：[`phase2-plan.md`](phase2-plan.md) v1.2 + [`combat-ui.md`](combat-ui.md)
**IDE Todo 同步**：保持 24 项一致
