# AI 仿真实验记录

> **用途**：每次调整 AI 逻辑 / `ai_config.json` / harness 后跑批仿真，在此追加一条实验记录。  
> **SoT 指标定义**：[`ai-system.md`](ai-system.md) §十四 · 门禁实现：`BattleSimHarness.check_i3_gates()`  
> **自动化入口**：`./tools/run_ai_experiment.sh "本次改动摘要"`  
> **原始遥测**：`logs/battle_sim_telemetry.json`（当次覆盖）· `logs/ai_experiments/<id>.json`（归档快照）

---

## 指标说明（§十四 · 镜像对称局为主门禁）

| 指标 | 字段 | 目标 | 说明 |
|---|---|---|---|
| 交火率 | `avg_engagement_rate` | ≥ 90% | 双方均出手的回合 / 总回合 |
| 中位回合 | `median_rounds` | 8 ~ 16 | 单场战斗回合数中位数（§十四 门禁；`avg_rounds` 仅作诊断） |
| 站桩率 | `avg_stall_rate` | < 2% | 有交火机会却未攻击的 AI 单位轮次占比 |
| AP 利用率 | `avg_ap_utilization` | ≥ 60% | AI 轮次 `(初AP−末AP)/初AP` 均值 |
| 镜像友胜率 | `ally_win_rate` | 45% ~ 55% | 仅 `mirror` 对称阵容 |
| 均攻击 | `avg_attacks` | ≥ 4 / 局 | demo 不变量亦检查 |
| 倾向差异 | berserk vs guard `median_rounds` 差 | ≥ 3 | `disposition_*` suite |

**辅助字段**（诊断用，非硬门禁）：`behavior_counts`（含 `defend`）、`post_contact`（接敌后 AP/站桩/Defend/hold 分段）、`avg_hits`、`avg_pincers`、`ai_decisions`。

**§十四 判定**：镜像 suite 调用 `check_i3_gates(strict)` → **PASS** / **FAIL**（`SIM_I3_STRICT=0` 时未达标记 WARN，sim 仍可 exit 0）。

---

## 实验条目格式

每条以 `## EXP-NNN` 开头，包含：**时间 · 改动 · 仿真配置 · 指标表 · behavior 分布 · 备注 · 快照路径**。

---

## EXP-001 — 2026-06-13（headless 基础设施）

**改动**：
- `BattleSimHarness`：Wait 后 `return`，禁止双 `end_turn`；仅当前单位时 `end_turn`
- headless preload 链：`Unit` / `DamageSystem` / `TurnManager` / `HexGrid` / `Ability` 链 / behavior `_BehaviorBase`
- `battle_sim_scene.gd` bootstrap 补 Ability 加载顺序

**配置**：`SIM_GAMES=1 SIM_MIRROR_GAMES=1 SIM_DISPOSITION_GAMES=0 SIM_I3_STRICT=0`（smoke）

**结果摘要**（smoke，非正式批跑）：
- demo：6 回合，交火 83%，站桩 6%，AP 35%，41 攻击/局 → 交火恢复（修复前 ≈0%）
- mirror：69 回合，交火 42%，站桩 27%，AP 16% → §十四 仍 FAIL（超长局 + 低 AP）

**备注**：修复前主因 = harness Wait bug + Ability 链 headless 未加载（攻击 `.new()` 失败）。数值 JSON 未动。

**快照**：无（retroactive 手工条目）

---

## EXP-002 — 2026-06-13 16:45:37

**改动**：建立实验日志流程；headless 修复后 baseline（未调 ai_config）

**配置**：`SIM_GAMES=3` `SIM_MIRROR_GAMES=3` `SIM_DISPOSITION_GAMES=4` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 均回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 3 | 7.3 | 72.8% | 7.5% | 34.9% | 100.0% | — |
| mirror 镜像 | 3 | 49.7 | 53.5% | 27.0% | 17.8% | 66.7% | WARN |
| disp berserk | 4 | 39.8 | 55.9% | 28.9% | 14.3% | 25.0% | — |
| disp guard | 4 | 51.5 | 50.5% | 26.5% | 17.2% | 50.0% | — |

### behavior_counts（mirror 汇总）

`move=117 attack=332 wait=892 end_turn=810 ability=133`

### 倾向差异

berserk 均回合 39.8 vs guard 51.5（差 11.8，目标 ≥3）

