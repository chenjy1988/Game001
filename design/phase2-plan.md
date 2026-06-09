# Phase 2 推进 Plan：战斗系统 × UI（v1.2 聚焦版）

> **目标**：把武器系统新公式（armor_mult + weight × 渗透）落地到战斗代码层，并做出**4 职业普攻可玩 + 战斗信息清晰呈现**的 Demo。
>
> **本期不做**：具体职业能力（疾风连击 / 全力一击 / 碎甲 / 击晕 / 双武器精通 / 锐意 / 残忍 / 伤势）—— 这些放到 **Phase 2.5（能力专题）** 单独推进，避免战斗系统底盘还没稳就先做花活。

---

## 一、本期范围（v1.2 聚焦）

```
✅ 战斗系统重构（DamageSystem 新公式 + 暴击 + Wisdom）
✅ 4 职业属性面板 + 武器专精系数（数据驱动）
✅ Ability 基类 + 普攻实现（为能力扩展留接口）
✅ 4v4 战斗 Demo 场景
✅ UI 升级：单位面板 / 战斗日志 / TopBar 重做
✅ 验收：4 职业普攻体感差异化 + 数值可读
```

**明确推迟**（Phase 2.5 再做）：

```
❌ 全力一击 / 瞄头 / 穿心刺 / 疾风连击
❌ 碎甲 / 击晕 / 横扫千军
❌ 双武器精通副手追击
❌ 锐意 / 背刺 / 残忍 被动
❌ 伤势触发系统
```

理由：战斗系统底盘（DamageSystem 新公式 + 4 职业差异化普攻）必须先稳定，否则后续能力堆叠会基于错误的基线。

---

## 二、设计文档基线（已落地）

- [`weapon-system.md`](weapon-system.md) v3.1：攻击类型 + weight × 渗透公式 + 疾风连击 + 双武器精通规则
- [`class-system.md`](class-system.md) v1.3：19 职业 + Wisdom→暴击 + 锐意/残忍/疾风连击
- [`status-effects.md`](status-effects.md)：伤势触发新规则（≥10% HP + HP 状态修正 + cap 75%）
- [`../data/weapons.json`](../data/weapons.json) v3.1：15 件武器 weight 校准完成

## 三、代码层基线（Phase 1 已落地）

- `Stats.gd`（含 wisdom + dodge/block 公式）
- `DamageSystem.gd`（**旧 v3 公式**：9 格 HP 渗透表 + armor_effectiveness/armor_penetration，**与新版严重脱节，必须重构**）
- `WeaponData.gd`（**旧字段**：damage_min/max + armor_effectiveness + armor_penetration，**需替换**为 damage_base + weight + attack_modes）
- `BattleScene.gd`（5 单位 demo 已跑通：2 友 vs 3 敌）
- `TurnManager.gd`（**旧 CT 累加调度，与新设计冲突**：design.md § 十二 已切到 AP + 回合制 + Init 排序 + 等待机制，待 Phase 2 重构）
- 职业系统 / 能力系统 / 被动系统：**完全不存在**

---

## 四、4 大支柱（v1.2 重新组织）

| 支柱 | 内容 | 工作量 | 优先级 |
|---|---|---|---|
| **A. DamageSystem 重构** | 旧公式 → 新公式（armor_mult / weight × 渗透 / 暴击率含 wisdom）| 中 | **P0** |
| **B. 4 个 Demo 职业数据落地** | JobClass 资源 + 4 职业属性面板 + 武器专精系数 | 中 | **P0** |
| **C. Ability 调度框架** | Ability 基类 + BasicAttack（普攻）实现，为后续能力扩展留接口 | 小 | **P0** |
| **D. UI 升级 + 4v4 Demo** | 战斗场景 + 单位面板 + 战斗日志 + TopBar | **大** | **P0** |

→ 与 v1.1 相比：**C 大幅瘦身**（从 7 个能力降到 1 个普攻 + 接口），**D 显著升级**（UI 是本期重点）。

---

## 五、4 个 Demo 职业（不变）

按"覆盖面 × 差异化"挑选：

