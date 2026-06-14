# AI 行动逻辑设计（决策核心准则）

> **核心准则**：**保全自身的前提下，尽可能杀伤敌方。**
>
> AI 采用 **统一候选池 + 风格权重表（Weighted Utility AI）** 架构：
>   - **风格层**：根据兵种、状态、战场局面，输出一张「权重表」（不过滤动作）。
>   - **评分层**：所有动作（进攻/防守/援助/撤退）始终全部参与评分，与权重表相乘后取最高。
>   - 不存在"风格切换 → 候选过滤"，权重表给每类动作的分数做缩放，由数据自然选出最优。

---

## 〇、为什么是「权重表」而不是「过滤器」

### 旧思路（已废弃）：风格过滤候选

```
Step1 选风格 = SUPPORT
Step2 只生成援助候选
Step3 选不到 → 切回 ATTACK 重选 → 再不行 → 切 DEFEND
→ "援助够不着就切风格"
```

**问题**：
- 风格切换链路复杂，回合内反复切换 → AI 鬼畜
- 援助候选池里走 1 步 OA 高 → 没考虑同类的「换位」「远程激励」
- 单点失败导致整个意图被放弃，浪费角色能力

### 新思路：统一候选池 × 风格权重

```
Step1 兵种 + 状态 → 权重表 { atk:1.5, def:0.5, sup:0.8, ret:0.3 }
Step2 生成所有候选（攻+防+援+退）→ 每类乘对应权重 → 全局取最高
Step3 执行后回 Step1 重算权重表
```

**优势**：
- ✅ 援助走 1 步 OA 高 → 同类的「换位」「远程激励」自动顶上（同表 1.5×）
- ✅ 援助全队失败 → 进攻类（0.6×）已在池中，自动接管，无需"切换"
- ✅ 权重表稳定 1 回合 → 战略意图维持，不鬼畜
- ✅ 调参聚焦：每兵种一张权重表，行为差异化清晰

---

## 一、决策三步走

```
                  ┌──────────────────────────────────┐
       Step 1     │  风格判定 → 权重表                 │
   "我现在偏好啥"  │  weights = { atk, def, sup, ret }  │
                  └──────────────┬───────────────────┘
                                 ↓
                  ┌──────────────────────────────────┐
       Step 2     │  统一候选池 × 权重 → 取最高分      │
   "全局打分选最优" │  所有动作（攻+防+援+退）参与评分    │
                  └──────────────┬───────────────────┘
                                 ↓
                  ┌──────────────────────────────────┐
       Step 3     │  执行 + 链式重决策                  │
   "动完再看一眼"  │  原子动作执行后回 Step 1            │
                  └──────────────────────────────────┘
```

---

## 二、Step 1 — 风格判定（输出权重表）

### 2.1 输入维度

| 维度 | 取值 | 来源 |
|---|---|---|
| **职业** | 18 个战斗职业之一（跳荡/枪兵/陌刀手/弩手/铁骑/僧兵 …） | `unit.job_id` |
| **HP 状态** | full(>70%) / wounded(30~70%) / critical(<30%) | `hp / max_hp` |
| **护甲状态** | intact(>50%) / damaged(<50%) / broken(=0) | `body_armor / max_body_armor` |
| **气力档位** | fresh(>50%) / steady / wavering / fatigued(<10%) | `fatigue / max_stamina` |
| **战场局面** | dominant / parity / pressured / collapsing | FactionBrain 阵营快照 |
| **盟友危机** | none / wounded / dying / surrounded | 盟友 HP + 邻敌数 |
| **远程优势** | enemy_adv / parity / ally_adv | 双方远程单位数对比 |
| **武器特性** | melee_only / ranged_main / hybrid | `unit.weapon` |

### 2.2 风格输出（权重表）

```
weights = {
  attack:  Float,   # 进攻类候选评分缩放
  defend:  Float,   # 防御类（架盾/Wait）评分缩放
  support: Float,   # 援助类（治疗/换位/buff）评分缩放
  retreat: Float,   # 撤退类（逃离/拉开距离）评分缩放
}
```

**关键约束**：权重不为零（除极端情况）。**风格不过滤候选**，永远保留至少 0.2~0.3 的 fallback，保证候选池始终非空。

### 2.3 职业基础权重表（18 个战斗职业 + 阵营修饰）

> **设计原则**：权重表来自三处合成：① 职业基线 ② 武器/装备倾向 ③ 阵营预设（敌方军阀的兵团风格）。
> 核心准则的体现：所有职业 attack 都不为零（红线：不存在打不动人的上场单位），但「靠攻击吃饭还是靠走位/控制吃饭」差异巨大。

#### 2.3.1 基础四职业

| 职业 | attack | defend | support | retreat | reposition¹ | 设计意图 |
|---|---|---|---|---|---|---|
| **跳荡**       | **1.4** | 1.0 | 0.4 | 0.2 | 0.6 | 突击+盾防双修，主攻不畏冲，兼顾队友守护 |
| **枪兵**       | 1.0     | **1.5** | 0.4 | 0.2 | 0.5 | 阵列防御为本，架枪反击优于硬冲 |
| **奇兵**       | **1.3** | 0.7 | 0.3 | 0.5 | **0.9** | 机动近战 + 副弓骚扰，打了就跑 |
| **斥候**       | 0.9     | 0.5 | **0.7** | **0.9** | **1.0** | 视野/标记/牵引，弱攻避战 |

