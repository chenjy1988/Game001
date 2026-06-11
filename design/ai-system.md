# 战斗 AI 系统 v1.1（重新设计）

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
| 20 | `Attack` 攻击 | 130 | 射程内最优目标 × 最优 attack_mode（斩/刺系数真实参与） | 无目标 / AP 不足 |
| 28 | `Ability_*` 技能 | 各表 | 职业技能逐个独立评分（架枪 120 / 战吼 90 / 处决…），Phase 2.5+ 按解锁挂入 | 未学 / CD / 气力不足 |
| 30 | `Defend` 防御 | 50 | 架盾/守位：被围次数 × 远程威胁 × FactionBrain 防守令 | 无威胁 |
| 40 | `Wait` 等待 | 35 | 延后行动（每回合限 1 次）：威胁高且换血不划算、或等长杆友军先动 | 已等待过 |
| 1000 | `Idle` | 1 | 兜底：原地结束 | 永不为 0 |

**友军托管追加**（§九）：`Loot`（Order 35，仅贪财注册）。

**Engage 落点评分项**（v1 收敛为 6 项）：

```
tile_score = proximity(离最优攻击位)        # 主项
           + flank_bonus(侧/背 arc)        × profile.flank_mult
           + ally_coord(咬同目标/分摊)     × profile.coord_mult
           - oa_cost(路径借机攻击期望伤害) × profile.oa_sensitivity
           - end_threat(落点敌方威胁合计)  × profile.threat_sensitivity
           - terrain_penalty(矛墙/恶劣地形)
```

`oa_sensitivity` / `threat_sensitivity` 受 **坦度**（甲+盾+HP）调整：重甲敢卡 ZoC，脆皮绕路——这是兵种差异的主要来源之一。

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
| Ability 框架（B/C，Phase 2.5） | 未实装 | M0~M2 只挂 `BreathRegulation`；`Ability_*` 评分器随框架补 |
| `Stats.sex` 字段（好色） | 不存在 | M3 前加；`unknown` 不触发 |
| `Loot` 地面战利品实体 | 不存在 | M3 与经济系统掉落实装联动；之前 `Loot` 不注册 |
| `disposition_id` spawn 字段 | 不存在 | M1 加进敌方生成（先 archetype 默认表，不动关卡格式） |
| `TurnManager` 旧 CT 残留 | 已知冲突 | AI 只经 `WorldView` 读回合状态，**不依赖 CT**；RoundManager 重构互不阻塞 |
| Engage 搜索性能（A7） | 风险低 | 候选 cap 60 + 帧预算监控（sim 输出每决策耗时 ms） |

---

## 十三、实施阶段

| 里程碑 | 内容 | 验收 |
|---|---|---|
| **M0 骨架** | `AIAgent` 循环 + `_pick_weighted` + `Idle/Engage/Attack/Wait` 4 个 Behavior + `ai_config.json` | `run_sim.sh` 4v4 能打完，交火率 ≥ 现状 |
| **M1 倾向接入** | `AIProfile` 三层乘法 + `DispositionDB`（先 default/berserk/guard/focus_fire）+ FactionBrain 快照 | sim 中狂战 vs 固守行为肉眼可辨；日志输出乘数链 |
| **M2 完整敌人 AI** | `Retreat/Flee/Disengage/Defend` + TargetScore 全项 + attack_mode 选择 + 12 倾向 | 仿真胜率 / 平均回合 / 站桩率达标（§十四） |
| **M3 我方托管** | 托管开关 UI + 友军 `disposition_id` 默认 | 托管与敌方同引擎打满 4v4；好色/贪财 **钩子** 日志可辨 |

旧 `BattleAI.gd` 在 M2 验收后下线；过渡期 sim 可 A/B 跑两套对比。

---

## 十四、验证与调试

**仿真指标**（`BattleSimHarness`，按 `evaluating-gameplay-balance` / `implementing-gameplay-invariants`）：

| 指标 | 目标 |
|---|---|
| 交火率（双方均出手的回合占比） | ≥ 90% |
| 平均战斗回合 | 8~16 |
| 无意义站桩率（有 AP 有目标却 Idle） | &lt; 2% |
| 镜像阵容胜率 | 45%~55%（先手优势可控） |
| 倾向差异 | berserk 阵均回合 &lt; cautious 阵 −3 以上 |

**调试设施**：

- 每次 pick 输出：`[AI] 王五 候选: Attack 142 / Engage 96 / Wait 38 → 选 Attack (r=0.71)`
- `deterministic` 模式 + 固定种子 → 单测可断言具体决策
- 倾向乘数链可 dump：`base 130 × archetype 1.0 × berserk 1.1 × morale 0.9 = 128.7`

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

**文档版本**：v1.2（性格与 AI 解耦；敌我托管同一 Profile 公式）  
**最后更新**：2026-06-11
