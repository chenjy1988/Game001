# FFT 职业系统深度拆解

> 接续 `final-fantasy-tactics.md`（已存在）的 3.4 节，做一份**只针对职业系统**的工程级拆解。
> 你的产品定位明确：**❌ 不做 38 职业，限 5-8 武器原型**。所以本文目标 = **抽出 FFT 职业系统的"骨架"，把规模留在外面**。

---

## 一、职业系统的 5 层结构（FFT 真正的设计精髓）

```
┌─────────────────────────────────────────────────────┐
│ 第 5 层：进阶职业树（38 职业 × 解锁前置）           │
│   Squire → Knight → Monk → Geomancer → ...          │
├─────────────────────────────────────────────────────┤
│ 第 4 层：4 类技能槽（Action / Reaction / Support /  │
│   Movement）+ 主副双槽位                            │
├─────────────────────────────────────────────────────┤
│ 第 3 层：JP 双重作用（学技能 + 升 Job Level）       │
├─────────────────────────────────────────────────────┤
│ 第 2 层：Job Level 是"前置门票"，决定能解锁谁       │
├─────────────────────────────────────────────────────┤
│ 第 1 层：每个职业 = 属性套 + 装备权 + 技能池        │
└─────────────────────────────────────────────────────┘
```

**结论先行**：FFT 的"深度"主要来自 **第 4 层（技能槽设计）+ 第 3 层（JP 复用）**——不是 38 这个数字。
你完全可以用 6-8 个职业 + 完整的 4 槽设计，复刻 90% 的体验。

---

## 二、第 1 层：单个职业 = 5 个数据集（标准模板）

以 Caves of Narshe 给出的 **Knight** 真实数据为例，每个 FFT 职业都由这 5 块组成：

### 2.1 基础属性（4 项静态数值）

| 属性 | Squire | Knight | 含义 |
|---|---|---|---|
| Move | 4 | 3 | 每回合最大移动格数 |
| Jump | 3 | 3 | 能跨越的最大高度差 |
| Speed | 6 | 6 | CT 累加速度 |
| Evade | 5% | 10% | 闪避率 |

### 2.2 成长率：Base × Bonus 双轨（5 项 × ★★★★★）

| 属性 | Squire | Knight | 设计意图 |
|---|---|---|---|
| Attack | ★★★ / ★★★ | ★★★★ / ★★★★ | 物理输出能力 |
| Magic | ★★★ / ★★★ | ★★★★★ / ★★★★ | 魔攻（Knight 居然魔基础高，迷惑设计）|
| HP | ★★★ / ★★★ | ★★★★★ / ★★★★★ | 生命池 |
| MP | ★★ / ★★★ | ★★★ / ★★★★★ | 法力池 |
| Speed | ★★ / ★★★ | ★★★ / ★★★ | 速度成长 |

> **关键机制**：左边是"基础"——决定你**这一职业**的当前数值；右边是"加成"——决定你**升级时**实际涨多少。
> 这就是为什么 FFT 玩家会**故意在低成长职业里升级，再切高成长职业战斗**——属性是"永久 stack"的。
> ⚠️ 这条机制虽然有趣，但**新人极难理解**，是 FFT 上手地狱的根源之一。**建议你不要照搬。**

### 2.3 Action 技能列表（带 JP 价格）

**Knight 的"Battle Skill"技能组**：

| 技能 | 效果 | JP |
|---|---|---|
| Rend Helm | 破坏头盔 | 300 |
| Rend Armor | 破坏护甲 | 400 |
| Rend Shield | 破坏盾 | 300 |
| Rend Weapon | 破坏武器 | 400 |
| Rend MP | 削 MP | 250 |
| Rend Speed | 减 Speed | 250 |
| Rend Power | 减 PA | 250 |
| Rend Magick | 减 MA | 250 |

**主题非常清晰**：Knight = "破坏者"，所有 Action 技能都围绕"破装备 / 破属性"。
Squire 的 4 个技能（Focus/Rush/Throw Stone/Heal）则是"杂工" —— 这就是设计风格化。

