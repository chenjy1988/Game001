# 战斗 AI 系统 v1.2（重新设计）

> **目标顺序**：
>
> 1. **P0 敌人 AI**——所有敌方单位的战斗决策（本文主体）
> 2. **P1 我方托管 AI**——自动战斗 / AI 接管友军；**复用同一引擎**，只换 Profile 与少量约束（§九）
>
> 架构参照 BB 反编译研读（`agent.nut` / `behavior.nut` / `strategy.nut`），按本作规模裁剪：
> 6~12 单位、10~20 回合、AP 回合制（DOS2 风）、无分帧需求。
>
> **性格与 AI 解耦**（`personality-system.md` v2.0）：战术 AI **只**消费 `archetype` + **战法倾向** `disposition_id`；敌我托管 **同一引擎**。性格走 **战斗结算钩子**（攻击后/击杀后），不进本文评分。

---

## 一、设计目标与原则

| # | 原则 | 说明 |
|---|---|---|
| 1 | **效用分 + 加权随机** | 每个候选动作打分；不永远选最高分（cutoff 抽签），避免被玩家读透 |
| 2 | **Behavior 拆分** | 移动 / 攻击 / 防御 / 撤退是独立模块，各自评分；不写巨型 `decide()` |
| 3 | **数据驱动战法** | 同一套 Behavior + `archetype` × `disposition` 乘数表 = 匪徒/官军/狂战；**性格不进 AI** |
| 4 | **一回合多动** | 执行完一个 Behavior 后若 AP 仍够 → 重新评估（移动→攻击→再攻击→架盾） |
| 5 | **轻量态势感知** | 阵营级统计（人数比、是否被围）供撤退/守点决策；不做 BB 全量 Strategy |
| 6 | **可解释** | 每次决策输出 `reason` + 候选分数表，写 `logs/`，供 `BattleSimHarness` 与人工调参 |
| 7 | **比 BB 轻** | 不做：Heat 寻路、分帧 generator、镜头演出调度、80+ Behavior |

---

## 二、架构评审结论（决策记录）

> 评审对象：现行运行时（`BattleScene._run_ai_turn` / `TurnManager` / `Unit` / `BattleSimHarness`）+ 本文 v1.0 草案。

| # | 现状问题 | 架构决策 |
|---|---|---|
| A1 | `BattleAI.decide()` 返回整条 plan（path+target），`BattleScene` 边播动画边执行；**执行中途世界变了 plan 失效**（现有「攻击计划取消」日志即此症状） | **决策粒度 = 单个原子 Action**。每执行完一个 Action 用新世界状态重新决策；不再产出多步 plan |
| A2 | 决策与执行耦合：场景版走 `await timer` 动画，`BattleSimHarness` 走 `move_along_path_sync`，**两套执行路径散落两处** | **决策核与执行器分离**：AI 引擎是纯 `RefCounted`，零场景依赖，只产出 Action；`SceneExecutor`（动画/await）与 `SimExecutor`（同步无头）各自消费同一种 Action |
| A3 | `BattleSimHarness` 用全局 `seed()`，AI 若加抽签会**消耗伤害 roll 的随机序列**，破坏复现 | AI 持有**独立 `RandomNumberGenerator`**（种子由外部注入）；伤害 roll 不受 AI 抽签次数影响 |
| A4 | `wait` 状态由 `TurnManager` 管（`can_wait/has_waited`），旧代码 AI 直接调 `turn_manager.wait_current()` | AI 不触碰 `TurnManager`；产出 `WaitAction`，由执行器转译。回合状态作为只读字段进 `WorldView` |
| A5 | 单位能力查询散落 `Unit`（`get_weapon_ap_cost` 等），AI 直接读 Unit 对象，可测性差 | 决策输入统一为 **`WorldView` 只读快照**；v1 允许内部仍引用 Unit/Grid，但**接口收敛**，便于后续替换为纯数据 |
| A6 | 士气系统（H2）、Ability 框架（B/C）、`sex` 字段均未实装 | 见 §十二：`morale_mult` 先恒 1；好色 **钩子** M2.5 前补 `Stats.sex`；性格 **不进** AI Profile |
| A7 | Engage 落点搜索 = 候选格 × 目标 × 模式，是性能大头 | 半径 9 地图 ~250 格、≤12 单位，一帧可算完；保险：候选格按「距最优攻击位距离」预排序，**cap 前 60 个** |

