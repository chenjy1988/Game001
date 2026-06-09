# 美术管线设计 v1（角色装备渲染）

> **设计目的**：让角色模型在战场上**视觉上随装备变化**——一眼看出"这人穿了重甲、拿着陌刀、配着盾"。
>
> **方案选定**：图块拼接（Paper Doll Lite）—— 4 层 Sprite 叠加，最少美术成本 + 最大组合多样性。
>
> **Phase 实施**：Phase 2 末做代码层（多层 Sprite2D），Phase 3 起正式生产美术资源。

---

## 一、4 种方案对比（决策依据）

| 方案 | 美术工作量 | 工程复杂度 | 组合多样性 | 推荐度 |
|---|---|---|---|---|
| **整图替换**（每装备一张图）| 极高（爆炸式）| 极低 | 受限于美术 | ❌ |
| **分层立绘 Paper Doll 完整版**（6-7 层）| 中 | 中 | 极高 | ⚠️ 战兄弟 / 火焰纹章用 |
| **骨骼动画**（Spine / DragonBones）| 低（一套骨架）| 极高 | 极高 + 动画灵活 | ⚠️ HD-2D / Triangle Strategy 用 |
| **图块拼接 4 层（Paper Doll Lite）** ⭐ | **极低** | 低 | 高 | ✅ **本项目采用** |

→ 我们项目的图层数从 7 简化到 4，**美术成本降到极致，但视觉装备区分仍清晰**。

---

## 二、4 层叠加方案（核心架构）

### 2.1 图层结构

```
角色显示节点（Unit Node2D）
  ├─ Layer 1: BodyLayer (Sprite2D)    - 角色基底（含身体 + 默认服装 + 头脸）
  ├─ Layer 2: ArmorLayer (Sprite2D)   - 护甲 overlay（覆盖到基底上）
  ├─ Layer 3: WeaponLayer (Sprite2D)  - 主手武器
  ├─ Layer 4: OffHandLayer (Sprite2D) - 副手（盾 / 副武器 / 箭袋）
  
  渲染顺序（z 由低到高）：
    BodyLayer → ArmorLayer → WeaponLayer → OffHandLayer
  
  无装备时：
    BodyLayer 显示
    ArmorLayer / WeaponLayer / OffHandLayer 隐藏（texture = null）
```

### 2.2 Godot 实现示例

```gdscript
class_name UnitVisual
extends Node2D

@onready var body_layer: Sprite2D = $BodyLayer
@onready var armor_layer: Sprite2D = $ArmorLayer
@onready var weapon_layer: Sprite2D = $WeaponLayer
@onready var off_hand_layer: Sprite2D = $OffHandLayer

func _ready() -> void:
    armor_layer.texture = null
    weapon_layer.texture = null
    off_hand_layer.texture = null

# 角色基底：一次设置（招募时）
func set_body(unit_data: Dictionary) -> void:
    body_layer.texture = load(unit_data["body_sprite"])

# 装备护甲
func equip_armor(armor_data: ArmorData) -> void:
    if armor_data == null:
        armor_layer.texture = null
    else:
        armor_layer.texture = load(armor_data.overlay_sprite)

# 装备武器（主手）
func equip_weapon(weapon_data: WeaponData) -> void:
    if weapon_data == null:
        weapon_layer.texture = null
    else:
        weapon_layer.texture = load(weapon_data.sprite)

# 装备副手（盾 / 副武器 / 箭袋）
func equip_off_hand(item_data) -> void:
    if item_data == null:
        off_hand_layer.texture = null
    else:
        off_hand_layer.texture = load(item_data.sprite)
```

### 2.3 数据层接口（WeaponData / ArmorData 新增字段）

```gdscript
class_name ArmorData
extends Resource

@export var id: String
@export var display_name: String
@export var head_armor: int
@export var body_armor: int
@export var weight: int
@export var combat_style: String
@export var overlay_sprite: String  ## ⭐ 新增：护甲 overlay PNG 路径
@export var armor_class: String  ## "light" / "medium" / "heavy"
```

```gdscript
class_name WeaponData
extends Resource

# ... 已有字段 ...
@export var sprite: String  ## ⭐ 新增：武器 PNG 路径（角色身上手持图）
@export var icon: String  ## 已有：装备槽小图标（不同图）
```

