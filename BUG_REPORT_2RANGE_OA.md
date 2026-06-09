# 2格攻击距离武器的借机攻击(OA)逻辑完整排查报告

## 执行时间
2026-06-09

## 概要
持有 `range: [1, 2]` 的武器（长矛、长棍）的**借机攻击被固定为 1 格**，无法达到 2 格距离。
根本原因：`HexGrid.get_zoc_controllers()` 硬编码了 ZoC=距离1，完全无视武器 range 属性。

---

## 1. 武器 Range 字段定义

### 1.1 weapons.json 中的定义

**✓ 正确**

```json
{
  "id": "spear",
  "display_name": "长矛",
  "range": [1, 2],  // 第 116 行
  ...
}

{
  "id": "staff",
  "display_name": "长棍/禅杖",
  "range": [1, 2],  // 第 184 行
  ...
}
```

所有其他近战武器：`"range": [1, 1]`

### 1.2 WeaponData.gd 中的字段定义

**✓ 正确** （第 67-69 行）

```gdscript
## 攻击距离范围 [min, max]（hex 格数）；近战 [1,1]，长矛 [1,2]，弓 [2,5]，弩 [2,6]
@export var range_min: int = 1
@export var range_max: int = 1
```

此外还有兼容旧代码的字段：
```gdscript
## DEPRECATED：旧 attack_range（v3.1 用 range_min/range_max 替代）
@export var attack_range: int = 1  // 第 97 行
```

### 1.3 WeaponArmorDB.gd 加载逻辑

**✓ 正确** （第 56-64 行）

```gdscript
# range：可能是 [min, max] 数组（新）或 int（旧）
var range_val: Variant = entry.get("range", 1)
if range_val is Array and (range_val as Array).size() >= 2:
    w.range_min = int((range_val as Array)[0])
    w.range_max = int((range_val as Array)[1])
else:
    w.range_min = int(range_val)
    w.range_max = int(range_val)
w.attack_range = w.range_max  # 兼容旧字段 ← 关键
```

**结论**：
- 长矛会被加载为 `range_min=1, range_max=2, attack_range=2` ✓
- 长棍会被加载为 `range_min=1, range_max=2, attack_range=2` ✓

---

## 2. 借机攻击的触发条件

### 2.1 主触发点：HexGrid.analyze_path_oa()

**文件**: `/scripts/core/HexGrid.gd`
**行号**: 480-494

```gdscript
## 沿一条路径走，识别每一步会触发哪些敌人借机攻击。
## 返回 Array[Dictionary]，每一步一个：{from, to, oa_attackers: Array[Unit]}
func analyze_path_oa(start: Vector2i, path: Array[Vector2i], self_faction: int, moving_unit = null) -> Array:
    var steps: Array = []
    var prev: Vector2i = start
    for step in path:
        var prev_ctrls: Array = get_zoc_controllers(prev, self_faction)  # ← 关键调用
        # 友方掩护过滤
        var filtered: Array = []
        for ctrl in prev_ctrls:
            if moving_unit != null and moving_unit.has_method("_is_covered_by_ally"):
                if moving_unit._is_covered_by_ally(prev, ctrl):
                    continue
            filtered.append(ctrl)
        steps.append({"from": prev, "to": step, "oa_attackers": filtered})
        prev = step
    return steps
```

**问题**：完全依赖 `get_zoc_controllers()` 返回的敌人列表。

### 2.2 关键 BUG 源头：HexGrid.get_zoc_controllers()

**文件**: `/scripts/core/HexGrid.gd`
**行号**: 429-443

```gdscript
## 站在 cell 的单位 / 即将进入 cell 的单位，会被哪些敌方单位的 ZoC 控制？
## 规则：装备近战武器、还活着、阵营不同的单位，距离恰好 1 视为控制 cell。
func get_zoc_controllers(cell: Vector2i, self_faction: int) -> Array:
    var result: Array = []
    for n in HexCoord.neighbors(cell):  # ← BUG：只迭代相邻 6 格（距离=1）
        var u = _occupants.get(n, null)
        if u == null:
            continue
        if not u.has_method("is_alive") or not u.is_alive():
            continue
        if not u.has_method("get_faction") or u.get_faction() == self_faction:
            continue
        # 远程单位不产生 ZoC
        if "weapon" in u and u.weapon != null and u.weapon.weapon_type != "melee":
            continue
        result.append(u)
    return result
```

**✗ 根本 BUG 位置**：

第 431 行：`for n in HexCoord.neighbors(cell):`