---

## 三、三层架构 + 决策/执行分离

```
                      决  策  侧（纯逻辑，RefCounted，可无头单测）
┌─ FactionBrain（阵营层，每回合更新一次）─────────────────┐
│  人数比 / 交战数 / 最近敌距 / stance / 集火标记 / 护卫   │
└──────────────┬───────────────────────────────────────┘
               ↓ 只读快照（并入 WorldView）
┌─ AIAgent（单位层）────────────────────────────────────┐
│  Profile = 兵种模板 × 战法倾向（disposition only）     │
│            × 士气档 × 气力档                           │
│  decide_next_action(WorldView) → AIAction              │
│  维护本回合 Intentions（engage_target / reserved_ap）  │
└──────────────┬───────────────────────────────────────┘
               ↓ 逐个评分（产出 Action 候选，不执行）
┌─ Behavior（动作层，无状态评分器）──────────────────────┐
│  evaluate(view, profile) → { score, action }           │
└──────────────┬───────────────────────────────────────┘
               ↓ AIAction（数据）
═══════════════╪═════════════════════════════════════════
               ↓ 执  行  侧（消费 Action，二选一）
   SceneExecutor（BattleScene：动画 / await / BattleLog）
   SimExecutor（BattleSimHarness：move_along_path_sync，零等待）
```

**AIAction**（Dictionary 或轻量类，执行器唯一输入）：

```gdscript
{ type: MOVE,    path: Array[Vector2i] }                  # 一段移动
{ type: ATTACK,  target: Unit, attack_mode: String }      # 一次攻击
{ type: ABILITY, id: "breath_regulation", target: ... }
{ type: WAIT }                                            # 延后行动（执行器调 TurnManager）
{ type: END_TURN }
```

| 层 | 类（规划） | 生命周期 | 职责 |
|---|---|---|---|
| 阵营 | `FactionBrain` | 每回合开始重算 | 全局统计 + stance + 集火标记；纯函数产快照 |
| 单位 | `AIAgent` | 单位行动期间 | 组装 Profile、`decide_next_action`、Intentions |
| 动作 | `AIBehavior` 子类 | 无状态 | `evaluate(view, profile) → {score, action}` |
| 执行 | `SceneExecutor` / `SimExecutor` | 宿主持有 | 消费 AIAction；动画与无头各一套 |

**Intentions**（单位内、本回合有效）：Engage 选好落点时写 `engage_target / engage_tile / reserved_ap`，下一轮决策中 Attack 直接消费（避免移动与攻击两次寻优打架）；回合结束清空。**Engage 评分时即预留攻击 AP**——杜绝「走到了却打不了」。

---

## 四、决策主循环（宿主驱动）

执行权在宿主（BattleScene / Harness），AI 每次只答「下一步做什么」：

```gdscript
# 宿主侧（以 BattleScene 为例）
func _run_ai_turn(unit):
    var agent = AIAgent.new(unit, _ai_rng)
    var guard = 0
    while guard < MAX_ACTIONS_PER_TURN:        # cap=6，防死循环
        guard += 1
        var view = WorldView.capture(unit, _all_units, hex_grid, faction_brain, turn_manager)
        var action = agent.decide_next_action(view)
        if action.type == AIAction.END_TURN:
            break
        await scene_executor.run(action)        # Sim 侧：sim_executor.run(action)（同步）
        if not unit.is_alive():
            return                              # 被 OA 打死，TurnManager 信号自会推进
        if action.type == AIAction.WAIT:
            return                              # 等待 = 本回合让出，不 end_turn
    unit.end_turn()
```