### 2.4 Reaction / Support / Movement 池（被动技能）

| 类型 | Knight 提供 | JP |
|---|---|---|
| **Reaction** | Weapon Guard（武器格挡） | 200 |
| **Support** | Equip Armor / Equip Shield / Equip Sword（让其他职业能装这些） | 500/250/400 |
| **Movement** | （Knight 无） | — |

**重大发现**：FFT 的 **Support 技能本质就是"装备权交易市场"**——
> 任何职业想穿重甲？去 Knight 学 Equip Armor（500 JP）。
> 任何职业想用斧？去 Squire 学 Equip Axe（170 JP）。
> 所以 **38 职业的"装备权差异"反而成了第二层 build 空间**。

### 2.5 装备权限（隐式表达）

Knight 原生可装：剑 / 盾 / 重甲 / 头盔 → 这又把"职业身份"和"装备绑定"。

---

## 三、第 2-3 层：JP 与 Job Level 的双重作用（最容易被忽视的天才设计）

### 3.1 一份 JP，两个用途

```
单位行动 → 获得 JP（基础 10 / 旁观 5）
            │
            ├── 用途 A：累积总 JP → 提升 Job Level
            │     Job Level 决定能解锁哪些进阶职业
            │
            └── 用途 B：花费 JP → 学习该职业的具体技能
                  （Action / Reaction / Support / Movement）
```

> **这是 FFT 的**"省一点是一点"**——同一个数值同时承担两个进度系统。**

### 3.2 JP 获得规则（实测）

| 行为 | JP |
|---|---|
| **行动者** 成功执行任意 Action（攻击 / 技能 / 道具） | **10** |
| **旁观者**（同职业友军见证行动者出招） | **5** |
| 单纯移动 | **0** |
| Reaction 触发 | **0**（不算"主动行动"） |
| JP Boost 被动 | **× 1.5** |

→ 衍生出"**Tailwind / Chocobo 互刷套路**"：4 名同职业兄弟围在一起轮流给彼此 buff，每回合每人净得 10+5×3 = 25 JP。
→ **这就是 grind 的根源**。FFT 的"刷 JP"被吐槽到死。

### 3.3 Job Level 解锁链（IGN 实证完整数据）

| 职业 | 解锁条件 |
|---|---|
| Squire / Chemist | 默认 |
| Knight / Archer | Squire Lv.2 |
| Monk | Knight Lv.3 |
| White Mage / Black Mage | Chemist Lv.2 |
| Time Mage | Black Mage Lv.3 |
| Summoner | Time Mage Lv.3 |
| Mystic | White Mage Lv.3 |
| Orator | Mystic Lv.3 |
| Thief | Archer Lv.3 |
| Geomancer | Monk Lv.4 |
| Dragoon | Thief Lv.4 |
| **Samurai** | **Knight Lv.4 + Monk Lv.5 + Dragoon Lv.2** |
| **Ninja** | **Archer Lv.4 + Thief Lv.5 + Geomancer Lv.2** |
| **Arithmetician** | **WMg Lv.5 + BMg Lv.5 + TMg Lv.4 + Mystic Lv.4** |
| Bard（仅男性）| Summoner Lv.5 + Orator Lv.5 |
| Dancer（仅女性）| Geomancer Lv.5 + Dragoon Lv.5 |
| **Mime** | Squire Lv.8 + Chemist Lv.8 + Summoner Lv.5 + Orator Lv.5 + Geomancer Lv.5 + Dragoon Lv.5 |

**模式提取**（这是真正可借鉴的部分）：

```
入门职业（2 个）→ 初级分支（4 个，需 Lv.2-3）
   → 中级专精（4 个，需 Lv.3-4）
   → 高级混血（3 个，需 2-3 个前置 Lv.4-5）
   → 终极职业（1-2 个，需 4+ 个前置 Lv.5-8）
```

**对你的启示**：你的 5-8 武器原型可以做成同样的"梯度"：
- 2 个起步武器 → 3-4 个中级 → 1-2 个高级混搭 → 1 个终极。
- 用 Job Level 做门槛，而不是"等级"。