→ 区分 `sprite`（角色手上的）和 `icon`（装备槽里的）—— 两种用途。

---

## 三、规格规范

### 3.1 通用规格

| 项 | 规格 |
|---|---|
| **像素单位** | 64×64（标准角色）/ 128×128（高清版可选）|
| **画布颜色空间** | sRGB（PNG 透明背景）|
| **Anchor 锚点** | 底部中心（脚踩 hex 格子中心）|
| **朝向** | 俯视 + 30° 斜俯角（参考 Darkest Dungeon / 战兄弟）|
| **风格基调** | 哥特卡通 + 唐朝丹青美学 |
| **色彩** | 暗调底色 + 重点色块鲜明（朱砂、靛青、土黄、墨黑）|

### 3.2 各层尺寸

| 图层 | 推荐尺寸 | 说明 |
|---|---|---|
| **BodyLayer** | 64×64 | 包含整个角色身体 + 默认便服 + 头脸 |
| **ArmorLayer** | 64×64 | 与基底同尺寸，alpha 透明叠加 |
| **WeaponLayer** | 32×48（竖向）或 48×32（横向）| 武器单独绘制，可超出角色边界 |
| **OffHandLayer** | 32×32 | 盾 / 副武器，副手位置 |

### 3.3 武器位置规范

```
WeaponLayer 锚点位置（相对 Unit 中心）：
  - 单手武器（短剑 / 匕首 / 锤）：右手位置（+8x, -2y）
  - 双手武器（陌刀 / 双手剑）：身体中央偏右（+4x, -4y）
  - 长矛 / 长戟：身体中央，竖直（0x, -8y）
  - 弓 / 弩：左手或竖向举起（0x, 0y）

OffHandLayer 锚点位置：
  - 盾 / 副武器：左手位置（-8x, -2y）
  - 箭袋（弓手）：背后（0x, +4y，z 在 BodyLayer 之下，特殊处理）
```

→ 锚点常量统一在代码中定义，所有武器/副手共用。

---

## 四、唐朝风格美术参考

### 4.1 文化参考

| 类别 | 参考资料 |
|---|---|
| 服饰 | 陕西历史博物馆唐代军服考据 / 《大唐军服图鉴》 |
| 美术 | 敦煌壁画武士像 / 唐墓壁画 / 出土文物（明光铠 / 横刀实物） |
| 现代作品 | 《长歌行》动画 / 《妖猫传》/ 《风起洛阳》|
| 武器 | 《唐六典》记载的军器制式 |

### 4.2 色彩规范

```
基础调色板：
  朱砂红 #B22D2D
  靛青   #2D4D77
  土黄   #B89F6F
  墨黑   #1A1A1A
  暗金   #8C7340
  铁灰   #5A5A5A
  
强调色：
  鎏金   #D4A847（神兵 / 上级装备）
  血红   #6E1A1A（受伤 / 重伤）
  幽蓝   #2D5577（玄学 / 道家）
```

### 4.3 黑暗 + 卡通化的具体表现

```
黑暗题材的视觉表达：
  ✅ 整体偏暗（不要饱和度过高）
  ✅ 阴影深邃（强对比，但不锐利）
  ✅ 线条粗厚（卡通风格的标志）
  ✅ 简化细节（不画肌肉纹理 / 不画织物褶皱细节）
  ✅ 色块明确（每个装备有醒目主色）
  ❌ 避免：欧美写实 / 日式精致 / 萌系可爱

参考标杆：
  - Darkest Dungeon（黑暗 + 哥特卡通）⭐⭐⭐
  - Hollow Knight（黑暗 + 极简卡通）
  - Don't Starve（黑暗 + Tim Burton 哥特）
```

---

## 五、素材清单（生产顺序）

### 5.1 Phase 3 起首批生产清单（最小可行版本，~30 张）

#### A. 角色基底（10 张）

| 类型 | 数量 | 备注 |
|---|---|---|
| 男雇佣兵·壮硕 | 2 | 络腮胡 / 光头 |
| 男雇佣兵·中等 | 2 | 普通体型 |
| 男雇佣兵·瘦削 | 1 | 江湖人士 |
| 女雇佣兵·普通 | 2 | 唐朝女武人 |
| 老兵 | 1 | 须发花白 |
| 西域武人 | 1 | 高鼻深目 |
| 流民出身 | 1 | 衣衫褴褛 |