| # | 职业 | 武器 | 本期能用的攻击 | Phase 2.5 待加能力 |
|---|---|---|---|---|
| 1 | **跳荡** | 横刀 + 团牌 | 普攻 | 瞄头 / 突击冲锋 |
| 2 | **陌刀手** | 陌刀（双模式 Slash/Pierce）| 普攻（含模式切换）| 全力一击 / 横扫千军 |
| 3 | **不良人** | 双匕首 | 普攻（主手单击，无副手追击）| 穿心刺 / 疾风连击 / 锐意 / 残忍 / 双武器精通 |
| 4 | **押衙亲兵** | 单手战锤 + 团牌 | 普攻 | 碎甲 / 击晕 |

→ **本期 4 职业的差异化体感来源**：
- 跳荡：高 block 25（团牌）+ 中等 base 42（横刀）→ 防御反击型
- 陌刀手：低 block 15 + 高 base 75（陌刀）+ 渗透 0.267~0.40 → 单击爆发
- 不良人：极低 block 6 + 双匕首 base 28×2 + AP 3 高频 → 高频小击数
- 押衙亲兵：盾 25 + 单手锤 base 32 + Crush armor_mult 1.5 → 破甲快

→ 普攻就能体现"4 流派各不相同"，不需要专属能力支撑。

---

## 六、详细任务拆解（13 项 todo）

### A. DamageSystem 重构（P0，Week 1）

| Todo | 子任务 | 估时 |
|---|---|---|
| **A1** | WeaponData.gd 加新字段：`damage_base: int` / `weight: int` / `attack_modes: Array[Dictionary]`（每个 mode 含 type/armor_mult/hp_mult/base_pen/hit_modifier）。旧字段 deprecated 但保留 | 0.5 天 |
| **A2** | DamageSystem.calculate_damage() 按 weapon-system.md § 6.1 完整重写 9 步流程：<br/>1. 命中检定<br/>2. 部位判定（头 25% / 身 75%）<br/>3. 暴击 roll<br/>4. base × 气力档位 × 精通 × 词条 × DG<br/>5. 加法叠加（头部 +0.5 / 暴击 +0.5）<br/>6. 攻击类型分配（armor_mult + weight × 渗透）<br/>7. 渗透 HP = damage × 基础率 × weight_modifier（暴击翻倍）<br/>8. 隐藏气力消耗 | 1.5 天 |
| **A3** | 暴击率公式落地：`5 + 武器 + 精通 + max(0, wisdom-40)*0.2`，软上限 50% | 0.5 天 |
| **A4** | 单元测试：陌刀手 vs 重甲（Pierce 全力+头+暴击 一击斩 → 但本期没全力一击，先跑普攻）/ 跳荡 vs 中甲（普攻基线）期望与文档 § 6.4 对齐 | 1 天 |

**Week 1 deliverable**：单元测试跑通陌刀普攻 / 不良人普攻 / 跳荡普攻 / 押衙普攻数值正确。

### B. 4 职业数据 + 武器专精（P0，Week 2）

| Todo | 子任务 | 估时 |
|---|---|---|
| **B1** | `scripts/core/data/JobClass.gd`（Resource）+ `data/jobs.json`：4 职业属性面板（HP/Init/Melee/Defense/Resolve/Wisdom/AP/Move/武器专精表）| 1 天 |
| **B2** | `JobDB.gd`（autoload）+ Unit.gd 接入 `job: JobClass` 字段，按职业 stats 范围 randomize | 0.5 天 |
| **B3** | 武器专精系数应用到 DamageSystem：伤害 × 系数（不擅 0.9 / 合格 1.0 / 擅长 1.10 / 精通 1.20）/ AP × 系数 / 精通暴击 +5 | 0.5 天 |

**Week 2 deliverable**：4 职业能正确生成 + 普攻数值因专精梯度而拉开差距。

### C. Ability 调度框架（P0，Week 2 末）

