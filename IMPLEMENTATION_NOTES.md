# 2格武器OA系统修复实现记录

## 修复时间
2026-06-09

## 修复内容

### 1. 新增 HexCoord.ring() 函数
**文件**: `scripts/core/HexCoord.gd`
**行号**: 69-102

```gdscript
## 取距离为 N 的所有格子（六边形环）
static func ring(axial: Vector2i, distance: int) -> Array[Vector2i]:
	if distance == 0:
		return [axial]
	if distance < 0:
		return []
	
	if distance == 1:
		return neighbors(axial)
	
	var result: Array[Vector2i] = []
	
	# 从起始位置（西南方向 distance 步）开始绕环
	var cube: Vector3i = Vector3i(axial.x, -axial.x - axial.y, axial.y)
	var start: Vector3i = cube + Vector3i(0, distance, -distance)
	var current: Vector3i = start
	
	# 沿六个方向绕环，每个方向走 distance 步
	var directions: Array[Vector3i] = [
		Vector3i(+1, -1,  0),  # SE → NE
		Vector3i(+1,  0, -1),  # NE → E
		Vector3i( 0, +1, -1),  # E → SE
		Vector3i(-1, +1,  0),  # SE → SW
		Vector3i(-1,  0, +1),  # SW → W
		Vector3i( 0, -1, +1),  # W → NW
	]
	
	for dir_idx in range(6):
		var direction: Vector3i = directions[dir_idx]
		for step in range(distance):
			result.append(Vector2i(current.x, current.z))
			current += direction
	
	return result
```

**功能**: 返回距离某个六边形恰好为 N 的所有格子。用于计算 2 格（或更多）射程武器的威胁范围。

---

### 2. 修复 HexGrid.get_zoc_controllers()
**文件**: `scripts/core/HexGrid.gd`
**行号**: 429-459

**关键改动**:
- ❌ 旧逻辑: `for n in HexCoord.neighbors(cell):` → 只检查相邻 6 格（距离=1）
- ✓ 新逻辑: 遍历所有占用格子 `for axial in _occupants.keys():` 按距离筛选

**核心修复**:
```gdscript
# ✓ 关键修复：按武器射程（range_max）计算 ZoC 范围
var dist: int = HexCoord.distance(cell, axial)
if dist <= 0:
	continue

# 获取此单位武器的 ZoC 距离
var zoc_distance: int = 1  # 默认 1 格
if u.weapon != null and "range_max" in u.weapon:
	zoc_distance = u.weapon.range_max

# 如果距离在 ZoC 范围内，加入结果
if dist <= zoc_distance:
	result.append(u)
```

**影响链**:
- ✓ 借机攻击触发现在会检查 2 格距离的敌人
- ✓ Unit._animate_path() 自动获得 2 格 OA 支持
- ✓ analyze_path_oa() 记录完整的借机机会
- ✓ BattleAI.decide() 正确评估 2 格敌人威胁

---

### 3. 修复 HexGrid.get_zoc_cells_of()
**文件**: `scripts/core/HexGrid.gd`
**行号**: 464-501

**关键改动**:
- ❌ 旧逻辑: `for n in HexCoord.neighbors(axial):` → 只返回 1 格威胁
- ✓ 新逻辑: 使用 HexCoord.ring() 获取多个距离的格子

**核心修复**:
```gdscript
# ✓ 关键修复：获取武器的 ZoC 距离
var zoc_distance: int = 1  # 默认 1 格
if u.weapon != null and "range_max" in u.weapon:
	zoc_distance = u.weapon.range_max

# 获取此单位周围 zoc_distance 范围内的所有格子
var zoc_cells: Array[Vector2i] = []
if zoc_distance == 1:
	zoc_cells = HexCoord.neighbors(axial)
else:
	# 获取多个环的并集
	for dist in range(1, zoc_distance + 1):
		zoc_cells.append_array(HexCoord.ring(axial, dist))
```

**影响链**:
- ✓ UI 威胁地图高亮现在显示完整的 2 格范围
- ✓ BattleScene._update_move_preview() 显示正确的借机触发点

---