#### B. 护甲 Overlay（3 张）

| 档次 | 文件名 | 说明 |
|---|---|---|
| 轻甲 | `overlay_armor_leather.png` | 麻甲 / 皮甲（褐色） |
| 中甲 | `overlay_armor_mail.png` | 棉甲 / 锁子甲（红蓝军服 + 银色金属） |
| 重甲 | `overlay_armor_plate.png` | 札甲 / 明光铠（暗金 + 圆护胸）⭐ |

#### C. 武器（10 张）

| 武器 | 文件名 | 类型 |
|---|---|---|
| 匕首 | `weapon_dagger.png` | Pierce |
| 横刀 | `weapon_saber.png` | Slash |
| 长矛 | `weapon_spear.png` | Pierce |
| 战斧 | `weapon_axe.png` | Slash |
| 战锤 | `weapon_hammer.png` | Crush |
| 陌刀 | `weapon_modao.png` | Slash（双手大刀）|
| 双手剑 | `weapon_greatsword.png` | Slash |
| 长弓 | `weapon_bow.png` | 远程 |
| 弩 | `weapon_crossbow.png` | 远程 |
| 火铳（保留 Phase 4）| `weapon_musket.png` | 远程，明朝晚期或唐朝实验性 |

#### D. 副手（5 张）

| 副手 | 文件名 |
|---|---|
| 团牌（藤盾，圆形） | `offhand_round_shield.png` |
| 铁盾（方形大）| `offhand_square_shield.png` |
| 箭袋 | `offhand_quiver.png` |
| 副手刀（双武器流）| `offhand_dagger.png` |
| 空（双手武器时不显示）| — |

→ **总计 ~28 张图**，可生成 10 × 4 × 10 × 5 = **2000+ 种独特外观**。

### 5.2 Phase 4 扩展清单（~20 张）

```
新增角色基底：6 张（更多体型 / 性别 / 出身）
新增武器：5 张（上级职业专属，如三眼铳、弯刀等）
新增护甲：2 张（特殊上级装备）
新增副手：3 张（特殊盾 / 暗器袋）
特效层：4 张（受伤 / 死亡 / 治疗光环 / 火焰）
```

### 5.3 Phase 5 完善清单（~20 张）

```
表情系统：每个角色 3 表情（普通 / 受伤 / 暴怒）
死亡帧：每个角色 1 张倒地图
特殊职业基底：8 张（家丁 / 锦衣卫 / 神机营等上级职业有独立基底）
```

→ 全完成约 **~70 张图**，仍属"独立小团队可承受"范围。

---

## 六、美术 Brief（给画师的工作说明）

### 6.1 项目概述

```
项目名：唐朝雇佣兵团 SRPG（开发代号 Game001）
游戏类型：2D 战棋 RPG
核心受众：30-45 岁 SRPG 老玩家
风格基调：黑暗 + 卡通化（参考 Darkest Dungeon）
题材：唐朝安史之乱时代 + 边军 / 雇佣兵团
```

### 6.2 单张素材交付要求

```
对每张 PNG：
  ✅ 像素 64×64（角色基底 / 护甲）/ 32-48px（武器 / 副手）
  ✅ 透明背景 PNG
  ✅ 锚点：底部中心（脚踩 hex 格子中心）
  ✅ 朝向：俯视 + 30° 斜俯角
  ✅ 风格：哥特卡通 + 唐朝丹青
  ✅ 命名：英文 snake_case，前缀分类（body_xxx / armor_xxx / weapon_xxx）
  ✅ 提供 1x（实际游戏分辨率）+ 2x（高清备份，可选）
```

### 6.3 单张素材风格指南

```
线条：
  - 粗厚黑色 outline（1-2px 像素感）
  - 内部细节用色块表达，不用线条勾勒
  - 远离精细写实

色彩：
  - 整体暗调（不要太鲜艳）
  - 主色不超过 3 种
  - 装备 overlay 与基底融合自然

光影：
  - 简化阴影（顶部稍亮，底部稍暗）
  - 避免复杂渐变
  - 重点装备（神兵 / 鎏金）可加微弱发光

抗锯齿：
  - 像素感保留（不平滑）
  - 但不是低分辨率像素风（保留 64x64 分辨率细节）
```