| Todo | 子任务 | 估时 |
|---|---|---|
| **C1** | `scripts/core/abilities/Ability.gd` 基类（Resource）：id / display_name / ap_cost / stamina_cost_extra / weapon_filter / mutex_group / `apply(attacker, target) -> AttackResult`<br/>+ `BasicAttack`（普攻）实现，作为基类的第一个具体能力 | 1 天 |

**为什么留 C1**：让"普攻"也走能力系统的调度，未来加能力时只需 `_register_ability(new_ability)`，不需要重写战斗主流程。

**Week 2 末 deliverable**：4 职业普攻全部走 Ability.apply() 路径，数据驱动。

### D. UI 升级 + 4v4 Demo（P0，Week 3-4）⭐

这是本期重点，原 v1.1 计划这只是 1 周的事，v1.2 升级为 2 周。

| Todo | 子任务 | 估时 |
|---|---|---|
| **D1** | BattleScene._spawn_units() 按 JobClass 生成 4v4：友方 4 职业各 1 / 敌方 4 单位（杂兵 ×3 + 1 精英带重甲 Body 200）| 0.5 天 |
| **D2** | **单位面板增强**：显示职业名 + 武器类型 + base damage / weight / 实际渗透 + Wisdom / 暴击率 + **战斗预览面板**（鼠标悬停敌人时显示：命中率 / 期望伤害分解 base × 气力档 × 精通 × 词条）| 2 天 |
| **D3** | **战斗日志 v2**：BBCode 多行结构化日志，呈现伤害公式各环节<br/>例：<br/>`陌刀手挥出陌刀（Slash 模式）`<br/>`命中率 75%（roll 42）→ 命中身体`<br/>`base 75 × 1.20（精通）× 1.00（满气力）× 1.05（利刃）= 94.5`<br/>`armor_mult 1.0 → Body -94.5（破甲）`<br/>`渗透 0.10 × 2.67（weight 14）= 0.267 → HP -25.2` | 2 天 |
| **D4** | **TopBar 升级**：Initiative 排序预览显示职业 icon + 当前气力档位（满/中/低/力竭）+ Wisdom 数值 | 1 天 |
| **D5** | 验收：4 职业普攻在 demo 中体感差异化清晰 + 战斗日志可读性达标 | 0.5 天 |

**Week 3 deliverable**：4v4 战斗能正常打完一场，战斗日志结构化输出。
**Week 4 deliverable**：UI 升级完成，验收清单全绿，可对外展示。

---

## 七、推进顺序（4 周）

```
Week 1：A1 + A2 + A3 + A4（DamageSystem 重构 + 单元测试）
Week 2：B1 + B2 + B3 + C1（4 职业数据 + Ability 框架 + 普攻）
Week 3：D1 + D2 + D3（4v4 spawn + 单位面板 + 战斗日志 v2）
Week 4：D4 + D5（TopBar 升级 + 验收）
```

**v1.1 → v1.2 节奏对比**：

| 阶段 | v1.1 | v1.2 |
|---|---|---|
| 周数 | 5 周 | **4 周**（瘦身） |
| 战斗系统 | Week 1（5 子任务） | Week 1（4 子任务） |
| 职业数据 | Week 2（5 子任务） | Week 2（3 子任务） |
| 职业能力 | **Week 3-4（13 子任务）** | **Week 2 末 1 子任务**（仅 BasicAttack）|
| UI | Week 5（5 子任务） | **Week 3-4（5 子任务，重点）** |

→ 本期把"能力实现"省下来的工时全部投入到**UI 和数值可读性**上，让玩家在 demo 中**看懂战斗发生了什么**。

---

## 八、风险 & 依赖

| 风险 | 影响 | 缓解 |
|---|---|---|
| **DamageSystem 重构破坏现有 Demo** | 大 | 保留旧 calculate_damage 为 fallback；新公式走 calculate_damage_v2，新旧并行 1-2 周 |
| **WeaponData 字段迁移破坏 weapons.json** | 大 | data/weapons.json 已是新 schema，但代码侧需适配；旧字段 deprecated 保留 1 版 |
| **职业属性面板调整** | 中 | 在 B1 落地前先确认 class-system.md § 4.1 数值是否要调整 |
| **战斗日志信息过载** | 中 | D3 落地时分两层：默认精简版 + 可点开详细版（玩家可 toggle） |
| **没有专属能力，4 职业差异化是否够？** | 中 | 关键是数值差异化（base / weight / block / 暴击），不是机制差异化。普攻就能拉开差距，验收时观察体感 |