```gdscript
# 决策核（AIAgent）
func decide_next_action(view) -> AIAction:
    _refresh_profile_if_dirty(view)            # 士气/气力档变了才重算
    var scored = []
    for b in profile.behaviors:                # 按 Order 升序
        var r = b.evaluate(view, profile)      # → {score, action}
        if r.score > 0.0:
            scored.append(r)
    if scored.is_empty():
        return AIAction.end_turn()
    return _pick_weighted(scored).action
```

**加权随机 `_pick_weighted`**（BB `pickBehavior` 同构）：

```
1. 按 score 降序
2. cutoff = top_score × CONSIDER_CUTOFF        # 默认 0.25；chaotic 倾向 0.4
3. 候选 = score ≥ cutoff 的行为
4. 非 Idle 且 0 < score < MIN_POOL_SCORE(10) 的抬到 10（保底进池）
5. r = rng.randf() × Σscore；按分数区间落点选中    # rng = AI 专用流
```

- **难度开关**：`deterministic = true` 直接取最高分（高难度 / 单测复现）。
- **每次决策只看当前世界**：上一步移动吃了 OA、目标被友军打死，下一步自动适应——A1 问题就此消除。

---

## 五、Behavior 清单 v1（9 个）

> Order 决定 **评估顺序**（先判逃不逃、再判走位、再判出招），不是优先级；最终看分数。

| Order | Behavior | 基础分 | 评什么 | 0 分门控 |
|---|---|---|---|---|
| 5 | `Flee` 溃逃 | 9000 | 士气 **崩溃** 档专用：向己方边缘逃跑 | 非崩溃档 |
| 8 | `Retreat` 撤退 | 60 | 战术后撤：HP 低 / 人数劣势 / FactionBrain 撤退令 | 满血优势局 |
| 10 | `Engage` 接敌 | 100 | **不在射程时** 选落点：A* 路径 + OA 代价 + 落点威胁 + 侧翼/协同加成 | 已在射程 / 被 3+ ZoC 锁死 |
| 15 | `Disengage` 脱战 | 55 | 远程/脆皮被贴脸：评估吃 OA 撤出 vs 原地反打 | 未被近身 |
| 20 | `Attack` 攻击 | — | `TargetScore × utility_scale`（默认 scale=100，典型 ~130） | 无目标 / AP 不足 |
| 28 | `Ability_*` 技能 | 各表 | 职业技能逐个独立评分（架枪 120 / 战吼 90 / 处决…），Phase 2.5+ 按解锁挂入 | 未学 / CD / 气力不足 |
| 30 | `Defend` 防御 | 50 | situation（被围×8 + 重盾 + hold 令）− `weight × attack_opportunity` | 邻敌 <2 / attack 令 / 已等待过 |
| 40 | `Wait` 等待 | 35 | situation（威胁衰减 + 散兵延后 + hold 令）− `weight × attack_opportunity` | 已等待过 / 力竭 / 被围 >2 |
| 1000 | `Idle` | 1 | 兜底：原地结束 | 永不为 0 |

**友军托管追加**（§九）：`Loot`（Order 35，仅贪财注册）。

**Engage 落点评分项**（v1 收敛为 6 项）：

```
tile_score = proximity(离最优攻击位)        # 主项
           + flank_bonus(侧/背 arc)        × profile.flank_mult
           + ally_coord(咬同目标/分摊)     × profile.coord_mult
           - oa_cost(路径借机攻击期望)     × profile.oa_sensitivity   # 见 §5.1 OA 三层
           - end_threat(落点敌方威胁合计)  × profile.threat_sensitivity
           - terrain_penalty(矛墙/恶劣地形)
```

**OA 决策惩罚**（`engage_scorer.oa_utility_penalty`，2026-06 落地；**无轻/重甲分类**）：

```
沿路径 Σ P(hit) × (冲击伤害, 护甲损耗)
penalty = ① 期望威胁(primary) × ② 己方护甲缓冲 × ③ 掉甲风险 × scale × oa_sensitivity

① primary = Σ hit × E[冲击] / max_hp × utility_scale     # DamageSystem 真管线
② buffer  = 1 / (1 + (body_armor+head_armor) / armor_ref) # 连续护甲值，非装备 tag
③ strip   = 1 + clamp(预期掉甲/当前总甲, 0, 1) × strip_weight；甲将破 +bonus
```