#### 2.3.2 上级近战职业

| 职业 | attack | defend | support | retreat | reposition | 设计意图 |
|---|---|---|---|---|---|---|
| **陌刀手**     | **1.7** | 0.8 | 0.2 | 0.1 | 0.5 | 横扫范围爆发，主动找密集人群 |
| **押衙亲兵**   | 1.0     | **1.6** | **0.9** | 0.2 | 0.5 | 顶级近卫，护卫弱后排为优先 |
| **铁骑**       | **1.8** | 0.7 | 0.2 | 0.1 | **1.2** | 直线冲锋核心，距离越足越爱冲 |
| **悍卒**       | **1.9** | 0.3 | 0.1 | 0.1 | 0.4 | 狂暴自损流，谁挡杀谁不计代价 |
| **游侠** ⭐    | **1.5** | 0.9 | 0.3 | 0.6 | **1.1** | 闪避反击 + 闪击位移 |
| **僧兵**       | 1.1     | **1.4** | **0.9** | 0.3 | 0.6 | 棍法控场 + 念力护体（Wisdom 系） |

#### 2.3.3 上级骑射 / 远程职业

| 职业 | attack | defend | support | retreat | reposition | 设计意图 |
|---|---|---|---|---|---|---|
| **弩手**       | **1.5** | 0.9 | 0.2 | **0.8** | 0.7 | 上弦节奏慢，避免贴脸；近身切横刀兜底 |
| **轻骑**       | **1.4** | 0.5 | 0.3 | **1.0** | **1.4** | 游击骚扰 / 残敌收割，不与阵线硬碰 |
| **蕃骑**       | **1.5** | 0.4 | 0.3 | **1.1** | **1.3** | 复合弓骑射，机动性优先 |
| **游奕都巡官** | 1.2     | 0.7 | **0.8** | 0.7 | **1.1** | 巡防/反伏击/指挥型骑射 |

#### 2.3.4 上级控场 / 辅助型职业

| 职业 | attack | defend | support | retreat | reposition | 设计意图 |
|---|---|---|---|---|---|---|
| **虞候**       | 0.8     | 1.1 | **1.5** | 0.3 | 0.5 | 督战 / 军法，给队友加 Resolve |
| **诗剑仙**     | **1.4** | 0.5 | **0.9** | 0.4 | **1.0** | 剑舞输出 + 吟唱 buff（Wisdom 系） |
| **方士战兵**   | 0.6     | 0.7 | **1.6** | 0.5 | 0.7 | 元素地形 + 太极推手，控场为本 |
| **不良人**     | **1.5** | 0.4 | 0.4 | **0.8** | **1.3** | 高 Init 暗杀，找残血/落单点杀 |

¹ **reposition**（位移类）独立成第 5 类权重，覆盖：擒拿拉拽、推撞、换位、滑步、瞬步、冲锋推退、扫杆逼退、移形等技能。

---

### 2.3.5 武器/装备修饰（在职业基线上叠乘）

> 同一职业带不同武器，行为应不同。例如「斥候带短弓」vs「斥候带匕首」差别巨大。

```
持远程武器（步弓 / 擘张弩 / 复合弓）为主：
  × { atk: 1.0, def: 1.0, ret: × 1.3, reposition: × 1.2 }   # 远程更怕贴脸

持双手大武器（陌刀 / 长枪 / 战锤 / 战斧）：
  × { atk: 1.2, def: 0.9, support: 0.7 }                     # 没盾更进攻

持团牌（盾）：
  × { atk: 0.95, def: 1.3, support: 1.2 }                    # 盾T倾向防守与护卫

持匕首/双匕：
  × { atk: 1.15, defend: 0.85, reposition: 1.2 }            # 灵巧打法
```

---

### 2.3.6 阵营 / 兵团预设（FactionBrain 层）

不同势力的同一职业应有差异化战法。**阵营给所有己方单位再叠一次乘**：

| 阵营预设 | 修饰 | 风格描述 |
|---|---|---|
| **强盗团**（disorganized） | × { atk: 1.1, support: 0.6, retreat: 1.3 } | 各打各的，残血就跑 |
| **朔方边军**（disciplined） | × { atk: 1.0, defend: 1.2, support: 1.3 } | 阵列推进，互相援护 |
| **狂热邪教**（fanatic）   | × { atk: 1.3, retreat: 0.3, support: 0.5 } | 不要命，进攻死战 |
| **精锐宿卫**（elite_guard）| × { atk: 1.0, defend: 1.3, support: 1.5 } | 团结严密，集火护卫 |
| **逃亡流民**（rabble）    | × { atk: 0.7, retreat: 1.5, defend: 1.0 } | 战意低落，残血即溃 |

### 2.4 状态/局面修正（叠加乘）