这只会迭代距离 cell 恰好为 1 的 6 个相邻格子，**完全无视持有武器的 `range_max` 属性**。

**具体危害**：
- 2 格武器的单位距离 2 时不被识别为"控制该 cell"
- `get_zoc_controllers(moved_to_cell)` 不会返回距离 2 的敌人
- 因此 `analyze_path_oa()` 不会记录该敌人的借机机会
- 借机攻击永远不会发生

---

## 3. 借机攻击的执行逻辑

### 3.1 Unit._animate_path() 中的执行

**文件**: `/scripts/core/Unit.gd`
**行号**: 274-365

**第 286-294 行（出发点 ZoC 检查）**：

```gdscript
# 1) 触发借机攻击的判定（六边形版改良规则）：
#    敌人 X 之前与你相邻（你在 X 的 ZoC 内）→ 本步无论你怎么动都触发：
#      • 在同一 X 的 ZoC 内绕侧（保持距离 1） → 触发（"在剑尖滑过"被劈）
#      • 脱离 X 的 ZoC（拉开距离 ≥2）           → 触发（背身撤退）
#    敌人 X 之前不与你相邻（你不在 ZoC 内）→ 不触发：
#      • 进入 X 的 ZoC（本步开始相邻） → 不触发（拉近距离时敌人无机会）
var prev_ctrls: Array = hex_grid.get_zoc_controllers(axial_pos, get_faction())
# 出发前在 ZoC 内的所有敌人都会触发本步借机
var leaving_ctrls: Array = []
for ctrl in prev_ctrls:
    if _is_covered_by_ally(axial_pos, ctrl):
        continue
    leaving_ctrls.append(ctrl)
```

**第 302-320 行（借机攻击执行）**：

```gdscript
# 3) 仅当本步是"脱离某敌人 ZoC"时，由该敌人触发借机攻击
var hit_blocked: bool = false
for ctrl in leaving_ctrls:
    if not is_alive():
        break
    var oa_result: Dictionary = DamageSystem.execute_attack(ctrl, self)
    oa_result["is_opportunity_attack"] = true
    # 防守方被攻击气力消耗（命中/闪避/格挡均触发）
    var def_fat: int = DamageSystem.calculate_defend_fatigue(self)
    if def_fat > 0:
        stats.add_fatigue(def_fat)
        oa_result["defend_fatigue"] = def_fat
    _apply_attack_result(ctrl, self, oa_result)
    ctrl.attacked.emit(ctrl, self, oa_result)
    # 命中即停：被任意一次借机攻击命中 → 中断剩余路径
    if oa_result.get("hit", false):
        hit_blocked = true
    if not is_alive():
        break
```

**问题链分析**：

1. 第 286 行调用 `get_zoc_controllers(axial_pos, ...)` 获取当前位置的敌方控制者
   - **BUG 传播**：该函数只返回距离 1 的敌人
   - 距离 2 的 2 格武器敌人被漏掉

2. 第 307 行执行攻击：`DamageSystem.execute_attack(ctrl, self)`
   - 理论上应该有距离检查（否则可能出错）
   - 但由于 `prev_ctrls` 已经是错的，这行永远到不了

**结论**：借机攻击完全依赖 ZoC 计算的正确性。

---

## 4. ZoC 计算是否考虑 weapon.range

### 4.1 get_zoc_cells_of() —— 获取"敌方威胁地图"

**文件**: `/scripts/core/HexGrid.gd`
**行号**: 447-465

```gdscript
## 取所有产生 ZoC 的格子（用于敌方阵营的"威胁地图"高亮）
func get_zoc_cells_of(enemy_faction: int) -> Array[Vector2i]:
    var seen: Dictionary = {}
    var result: Array[Vector2i] = []
    for axial in _occupants.keys():
        var u = _occupants[axial]
        if u == null or not u.has_method("is_alive") or not u.is_alive():
            continue
        if not u.has_method("get_faction") or u.get_faction() != enemy_faction:
            continue
        if "weapon" in u and u.weapon != null and u.weapon.weapon_type != "melee":
            continue
        for n in HexCoord.neighbors(axial):  # ← 同样是硬编码 neighbors()
            if not _hexes.has(n):
                continue
            if seen.has(n):
                continue
            seen[n] = true
            result.append(n)
    return result
```

**✗ 同样的 BUG**：第 458 行也是 `for n in HexCoord.neighbors(axial):`