- **不单独评 HP 渗透**；甲将破视为高危。
- **合理换打可吃 OA**：setup 净收益 > OA 惩罚时 Move 仍可选（见 §5.1）。
- **移形/换位不豁免 OA 硬规则**：是否用技能由统一框架比净效用，不为单个技能写特例。

`oa_sensitivity` 仍受 Profile / archetype 调整；**不再**用护甲 weight 做皮甲/重甲 floor。

**决策硬规（仅一条）**

- **AP 花在有收益处**：本回合**不能再 Q** 且仍有 AP、存在 `best_ap_spend > 0` 时，不得 **Wait / 空结束**；须攻击、**净正收益**走位或花 AP 技能。**无正收益时允许 `end_turn`**（勿为抬 AP 利用率硬走吃 OA 的步）。**Defend 在防御场景允许**。
- **攻后余 AP**（综合决策，非移形优先）：已在射程但 AP 不足再攻时，在 **Attack / Ability / setup Move / Preempt / Breath（满 AP）** 间比净效用；**可顶 OA 移动**当 setup−OA > 0；**薄 Move 输给收手**（`should_prefer_end_over_move`）；Wait 恢复后再决策 margin ×1.5。
- **技能不是残 AP 默认解**：移形/换位/推撞等与 Move 同池竞争；仅当**技能落点净效用**显著优于「普通 Move−OA」或 End/Preempt 时才选（§5.1 统一框架，不为单技能写 if）。
- **友军未接敌延后**（`skirmisher` / `scout` / `archer` / 匕首）：场上有步兵/重甲友军且**无友邻敌**时，Engage/Advance/Attack/`_fallback_spend_ap` 均不抢冲；允许远距 **Wait(Q)**。友军贴脸后解除。
- **进攻型目标优选**（非 `guard` 倾向、非重甲守势）：枚举原地攻与 1～2 步走+打；`TargetScore` 偏残血低甲；**邻格直攻效用 ≥ 走打净效用**（扣 OA）时只换目标不走位。

**击杀不做硬拦**：残血可收时，收益走 `TargetScore × kill_mult(×3)` 进入 Attack 综合分；命中极低时 Attack 分自然低，AI 可改选吐纳/Wait/Defend。

其余 **Wait / Defend / Breath / Attack** 一律按综合分竞争，**无固定优先级**（Defend 为 M0 占位行为，正式防御技能 Phase 2.5+ 再挂）。

**Wait / Defend / Breath 机会成本**（同池竞争）：

```
attack_opportunity = max(TargetScore × utility_scale)   # 含走+打；击杀×kill_mult 已计入
breath_utility     = (Δremaining/max + urgency×2.0) × recovery_scale
breath_score       = breath_utility − weight × attack_opportunity

wait_score   = wait_baseline + situation − weight × attack_opportunity − ap_hold × best_ap_spend
defend_score = defend_baseline + situation − weight × attack_opportunity   # 不扣 ap_hold
```

- `best_ap_spend`：当前 AP 下最佳「花 AP」行动效用 = max(Attack, Move/setup, **Ability**, Preempt, Breath@满AP)（见 §5.1）。
- `ap_hold`：仅 **Wait**、且 **`can_wait() == false`** 时扣 `best_ap_spend`。
- 低命中被围：attack_opportunity 低 → Defend 可高于 Breath/Attack；**已接敌且本回合能攻或能走+打时 Wait=0**（Q 扣 +5 气力，无战术收益）。
- **远距 Wait**：`ranged_balance != ALLY_ADVANTAGE` 且射程外、本回合还能走位（`AP ≥ AP_PER_HEX`）→ **Wait=0**；己方远程占优（`ALLY_ADVANTAGE`）时允许远距持距 Wait（×2.0）。

---

## 5.1 统一决策评估框架（Action Utility）

