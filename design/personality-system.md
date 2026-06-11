# 性格与战法倾向 v2.0

> **v2.0 核心决策**：**性格不驱动 AI 选招**（避免玩家把「AI 弱智」和「人设」混在一起）；**敌我共用同一套战术 AI**（`ai-system.md`）。性格主战场是 **战斗结算钩子**（攻击后 / 击杀后）+ 营地事件 + 经济——有日志、有音效，怪得可解释。
>
> | 轨道 | 对象 | 字段 | 改什么 |
> |---|---|---|---|
> | **战术 AI** | 敌我 **共用** | `archetype` + `disposition_id` | **只**影响移动/攻击/等待选型（`ai-system.md`） |
> | **性格** | 有 `personality_id` 的单位（主为我方雇佣兵；敌方精英可挂） | `personality_id` | **结算钩子** + 事件 + 经济；**默认不改 AI** |
>
> **与天赋 / 背景区分**：性格≠天赋；性格≠背景（`camp-events-system.md`）。
>
> AI 架构见 `ai-system.md`（BB 式 Behavior + 加权随机，与性格解耦）。

---

## 一、术语与边界

| 概念 | 适用 | 数量 | 战外 | 示例 |
|---|---|---|---|---|
| **性格**（本文 §三） | 主为 **我方雇佣兵**；敌方名将可挂 | 1 人 1 个 | ✅ **结算钩子**、事件、经济、好感 | 贪财、好色 |
| **战法倾向**（本文 §四） | **敌我 AI 均可挂**（敌军默认有，友军托管同引擎） | 1 单位 1 个 | ✅ **仅战术 AI** | 狂战、固守、集火 |
| **天赋 Trait** | 双方可有，独立系统 | 0～N（Phase 3） | 部分有 | 身法、矮小、双武器精通（`design.md` §四） |
| **背景 Background** | 仅我方招募 | 1 人 1 个 | ✅ **事件池**、剧情、属性偏置 | 沙陀血统、募兵出身（`camp-events-system.md` §二） |

敌方杂兵 **默认无性格**（只有 `disposition_id`）；名将/Boss 可额外挂 `personality_id` 以触发对称结算钩子。

---

## 二、设计原则（v2.0）

1. **AI 与性格解耦**——战术 AI（敌我同一套）只读 `archetype` + `disposition`；**性格不进 `behavior_mult`**（v2 默认）。玩家觉得「该打不打」= 查 AI 质量，不是查性格表。
2. **性格 = 结算惊喜**——攻击后 / 击杀后钩子；**敌我对称**（带 `personality_id` 的单位都触发）；**BattleLog 必写** + 关键性格配 **音效**（贪财阴险低笑）。
3. **手控不拦指令**——玩家点的攻击照常结算；性格代价在结算层兑现（好色掉士气、贪财改掉落）。
4. **一单位一性格 + 一战法倾向**——`personality_id` 与 `disposition_id` **可并存**（友军：贪财性格 + 寻常战法；敌军：无性格 + 狂战战法）。
5. **有代价**——贪财多掉战利品但可能损队友好感；好色打异性可能自乱阵脚。

### 2.1 为什么不让性格改 AI

| 若性格改 AI 选型 | 玩家感受 |
|---|---|
| 好色拒打异性 | 「这 AI 怎么不打女匪？」→ 以为是 bug |
| 贪财先去捡 | 「怎么不集火？」→ 和加权随机的「次优招」叠在一起，无法归因 |
| 敌我同一套 AI + 性格各搞一套 | 敌方也被骂弱智，且原因说不清 |

**解法**：AI 只负责「像会打仗的兵」；性格在 **刀砍下去之后** 才显现——玩家看到日志就知道是人设。

### 2.2 战斗结算钩子（PersonalityCombatHooks）

挂载点（`DamageSystem` / `BattleScene` 伤害与死亡管线，**与 AI 无关**）：

```
on_damage_dealt(attacker, target, result)   # 好色等
on_unit_killed(killer, victim, loot_ctx)    # 贪财等
```