---

## 四、第 4 层：4 类技能槽 ⭐（最值得抄的部分）

### 4.1 5 个槽位的精确划分

每个角色出战时持有 **5 个技能槽**：

| # | 槽位 | 数量 | 来源 | 切换灵活度 |
|---|---|---|---|---|
| 1 | **Action - Primary** | 1 | **当前主职业（强制锁定）** | ❌ 不可换，跟着主职走 |
| 2 | **Action - Secondary** | 1 | 任一已学职业的 Action 池 | ✅ 战外自由换 |
| 3 | **Reaction** | 1 | 任一已学的 Reaction | ✅ 战外自由换 |
| 4 | **Support** | 1 | 任一已学的 Support | ✅ 战外自由换 |
| 5 | **Movement** | 1 | 任一已学的 Movement | ✅ 战外自由换 |

> **关键不对称**：主 Action 必须跟着主职走，副 Action 完全自由 —— 这一条规则单独造就了 FFT 的"职业组合"玩法。

### 4.2 各槽位职责（设计意图反推）

| 槽 | 设计意图 | 代表技能 |
|---|---|---|
| **Action** | 主动操作的"动词" | 攻击、施法、投掷、Rend、Throw Stone |
| **Reaction** | 被动响应敌方动作 | Counter（反击）、Weapon Guard（武器格挡）、Auto-Potion（HP 低自动喝药）、HP Restore |
| **Support** | 永久 buff / 装备权 | Equip Sword（让法师拿剑）、JP Boost、Two Swords（双持）、Defend |
| **Movement** | 改变移动方式 | Move +1（移动 +1 格）、Teleport（瞬移）、Move-HP Up（每移动一格回血） |

> **这就是 FFT 的"动词框架"**：
> - Action = 主动出招
> - Reaction = 被动还手
> - Support = 永久身份（穿什么、拿什么、JP 怎么涨）
> - Movement = 移动方式
> 4 个槽位**互不重叠**，玩家组合时不会冲突，**这是 build diversity 的根本保证**。

### 4.3 跨职业借用 = build 空间爆炸

**举例：Knight 主 + Time Mage 副**
- 主 Action：Battle Skill（破装备）
- 副 Action：Time Magic（Haste / Slow / Stop / Teleport2）
- Reaction：Weapon Guard（Knight 学的）
- Support：Short Charge（缩咏唱时间，从 Time Mage 学）
- Movement：Teleport（从 Time Mage 学）

→ 一个穿重甲的物理战士，会瞬移、能减速敌人、还能把魔法咏唱时间砍半。
→ **这套灵活度，是 BB（背景天赋只能选 2 个）和 TO（职业切换损失等级）都做不到的**。

### 4.4 副 Action 的 JP 流向（关键设计）

> 你装着 White Mage 当副 Action 战斗 → 你扔出的所有 White Magic 都计入 **White Mage 的 JP 池**。
> 这意味着：**你可以一边当 Knight 主战，一边偷偷把 White Mage 升级**。

→ 这是 FFT "玩家替代刷级"的核心机制。
→ ⚠️ 但也是 grind 灾难的根源 —— 玩家会"为了升 Job 而做无用动作"。

---

## 五、对你项目的工程化建议（按"抄 vs 改 vs 弃"分类）

### ✅ **直接抄**（FFT 真正天才的部分）

#### A1. 4 类技能槽（Action / Reaction / Support / Movement）
```gdscript
# scripts/core/Unit.gd
class_name Unit
var primary_class: WeaponClass            # 主武器原型（≈ FFT 主职）
var action_primary: Array[Skill]          # 主职 Action 池（强制锁定）
var action_secondary: Array[Skill]        # 副职 Action 池（自由切换）
var reaction: Skill                        # 1 个反应
var support: Skill                         # 1 个支援
var movement: Skill                        # 1 个移动
```