> **原则**：不为「移形」「换位」等单个技能写适配分支；所有 **Attack / Move / Wait / Ability / Preempt / Breath / End** 走同一套「候选 → 效用 → 机会成本 → 入池竞争」管线。Behavior 负责**枚举候选**；**评分器**负责**估效用**；`AIAgent` 负责**加权选取**。

### 管线（目标架构）

```
WorldView + Profile
    ↓
① 候选生成（各 Behavior / Ability 插件）
    Attack  → (target, mode)
    Engage/Advance → (path)
    Ability   → (ability_id, target, context)   # 移形/换位/推撞/嘲讽…同一入口
    Wait / Preempt / Breath / Defend
    ↓
② 毛效用 gross_u(action)
    Attack     → TargetScore × utility_scale
    Move       → setup_gain 或 score_path；− oa_penalty；− defer_cost（可选）
    Ability    → project_post_state(action)     # 见下；读 Ability.movement / effects
    Wait/…     → baseline + situation
    ↓
③ 共享机会成本（同一函数，避免 Behavior 互递归）
    net_u = gross_u − weight × max(其它候选 gross_u)
    best_ap_spend = max(net_u) over 花 AP 类
    ↓
④ 入池 × profile.behavior_mult × IntentWeights(category)
    ↓
⑤ AIAgent._pick_weighted（或 deterministic）
```

### Ability 评分（通用，非 per-id）

`Behavior_Ability` 对每个 `job.abilities[]` 条目：

1. **`Ability.can_use(user, target)`** — AP/射程/约束（数据驱动）
2. **`AbilityScorer.project(action)`** — 根据 `kind` + `movement.kind` + `effects` 投影**执行后**状态效用，例如：
   - `TELEPORT` / `SWAP` / `PUSH`：模拟落点 → 调 `EngageScorer` / `TargetScore` 问「下回合或同回合剩余 AP 能做什么」
   - `DEBUFF/BUFF`：读 `ai_hint.situational` + 效果期望（Phase 2.5 接 CombatEffect）
3. **共享成本**：与 Move 相同扣除「若不用技能、改走普通 path 的 OA/setup 效用」；**不**因 TELEPORT 无视 ZoC 自动 +100

**移形何时高分的语义（由投影得出，非硬规则）**：

| 态势 | 普通 Move 净效用 | 移形相对优势 |
|---|---|---|
| 多人包夹 / OA 三层惩罚高 / 自身甲薄 | 低或负 | 高（免 OA + 落点兑现） |
| 邻格可换打脆皮，setup−OA > 0 | 高 | 低（应顶 OA Move，非移形） |
| 薄 setup / 无兑现 | ≤0 | 无；End/Preempt 竞争 |

### 代码现状（2026-06）

| 模块 | 状态 |
|---|---|
| Move setup + OA 三层 + defer + 薄 Move 收手 | ✅ `engage_scorer` + `behavior_base` |
| Attack / TargetScore / attack_mode | ✅ |
| Wait/Preempt/Breath 机会成本 | ✅ `best_ap_spend_utility` |
| Ability 入池 | 🟡 `behavior_ability.gd` 仅 `ai_hint` 启发式，**未**接 `project_post_state` |
| 统一 `ActionScorer` 类 | ❌ 待 I4 |
| `[AI]` 决策日志（setup/oa/nd0→nd1） | ❌ 待 I4 |

**单测**：`test_ai_m0_scene.gd` T31–T38 + 93 PASS（`./tools/run_tests.sh --full`）。

---

## 六、目标评分 TargetScore（攻击类共用）

```
target_score = hit_chance^1.1 × W_HIT          # 0.45
             + expected_dmg / target_max_hp × W_DMG    # 0.25
             + (1 - target_hp_ratio) × W_LOWHP         # 0.30  集火（补 BB 弱点）
× kill_mult        # 期望伤害 ≥ 剩余 HP → ×3.0
× ally_focus_mult  # 友军本回合打过该目标 → ×1.3（BB 没有，本作补）
× counter_mult     # 目标有反击/借势反刺 → ×0.6
× fleeing_mult     # 溃逃目标 → ×0.5（默认不追残兵，嗜血/残忍倾向覆盖）
× ranged_mult      # 目标是远程 → ×1.25（优先拆火力点）
× disposition.target_mult(attacker, target)   # §七：战法倾向最后乘；无性格项
```