```
HP 修正：
  full       → × { atk: 1.0, ret: 0.5 }
  wounded    → × { atk: 0.85, def: 1.2, ret: 1.2 }
  critical   → × { atk: 0.5, def: 1.0, ret: 2.0, reposition: 1.5 }   # 残血时往安全格走

护甲修正：
  body_armor broken → × { def: 0.7, retreat: 1.4 }    # 甲废了别站桩，撤

气力修正：
  fatigued (<10%)   → × { atk: 0.5, retreat: 1.3, support: 0.6 }    # 力竭只能挣扎
  wavering (<30%)   → × { atk: 0.85, defend: 1.1 }

盟友危机修正（仅当自己有援助手段时）：
  ally dying        → × { support: 2.0, atk: 0.6 }
  ally surrounded   → × { support: 1.5, reposition: 1.3 }   # 救援+换位

战场局面修正（FactionBrain）：
  collapsing → × { atk: 0.5, ret: 1.8 }              # 全军溃败，撤
  pressured  → × { atk: 0.85, def: 1.2 }
  parity     → × { /* 不变 */ }
  dominant   → × { atk: 1.3, def: 0.7 }              # 占优压上

远程优势修正：
  enemy_ranged_adv → × { atk: 1.3, def: 0.5, reposition: 1.4 }  # 敌方有弓 → 必须冲或绕侧
  ally_ranged_adv  → × { atk: 0.7, def: 1.5 }                    # 我方有弓 → 等敌人来

对位修正（敌方阵容触发）：
  对方有大量重甲     → × { reposition: 1.3 }   # 自己是匕首/弓 → 想办法绕到甲薄
  对方有 1 个核心    → × { atk: 1.4 if 自己能集火该核心 else 1.0 }   # 集火加成
```

### 2.5 完整示例（用项目真实职业）

#### 示例 1：陌刀手 + 朔方边军 + HP 60% + 战场胶着

```
基础（陌刀手）        : { atk: 1.7,   def: 0.8,  sup: 0.2,  ret: 0.1,  rep: 0.5 }
× 武器（陌刀双手大）  : { atk: 2.04,  def: 0.72, sup: 0.14, ret: 0.1,  rep: 0.5 }
× 阵营（朔方边军）    : { atk: 2.04,  def: 0.86, sup: 0.18, ret: 0.1,  rep: 0.5 }
× wounded            : { atk: 1.73,  def: 1.04, sup: 0.18, ret: 0.12, rep: 0.5 }
× parity             : { /* 不变 */ }

→ Attack 主导（1.73），找密集人群挥陌刀；负伤但不撤
```

#### 示例 2：弩手 + 朔方边军 + 敌方贴脸 + HP 80%

```
基础（弩手）          : { atk: 1.5,  def: 0.9,  sup: 0.2,  ret: 0.8,  rep: 0.7 }
× 武器（擘张弩远程）  : { atk: 1.5,  def: 0.9,  sup: 0.2,  ret: 1.04, rep: 0.84 }
× 阵营（朔方边军）    : { atk: 1.5,  def: 1.08, sup: 0.26, ret: 1.04, rep: 0.84 }
× full HP            : { /* atk 不变, ret 0.5 → 0.52 */ }
× pressured          : { atk: 1.28, def: 1.30, sup: 0.26, ret: 0.52, rep: 0.84 }

→ Defend 略高于 Attack —— 切横刀格挡 / Wait 等队友支援
  Attack 候选仍参与，但只在「邻敌残血一击必杀」时才能压过 Defend
```

#### 示例 3：游侠 + 队友被围 dying + HP 100%

```
基础（游侠 ⭐）       : { atk: 1.5,  def: 0.9,  sup: 0.3,  ret: 0.6,  rep: 1.1 }
× 武器（双匕）        : { atk: 1.73, def: 0.77, sup: 0.3,  ret: 0.6,  rep: 1.32 }
× 阵营（朔方边军）    : { atk: 1.73, def: 0.92, sup: 0.39, ret: 0.6,  rep: 1.32 }
× ally_dying         : { atk: 1.04, def: 0.92, sup: 0.78, ret: 0.6,  rep: 1.32 }
× ally_surrounded    : { atk: 1.04, def: 0.92, sup: 1.17, ret: 0.6,  rep: 1.72 }

→ Reposition (1.72) 主导：换位救人 / 滑步穿 ZoC 接敌
  Support (1.17) 次之；游侠没主动治疗，但可以"闪击"敌人为友军解围
  Attack (1.04) 仍在候选——若顺路斩杀威胁友军的那个敌人，照样上
```

#### 示例 4：强盗团跳荡 + HP 25% + 队友全死

```
基础（跳荡）          : { atk: 1.4,  def: 1.0,  sup: 0.4,  ret: 0.2,  rep: 0.6 }
× 武器（横刀+团牌）   : { atk: 1.33, def: 1.30, sup: 0.48, ret: 0.2,  rep: 0.6 }
× 阵营（强盗团）      : { atk: 1.46, def: 1.30, sup: 0.29, ret: 0.26, rep: 0.6 }
× critical            : { atk: 0.73, def: 1.30, sup: 0.29, ret: 0.52, rep: 0.9 }
× collapsing          : { atk: 0.37, def: 0.91, sup: 0.29, ret: 0.94, rep: 0.9 }

→ Retreat (0.94) ≈ Reposition (0.9) ≈ Defend (0.91) 三足鼎立
  逃命（强盗团特性）+ 找掩体（撤退/换位）+ 抱盾死磕（没退路时）
  Attack (0.37) 几乎绝迹——除非邻敌 1HP 残血一击必杀
```