→ 即便你只有 6 个武器原型，每个原型给 4-6 个 Action + 1-2 个 Reaction + 1-2 个 Support + 1 个 Movement，
   就能产生 6 × 6 × 6 × 6 × 6 = **7776 种 build**。深度爆炸。

#### A2. JP 双重作用（解锁货币 + 升级数值）
- 不要做"等级 + JP"两套货币，**复用一套**：
  - 累积 JP → 提升武器熟练度（≈ Job Level）
  - 消耗 JP → 学具体技能
- 熟练度等级 → 解锁更高阶武器原型

#### A3. 旁观 JP（同武器友军获得 50%）
- 鼓励队伍多样性而非"一个万金油主角"
- 但**要克制**：FFT 这个机制是 grind 灾难的源头之一。
  - **建议**：旁观 JP 改成"每场战斗结算时"算一次，而不是"每次行动"。

#### A4. 装备权限作为 Support 技能交易
- "Equip Heavy Armor"、"Equip Crossbow" 作为可学的 Support
- 让"魔法师穿重甲"变成有代价的 build 选择，而不是默认禁止

### 🟡 **改良后用**（精神保留，规模砍掉）

#### B1. 武器原型而非 38 职业（你已经定了）
| FFT | 你的项目 |
|---|---|
| 38 职业 | 6-8 武器原型 |
| Job Level | 武器熟练度 |
| 主职业 + 副职业槽 | 主武器 + 1 副 Action 池 |
| 单角色可换所有职业 | 单角色可换所有武器原型 |

#### B2. 解锁链：用"梯度"而非"穷举"
```
入门：剑 / 弓
   ↓ 武器熟练度 Lv.2
中级：双手斧 / 长矛 / 法杖 / 匕首
   ↓ 多个前置 Lv.3
高级：双手剑（Knight 风）/ 弩 / 战锤
   ↓ 多个前置 Lv.5
终极：双持 / 重弩
```

→ 用 4 层梯度替代 38 职业的复杂度，但保留"长期目标驱动"。

#### B3. 双轨成长：保留"基础+加成"思路，但不做星级
- FFT 的 Base/Bonus 双轨太复杂、新人不可见
- 改为：**职业固定属性 + 简单等级成长**，把"职业切换的 stat 优化"完全砍掉
- 想要"build 深度" → 通过技能槽实现，而不是属性优化

### ❌ **绝对不抄**（FFT 的坑）

| FFT 设计 | 为什么不抄 | 替代方案 |
|---|---|---|
| 性别限制（Bard 只男 / Dancer 只女）| 1997 年的产物，今天会被骂 | **不做** |
| 在低成长职业刷级再切高成长 | 隐藏机制，新人地狱 | **属性成长固定不变** |
| 38 职业完全解锁要 80 小时 | grind 灾难 | **6-8 武器原型，30 小时全解锁** |
| Mime 需要 6 个前置职业 Lv.5+ | 终极职业门槛太高，普通玩家见不到 | **终极武器只需 2-3 个前置** |
| 副 Action 用了也涨副职业 JP | grind 互刷套路源头 | **JP 只在结算时按"实际贡献"分配** |
| 必杀技 30 秒 cutscene | 你 design.md 已经标注 | **所有动画必须可跳过** |

---

## 六、一份"最小可跑"的职业系统数据结构（直接给你）

```gdscript
# scripts/core/data/JobClass.gd
class_name JobClass extends Resource

@export var id: String                      # "knight" / "archer" / ...
@export var display_name: String

# 第 1 层：基础属性
@export var move: int = 4
@export var jump: int = 3
@export var speed: int = 6
@export var evade: int = 5

# 第 2 层：固定属性修正（不做双轨成长，避免 FFT 复杂度）
@export var hp_mult: float = 1.0
@export var atk_mult: float = 1.0
@export var def_mult: float = 1.0

# 第 3 层：技能池（按 4 槽分类）
@export var action_skills: Array[SkillData]      # 主职专属 Action
@export var reaction_skills: Array[SkillData]    # 该职业能学的 Reaction
@export var support_skills: Array[SkillData]     # 该职业能学的 Support
@export var movement_skills: Array[SkillData]    # 该职业能学的 Movement

# 第 4 层：装备权限（原生可装）
@export var native_weapons: Array[String] = []   # ["sword", "shield"]
@export var native_armors: Array[String] = []    # ["heavy"]

# 第 5 层：解锁条件
@export var prerequisites: Array[Dictionary] = []  # [{"job": "squire", "level": 2}]
```