### 摘要

- 镜像未达标：交火率 53.5% < 90%；站桩率 27.0% > 2%；均回合 49.7 ∉ [8,16]；友胜率 66.7% ∉ 45~55%；AP 利用 17.8% < 60%

**快照**：`logs/ai_experiments/20260613_baseline_exp002.json`

---

## EXP-003 — 2026-06-13 17:04:11

**改动**：重甲前压+接敌禁Wait（is_hanging_back/can_attack_now 门控+气力惩罚）

**配置**：`SIM_GAMES=6` `SIM_MIRROR_GAMES=6` `SIM_DISPOSITION_GAMES=4` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 均回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 6 | 7.7 | 62.9% | 8.5% | 24.9% | 100.0% | — |
| mirror 镜像 | 6 | 98.2 | 41.9% | 29.8% | 17.7% | 50.0% | WARN |
| disp berserk | 4 | 37.0 | 57.0% | 38.5% | 9.0% | 25.0% | — |
| disp guard | 4 | 90.2 | 38.7% | 26.4% | 15.7% | 50.0% | — |

### behavior_counts（mirror 汇总）

`move=1723 attack=654 wait=1381 end_turn=2189 ability=336`

### 倾向差异

berserk 均回合 37.0 vs guard 90.2（差 53.2，目标 ≥3）

### 摘要

- 镜像未达标：交火率 41.9% < 90%；站桩率 29.8% > 2%；均回合 98.2 ∉ [8,16]；AP 利用 17.7% < 60%

**快照**：`logs/ai_experiments/20260613_170411.json`

---

## EXP-004 — 2026-06-13 17:19:05

**改动**：远距Wait条件门控(NEUTRAL禁/ALLY_ADV保留)+中位回合指标

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=12` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 8.0 | 61.8% | 9.9% | 20.3% | 100.0% | — |
| mirror 镜像 | 12 | 43.5 | 52.2% | 37.8% | 10.3% | 66.7% | WARN |
| disp berserk | 8 | 39.0 | 54.2% | 39.0% | 9.5% | 62.5% | — |
| disp guard | 8 | 45.0 | 52.2% | 35.9% | 8.9% | 25.0% | — |

### behavior_counts（mirror 汇总）

`move=422 attack=1327 wait=1164 end_turn=3407 ability=318`

### 倾向差异

berserk 中位回合 39.0 vs guard 45.0（差 6.0，目标 ≥3）

### 摘要

- 镜像未达标：交火率 52.2% < 90%；站桩率 37.8% > 2%；中位回合 43.5 ∉ [8,16]；友胜率 66.7% ∉ 45~55%；AP 利用 10.3% < 60%

**快照**：`logs/ai_experiments/20260613_171905.json`

---

## EXP-005 — 2026-06-13 17:27:27

**改动**：接敌后遥测修复+AP/Defend/hold诊断

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=12` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 8.0 | 61.8% | 17.0% | 63.6% | 100.0% | — |
| mirror 镜像 | 12 | 43.5 | 52.2% | 40.4% | 30.2% | 66.7% | WARN |
| disp berserk | 8 | 39.0 | 54.2% | 41.6% | 31.1% | 62.5% | — |
| disp guard | 8 | 45.0 | 52.2% | 39.4% | 31.0% | 25.0% | — |

### behavior_counts（mirror 汇总）

`move=422 attack=1327 wait=1051 defend=113 end_turn=3407 ability=318`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=29.7% 站桩=40.7% AP空转=68.0% Defend轮=2.4% hold轮=63.5% | move=398 attack=1327 wait=1039 defend=113 end_turn=3335 ability=318`

### 倾向差异

berserk 中位回合 39.0 vs guard 45.0（差 6.0，目标 ≥3）

### 摘要

- 镜像未达标：交火率 52.2% < 90%；站桩率 40.4% > 2%；中位回合 43.5 ∉ [8,16]；友胜率 66.7% ∉ 45~55%；AP 利用 30.2% < 60%

**快照**：`logs/ai_experiments/20260613_172727.json`

---

## EXP-006 — 2026-06-13 17:34:26

**改动**：攻后余AP强制消耗+禁止空end_turn

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=12` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 7.0 | 55.1% | 12.7% | 76.1% | 100.0% | — |
| mirror 镜像 | 12 | 20.0 | 73.8% | 13.9% | 75.9% | 33.3% | WARN |
| disp berserk | 8 | 17.5 | 72.4% | 12.9% | 77.1% | 25.0% | — |
| disp guard | 8 | 18.0 | 77.9% | 14.2% | 75.1% | 37.5% | — |