| 钩子 | 谁触发 | 日志 | 音效 |
|---|---|---|---|
| 结算钩子 | 攻击者/击杀者 **有** `personality_id` | **必须** `【性格·xxx】` 一行 | 按性格表（贪财触发时） |
| 战术 AI | 所有单位（`disposition`） | 仅 debug / sim log | 无 |

**友军手控**：指令照常；钩子仍在结算时跑（与 AI 托管、敌方攻击对称）。

#### 2.2.1 好色 `lustful`（攻击后）

```
触发：攻击者 lustful + 目标异性 + 武器伤害 HP > 0
判定：50% 概率（独立 roll，与 AI RNG 分离）
效果：攻击者 morale -1 档；每攻击者每回合限 1 次
敌我：对称（女匪首好色打男佣兵，同样可能掉士气）
```

- **预演**（可选）：悬停异性时 UnitTooltip 一行「〔性格·好色〕命中异性后可能自乱士气」——**不**改 AI 目标选择。
- **日志（必须）**：

```text
【性格·好色】王五 对 红拂 不忍下手，士气 稳定→动摇
```

- **实现**：`PersonalityDB.on_damage_dealt()`；不调 `TargetScore`。

#### 2.2.2 贪财 `greedy`（击杀后）

```
触发：击杀者 greedy +  victim 死亡本次由该单位造成
判定：70% 触发「私藏」roll
效果：该次掉落 数量 ×1.25~×1.5，或额外 +1 小袋金钱（不额外占格则并入堆）
代价：同场友军好感 -2（周上限）；敌方贪财不影响玩家好感
反馈：触发时播放阴险低沉笑声（`CombatAudio`）；BattleLog：
  【性格·贪财】王五顺手揣走些许战利品（本场掉落 +30%）
```

- **不做**：`Loot` Behavior、结束回合捡钱弹窗、AI 脱线拾取——开发量大且像 AI 弱智。
- **战外**：俘虏 AP-1 等仍见 `economy-system.md` §4.5。

#### 2.2.3 其余 26 性格（路线图）

| 阶段 | 策略 |
|---|---|
| Phase 2.5 | 先落地 **好色 + 贪财** 两个钩子 |
| Phase 3+ | 优先改 **结算/战后**（残忍→俘虏率、嗜血→击杀回血 flavour）；仅少数保留 **极轻 AI 偏置**（≤10% 乘数，且必须打日志） |
| 不做 | 性格导致拒打、弃目标、随机不执行玩家指令 |

### 2.3 玩家可感知性（验收）

- [ ] 性格 **不进** AI 决策日志的乘数链（sim 可断言）
- [ ] 每次钩子触发 **必有** BattleLog `【性格·xxx】`
- [ ] 贪财触发 **必有** 阴险笑声（可设置关闭）
- [ ] 名册 / P 面板显示性格 + 一行「战斗影响：…」（如「击杀后可能私藏战利品」）

---

## 三、我方性格（雇佣兵）

### 3.0 总则

- 招募 / 随机生成时确定，战斗中不可切换（极稀有剧情事件除外，Phase 5）。
- 每人 **恰好 1 个**；不考虑多性格冲突。
- 影响：**战斗结算钩子**（§2.2）、经济/俘虏、营地事件选项（`camp-events-system.md`）；**默认不影响战术 AI**。

### 3.1～3.4 性格一览表

以下 **28 个** 为友军 v1 完整池；招募时按权重随机 1 个（出身可偏置，见 §七.1）。

图例：**钩子**=结算钩子（v2 主路径）；**Meta**=战外；**AI×**=仅 Phase 4+ 可选轻偏置（默认关）。

#### 3.1 缺陷与欲望（玩家最初关注的四类）

