# 营地随机事件与好感度 v1.0

> **三轴分工**（勿混用）：
>
> | 轴 | 字段 | 决定什么 |
> |---|---|---|
> | **背景** | `background_id` | **能遇到哪些** 随机事件（事件池、触发权重） |
> | **性格** | `personality_id` | 事件里 **出现哪些回答选项**、各选项默认倾向 |
> | **好感度** | `affection`（隐藏） | 玩家选哪条回答 → 数值变化 → 战斗士气 / 特殊事件 / 结局 |
>
> 战场 AI 规则见 `personality-system.md`；背景属性表见 `class-system.md` §七。

---

## 一、设计原则

1. **背景开门，性格定选项**——同一事件对不同性格展示不同选项子集；无对应性格标签的选项不显示（或灰显说明「此人做不出这种事」）。
2. **选项即态度**——每次选择是对 **该雇佣兵本人** 或 **全队对其看法** 的信号；Δ好感写在选项数据里，玩家不直接看到数值。
3. **好感隐藏、后果可见**——名册不显示 `72/100`；通过台词态度、开局士气、拒服事件让玩家 **感受到** 关系。
4. **低好感有战损**——不是纯剧情装饰；长期冷落会在战场上兑现（开局低士气）。
5. **高好感有回报**——专属营地事件、关键剧情节点、结局分支资格（Phase 4+）。

---

## 二、随机事件触发（背景主导）

### 2.1 事件池结构

```
事件可触发 ⟺
  大地图/营地 tick 满足 base_weight
  AND 队伍中存在 background_id ∈ event.required_backgrounds（或 party_tag）
  AND 未在 event.cooldown 内重复
  AND （可选）主线章节 ≥ event.min_chapter
```

- **背景专属**：仅当队伍里有对应出身才 **入池**。例：`evt_sogdian_caravan` 要求 `background=sute_merchant`。
- **通用事件**：`required_backgrounds: []`，任何队伍可抽；但选项仍按 **在场雇佣兵性格** 展开。
- **多人背景**：事件可指定 `focus_unit` = 随机一名满足背景的队员，对话与好感 Δ 主要落在他身上。

### 2.2 背景 → 事件类型（示例）

| 背景 | 倾向事件主题 | 示例 id |
|---|---|---|
| 粟特商人 | 商路、互市、走私 | `evt_silk_road_deal` |
| 罪犯/流民 | 黑市、通缉、旧债 | `evt_bounty_hunter` |
| 沙陀血统 | 族裔故旧、边军旧事 | `evt_shatuo_reunion` |
| 汉人世家 | 朝廷文书、门第荣辱 | `evt_imperial_edict` |
| 募兵出身 | 通用军营琐事（高权重兜底） | `evt_dice_debt` |

完整表与 `data/backgrounds.json` 同步维护；**新增背景必须挂至少 2 条专属事件或 1 条专属+权重偏置**。

---

## 三、回答选项（性格主导）

### 3.1 选项过滤

每条选项带 `personality_tags`（满足其一即可显示）或 `personality_required`（必须）：

```json
{
  "id": "take_bribe",
  "text": "收下银子，睁一只眼闭一只眼",
  "personality_any": ["greedy", "cunning"],
  "affection_delta": { "focus": -5, "party_others_avg": -3 },
  "follow_up": null
}
```

| 规则 | 说明 |
|---|---|
| 显示 | 焦点雇佣兵 `personality_id` 命中 `personality_any` / `personality_required` |
| 全队事件 | 选项可标 `who_speaks: focus`，好感 Δ 记在焦点单位；伤及全队用 `party_others_avg` |
| 性格契合 | 选 **契合** 性格的标签项 → 焦点 `affection +小`；选 **违背** 人设的项（若强行提供「克制」选项）→ `+大` 或 `-大` 由策划表定 |
| 玩家 | 永远 2～4 个可见选项；不足时用 `neutral` 通用项兜底（「不多言，按军规办」） |

### 3.2 性格 ↔ 选项风味（示例）

事件：`evt_camp_loot_dispute`（两名雇佣兵争一件缴获）

| 选项 | 可见性格 | 对焦点好感 | 对他人 |
|---|---|---|---|
| 「平分，闹到监军那里谁都不好看」 | `calm`, `disciplined`, `loyal` | +3 | +1 |
| 「老子先拿到的」 | `greedy`, `arrogant`, `glory_hound` | +5（贪财）/ -8（悲悯者在场） | -2 |
| 「让给伤重的兄弟」 | `merciful`, `protective` | +6 | +4 |
| 「干脆赌一把」 | `reckless`, `drunkard` | ±随机 | -1 |

**贪财**在 **商队事件** 里多「私藏货物」项；**好色**在 **营地邂逅** 里多「搭讪/失礼」项——背景决定 **有没有这场戏**，性格决定 **台上能演哪些戏**。

---

## 四、好感度（Affection）

### 4.1 数值与存储

