extends Node
class_name HitEffect
##
## HitEffect.gd — 攻击/受击/死亡的一次性粒子特效（GPUParticles2D）
##
## 设计原则：
## - 静态工厂方法，调用方一行 `HitEffect.spawn(layer, pos, "blood", 1.0)` 即可。
## - 每次 spawn 都新建一个 GPUParticles2D + ParticleProcessMaterial，发射完自动 queue_free。
## - 颜色走 CombatPalette，与 HexGrid / TopBar / 飘字统一。

const SPARK_TEX: Texture2D = preload("res://assets/effects/spark_particle.png")
const SMOKE_TEX: Texture2D = preload("res://assets/effects/smoke_particle.png")


class ImpactRing extends Node2D:
	var ring_color: Color = Color.WHITE
	var _radius: float = 6.0
	var _max_radius: float = 30.0

	func _ready() -> void:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "_radius", _max_radius, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "modulate:a", 0.0, 0.16)
		tw.chain().tween_callback(queue_free)

	func _draw() -> void:
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 28, ring_color, 2.2, true)


## 在 `parent` 的本地坐标 `local_pos` 处生成一次性粒子。
## intensity ∈ [0.4, 1.5]：影响数量 / 速度 / 尺寸（暴击给 1.5，普通命中 1.0）。
## direction：击退/飞溅主方向（世界单位向量，默认向上）。
static func spawn(parent: Node, local_pos: Vector2, kind: String, intensity: float = 1.0,
		direction: Vector2 = Vector2.UP) -> void:
	if parent == null:
		return
	intensity = clamp(intensity, 0.3, 1.6)
	if direction.length_squared() < 0.01:
		direction = Vector2.UP
	else:
		direction = direction.normalized()

	var p: GPUParticles2D = GPUParticles2D.new()
	p.position = local_pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.55
	p.local_coords = false

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.gravity = Vector3(0, 120, 0)
	mat.angular_velocity_min = -220.0
	mat.angular_velocity_max = 220.0
	mat.direction = Vector3(direction.x, direction.y, 0.0)

	var amount: int = 20
	var tex: Texture2D = SPARK_TEX
	var ring_color: Color = CombatPalette.damage_hp
	var ring_size: float = 24.0

	match kind:
		"blood":
			amount = int(round(32 * intensity))
			p.lifetime = 0.60
			tex = SPARK_TEX
			mat.spread = 55.0
			mat.initial_velocity_min = 100.0 * intensity
			mat.initial_velocity_max = 230.0 * intensity
			mat.scale_min = 0.85 * intensity
			mat.scale_max = 1.55 * intensity
			mat.scale_curve = _build_scale_curve(1.0, 0.15)
			mat.color_ramp = _build_color_ramp([
				CombatPalette.with_alpha(CombatPalette.damage_hp, 1.0),
				Color(0.55, 0.05, 0.05, 0.9),
				Color(0.30, 0.00, 0.00, 0.0),
			])
			mat.gravity = Vector3(direction.x * 40.0, direction.y * 40.0 + 200.0, 0.0)
			ring_color = CombatPalette.with_alpha(CombatPalette.damage_hp, 0.75)
			ring_size = 28.0 + 10.0 * intensity
		"spark":
			amount = int(round(22 * intensity))
			p.lifetime = 0.38
			tex = SPARK_TEX
			mat.spread = 140.0
			mat.initial_velocity_min = 160.0 * intensity
			mat.initial_velocity_max = 300.0 * intensity
			mat.scale_min = 0.45 * intensity
			mat.scale_max = 1.0 * intensity
			mat.scale_curve = _build_scale_curve(1.0, 0.0)
			mat.color_ramp = _build_color_ramp([
				Color(1.00, 1.00, 0.90, 1.0),
				CombatPalette.with_alpha(CombatPalette.accent_gold, 0.95),
				CombatPalette.with_alpha(CombatPalette.armor_hit, 0.0),
			])
			mat.gravity = Vector3.ZERO
			ring_color = CombatPalette.with_alpha(CombatPalette.armor_hit, 0.85)
			ring_size = 22.0
		"smoke":
			amount = int(round(16 * intensity))
			p.lifetime = 1.20
			tex = SMOKE_TEX
			mat.spread = 35.0
			mat.initial_velocity_min = 30.0
			mat.initial_velocity_max = 70.0
			mat.scale_min = 0.6
			mat.scale_max = 1.2
			mat.scale_curve = _build_scale_curve(0.6, 1.7)
			mat.color_ramp = _build_color_ramp([
				Color(0.65, 0.60, 0.55, 0.9),
				Color(0.45, 0.42, 0.38, 0.5),
				Color(0.30, 0.28, 0.25, 0.0),
			])
			mat.gravity = Vector3(0, -25, 0)

	p.amount = amount
	p.process_material = mat
	p.texture = tex

	parent.add_child(p)
	p.emitting = true

	if kind == "blood" or kind == "spark":
		_spawn_impact_ring(parent, local_pos, ring_color, ring_size)

	var tree: SceneTree = parent.get_tree()
	if tree:
		var timer: SceneTreeTimer = tree.create_timer(p.lifetime + 0.3)
		timer.timeout.connect(p.queue_free)


static func _spawn_impact_ring(parent: Node, local_pos: Vector2, color: Color, max_r: float) -> void:
	var ring := ImpactRing.new()
	ring.position = local_pos
	ring.ring_color = color
	ring._max_radius = max_r
	ring.modulate = Color(1, 1, 1, 0.9)
	parent.add_child(ring)


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