- 权重全部进 `data/ai_config.json`，调平衡不改代码。
- `ForcedOpponent`（嘲讽/睚眦）：直接 ×1000。
- **attack_mode 选择**：对每个目标分别用斩/刺等模式算 `expected_dmg`（接 `DamageSystem` 真实公式），取最高——双模式武器的 AI 收益在此兑现。

---

## 七、Profile：战法倾向如何进入评分

`AIProfile` = 三层乘法；**不含 `personality_id`**（v2.0 硬规，见 `personality-system.md` §2.1）：

```
profile.behavior_mult[b] = archetype_mult[b]      # 兵种模板（重步/弓手/骑兵）
                         × disposition_mult[b]   # DispositionDB（12 个战法倾向）
                         × morale_mult[b]         # 士气档（动摇→Eng↓ Ret↑）
                         × fatigue_mult[b]        # 气力档（力竭→Attack↓）

behavior_final = base_score × profile.behavior_mult[b] × situation_terms
```

| 来源 | 敌军 | 友军托管 |
|---|---|---|
| 模板 `archetype` | `data/enemy_units.json` | JobClass 推导 |
| 战法 `disposition` | spawn / 派系默认 | 默认 `default` 或 `disciplined` |
| **性格** | ❌ 不进 AI | ❌ 不进 AI；见 `PersonalityCombatHooks` |

```gdscript
var ai_mods = DispositionDB.get(unit.disposition_id)   # 敌我相同 API
```

---

## 八、FactionBrain（阵营层，轻量）

每回合开始为每个阵营算一次快照（纯函数，无状态机）：

| 字段 | 用途 |
|---|---|
| `power_ratio` | 双方有效战力比（HP×甲×均伤粗估）→ Retreat / `rout` 倾向触发 |
| `engaged_count / total` | 交战比例 → 后排该不该压上 |
| `nearest_gap` | 两军最近距离 → 开局对峙 vs 混战 |
| `stance` | `attack / hold / retreat`：关卡脚本可写死（守营、伏击），否则由 power_ratio 推导 |
| `focus_marks` | **集火标记**：本回合被友方攻击过的目标列表 → TargetScore `ally_focus_mult`（BB 缺失，本作补强协同） |
| `protect_unit` | `bodyguard` 倾向的护卫对象（Boss/旗手） |

v1 不做：被风筝检测、延迟进攻、按玩家等级缩放。

---

## 九、我方托管 AI（P1，与敌方同一引擎）

| 维度 | 敌人 | 友军托管 |
|---|---|---|
| 决策引擎 | `AIAgent` + Behavior + pick | **完全相同** |
| AI Profile | `archetype` + `disposition_id` | **相同**；缺省 `disposition_id = default` |
| 性格 | 精英可挂 `personality_id` → **仅结算钩子** | 招募必有 `personality_id` → **仅结算钩子** |
| 玩家接管 | — | 可切回手控；托管不拦玩家指令 |
| 「弱智感」归因 | 查 AI / disposition，**不**查性格 | 同左；贪财/好色怪在 **日志+笑声**，不怪选招 |

**无**友军专属 Behavior（无 `Loot`、无好色拒打）。贪财/好色在 `PersonalityDB.apply_combat_hooks()`，敌我对称。

---

## 十、模块与文件布局