---

## 九、验收清单（Week 4 末）

战斗 Demo 必须能复现以下场景，每项需在战斗日志 + UI 上可观察：

- [ ] **跳荡盾防体感**：跳荡 + 团牌（base_block 25）正面被攻击，hit_chance 显著降低（30-40%）
- [ ] **陌刀手 Slash 普攻人马俱碎**：陌刀 weight 14 → 渗透 0.267，普攻命中重甲 → Body -75 / HP -20
- [ ] **陌刀手 Pierce 普攻**：渗透 0.40，戳穿要害体感强
- [ ] **不良人高频体感**：双匕首 AP 3，9 AP 一回合 3 次普攻，命中 3 次有 1 次暴击的概率高
- [ ] **押衙破甲快**：单手锤 Crush armor_mult 1.5，普攻 1 击 Body -50（vs 跳荡 -42）
- [ ] **战斗日志可读**：从 base 到 HP 的完整公式链路在日志中清晰呈现
- [ ] **战斗预览**：鼠标悬停敌人时显示命中率 + 期望伤害（基础值，不含 buff/debuff）
- [ ] **TopBar Initiative**：所有单位按 Init 排序，显示职业 icon + 气力档位
- [ ] **Wisdom 暴击梯度**：陌刀手 Wisdom 30（暴击+0）vs 不良人 Wisdom 60（暴击+4）数值反映正确
- [ ] **现有 Phase 1 战斗 demo 不被破坏**：旧 5 单位场景仍可启动（向后兼容）

---

## 十、Phase 2.5 待办（本期不做，下一阶段）

完成 v1.2 之后，回到能力专题：

```
Phase 2.5 - 职业能力专题（约 3-4 周）：
  ▢ 全力一击（陌刀 / 双手战锤 / 双手战斧）
  ▢ 瞄头 / 横扫千军
  ▢ 穿心刺 + 疾风连击（不良人）
  ▢ 双武器精通副手追击
  ▢ 碎甲 / 击晕（押衙亲兵）
  ▢ 锐意 / 背刺 / 残忍 被动池
  ▢ 临时伤势触发系统
  ▢ 互斥规则 / 隐藏气力消耗
```

完成 Phase 2.5 后再进入 Phase 3（角色养成）。

---

## 十一、跨文档影响检查

落地中如发现以下情况需要更新设计文档：

| 场景 | 更新文档 |
|---|---|
| Stats.gd 字段名变化 | class-system.md § 4.1 |
| DamageSystem 新公式与文档不一致 | weapon-system.md § 6.1 |
| 职业属性面板调整 | class-system.md § 4.1 |
| 武器数值平衡调整 | data/weapons.json + weapon-system.md § 5 |

---

## 十二、Phase 2 (v1.2) 完成的成功标志

1. ✅ DamageSystem 用新公式（armor_mult + weight × 渗透）跑通
2. ✅ 4 职业普攻在 demo 中**手感明显不同**（盾兵 / 双手 / 高频 / 破甲控）
3. ✅ 战斗日志能让玩家**看懂"为什么这一击造成这么多伤害"**
4. ✅ 单位面板 + TopBar UI 信息密度高但可读
5. ✅ Ability 框架已搭好接口，Phase 2.5 加能力时不需要改战斗主流程
6. ✅ 现有 Phase 1 战斗 demo 不被破坏

---

**文档版本**：v1.2（聚焦版）
**前一版**：v1.1（含 7 个能力 + 3 个被动 + 伤势）
**变更说明**：剔除"具体能力实现"，聚焦战斗系统底盘 + UI；从 5 周压缩到 4 周
**更新时间**：2026-06-05
**关联 IDE Todo**：A1-A4 / B1-B3 / C1 / D1-D5，共 13 项