| 项 | 规则 |
|---|---|
| 范围 | `0～100`，招募初始 `50`（传奇招募可 `60`） |
| 可见性 | **默认隐藏**；名册仅氛围文案（亲近 / 冷淡 / 离心）三档提示，Phase 4 可选「军师洞悉」天赋看精确值 |
| 变化来源 | ① 随机事件选项 ② 战斗抉择（弃友、抢功）③ 工资拖欠/赏赐 ④ 性格偏差累计（见 `personality-system.md` §2.1，微量） |
| 下限 | 0 不解雇；触发 **离心 / 叛逃 / 消极** 事件链（Phase 4） |

### 4.2 事件选项 → 好感 Δ

```
选择 option 后：
  focus_unit.affection += option.affection_delta.focus
  foreach ally != focus:
    ally.affection += option.affection_delta.party_others  // 或按性格二次修正
```

- 同一雇佣兵 **同周** 好感净变化 clamp 在 `[-15, +15]`，防刷。
- **残忍**选虐杀选项：焦点 +贪虐玩家认同 +5，**悲悯**性格队友每人 -8。

---

## 五、好感度 → 战斗开局士气

> 战斗内士气五档定义见 `status-effects.md` §三。此处只规定 **开战瞬间** 的初始档位偏移。

### 5.1 映射表（单雇佣兵）

| 好感区间 | 开局 `morale_tier` | 相对默认 |
|---|---|---|
| 75～100 | 稳定 `steady`（80+ 可 20% 概率 **振奋** `inspired`） | 正常或略高 |
| 40～74 | 稳定 `steady` | 基线 |
| 20～39 | **动摇** `shaken` | 天然低一档 |
| 0～19 | **惊惧** `afraid` | 天然低两档 |

实现：`BattleScene._spawn_units()` → `unit.stats.apply_battle_start_morale(affection)`。

### 5.2 设计意图

- 玩家忽视营地对话、总选伤人心的选项 → 下一场硬仗 **开局即亏命中/防**。
- 与战斗内士气升降 **叠加**：低好感开局动摇，再目睹阵亡 → 更快滑向崩溃。
- **Resolve** 检定不改；低好感不直接改属性，只改士气起点。

---

## 六、好感度 → 特殊事件与结局

### 6.1 特殊事件（阈值触发）

| 条件 | 事件类型 |
|---|---|
| 某单位 affection ≥ 85 | 个人 **羁绊营地事件**（赠礼、请求、专属支线入口） |
| 某单位 affection ≤ 15 | **离心预警** → 拒战、消极、叛逃前奏 |
| 全队平均 affection ≥ 70 | **团建/誓师** 类 buff 事件（下一场全员开局振奋概率↑） |
| 关键 NPC（剧情标记）好感 + 章节 | 解锁 **隐藏关卡 / 真结局前置** |

### 6.2 结局影响（Phase 5 框架）

- 结局判定读 **存活雇佣兵好感快照** + **关键选择旗标**（非单一数值）。
- 示例维度：
  - **众将离心**：平均好感 &lt; 35 → 坏结局分支「阵前哗变」资格
  - **忠义长随**：`loyal` 且 affection ≥ 90 的单位存活 → 真结局援军事件
  - **贪财连锁**：多次选贪财选项导致队伍分裂旗标 → 中期金币多但结局少人

详细结局表挂主线设计文档；本文只定义 **好感是结局输入之一**。

---

## 七、数据与流程

### 7.1 文件（规划）

| 文件 | 内容 |
|---|---|
| `data/backgrounds.json` | 背景 id、`event_tags`、`event_weight_mult` |
| `data/camp_events.json` | 事件条件、文案、选项、`personality_*`、`affection_delta` |
| `data/affection_thresholds.json` | 士气映射、特殊事件阈值 |

### 7.2 运行时流程

```
大地图休息 / 营地 tick
  → EventDB.roll(backgrounds_in_party, chapter, cooldowns)
  → 选中 event，定 focus_unit
  → UIEvents.show(event, filter_options_by(focus.personality_id))
  → 玩家选 option
  → AffectionSystem.apply(option.delta)
  → 可能 chain follow_up event

进入战斗
  → 每名友军 apply_battle_start_morale(affection)
```

### 7.3 与性格战场的边界

| 系统 | 场景 |
|---|---|
| `personality-system` §2.1 | **战斗内** AI / 手控偏差 |
| 本文 | **战斗外** 营地/大地图事件与好感 |
| 交叉 | 战斗内「他又在捡钱」可微量 -1 好感（周上限）；低好感再反哺开战士气 |

---

## 八、实施阶段

| Phase | 内容 |
|---|---|
| **3** | `affection` 字段 + 3 条通用事件 + 2 背景专属；选项按 6 性格过滤 |
| **4** | 全背景事件池；好感→开战士气；离心/羁绊事件 |
| **5** | 结局分支输入；隐藏好感显示（可选天赋） |

---

## 九、文档交叉引用

| 文档 | 关系 |
|---|---|
| `class-system.md` §七 | 背景属性与 **事件 tag** SoT |
| `personality-system.md` §三 | 性格列表与 **选项 tag** SoT |
| `status-effects.md` §三 | 士气档位与开战偏移 |
| `economy-system.md` §5.1 | 招募生成：背景 + 性格 + 天赋 |
| `design.md` §人物培养 | 顶层索引 |

---

**文档版本**：v1.0  
**最后更新**：2026-06-11