```
scripts/ai/                          # 决策核：零场景依赖，可无头单测
├── ai_agent.gd          AIAgent     # decide_next_action / Profile 组装 / Intentions
├── ai_action.gd         AIAction    # Action 类型常量与构造器
├── ai_profile.gd        AIProfile   # 三层乘法、dirty 刷新
├── world_view.gd        WorldView   # 只读快照（units / grid 查询 / faction / turn 状态）
├── faction_brain.gd     FactionBrain
├── target_score.gd      TargetScore # §六公式（静态）
├── scoring/
│   ├── engage_scorer.gd             # Move/setup、OA 三层、defer
│   └── action_scorer.gd             # 【I4 规划】统一 gross/net 效用入口
└── behaviors/
    ├── behavior_base.gd             # evaluate(view, profile) → {score, action}
    ├── behavior_engage.gd / attack.gd / wait.gd / idle.gd        # M0
    ├── behavior_retreat.gd / flee.gd / disengage.gd / defend.gd  # M2

scripts/data/
└── DispositionDB.gd（autoload）     # data/enemy_dispositions.json
# PersonalityDB → 战斗结算钩子，见 personality-system.md §5.2；不 import scripts/ai/

执行器（贴宿主放，不进 scripts/ai/）：
├── BattleScene 内 SceneExecutor（动画 / await / BattleLog）
└── BattleSimHarness 内 SimExecutor（同步，复用 move_along_path_sync）
```

依赖方向（单向，禁止反向）：

```
behaviors → world_view / target_score / ai_profile
ai_agent  → behaviors
执行器     → ai_action + Unit/TurnManager/HexGrid
scripts/ai/* 不 import BattleScene / UI / CombatAudio
```

---

## 十一、数据文件

| 文件 | 内容 |
|---|---|
| `data/ai_config.json` | 全局：基础分表、TargetScore 权重、CONSIDER_CUTOFF、MAX_ACTIONS_PER_TURN |
| `data/ai_archetypes.json` | 兵种模板：behavior 列表 + archetype_mult + 坦度修正 |
| `data/enemy_dispositions.json` | 敌方 12 倾向（`personality-system.md` §7.3） |
| `data/personalities.json` | 性格 **钩子表**（不进 AI，见 `personality-system.md` §5.2） |

```json
// ai_archetypes.json 示例
{
  "heavy_infantry": {
    "behaviors": ["flee", "retreat", "engage", "attack", "defend", "wait", "idle"],
    "behavior_mult": { "engage": 1.15, "defend": 1.3, "retreat": 0.7 },
    "flank_mult": 0.8, "threat_sensitivity": 0.5
  },
  "archer": {
    "behaviors": ["flee", "retreat", "disengage", "engage", "attack", "wait", "idle"],
    "behavior_mult": { "disengage": 1.5, "engage": 0.8 },
    "threat_sensitivity": 1.4
  }
}
```

---

## 十二、外部依赖与风险

| 依赖 | 状态 | 对策 |
|---|---|---|
| 士气系统（`phase2-todo.md` H2） | 未实装 | `morale_mult` 恒 1.0，接口先留；H2 落地后填表 |
| Ability 框架（B/C） | **部分实装** | `AbilityLibrary` + JSON 技能；AI 侧 `Behavior_Ability` 启发式评分；**I4 统一 ActionScorer** |
| `Stats.sex` 字段（好色） | 不存在 | M3 前加；`unknown` 不触发 |
| `Loot` 地面战利品实体 | 不存在 | M3 与经济系统掉落实装联动；之前 `Loot` 不注册 |
| `disposition_id` spawn 字段 | 不存在 | M1 加进敌方生成（先 archetype 默认表，不动关卡格式） |
| `TurnManager` 旧 CT 残留 | 已知冲突 | AI 只经 `WorldView` 读回合状态，**不依赖 CT**；RoundManager 重构互不阻塞 |
| Engage 搜索性能（A7） | 风险低 | 候选 cap 60 + 帧预算监控（sim 输出每决策耗时 ms） |

---

## 十三、实施阶段

| 里程碑 | 内容 | 验收 |
|---|---|---|
| **M0 骨架** | `AIAgent` 循环 + Behavior 池 + `ai_config.json` | ✅ 单测 93 PASS；4v4 可打完 |
| **M1 倾向接入** | `AIProfile` + `DispositionDB` + FactionBrain | ✅ sim 可辨 berserk/guard |
| **M1.5 残 AP / OA** | setup 门控、OA 三层、defer、Wait 恢复 margin、薄 Move→End | ✅ T31–T38 |
| **M2 完整敌人 AI** | §十四镜像门禁 + **I4 统一 Action 评分** | ⏳ 镜像 FAIL（见 `ai-experiments.md` EXP-015） |
| **M3 我方托管** | 托管开关 + 友军 disposition 默认 | 未启动 |