---

## 三、Step 2 — 统一候选池 × 权重 → 取最高分

### 3.1 候选池：永远囊括五类

每个回合都生成所有五类候选，**不因风格过滤任何一类**：

```
candidates = []

# 1. 进攻类（× weights.attack）
for pos in [当前位置] + 走 1 格落点 + 走 2 格落点:
  for target in 该位置射程内敌人:
    for mode in 攻击模式:                        # pierce/slash/crush
      candidates.append({
        category: "attack",
        action: ATTACK(pos, target, mode),
        score: TargetScore - 走位风险
      })

# 2. 防御类（× weights.defend）
for ability in 防御技能（盾牌格挡/架枪/镇阵/野战八方）:
  candidates.append({
    category: "defend",
    action: USE_DEFENSE(ability),
    score: 减伤期望 × 邻敌数
  })
candidates.append({ category: "defend", action: WAIT, score: Wait 评分 })

# 3. 援助类（× weights.support）
for ally in 需要援助的盟友:
  for ability in 援助手段（包扎/振奋军心/持盾护卫/督战/标记…）:
    for path in 到位的路径（含原地）:
      candidates.append({
        category: "support",
        action: ASSIST(ability, ally, path),
        score: 援助价值 - 走位风险
      })

# 4. 位移类（× weights.reposition）—— 独立第 5 类
for ability in 位移技能（换位/滑步/擒拿拉拽/推撞/瞬步/突击冲锋…）:
  for params in 位移参数（目标格 / 推拉对象 / 距离）:
    candidates.append({
      category: "reposition",
      action: USE_MOVEMENT(ability, params),
      score: 位移价值 - OA 风险
    })

# 5. 撤退类（× weights.retreat）
for dest in 远离敌人的落点:
  candidates.append({
    category: "retreat",
    action: RETREAT(dest),
    score: 撤退评分
  })
```

> **关键**：**位移类 (reposition) 与 进攻/援助/撤退 是平级**。冲撞、移形、换位虽然都"涉及移动"，但本质是「改变位置」的战术工具，不是「逃跑」（retreat）也不是「援助」（support）。  
> 例如「冲撞推敌人下悬崖」属于 reposition；「换位救人」属于 support 与 reposition 都生成候选，分别打分参与竞争。

### 3.2 评分加权 + 选择

```gdscript
for c in candidates:
    var w = weights[c.category]            # 该类动作的权重
    c.final = c.score * w

best = candidates.argmax(c → c.final)
return best.action
```

### 3.3 最关键的回答：援助 OA 高怎么办

**不切风格，不另选援助。让评分系统自动选同类的更优解，或落到进攻**：

```
场景：押衙亲兵（持盾），队友弩手 HP 20% 被 2 个敌兵围攻
权重表：{ atk: 0.6, def: 1.5, sup: 1.8, ret: 0.2, rep: 0.65 }
       （base × ally_dying × ally_surrounded）

候选池（所有列出，按 final 排序）：

援助类（× 1.8）：
  ① 走 1 步 + 持盾护卫弩手（路径 OA 60%）
     score = 90 × (1 - 0.6) = 36   → final = 65
  ② 原地呼喊"振奋军心"buff
     score = 30 × 1.0 = 30          → final = 54

位移类（× 0.65）：
  ③ 走 1 步 + 换位（自己换到弩手位置）
     score = 80 × (1 - 0.4) = 48    → final = 31
  ④ 推撞（把贴脸敌兵推开）
     score = 70 × 1.0 = 70          → final = 46

进攻类（× 0.6）：
  ⑤ 攻击围攻弩手的敌兵 A
     score = 90 × 1.0 = 90          → final = 54
  ⑥ 走 1 步攻击敌兵 B
     score = 80 × (1 - 0.4) = 48    → final = 29

防御类（× 1.5）：
  ⑦ 镇阵（自保）
     score = 30 × 1.0 = 30          → final = 45
  ⑧ Wait
     score = 20 × 1.0 = 20          → final = 30

→ 选 ① 持盾护卫弩手（final = 65）
   即使路径 OA 高（60%），援助权重 ×1.8 让它仍是最优解
   退一步：若 ① 不可达（AP 不足），② 振奋军心（final = 54）= ⑤ 攻击 A（final = 54）
   两者 final 相同 → AI 倾向援助类（更稳）
```

**注意**：哪怕援助全失败（所有援助 final < 进攻），进攻类候选已在池中，AI 自动转去打架，**完全不需要"切换风格"逻辑**。

### 3.4 边界：候选池为空

```
所有候选 final = 0：
  → 无 AP / 无可达落点 / 无敌人 / 无盟友需要援助
  → END_TURN（结束回合）
```