### behavior_counts（mirror 汇总）

`move=568 attack=928 wait=692 defend=49 end_turn=695 ability=194`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=75.9% 站桩=14.0% AP空转=24.9% Defend轮=3.0% hold轮=62.5% | move=556 attack=928 wait=680 defend=49 end_turn=695 ability=194`

### 倾向差异

berserk 中位回合 17.5 vs guard 18.0（差 0.5，目标 ≥3）

### 摘要

- 镜像未达标：交火率 73.8% < 90%；站桩率 13.9% > 2%；中位回合 20.0 ∉ [8,16]；友胜率 33.3% ∉ 45~55%

**快照**：`logs/ai_experiments/20260613_173426.json`

---

## EXP-007 — 2026-06-13 19:42:29

**改动**：进攻目标优选+OA净收益+兵种延后+AP有收益才花

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=12` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 12.0 | 59.4% | 15.4% | 54.0% | 100.0% | — |
| mirror 镜像 | 12 | 65.5 | 52.0% | 34.4% | 31.8% | 41.7% | WARN |
| disp berserk | 8 | 72.0 | 47.7% | 30.3% | 31.1% | 75.0% | — |
| disp guard | 8 | 74.5 | 52.0% | 31.1% | 30.3% | 62.5% | — |

### behavior_counts（mirror 汇总）

`move=1848 attack=1162 wait=2463 defend=11 end_turn=4067 ability=599`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=32.3% 站桩=34.0% AP空转=54.6% Defend轮=0.2% hold轮=62.1% | move=1824 attack=1162 wait=2379 defend=11 end_turn=4067 ability=599`

### 倾向差异

berserk 中位回合 72.0 vs guard 74.5（差 2.5，目标 ≥3）

### 摘要

- 镜像未达标：交火率 52.0% < 90%；站桩率 34.4% > 2%；中位回合 65.5 ∉ [8,16]；友胜率 41.7% ∉ 45~55%；AP 利用 31.8% < 60%

**快照**：`logs/ai_experiments/20260613_194229.json`

---

## EXP-008 — 2026-06-14 07:49:18

**改动**：P0+P1: AP短Wait/跨回合接近/FactionBrain均势attack/stalemate检测

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=12` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=1`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 8.0 | 61.3% | 12.4% | 59.8% | 100.0% | — |
| mirror 镜像 | 12 | 49.5 | 46.5% | 35.7% | 29.0% | 58.3% | FAIL |
| disp berserk | 8 | 59.0 | 36.4% | 32.0% | 27.2% | 25.0% | — |
| disp guard | 8 | 41.0 | 46.9% | 36.8% | 26.0% | 37.5% | — |

### behavior_counts（mirror 汇总）

`move=1537 attack=1410 wait=1862 defend=49 end_turn=4248 ability=477`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=28.3% 站桩=34.3% AP空转=64.1% Defend轮=0.7% hold轮=27.6% | move=1525 attack=1410 wait=1778 defend=49 end_turn=4248 ability=477`

### 倾向差异

berserk 中位回合 59.0 vs guard 41.0（差 18.0，目标 ≥3）

### 摘要

- 镜像未达标：交火率 46.5% < 90%；站桩率 35.7% > 2%；中位回合 49.5 ∉ [8,16]；友胜率 58.3% ∉ 45~55%；AP 利用 29.0% < 60%

**快照**：`logs/ai_experiments/20260614_074918.json`

---

## EXP-009 — 2026-06-14 07:59:47

**改动**：P0-fix: 撤hold Wait/修正telemetry/can_attack空转

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=12` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=1`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 8.0 | 63.4% | 6.5% | 63.5% | 100.0% | — |
| mirror 镜像 | 12 | 48.5 | 52.8% | 37.6% | 27.3% | 33.3% | FAIL |
| disp berserk | 8 | 41.5 | 54.6% | 40.4% | 28.9% | 62.5% | — |
| disp guard | 8 | 43.0 | 53.6% | 40.1% | 29.1% | 62.5% | — |

### behavior_counts（mirror 汇总）