| ID | 名称 | 战斗表现（v2） | 钩子 / 战外 |
|---|---|---|---|
| `greedy` | 贪财 | 击杀后可能私藏战利品；阴险笑声 | **击杀钩子** §2.2.2；战外俘虏 AP-1 |
| `cowardly` | 胆小 | Phase 3：受重击后概率额外 -1 士气 | 钩子待做；**不进 AI** |
| `arrogant` | 自大 | Phase 3：被低等级反杀时羞耻 flavour | 钩子待做 |
| `lustful` | 好色 | 命中异性 50% 自掉士气 | **攻击钩子** §2.2.1；敌我对称 |

#### 3.2 战斗倾向

> Phase 3+ 逐步从「AI 乘数」迁到「结算钩子」；下表 **AI 列** 为旧案，v2 **默认不实现**。

| ID | 名称 | v2 方向（钩子优先） |
|---|---|---|
| `bloodthirsty` | 嗜血 | 击杀后小概率回复 1~3 HP + 日志 |
| `calm` | 冷静 | 受惊惧类技能时 Resolve +10% |
| `reckless` | 鲁莽 | 暴击后自身防御 -5% 1 回合（代价） |
| `sparing` | 惜命 | HP&lt;40% 受击后额外士气检定 |
| `protective` | 护短 | 邻格友军阵亡时自身士气 -1 + 日志 |
| `vengeful` | 睚眦 | 被某敌人打伤后，下次对其伤害 +10%（1 次） |
| `conformist` | 从众 | Meta / 营地 |
| `lone_wolf` | 独狼 | 单独与目标相邻时命中 +5% |
| `disciplined` | 守序 | 架枪类技能效果 +10% |
| `impatient` | 急躁 | 回合末剩余 AP≥3 时小概率掉士气 |
| `stubborn` | 执拗 | 对同一目标连续命中第 3 次起伤害 +5% |
| `suspicious` | 多疑 | 首回合受击前防御 +5% |
| `valorous` | 崇勇 | 振奋档延长 1 回合（战后衰减） |

#### 3.3 道德与边军叙事

| ID | 名称 | v2 方向 |
|---|---|---|
| `loyal` | 忠义 | 友军阵亡目击士气检定 +15% 通过 |
| `callous` | 凉薄 | 友军阵亡无士气惩罚（战外好感↓） |
| `snobbish` | 势利 | 营地 / 好感 |
| `cruel` | 残忍 | 击杀流血目标额外掉血 flavour；战外俘虏率↓ |
| `merciful` | 悲悯 | 击杀濒死敌人不掉好感 |
| `cunning` | 狡诈 | 侧背攻击伤害 +5% |
| `vain` | 虚荣 | 击杀高等级敌人额外 +好感 |
| `superstitious` | 迷信 | 对 `undead` 标签受击士气检定更难 |
| `drunkard` | 酒性 | 回合 1–3 命中 +5%；回合 ≥6 命中 -5% |
| `homesick` | 恋乡 | 营地事件为主 |

#### 3.4 体质与怪癖

| ID | 名称 | v2 方向 |
|---|---|---|
| `shaky` | 手抖 | 命中 &lt;50% 时暴击率 -50% |
| `fastidious` | 洁癖 | 经过尸体格受击防御 -5%（1 回合） |
| `attached` | 恋物 | 换武器后首回合命中 -10% |
| `hippophobic` | 惧马 | 邻格骑兵攻击时额外士气检定 |
| `arrow_shy` | 惧弓 | 被远程命中后下回合防御 +5% |
| `glory_hound` | 贪功 | 抢最后一刀击杀时 +好感 |
| `battle_drunk` | 恋战 | HP&lt;25% 时士气下降检定 +20% 通过 |

---

## 四、战法倾向（Disposition）— 唯一驱动战术 AI 的人设层

### 5.0 总则

