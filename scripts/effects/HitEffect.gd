extends Node
class_name HitEffect
##
## HitEffect.gd — 攻击/受击/死亡的一次性粒子特效（GPUParticles2D）
##
## 设计原则：
## - 静态工厂方法，调用方一行 `HitEffect.spawn(layer, pos, "blood", 1.0)` 即可。
## - 每次 spawn 都新建一个 GPUParticles2D + ParticleProcessMaterial，发射完自动 queue_free。
## - 不引入额外 .tscn，所有参数代码内可读 / 可调；特效细节（发射数量、初速度、颜色渐变）
##   按 kind 在 `_build_material` 里集中分支。
##
## 三类预设（kind）：
##   "blood"  — 红色血溅（命中 + 造成 HP 伤害时使用）
##   "spark"  — 黄白火花（命中护甲、未破防时使用）
##   "smoke"  — 灰色烟雾（单位死亡时使用，配合血色）
##
## 素材来源：godot-demo-projects/2d/particles（官方 CC0），spark/smoke 两张通用粒子贴图。

const SPARK_TEX: Texture2D = preload("res://assets/effects/spark_particle.png")
const SMOKE_TEX: Texture2D = preload("res://assets/effects/smoke_particle.png")


## 在 `parent` 的本地坐标 `local_pos` 处生成一次性粒子。
## intensity ∈ [0.4, 1.5]：影响数量 / 速度 / 尺寸（暴击给 1.5，普通命中 1.0）。
static func spawn(parent: Node, local_pos: Vector2, kind: String, intensity: float = 1.0) -> void:
	if parent == null:
		return
	intensity = clamp(intensity, 0.3, 1.6)

	var p: GPUParticles2D = GPUParticles2D.new()
	p.position = local_pos
	p.one_shot = true
	p.explosiveness = 1.0          ## 全部粒子瞬时喷出（命中瞬间）
	p.lifetime = 0.55
	p.local_coords = false         ## 粒子留在世界空间，单位被击退也不会拖着走

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	# 通用：圆形点状发射，向四周扩散
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.gravity = Vector3(0, 120, 0)              ## 受重力下坠（血点会"溅落"）
	mat.angular_velocity_min = -180.0
	mat.angular_velocity_max = 180.0

	var amount: int = 20
	var tex: Texture2D = SPARK_TEX

	match kind:
		"blood":
			# 血溅：红 → 暗红渐隐，初速 90~180 px/s 向上半球扩散
			amount = int(round(28 * intensity))
			p.lifetime = 0.55
			tex = SPARK_TEX
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 70.0
			mat.initial_velocity_min = 90.0 * intensity
			mat.initial_velocity_max = 200.0 * intensity
			mat.scale_min = 0.8 * intensity
			mat.scale_max = 1.4 * intensity
			mat.scale_curve = _build_scale_curve(1.0, 0.2)
			mat.color_ramp = _build_color_ramp([
				Color(1.00, 0.20, 0.20, 1.0),
				Color(0.55, 0.05, 0.05, 0.9),
				Color(0.30, 0.00, 0.00, 0.0),
			])
			mat.gravity = Vector3(0, 220, 0)
		"spark":
			# 火花：黄白 → 橙 → 透明，初速更快、更扁的椭圆扩散，无重力
			amount = int(round(18 * intensity))
			p.lifetime = 0.35
			tex = SPARK_TEX
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 180.0
			mat.initial_velocity_min = 140.0 * intensity
			mat.initial_velocity_max = 280.0 * intensity
			mat.scale_min = 0.4 * intensity
			mat.scale_max = 0.9 * intensity
			mat.scale_curve = _build_scale_curve(1.0, 0.0)
			mat.color_ramp = _build_color_ramp([
				Color(1.00, 1.00, 0.85, 1.0),
				Color(1.00, 0.70, 0.30, 0.9),
				Color(0.55, 0.30, 0.10, 0.0),
			])
			mat.gravity = Vector3.ZERO
		"smoke":
			# 烟雾：灰白 → 透明，慢、向上漂、变大；用于死亡
			amount = int(round(14 * intensity))
			p.lifetime = 1.20
			tex = SMOKE_TEX
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 35.0
			mat.initial_velocity_min = 30.0
			mat.initial_velocity_max = 70.0
			mat.scale_min = 0.6
			mat.scale_max = 1.1
			mat.scale_curve = _build_scale_curve(0.6, 1.6)   ## 烟雾渐渐变大
			mat.color_ramp = _build_color_ramp([
				Color(0.65, 0.60, 0.55, 0.9),
				Color(0.45, 0.42, 0.38, 0.5),
				Color(0.30, 0.28, 0.25, 0.0),
			])
			mat.gravity = Vector3(0, -25, 0)                  ## 反重力上飘

	p.amount = amount
	p.process_material = mat
	p.texture = tex

	parent.add_child(p)
	p.emitting = true

	# 生命周期到了自动清理（多给 0.2s 余量避免还在飞的粒子被截断）
	var tree: SceneTree = parent.get_tree()
	if tree:
		var timer: SceneTreeTimer = tree.create_timer(p.lifetime + 0.3)
		timer.timeout.connect(p.queue_free)


# ──────────── 内部工具：构造 Curve / Gradient ────────────

static func _build_scale_curve(start: float, end: float) -> CurveTexture:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, start))
	curve.add_point(Vector2(1.0, end))
	var ct: CurveTexture = CurveTexture.new()
	ct.curve = curve
	return ct


static func _build_color_ramp(colors: Array) -> GradientTexture1D:
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray(colors)
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var n: int = colors.size()
	for i in n:
		offsets.append(float(i) / max(1, n - 1))
	grad.offsets = offsets
	var gt: GradientTexture1D = GradientTexture1D.new()
	gt.gradient = grad
	return gt