---

## 四、各类动作的内部评分

### 4.1 进攻动作评分（TargetScore）

```
score = 命中率^1.1 × 0.35
      + (期望伤害 / 目标最大HP) × 0.25
      + (1 - 目标HP比例) × 0.40
      × kill_mult       (期望伤害 ≥ 剩余 HP 或 HP < 50%)   ×3.0
      × counter_mult    (目标会反击)                      ×0.6
      × ranged_mult     (目标是远程，需要拆掉)             ×1.25
      × ally_focus_mult (友方包围的集火目标)               ×1.3
      × armor_mult      (已破甲)                          ×1.4

走位修正（叠加在路径化候选上）：
  + 走完仍在 range_max 距离              +30
  + 走完有侧/背攻击位                    +15
  + 落点是高地                          +10
  - 路径上每格 ZoC                      -10
  - 落点被多个敌方威胁                  -8/敌
  - 走位消耗导致下回合 AP 不足           -20
```

### 4.2 防御动作评分

| 候选 | 公式 |
|---|---|
| 架盾/防御技能 | 减伤量 × 邻敌数 × 邻敌期望命中 |
| Wait | 友方距离收敛速度 - 敌方逼近速度 |
| 后撤地形点 | 地形防御加成 + 与友方距离 |

### 4.3 援助动作评分（无治疗系下的项目落地）

> **项目红线**：战斗内不能回 HP（class-system §一）。所以援助≠治疗，主要靠 **保护、控场、增益、护卫、解状态**。

```
score = 援助价值 × (1 - 失败风险)

援助价值（按当前实装/计划技能）：
  持盾护卫（押衙/跳荡/枪兵 §5.12）→ 80    护理被围弱后排
  包扎（解流血，§5.4 通用）       → 70    清除流血/控场
  振奋军心（morale +1，§5.4）     → 50
  督战斩（虞候 §5.6 杀敌后 +morale） → 60
  标记（斥候 §5.5 友军命中 +10%）  → 35
  嘲讽（跳荡 §5.5 强制吸火）       → 65    保护残血队友
  战吼压阵（枪兵 §5.5 士气压制）   → 55
  野战八方 / 镇阵（§5.5 / §5.3.1）  → 60   死战护卫
  战场急救（PhasA 全场限 1 次）    → 90    HP=1 起身

失败风险：
  路径 OA 命中率 × OA 期望伤害 / 自身 HP
  AP 不够 → 失败风险 = 1.0 → score = 0
  路径不通 → 失败风险 = 1.0 → score = 0
```

### 4.4 位移动作评分（reposition）

> **覆盖**：§六 通用辅助技能池中的位移类 + 武器/职业的位移技能。  
> **价值核心**：「把谁/把自己挪到谁那里」给战局带来的好处。

```
score = 位移价值 × (1 - OA 风险) × 地形加成

位移类型与基础价值：
  推撞（推敌 1 格）                     → 50
   + 推入悬崖/水泽/火墙                  +200    （环境击杀，详见 terrain-system）
   + 推离队友救援距离                    +30
   + 推出 ZoC 让队友脱困                 +40

  擒拿拉拽（拉敌 1-2 格）               → 60
   + 拉出敌方阵列断队                    +30
   + 拉到我方 AOE / 火圈 / 围攻区         +50

  换位（与友军互换位置）                → 70
   + 换出残血队友脱离 ZoC                +60
   + 自己顶到弩手身前                    +40

  滑步 / 瞬步（自身位移不触发借机）     → 40
   + 进入敌方背刺位                      +25
   + 脱离 ZoC                            +30

  突击冲锋（≥2 格冲锋后攻击）           → 80
   + 撞墙/单位附加眩晕                   +50（跳荡分支A 制敌）
   + 命中破阵 +30% 伤                    +30（跳荡分支B 破阵）

  骑乘冲锋（铁骑 ≥3 格直线）            → 100
   + 冲锋后击退                          +50
   + 满血目标首击 +20%                   +40（摧锋陷阵）

  扫杆逼退（双手矛击退）                → 55
  长虹贯日（直线穿透 §5.10.1）          → 60     （含进攻评分，归 reposition 看穿透价值）

OA 风险：
  路径上每格 ZoC 借机命中率 × 期望伤害

地形加成：
  推到火 / 推下悬崖 → ×2.0
  从泥沼/障碍走出 → ×1.3
```

### 4.5 撤退动作评分

```
score = + 远离最近敌人距离      ×5/格
       + 接近最近友方距离       ×3/格
       + 落点地形防御           +5~+15
       + 路径不经 ZoC          +20
       - 路径 ZoC 借机          -15/格
```

---

## 五、Step 3 — 链式重决策

### 5.1 原子动作后必须重新走 Step 1

```
执行 MOVE → 完成 → 重算权重表（局面变了）
执行 ATTACK → 命中 → 重算（敌人可能死了）
执行 SKILL → 完成 → 重算（TP 减了/buff 加了）

每个单位每回合最多 6 次决策（防死循环）
```

### 5.2 权重表稳定 1 回合（关键设计）