- **不是「性格」**：无贪财、好色、恋乡等叙事缺陷；只表达 **这支兵在战场上怎么打**。
- **只走 AI 通道**：战法倾向 **直接** 影响战术 AI（`ai-system.md`）；与 **性格结算钩子** 完全分离。
- 来源：**关卡配置 > 兵种模板 > 派系默认**（见 5.2）；Boss / 精英可写死 `disposition_id` 覆盖。
- 玩家可见：单位 Tooltip 显示「战法：狂战」等（可选隐藏杂兵，仅精英/Boss 显示）。
- 与 BB 对照：接近 `bandit_melee_agent` / `orc_warrior_agent` 的 **Properties 差**，但粒度为 **单位/编制** 而非整类 Agent 脚本。

### 5.1 战法倾向一览（v1，12 个）

| ID | 名称 | 战术摘要 | AI 要点 |
|---|---|---|---|
| `default` | 寻常 | 均衡，接近当前 `BattleAI` | 无额外乘数（基线） |
| `berserk` | 狂战 | 猛冲、轻视 OA | Eng×1.3，OA 惩罚×0.3，Wait×0.1 |
| `cautious` | 谨慎 | 怕吃亏、爱等 | Eng×0.7，Wait×1.5，威胁等待阈值↓ |
| `guard` | 固守 | 守点、架枪/盾 | Def/架枪×1.6，Eng 距离&gt;2×0.5；`strategy.isDefending` 时 Eng×0.3 |
| `skirmish` | 游击 | 打带跑、远程风筝 | 远程 Eng×1.4；近战 Engage 后倾向 Disengage；不爱深追 |
| `focus_fire` | 集火 | 协同咬同一目标 | 友军本回合攻击过的目标 Tgt×2.0；换目标 Atk×0.7 |
| `opportunist` | 投机 | 爱捡漏残血 | 目标 HP&lt;40% Tgt×2.2；满血目标 Tgt×0.85 |
| `bully` | 欺软 | 打低防低等级 | 低 def / 低 level Tgt×1.5；重甲 Tgt×0.8 |
| `bodyguard` | 护卫 | 贴头目 / 标记单位 | 与 `protect_tag` 单位距离≤2 Eng×1.5；远离时 Eng 向护卫对象 |
| `rout` | 溃兵 | 劣势快逃 | 人数比&lt;0.6 或 士气≤动摇：Ret×3.0，Atk×0.5 |
| `fanatic` | 死战 | 不撤到最后 | Ret×0.1；士气崩溃前 Eng×1.15 |
| `chaotic` | 混乱 | 编制差、各自为战 | `pickBehavior` cutoff 提高到 0.4（更随机）；`focus_fire` 类乘数×0.5 |

**命名注意**：敌方 `cautious` ≠ 友军 `cowardly`（后者更重叙事与士气）；敌方 `berserk` ≠ 友军 `reckless`（友军还影响战外事件）。

### 5.2 指派优先级

```
1. 关卡 spawn 条目显式 disposition_id（Boss、剧情战）
2. 单位 archetype：elite → opportunist / bodyguard；grunt → default / chaotic
3. 派系默认：匪徒 chaotic、官军 guard、兽人 berserk、弓手 skirmish …
4. 回落 default
```

与 `BattleSimHarness` / 关卡 JSON 字段：`enemy_spawn.disposition`（规划）。

### 5.3 与派系 / Agent 的关系

远期可叠 **第三层**：派系 `AgentProfile`（BB 式 behavior 列表），**战法倾向** 只调乘数，不替换 behavior 池。

```
final_ai_mods = faction_agent_defaults
              × disposition_mult
              × personality_mult   // 仅友军
```

---

## 五、两套接口（AI vs 结算，勿混用）

### 5.1 战术 AI（`ai-system.md`）— 只读 `DispositionProfile`

```gdscript
# 敌我托管同一套
var ai_mods = DispositionDB.get(unit.disposition_id)   # 无则 default
behavior_score = base × archetype_mult × ai_mods.behavior_mult × morale_mult
```

- **性格不进此公式**（v2 硬规）。
- 友军托管若无 `disposition_id` → 用 `disciplined` 或 `default` 占位。

### 5.2 性格结算（`PersonalityCombatHooks`）