### 6.4 唐朝服饰参考要点

```
唐朝军装基本款：
  - 圆领袍 + 革带 + 长靴
  - 颜色以红、青、白军服为主
  - 头戴幞头 / 头盔（视职位）

护甲层次：
  - 麻甲 / 皮甲：褐色调，简朴
  - 棉甲 / 锁子甲：红蓝军服 + 银色锁链甲
  - 札甲：暗金色金属甲叶
  - 明光铠：亮银 + 标志性圆护胸（圆形护板）⭐

武器特色：
  - 横刀：唐军标准刀，单手刀，环首
  - 陌刀：双手大刀，超长，威武感 ⭐
  - 长矛：5-8 尺长（图中夸张表达即可）
```

---

## 七、技术接口预留

### 7.1 现有 Unit.gd 改造预留

```gdscript
# 当前 Unit.gd 渲染：单个 Sprite2D 显示 portrait
# Phase 2 末改造：

class_name Unit
extends CharacterBody2D

# 新增子节点：
@onready var visual: UnitVisual = $UnitVisual

func equip_weapon_and_update(weapon_data: WeaponData) -> void:
    self.weapon = weapon_data
    visual.equip_weapon(weapon_data)  ## ⭐ 同步视觉

func equip_armor_and_update(armor_data: ArmorData) -> void:
    self.armor = armor_data
    visual.equip_armor(armor_data)
```

### 7.2 战斗中装备变化的视觉响应

```
触发场景：
  - 战利品拾取（地面物品 → 装备）
  - 武器损坏（耐久 0）→ 武器图层消失
  - 头盔被打掉（头部受致命攻击）→ 头盔层消失（如果做头盔层）

实现：
  visual.equip_xxx(null) 即可隐藏图层
```

---

## 八、Phase 实施时间线

| Phase | 内容 |
|---|---|
| **Phase 2**（当前）| 不动美术 —— 用现有 portrait_xxx.png 单层显示 |
| **Phase 2 末** | 实现 `UnitVisual` 多层 Sprite2D 节点（代码层）|
| **Phase 3** | 美术资源生产 P0（首批 28 张），先做 1-2 个角色完整管线验证 |
| **Phase 4** | 美术 P1（扩展角色 / 武器 / 副手）+ 性别 / 多体型 |
| **Phase 5** | 美术 P2（表情 / 受伤 / 死亡 / 特效层）|

---

## 九、风险与对策

| 风险 | 对策 |
|---|---|
| 美术资源延迟 | Phase 2-3 用占位图（程序员风格）继续开发，美术不阻塞代码 |
| 武器手持位置不自然 | 锚点常量化在代码里，先调一个武器，后续武器对照调整 |
| 黑暗+卡通化实现难 | 先做 1-2 张试点（最小化风险），通过后批量生产 |
| 角色基底过多导致风格不统一 | 招募一个固定画师，所有角色一人画完 |
| 64×64 分辨率不够表现细节 | 备份 128×128 高清版，未来如果改画风可重渲染 |

---

## 十、设计决策固化

| # | 决策 | 选定 |
|---|---|---|
| 1 | 装备变化方案 | ✅ 图块拼接（4 层 Paper Doll Lite）|
| 2 | 角色基底数量（首批）| ✅ 6-10 个，男女各 ~5 个体型 |
| 3 | 武器手持显示 | ✅ 武器作为独立图层显示，可超角色边界 |
| 4 | 副手显示 | ✅ 盾 / 副武器 / 箭袋 各自独立图层 |
| 5 | 头盔层是否独立 | ❌ 暂不独立（包含在角色基底/护甲 overlay 内）|
| 6 | 性别 + 多体型 | ✅ 加，扩大受众 |
| 7 | 单张分辨率 | ✅ 64×64 标准 + 128×128 备份 |
| 8 | 风格基调 | ✅ Darkest Dungeon × 唐朝丹青 |

---

**文档版本**：v1
**最后更新**：2026-06-02
**关联文档**：design.md（产品定位）/ economy-system.md（经济）
**实施 Phase**：代码层 Phase 2 末，美术层 Phase 3 起