旧 `BattleAI.gd` 在 M2 验收后下线；过渡期 sim 可 A/B 跑两套对比。

### I 段任务对照（`phase2-todo.md` §I）

| ID | 内容 | 状态 |
|---|---|---|
| I0–I2 | 骨架 / 倾向 / 遥测 | ✅ |
| I3 | §十四镜像数值门禁 | 🚧 未达标 |
| **I4** | **统一决策评估框架**（§5.1；Ability 通用投影，非移形/换位特例） | ⏳ 下一实现焦点 |
| I5 | 决策日志增强 + mirror 回归 EXP | ⏳ 随 I4 |

---

## 十四、验证与调试

**仿真指标**（`BattleSimHarness`，按 `evaluating-gameplay-balance` / `implementing-gameplay-invariants`）：

| 指标 | 目标 |
|---|---|
| 交火率（双方均出手的回合占比） | ≥ 90% |
| 平均战斗回合 | 8~16 |
| 无意义站桩率（有 AP 有目标却 Idle） | &lt; 2% |
| **AP 利用率**（AI 单位轮次 `(初AP−末AP)/初AP` 均值） | **≥ 60%** |
| **接敌后 AP 利用率**（`post_contact.ap_utilization`，最近敌我距 ≤2 起） | 诊断用 |
| **接敌后站桩 / Defend / hold** | `post_contact.stall_rate` / `defend_turn_rate` / `hold_stance_turn_rate` |
| 镜像阵容胜率 | 45%~55%（先手优势可控） |
| 倾向差异 | berserk 阵均回合 &lt; cautious 阵 −3 以上 |

**调试设施**：

- 每次 pick 输出：`[AI] 王五 候选: Attack 142 / Engage 96 / Wait 38 → 选 Attack (r=0.71)`
- `deterministic` 模式 + 固定种子 → 单测可断言具体决策
- 倾向乘数链可 dump：`base 130 × archetype 1.0 × berserk 1.1 × morale 0.9 = 128.7`
- **实验日志**：[`ai-experiments.md`](ai-experiments.md) — 每次调 AI 后 `./tools/run_ai_experiment.sh "改动摘要"` 追加指标快照

---

## 十五、与 BB 的差异速查

| 维度 | BB | 本作 |
|---|---|---|
| Behavior 数 | 84 | v1 = 9 |
| 评估 | 分帧 generator | 一帧评完（单位少） |
| 集火 | 弱（无全局标记） | **FactionBrain.focus_marks + ally_focus_mult** |
| 目标偏好 | 命中 &gt; 残血 | 残血权重提高（W_LOWHP 0.30） |
| 性格 | Agent Properties 混在 AI 里 | **不进 AI**；结算钩子 + 日志 |
| 我方托管 | 无 | 与敌方 **同一** `AIAgent` |
| Heat 寻路 | 有 | 省略（A* + 落点威胁足够） |

---

## 十六、交叉引用

| 文档 | 关系 |
|---|---|
| `personality-system.md` | 倾向/性格数据 SoT；本文是消费方 |
| `status-effects.md` §三 | morale_mult 档位来源 |
| `design.md` §AI | 顶层索引 → 指向本文 |
| `phase2-plan.md` | 排期挂靠（M0~M2 建议进 Phase 2.5） |
| BB 研读（对话记录） | `agent.nut` think/evaluate/pickBehavior、`queryTargetValue`、Strategy 架构 |

---

## 后期：自动权重优化

> 详见 [`design/ai-decision-logic.md` §十一](ai-decision-logic.md) —— Sim 引擎 + 贝叶斯搜索自动调 18 职业权重表，RL 启发，无需改代码。

---

**文档版本**：v1.3（性格与 AI 解耦；敌我托管同一 Profile 公式 + 自动优化索引）  
**最后更新**：2026-06-11