**误区**：每次原子动作后都重判风格 → AI 鬼畜。  
**正确**：权重表每回合开始时计算一次；中途仅在「重大事件」时重算。

```
重大事件（强制重算权重表）：
  - 自己 HP 跨档（full→wounded、wounded→critical）
  - 盟友死亡 / 复活
  - 敌方援军到场
  - 自身被加 critical buff（眩晕/恐惧）

普通事件（保持原权重表）：
  - 自己刚移动了 1 格
  - 刚攻击完一次
  - 有敌人被打残
```

### 5.3 完整决策示例（押衙亲兵护卫弩手）

```
回合开始：押衙亲兵 HP 100%，队友弩手 HP 20% 被 2 敌兵围攻
  权重表 = { atk:0.6, def:1.5, sup:1.8, rep:0.65, ret:0.2 }
  候选池：
    ① 走+持盾护卫弩手（OA 60%）：final = 65   ✅
    ② 振奋军心 buff：             final = 54
    ③ 攻击围弩手的敌兵 A：         final = 54
    ④ 推撞敌兵开（rep）：          final = 46

  → ① 持盾护卫（援助 + 顺路接近）

重决策（已贴到弩手，开了护卫；周围 2 敌兵进入相邻）：
  ★ 重大事件：自身被多敌包夹（pressured 修饰生效）→ 重算
  权重表 = { atk:0.51, def:1.8, sup:1.8, rep:0.65, ret:0.16 }
  候选池：
    ① 镇阵（§5.3.1，本回合 -50% HP 伤）：final = 60 × 1.8 = 108  ✅
    ② 攻击邻敌 A：                       final = 80 × 0.51 = 41
    ③ 嘲讽（吸引仇恨保护弩手）：           final = 50 × 1.8 = 90

  → ① 镇阵（最大化生存）

重决策（已开镇阵，AP 剩 1）：
  权重表保持
  候选池：
    ① 攻击邻敌 A（弩手身上有威胁）：final = 70 × 0.51 = 36  ✅
    ② Wait：                       final = 20 × 1.8 = 36

  → ① 顺手补刀（同分时倾向进攻类，因为推进战局）
```

→ AI 自然形成「冲过去护卫 → 站定镇阵扛 → 顺手补刀」的护卫战术，**全部由数据驱动**。

---

## 六、核心数学模型

### 6.1 完整效用公式

```
final_score(action) = base_score(action) × weights[category(action)]

其中：
  base_score = Damage(action) - Risk(action) × SelfPreservation(unit)

  Damage           - 这个动作的杀伤期望（攻击伤害 / 治疗量 / buff 收益）
  Risk             - OA + 落点威胁 + 反击期望
  SelfPreservation - 1.0 默认；wounded 1.5；critical 2.0
  weights          - Step 1 输出的风格权重表
```

### 6.2 核心准则的数学体现

```
"保全自身"  → SelfPreservation 高 → Risk 主导 base_score 下行 → 选低风险候选
"杀伤敌方"  → Damage 主导 base_score 上行 → 选高伤害候选
"动态平衡"  → weights 缩放四类动作 → 兵种差异自动涌现
```

---

## 七、AI 决策的「涌现」特性（项目真实场景）

不需要为每个场景写 if/else，AI 会自动产生这些行为：

| 场景 | 涌现行为 | 原因 |
|---|---|---|
| **陌刀手** 看到 3 个敌兵贴一起 | 走位到能打全部 3 个的位置释放横扫千军 | 攻击候选生成时 AOE 模式天然分高 |
| **铁骑** 距敌方阵列 4 格直线 | 主动冲锋（reposition × atk 双计） | 骑乘冲锋 reposition 1.2 + atk 1.8 |
| **铁骑** 被枪兵架枪 | 切换迂回攻击侧翼 | 架枪反制 → 直冲候选 final 极低 |
| **弩手** 邻敌贴脸 | 抵近射击或切横刀格挡 | atk(贴脸 +50%) 或 defend(高于撤退) |
| **斥候** 见敌方阵列严整 | 标记敌方核心 + 后撤 | sup 标记 1 → friendly 命中 +10%；ret 0.9 |
| **押衙亲兵** 见弩手被围 | 走过去开持盾护卫 + 镇阵 | sup 1.8 + 武器加成（持盾 1.2）|
| **不良人** 见弩手落单 | 滑步穿 ZoC 暗杀 | reposition 1.3 + atk 1.5 + 残血 kill ×3 |
| **悍卒** HP 30% | 不退反进狂暴 | 悍卒 atk 1.9 + 武器加成 1.2，retreat 0.1 |
| **强盗团跳荡** 队友全死 | 拼死或逃命二选一 | collapsing × 强盗团 retreat 1.3 |
| **朔方枪兵** 与友军相邻 | 主动架枪 / 长虹贯日 | def 1.5 × 朔方 1.2 = 1.8，主控 |
| **僧兵** 见队友被打恐惧 | 振奋军心 + 棍法控场 | 僧兵 sup 0.9 + 武器加成 |
| **方士战兵** 远距离 | 元素地形覆盖关键格 | atk 0.6 → support 1.6 主导 |
| 援助走位 OA 高 | 选同类无走位援助 / 进攻补位 | 同表竞争 |
| 队友 dying → wounded | 战术从援助转进攻 | 重大事件触发权重重算 |