`move=739 attack=1111 wait=1380 defend=40 end_turn=3677 ability=361`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=25.0% 站桩=30.4% AP空转=48.4% Defend轮=0.7% hold轮=22.6% | move=727 attack=1111 wait=1308 defend=40 end_turn=3665 ability=361`

### 倾向差异

berserk 中位回合 41.5 vs guard 43.0（差 1.5，目标 ≥3）

### 摘要

- 镜像未达标：交火率 52.8% < 90%；站桩率 37.6% > 2%；中位回合 48.5 ∉ [8,16]；友胜率 33.3% ∉ 45~55%；AP 利用 27.3% < 60%

**快照**：`logs/ai_experiments/20260614_075947.json`

---

## EXP-010 — 2026-06-14 08:11:39

**改动**：缩短回合: stalemate12+清场禁Wait

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=12` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 7.0 | 61.9% | 6.0% | 67.7% | 100.0% | — |
| mirror 镜像 | 12 | 86.0 | 60.5% | 44.8% | 39.2% | 25.0% | WARN |
| disp berserk | 8 | 74.0 | 67.1% | 45.6% | 35.3% | 50.0% | — |
| disp guard | 8 | 73.0 | 59.3% | 45.5% | 37.8% | 25.0% | — |

### behavior_counts（mirror 汇总）

`move=2474 attack=1365 wait=524 defend=1 end_turn=4778 ability=507`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=40.7% 站桩=41.3% AP空转=51.7% Defend轮=0.0% hold轮=21.5% | move=2450 attack=1365 wait=452 defend=1 end_turn=4766 ability=507`

### 倾向差异

berserk 中位回合 74.0 vs guard 73.0（差 1.0，目标 ≥3）

### 摘要

- 镜像未达标：交火率 60.5% < 90%；站桩率 44.8% > 2%；中位回合 86.0 ∉ [8,16]；友胜率 25.0% ∉ 45~55%；AP 利用 39.2% < 60%

**快照**：`logs/ai_experiments/20260614_081139.json`

---

## EXP-011 — 2026-06-14 08:42:17

**改动**：残局收刀(低HP/disengage禁)+1v1 stalemate熔断(last_kill_round)

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=20` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=1`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 9.0 | 84.4% | 9.2% | 79.5% | 100.0% | — |
| mirror 镜像 | 20 | 22.5 | 72.6% | 12.7% | 75.1% | 20.0% | FAIL |
| disp berserk | 8 | 18.0 | 72.6% | 11.2% | 77.2% | 0.0% | — |
| disp guard | 8 | 21.5 | 68.2% | 12.2% | 73.1% | 25.0% | — |

### behavior_counts（mirror 汇总）

`move=1152 attack=1637 wait=300 defend=44 end_turn=1514 ability=284`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=71.8% 站桩=12.6% AP空转=12.4% Defend轮=2.1% hold轮=21.6% | move=1112 attack=1637 wait=300 defend=44 end_turn=1494 ability=284`

### 倾向差异

berserk 中位回合 18.0 vs guard 21.5（差 3.5，目标 ≥3）

### 摘要

- 镜像未达标：交火率 72.6% < 90%；站桩率 12.7% > 2%；中位回合 22.5 ∉ [8,16]；友胜率 20.0% ∉ 45~55%

**快照**：`logs/ai_experiments/20260614_084217.json`

---

## EXP-012 — 2026-06-14 09:08:52

**改动**：Phase A/B 框架落地：BehaviorAbility+CombatEffectContainer+职业技能绑定

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=20` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 35.5 | 53.2% | 30.4% | 82.4% | 33.3% | — |
| mirror 镜像 | 20 | 19.0 | 0.0% | 16.6% | 73.0% | 0.0% | WARN |
| disp berserk | 8 | 19.0 | 0.0% | 75.2% | 87.5% | 0.0% | — |
| disp guard | 8 | 19.0 | 0.0% | 16.6% | 73.0% | 0.0% | — |

### behavior_counts（mirror 汇总）

`move=1360 attack=0 wait=2060 defend=0 end_turn=2040 ability=10800`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=72.9% 站桩=16.7% AP空转=29.3% Defend轮=0.0% hold轮=0.0% | move=1360 attack=0 wait=2040 defend=0 end_turn=2040 ability=10720`

### 倾向差异

berserk 中位回合 19.0 vs guard 19.0（差 0.0，目标 ≥3）

### 摘要