该函数用于计算"整片敌方威胁地图"（UI 高亮），也没有考虑 `weapon.range_max`。

---

## 5. BattleAI 的 ZoC 惩罚评分

### 5.1 落点处于敌方 ZoC 的惩罚

**文件**: `/scripts/core/BattleAI.gd`
**行号**: 88-109

```gdscript
for tgt in enemies:
    var d: int = HexCoord.distance(pos, tgt.axial_pos)
    if d > unit.weapon.attack_range:
        continue
    # ...
    # 落点处在另一个敌人 ZoC（除目标外）
    var threats: Array = hex_grid.get_zoc_controllers(pos, unit.get_faction())  # ← 使用错的函数
    atk_score += SCORE_END_IN_ENEMY_ZOC * float(max(0, threats.size() - 1))
```

和

**行号**: 141-142

```gdscript
var threats: Array = hex_grid.get_zoc_controllers(pos, unit.get_faction())
proximity_bonus += SCORE_END_IN_ENEMY_ZOC * float(threats.size())
```

**✗ 问题**：直接调用 `get_zoc_controllers()`，继承了 1 格距离的 BUG。

**后果**：
- 2 格武器的敌人对 AI 的威胁被大幅低估
- AI 会错误地觉得距离 2 的敌人"不在 ZoC 中"是安全的
- AI 决策质量下降

---

## 6. 现状 vs 预期对比表

| 项目 | 现状 | 预期 | 状态 |
|------|------|------|------|
| **武器 range 字段定义** | `range: [1, 2]` | `range: [1, 2]` | ✓ 正确 |
| **武器加载逻辑** | `range_max=2, attack_range=2` | `range_max=2, attack_range=2` | ✓ 正确 |
| **ZoC 距离** | 固定 1 格 | 应为 range_max(2 格) | ✗ **BUG** |
| **借机触发条件** | 仅 1 格内 | 应为 range_max(2 格) | ✗ **BUG** |
| **借机执行距离** | 最大 1 格 | 应为 range_max(2 格) | ✗ **BUG** |
| **AI ZoC 惩罚** | 仅 1 格内 | 应为 range_max(2 格) | ✗ **BUG** |
| **UI 威胁高亮** | 仅 1 格内 | 应为 range_max(2 格) | ✗ **BUG** |

---

## 7. 关键代码位置一览表

| 文件 | 函数 | 行号 | 问题 | 优先度 |
|------|------|------|------|--------|
| **weapons.json** | - | 116, 184 | ✓ 正确 | - |
| **WeaponData.gd** | - | 67-69 | ✓ 正确 | - |
| **WeaponArmorDB.gd** | `_load_weapons()` | 56-64 | ✓ 正确 | - |
| **HexGrid.gd** | `get_zoc_controllers()` | 429-443 | ✗ **主 BUG** | P0 |
| **HexGrid.gd** | `get_zoc_cells_of()` | 447-465 | ✗ **次 BUG** | P0 |
| **HexGrid.gd** | `analyze_path_oa()` | 480-494 | ✗ 依赖 ZoC | P1 |
| **Unit.gd** | `_animate_path()` | 274-320 | ✗ 依赖 ZoC | P1 |
| **BattleAI.gd** | `decide()` | 108, 141 | ✗ 使用错的 ZoC | P1 |
| **BattleScene.gd** | `_update_move_preview()` | 713 | ✗ UI 高亮错误 | P2 |

---

## 8. BUG 影响范围

### 直接受影响的功能
1. **长矛借机攻击**：只能在 1 格距离触发，2 格敌人完全无法触发
2. **长棍借机攻击**：同上
3. **敌方威胁高亮**：2 格武器的威胁范围不显示（UI 只显示 1 格）
4. **AI 决策**：对 2 格武器敌人的评价过于乐观（未计算 2 格 ZoC 威胁）

### 间接受影响的功能
1. **友方掩护规则**：虽然代码在 Unit._animate_path() 中调用 `_is_covered_by_ally()`，但由于 ZoC 本身是错的，掩护机制也无法正确保护
2. **路径预览**：显示的"借机触发点"高亮不完整（缺 2 格距离的点）

---

## 9. 修复方案

### 方案 A：扩展 get_zoc_controllers() 考虑 weapon.range_max（推荐）

修改 `HexGrid.gd` 第 429-443 行：