---

## 八、与现有实现的对照

| 设计 | 当前实现 | 状态 |
|---|---|---|
| 三步决策框架 | AIAgent + Behavior + 加权随机 | ✅ 已实现 |
| 5 类风格权重表（atk/def/sup/rep/ret） | Behavior 各自带 baseline | ⚠️ **需重构为权重表** |
| 18 职业权重配置 | 当前用 archetype（brave/cautious） | ⚠️ **改为 job_id 直查** |
| 统一候选池（5 类） | 各 Behavior 独立产候选 | ⚠️ 已分散，需汇总 |
| 进攻评分（残血/破甲/走位） | TargetScorer + EngageScorer | ✅ 已实现 |
| 防御评分（架盾/Wait/镇阵） | Defend stub + Wait | ⚠️ Defend 需实现 |
| 援助评分（持盾护卫/嘲讽/标记/振奋） | 暂无 | ❌ **Phase 2.5 接入** |
| 位移评分（推/拉/换/瞬/冲） | 暂无 | ❌ **Phase 2.5 接入** |
| 撤退评分 | Retreat stub | ❌ **需补全** |
| 链式重决策 | guard 循环 | ✅ 已实现 |
| 权重表「重大事件」重算 | 暂无（每步全量重算） | ⚠️ Phase 2.5 优化 |

---

## 九、下一步开发计划

### Phase 2.5 P0（架构重构）

1. **`scripts/ai/intent_weights.gd`** —— IntentWeights 模块
   - 输入：`AIProfile`（archetype/disposition）+ `WorldView` + `unit.job_id`
   - 输出：`{ attack, defend, support, reposition, retreat }` **5 维权重表**
   - 在 AIAgent 决策开头调用一次，回合末或重大事件触发重算

2. **`AIAgent.decide_next_action()`** 重构
   ```gdscript
   if _need_recompute_weights():
       _weights = IntentWeights.compute(unit, profile, view)
   var scored = []
   for behavior in _behaviors:
       var r = behavior.evaluate(view, profile)
       if r.score > 0:
           r.final = r.score * _weights[behavior.category]
           scored.append(r)
   return argmax(scored).action
   ```

3. **每个 Behavior 声明 category**
   ```gdscript
   class_name AIBehavior_Engage
   var category = "attack"

   class_name AIBehavior_Knockback     # 冲撞 / 推撞
   var category = "reposition"
   ```

4. **`data/ai_intent_weights.json`** —— 配置化权重表
   ```json
   {
     "jobs": {
       "tiaodang":  { "attack": 1.4, "defend": 1.0, "support": 0.4, "reposition": 0.6, "retreat": 0.2 },
       "qiangbing": { "attack": 1.0, "defend": 1.5, "support": 0.4, "reposition": 0.5, "retreat": 0.2 },
       ...18 职业全部
     },
     "weapon_modifiers": {
       "ranged_main": { "retreat": 1.3, "reposition": 1.2 },
       ...
     },
     "factions": {
       "bandit_band":  { "attack": 1.1, "support": 0.6, "retreat": 1.3 },
       "shuofang":     { "defend": 1.2, "support": 1.3 },
       ...
     },
     "modifiers": {
       "hp_critical":  { "attack": 0.5, "retreat": 2.0, "reposition": 1.5 },
       ...
     }
   }
   ```

### Phase 2.5 P1（援助 + 位移行为接入）

5. **援助 Behavior 池**
   - `AIBehavior_GuardWard`（持盾护卫，category=support）
   - `AIBehavior_Taunt`（嘲讽吸火，category=support）
   - `AIBehavior_RallyCry`（振奋军心 buff，category=support）
   - `AIBehavior_Mark`（斥候标记，category=support）

6. **位移 Behavior 池**（依赖 §10 MovementSpec 抽象层）
   - `AIBehavior_Reposition`（统一入口）
   - 评估所有 reposition tag 技能：换位 / 推撞 / 擒拿 / 滑步 / 突击冲锋 / 骑乘冲锋 / 扫杆逼退
   - 每个候选：`位移价值 × (1 - OA风险) × 地形加成`

7. **Retreat 行为**（category=retreat）
   - 落点评分公式 + 撤退条件门控

### Phase 3 后置

8. **「重大事件」检测**：HP 跨档 / 盟友死亡 / 援军 → 触发权重表重算
9. **可视化**：UI 显示敌方权重表（debug 模式）+ 决策日志
10. **平衡测试**：用 sim 跑 24 局 × 18 职业组合，回归权重表

---

## 十、配套设计：MovementSpec 抽象层

> 位移类技能（reposition）能否落地，依赖一个统一的「移动效果声明」抽象层。  
> 详见 [`design/ability-extension-guide.md`](ability-extension-guide.md) §三 MovementSpec 设计。  
> 简要：补一个 `AbilityMovementSpec`（仿 EffectSpec）+ `MovementSystem` 执行器，5 种位移类型（TELEPORT / PUSH / PULL / SWAP / DASH）覆盖未来所有位移技能。  
> 加新位移技能 ≈ 30 行 Resource 文件，AI 评分代码 0 改动。