- 镜像未达标：交火率 0.0% < 90%；站桩率 16.6% > 2%；中位回合 19.0 ∉ [8,16]；友胜率 0.0% ∉ 45~55%

**快照**：`logs/ai_experiments/20260614_090852.json`

---

## EXP-013 — 2026-06-14 09:13:02

**改动**：Phase A/B + ability门控修复

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=20` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 30.0 | 75.4% | 33.5% | 64.8% | 91.7% | — |
| mirror 镜像 | 20 | 19.0 | 0.9% | 93.7% | 23.7% | 0.0% | WARN |
| disp berserk | 8 | 21.5 | 0.5% | 83.9% | 22.7% | 0.0% | — |
| disp guard | 8 | 19.0 | 0.5% | 92.4% | 23.2% | 0.0% | — |

### behavior_counts（mirror 汇总）

`move=259 attack=90 wait=21 defend=7 end_turn=53 ability=2896`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=23.3% 站桩=94.3% AP空转=0.7% Defend轮=0.2% hold轮=20.5% | move=239 attack=90 wait=21 defend=7 end_turn=53 ability=2876`

### 倾向差异

berserk 中位回合 21.5 vs guard 19.0（差 2.5，目标 ≥3）

### 摘要

- 镜像未达标：交火率 0.9% < 90%；站桩率 93.7% > 2%；中位回合 19.0 ∉ [8,16]；友胜率 0.0% ∉ 45~55%；AP 利用 23.7% < 60%

**快照**：`logs/ai_experiments/20260614_091302.json`

---

## EXP-014 — 2026-06-14 09:15:15

**改动**：Phase A/B ability门控v2

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=20` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 11.5 | 83.8% | 11.3% | 81.9% | 100.0% | — |
| mirror 镜像 | 20 | 20.5 | 72.0% | 10.7% | 79.0% | 5.0% | WARN |
| disp berserk | 8 | 12.5 | 74.5% | 10.7% | 82.2% | 0.0% | — |
| disp guard | 8 | 17.0 | 74.3% | 10.6% | 79.9% | 0.0% | — |

### behavior_counts（mirror 汇总）

`move=1209 attack=1565 wait=430 defend=73 end_turn=1573 ability=1510`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=75.7% 站桩=10.6% AP空转=8.7% Defend轮=3.1% hold轮=21.7% | move=1189 attack=1565 wait=410 defend=73 end_turn=1573 ability=1490`

### 倾向差异

berserk 中位回合 12.5 vs guard 17.0（差 4.5，目标 ≥3）

### 摘要

- 镜像未达标：交火率 72.0% < 90%；站桩率 10.7% > 2%；中位回合 20.5 ∉ [8,16]；友胜率 5.0% ∉ 45~55%

**快照**：`logs/ai_experiments/20260614_091515.json`

---

## EXP-015 — 2026-06-14 11:13:43

**改动**：镜像对称出生点+Init tie-break；preempt/ability best_ap_spend

**配置**：`SIM_GAMES=12` `SIM_MIRROR_GAMES=20` `SIM_DISPOSITION_GAMES=8` `SIM_I3_STRICT=0`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
| demo 不对称 | 12 | 11.5 | 87.6% | 11.8% | 82.3% | 100.0% | — |
| mirror 镜像 | 20 | 25.5 | 73.7% | 13.9% | 81.3% | 35.0% | WARN |
| disp berserk | 8 | 23.5 | 76.6% | 13.4% | 81.9% | 37.5% | — |
| disp guard | 8 | 26.0 | 72.6% | 14.2% | 80.5% | 25.0% | — |

### behavior_counts（mirror 汇总）

`move=1269 attack=1722 wait=265 defend=60 end_turn=1589 ability=1752`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`接敌回合中位=1 AP=79.0% 站桩=13.7% AP空转=9.7% Defend轮=2.6% hold轮=17.7% | move=1249 attack=1722 wait=245 defend=60 end_turn=1589 ability=1732`

### 倾向差异

berserk 中位回合 23.5 vs guard 26.0（差 2.5，目标 ≥3）

### 摘要

- 镜像未达标：交火率 73.7% < 90%；站桩率 13.9% > 2%；中位回合 25.5 ∉ [8,16]；友胜率 35.0% ∉ 45~55%（decisive 70.0%，draws 10）

**快照**：`logs/ai_experiments/20260614_111343.json`

---