`data/personalities.json` 每条除文案外增加 **钩子表**：

```json
{
  "id": "greedy",
  "hooks": {
    "on_kill": { "chance": 0.7, "loot_mult_min": 1.25, "loot_mult_max": 1.5, "sfx": "greedy_snicker" }
  }
},
{
  "id": "lustful",
  "hooks": {
    "on_damage_dealt": { "chance": 0.5, "morale_delta": -1, "requires_opposite_sex": true }
  }
}
```

```gdscript
PersonalityDB.apply_combat_hooks(event_id, ctx) -> { log_bbcode, sfx, stat_deltas }
```

挂载：`BattleScene` 在 `Unit.attacked` / 死亡掉落 **之后** 调用，写 BattleLog + `CombatAudio`。

---

## 六、生成与数据

### 6.1 友军招募

```
personality_id = weighted_pick(PERSONALITIES, background_weights)
disposition_id = "default"    # 托管 AI 用；与性格独立
```

- 28 性格 + 钩子表，`data/personalities.json`

### 6.2 敌军生成

```
disposition_id = spawn.disposition ?? archetype.default ?? faction.default
personality_id = spawn.personality ?? null    # 仅精英/Boss 可选
```

- 12 战法倾向，`data/enemy_dispositions.json`，**无 spawn_weight**（由关卡/派系表决定）

### 6.3 JSON 草案

`data/personalities.json`（友军）— 见 v1.0 示例 `greedy` 条目。

`data/enemy_dispositions.json`（敌军）：

```json
{
  "dispositions": [
    {
      "id": "berserk",
      "display_name": "狂战",
      "behavior_mult": { "engage": 1.3, "attack": 1.1, "wait": 0.1 },
      "tags": ["faction_orc", "faction_bandit_elite"]
    }
  ]
}
```

### 6.4 UI

| 对象 | 显示 |
|---|---|
| 友军 | 名册：**性格** + 一行战斗影响（如「击杀可能私藏战利品」）；战法托管不单独标 |
| 敌军 | Tooltip：**战法**（精英+）；有性格的名将额外标性格 |
| 战斗 | 钩子触发 → **BattleLog** `【性格·xxx】` + 贪财笑声 |

---

## 七、实施阶段

| Phase | 战术 AI（`ai-system.md`） | 性格钩子（本文） |
|---|---|---|
| **2.5** | M0~M1 骨架 + 4 disposition | **好色 + 贪财** 两钩子 + 日志 + 贪财 SFX |
| **3** | M2 完整 12 disposition | 28 性格 JSON + 再补 4~6 个钩子 |
| **4** | 托管开关 | 经济/俘虏/营地联动 |
| **5** | 关卡 stance 脚本 | 剧情改性格（稀有） |

**代码落点**：

- `scripts/ai/*` — 只读 `DispositionDB` + `archetype`
- `PersonalityDB.apply_combat_hooks()` — 伤害/死亡管线，**不** import `scripts/ai/`
- `CombatAudio.play_personality_sfx("greedy_snicker")`

---

## 八、与现有文档对齐

| 文档 | 关系 |
|---|---|
| `economy-system.md` §4.5、§5.5 | 贪财击杀钩子与战外经济 |
| `status-effects.md` §三 | 好色钩子改士气档 |
| `ai-system.md` | **战术 AI SoT**；**不**消费性格 |
| `camp-events-system.md` | 背景→事件池；性格→选项；好感→士气/结局 |
| `class-system.md` §七、§十三 | **背景**与**性格**分开；Phase 5 性格以本文为准 |
| `design.md` §AI、§人物培养 | 双轨说明 + 链到本文 |
| `design/references/wandering-sword.md` | 敌方「有意图」= 战法倾向 |
| BB `agents/*_agent.nut` | 敌方远期 AgentProfile；倾向 = 轻量乘数层 |

---

**文档版本**：v2.0（性格改结算钩子，与战术 AI 解耦）  
**最后更新**：2026-06-11