---

## 十、设计精髓

> **风格不是过滤器，而是缩放器。**  
> AI 永远全局打分所有候选，权重表只决定「哪类动作此刻最受偏爱」。  
> 单个候选失败（OA 高、不可达）由同类的其他候选或异类候选自动接管，  
> 不需要任何"风格切换"控制流——**数据驱动，自然涌现**。

---

## 十一、自动权重优化（RL 启发 + Sim 搜索）

> Phase 3+ 预留；当前权重表手调足够，本节约为后期数值平衡提供方法论与工具锚点。

### 11.1 问题

手动调 18 职业 × 5 维度 × 5 状态修正 × 3 武器修饰 ≈ **1350 个权重参数**不现实。RL（强化学习）的通用做法是让 agent 自对弈百万局自动搜索最优参数——这对项目不现实（无 GPU 集群、无加速引擎、SRPG 单局长），但 RL 的核心思想——**定义 reward → 批量评估 → 自动搜索参数**——可以直接移植到现有 sim 引擎上。

### 11.2 方案：Sim 引擎 + 贝叶斯优化 → 自动搜权重

不需要神经网络。流程：

```
┌─────────────────────────────────────────────────┐
│  tools/optimize_weights.py（Python 外挂）        │
│                                                  │
│  param_space = {                                  │
│    "tiaodang.attack":     (1.0, 2.0),            │
│    "nushou.retreat":      (0.5, 1.5),            │
│    "tieqi.reposition":    (0.8, 1.5),            │
│    ... 18 职业 × 5 维度                           │
│  }                                               │
│                                                  │
│  for trial in range(200):                        │
│    weights = bayesian_optimize.suggest(param_space) │
│    result  = run_sim_batch(weights, games=100)   │
│    bayesian_optimize.record(weights, result)      │
│                                                  │
│  best_weights = bayesian_optimize.best()          │
│  → 写入 data/ai_intent_weights.json               │
└─────────────────────────────────────────────────┘
         │ 每次 trial 调 $GODOT --headless 跑 sim
         ▼
┌─────────────────────────────────────────────────┐
│  BattleSimHarness（已有）                         │
│  批量 4v4 / 8v8，返回胜率/均回合/存活率/AP 利用率  │
└─────────────────────────────────────────────────┘
```

**Reward 函数**（"好 AI"的定义）：

```python
reward = win_rate * 0.5         # 想赢
       + avg_survival * 0.2     # 想活
       + ap_efficiency * 0.2    # 少摆烂（Wait 少）
       - avg_rounds * 0.1       # 快节奏（别拖）
       - stalemate_rate * 2.0   # 强烈惩罚僵局
```

### 11.3 落地条件（全部已就绪）

| 条件 | 状态 | 文件 |
|---|---|---|
| 18 职业权重表 | ✅ 已存在 | `data/ai_intent_weights.json` |
| 批量 sim 引擎 | ✅ 已存在 | `BattleSimHarness.gd` + `tools/run_sim.sh` |
| Headless Godot | ✅ 已有 | `$GODOT --headless` |
| JSON 可读写 | ✅ 已有 | `AIIntentWeightsDB.gd` 读/写 |
| 调参不碰代码 | ✅ 已有 | `ai_intent_weights.json` 是纯数据 |

### 11.4 与设计无关的注意事项（Reward Shaping 防刷分）

RL 中的一个关键教训：**中间 reward 给多了，agent 会学会刷 reward 而不是赢**。对应到我们的权重表：

| 症状 | 根因 | 解法 |
|---|---|---|
| AI 反复推拉同一目标不杀 | reposition.situational 太高 | 对同目标重复位移衰减 situational 分 |
| AI 在全军溃败时原地 buff | support 权重压倒 retreat | 追加 collapsing 修正乘数硬化撤退 |
| AI 高甲单位疯狂走位不打人 | reposition > attack | 优化搜索时把 "伤害/回合" 作为 reward 项 |

### 11.5 实施时间线

| 阶段 | 工作 | 时机 |
|---|---|---|
| 当前 | 手工调 4 基础职业权重到"体感 OK" | Phase 2.5 |
| Phase 3 | 18 职业全数设计初版权重表 | 职业技能实装后 |
| Phase 3 末 | 写 `tools/optimize_weights.py`，跑 500~1000 局 sim 搜索 | 全部职业可 sim 后 |
| Phase 4 | 用玩家数据校准（behavioral cloning 锚点） | 有测试玩家后 |

---

**文档版本**: v2.2（18 职业权重表 + RL 启发自动优化）  
**修订时间**: 2026-06-13  
**核心准则**: 保全自身的前提下，尽可能杀伤敌方  
**关联文档**: `class-system.md`（18 职业基线）/ `ability-extension-guide.md`（MovementSpec）/ `ai-system.md`（AI 实现现状）/ `design/passive-effect-system.md`（被动技能钩子）