```gdscript
func get_zoc_controllers(cell: Vector2i, self_faction: int) -> Array:
    var result: Array = []
    
    # ✓ 修复：遍历所有占用格子，按 weapon.range_max 筛选
    for axial in _occupants.keys():
        var u = _occupants[axial]
        if u == null:
            continue
        if not u.has_method("is_alive") or not u.is_alive():
            continue
        if not u.has_method("get_faction") or u.get_faction() == self_faction:
            continue
        # 远程单位不产生 ZoC
        if "weapon" in u and u.weapon != null and u.weapon.weapon_type != "melee":
            continue
        
        # ✓ 新增：检查距离，使用 weapon.range_max 代替固定 1
        var dist: int = HexCoord.distance(cell, axial)
        if dist <= 0 or dist > 1:  # 暂时保持兼容，只修复距离检查逻辑
            # 获取此单位武器的 ZoC 距离
            var zoc_distance: int = 1  # 默认 1 格
            if u.weapon != null and "range_max" in u.weapon:
                zoc_distance = u.weapon.range_max
            
            if dist > 0 and dist <= zoc_distance:
                result.append(u)
        elif dist == 1:  # 相邻格子永远算
            result.append(u)
    
    return result
```

### 方案 B：新增 get_zoc_controllers_by_range() 不影响旧代码

如果不想改动现有函数，可新增：

```gdscript
func get_zoc_controllers_by_range(cell: Vector2i, self_faction: int) -> Array:
    """考虑武器 range 的 ZoC 控制者查询"""
    # 实现同方案 A
```

然后逐步将调用点从 `get_zoc_controllers()` 切换为 `get_zoc_controllers_by_range()`。

### 方案 C：同步修复 get_zoc_cells_of()

需要获取 HexCoord 中的"距离 N 的所有格子"工具函数。

当前 HexCoord.gd 中只有 `neighbors(axial)` 返回距离 1 的 6 个格子。

需要新增：

```gdscript
# HexCoord.gd 中新增
static func ring(axial: Vector2i, distance: int) -> Array[Vector2i]:
    """返回距离 axial 恰好为 distance 的所有格子"""
    if distance == 1:
        return neighbors(axial)
    if distance <= 0:
        return []
    
    var result: Array[Vector2i] = []
    var cube: Vector3i = Vector3i(axial.x, -axial.x - axial.y, axial.y)
    var cube_n: Vector3i = cube + Vector3i(DIRECTIONS[4].x, 0, DIRECTIONS[4].y) * distance
    
    for i in range(6):
        for j in range(distance):
            result.append(Vector2i(cube_n.x, cube_n.z))
            # 沿六边形方向步进
            var dir_idx: int = (4 + i) % 6
            cube_n += Vector3i(DIRECTIONS[dir_idx].x, 0, DIRECTIONS[dir_idx].y)
    
    return result
```

然后修复 `get_zoc_cells_of()` 使用 `ring(axial, range_max)`。

---

## 10. 测试建议

修复后应测试：

1. **借机攻击距离**
   - 1 格武器敌人：借机应在 1 格内触发 ✓
   - 2 格武器敌人：借机应在 2 格内触发 ✓

2. **UI 高亮**
   - 2 格武器单位应显示"2 格威胁范围"高亮（敌方威胁地图）✓
   - 移动预览应显示"2 格内会触发借机的格子"✓

3. **AI 决策**
   - AI 应在计算"落点 ZoC 风险"时正确评估 2 格武器 ✓
   - 同样距离下，2 格武器的威胁应被评价更高 ✓

4. **路径执行**
   - 穿过 2 格武器敌人 2 格范围内时应触发借机 ✓
   - 击中后移动中断 ✓

---

## 11. 总结

**根本原因**：
```
HexGrid.get_zoc_controllers() 第 431 行硬编码 for n in HexCoord.neighbors(cell)
→ ZoC 固定为距离 1，无视 weapon.range_max
```

**影响链**：
```
get_zoc_controllers() [BUG]
  ↓
analyze_path_oa() → 只返回 1 格内的借机机会 [次级 BUG]
  ↓
Unit._animate_path() → 只在 1 格内执行借机 [表现 BUG]
  ↓
BattleAI.decide() → AI 对 2 格 ZoC 风险低估 [AI 问题]
  ↓
BattleScene UI → 威胁地图高亮不完整 [UI 问题]
```

**修复优先度**：
- **P0 (立即修)**: `get_zoc_controllers()` 和 `get_zoc_cells_of()`
- **P1 (自动解决)**: `analyze_path_oa()` 和 `_animate_path()` 会自动利用修复
- **P2 (验证)**: AI 决策和 UI 需测试验证