```gdscript
# scripts/core/data/SkillData.gd
class_name SkillData extends Resource

enum SkillType { ACTION, REACTION, SUPPORT, MOVEMENT }

@export var id: String
@export var display_name: String
@export var type: SkillType
@export var jp_cost: int                  # 学习需要的 JP
@export var description: String
# Action 专用
@export var range: int = 1
@export var aoe: int = 1
@export var ap_cost: int = 4
@export var charge_time: int = 0          # ≥0 时为咏唱技能（FFT 核心）
@export var effect: Callable              # 实际效果回调
```

```gdscript
# scripts/core/Unit.gd
class_name Unit extends Node2D

# 已学职业（id → JP 累计）
var jobs_jp: Dictionary = {}              # {"knight": 540, "archer": 230}
var jobs_learned_skills: Dictionary = {}  # {"knight": ["rend_helm"], ...}

# 当前装配
var current_job: String = "squire"
var equipped_secondary_action: String = ""    # 副 Action 池来自哪个职业
var equipped_reaction: SkillData = null
var equipped_support: SkillData = null
var equipped_movement: SkillData = null

func gain_jp(amount: int, job_id: String) -> void:
    var bonus = 1.5 if has_support("jp_boost") else 1.0
    jobs_jp[job_id] = jobs_jp.get(job_id, 0) + int(amount * bonus)

func get_job_level(job_id: String) -> int:
    # 简单的 JP → Lv 转换：100/250/450/700/1000/...（递增）
    var jp = jobs_jp.get(job_id, 0)
    return JP_TO_LEVEL_TABLE.find_floor(jp)
```

---

## 七、一句话提炼

> **FFT 职业系统的精髓 = 4 类技能槽 × JP 双重作用 × Job Level 梯度解锁**。
> 38 这个数字、性别限制、属性双轨成长，都只是 1997 年的时代产物。
>
> 你完全可以用 **6-8 个武器原型** 复刻这套系统，而且**比 FFT 更友好**：
> - 用槽位而非数量制造深度
> - 用熟练度梯度而非性别/等级强制
> - 用结算 JP 而非互刷 JP 杜绝 grind
> - 把"基础+加成"双轨砍成单轨，新人秒懂

---

## 八、引用

- [IGN: All Jobs and Requirements](https://www.ign.com/wikis/final-fantasy-tactics-the-ivalice-chronicles/All_Jobs_and_Requirements_in_Final_Fantasy_Tactics) — 完整 38 职业解锁表
- [IGN: How to Level Up Fast](https://www.ign.com/wikis/final-fantasy-tactics-the-ivalice-chronicles/How_to_Level_Up_Fast) — JP 与 Job Level 机制
- [Caves of Narshe: Squire 完整页面](https://www.cavesofnarshe.com/fft/w_job.php?job=psx::Squire) — 职业页面骨架
- [Caves of Narshe: Knight 完整页面](https://www.cavesofnarshe.com/fft/w_job.php?job=psx::Knight) — 含完整 Action/Reaction/Support/Movement 数据 + JP 价格
- [Caves of Narshe: Jobs 列表](https://www.cavesofnarshe.com/fft/jobs.php) — 22 职业完整列表（WotL）
- [Final Fantasy Wiki: FFT Jobs](https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_jobs) — 系列权威源
- [Final Fantasy Wiki: FFT Abilities](https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_abilities) — 技能系统权威源
- [天幻网 FFT 能力一览](http://fft.ffsky.cn/ability.htm) — 中文老资料，1999 年起
- 已有：项目内 `final-fantasy-tactics.md` 第 3.4 节（本文是其延伸）