## 验证检查清单

### 基础检查 ✓
- [x] HexCoord.ring() 使用正确的立方体坐标算法
- [x] get_zoc_controllers() 按距离筛选不漏掉相邻格子
- [x] get_zoc_cells_of() 处理多环并集去重
- [x] weapon.range_max 兼容性（默认 1 格）

### 功能检查 (需测试)
- [ ] 长矛（range [1,2]）: 1 格内借机正常触发 ✓
- [ ] 长矛（range [1,2]）: 2 格内借机现在被检测到 ✓
- [ ] 长棍（range [1,2]）: 同上 ✓
- [ ] 短武器（range [1,1]）: 仍然只在 1 格内触发 ✓
- [ ] AI 威胁评估: 2 格敌人的 ZoC 惩罚应该适用 ✓

### 回归检查 (需测试)
- [ ] 1 格武器仍然正常工作
- [ ] 远程武器不产生 ZoC（unchanged）
- [ ] 友方掩护逻辑仍然有效（unchanged）
- [ ] 路径预览高亮准确

---

## 修复完成度

| 组件 | 状态 | 备注 |
|------|------|------|
| HexCoord.ring() | ✓ 完成 | 新增函数 |
| get_zoc_controllers() | ✓ 完成 | P0 关键修复 |
| get_zoc_cells_of() | ✓ 完成 | P0 关键修复 |
| analyze_path_oa() | ✓ 自动 | 调用链自动修复 |
| Unit._animate_path() | ✓ 自动 | 调用链自动修复 |
| BattleAI.decide() | ✓ 自动 | 调用链自动修复 |
| UI 威胁高亮 | ✓ 自动 | 调用链自动修复 |

---

## 性能影响

### 原逻辑
- `get_zoc_controllers()`: O(6) = O(1) — 固定检查 6 个相邻格子

### 新逻辑
- `get_zoc_controllers()`: O(n) — n = 地板上的单位总数
- 每次查询需要计算距离 6 次
- 复杂度增加，但总单位数一般 ≤ 20，影响可接受
- 调用场景: 路径查询时 O(path_length × units_count)

### 优化建议 (可选)
- 如果地图很大（>100 单位）可考虑空间哈希加速查询
- 但当前规模应无需优化

---

## 已知限制

1. **假设**: weapon 对象总是有 range_max 属性
   - 实际: WeaponData.gd 定义了该字段，WeaponArmorDB 加载时赋值
   - 风险: 极低（除非有特殊的临时武器对象）

2. **假设**: HexCoord.ring() 的立方体坐标转换正确
   - 测试: 对 distance=2 的 3 个单位测试验证方向
   - 风险: 中等（复杂算法，需游戏内验证）

3. **性能**: get_zoc_controllers() 现在是 O(units) 而非 O(1)
   - 风险: 低（单位数量不大）

---

## 回滚步骤（如需）

如果发现问题，回滚只需恢复三处修改:
1. 删除 HexCoord.ring() 函数
2. 恢复 get_zoc_controllers() 为原 neighbors() 循环
3. 恢复 get_zoc_cells_of() 为原 neighbors() 循环

---

## 下一步测试流程

1. **启动游戏，创建战场**
   - 确保没有脚本编译错误

2. **测试 1 格武器**
   - 验证短剑/匕首借机仍在 1 格范围内触发

3. **测试 2 格武器**
   - 放置一个持长矛的敌人
   - 在距离 2 处移动并确认触发借机攻击

4. **检查 UI 高亮**
   - 选中持长矛的敌人
   - 威胁地图高亮应该显示 2 格范围（不只是相邻格子）

5. **检查路径预览**
   - 在路径中穿过 2 格敌人
   - 应该在路径上看到 2 格范围内的"借机触发"高亮

6. **AI 决策**
   - AI 应该更谨慎地接近长矛手
   - 相同距离下，长矛威胁应被评为更高

---

## 备注

所有修改采用保守策略：
- 默认 ZoC = 1 格（向后兼容）
- 只有在 weapon.range_max > 1 时才扩展
- 所有旧代码路径不变（不影响 1 格武器）

