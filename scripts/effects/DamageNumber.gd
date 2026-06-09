extends Node
class_name DamageNumber
##
## DamageNumber.gd — 战斗中的伤害飘字（一次性 Label + Tween）
##
## 设计：
## - 每次调用 `spawn(layer, pos, text, color, big)` 在指定世界坐标创建 Label，
##   1 秒内向上飘 + 渐隐 + 自销毁；调用方零状态管理。
## - 不依赖 .tscn，所有视觉风格在此文件常量集中调；与 HitEffect 风格保持一致。
## - 字号：暴击 30 / 普通 20 / 未命中 16；颜色由调用方决定（红/灰/黄/白等）。
##
## 三种典型用法（约定，不强制）：
##   普通伤害      DamageNumber.spawn(layer, pos, "12", Color.RED)
##   暴击          DamageNumber.spawn(layer, pos, "27!", Color(1, 0.5, 0.2), true)
##   未命中        DamageNumber.spawn(layer, pos, "MISS", Color(0.7,0.7,0.7))
##   纯破甲        DamageNumber.spawn(layer, pos, "甲-8", Color(0.7,0.85,1.0))

const RISE_DISTANCE: float = 38.0   ## 上飘像素
const DURATION: float = 0.85        ## 总时长（s）
const FADE_DELAY: float = 0.30      ## 淡出开始时间（前 0.3s 保持完全不透明）


static func spawn(parent: Node, local_pos: Vector2, text: String,
		color: Color = Color(1, 1, 1), big: bool = false) -> void:
	if parent == null:
		return

	var label: Label = Label.new()
	label.text = text
	label.modulate = color
	label.z_index = 100   ## 永远在单位之上
	# 文本居中：把 Label 当成"以指定点为底部中点"的浮字
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font_size: int = 22 if big else 14
	if text == "MISS" or text.begins_with("甲"):
		font_size = 12
	label.add_theme_font_size_override("font_size", font_size)
	# 描边让数字在乱底色里也清晰
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 2)

	# 摆放：以 local_pos 为下方中点，初始略微随机偏移避免叠字
	var jitter: Vector2 = Vector2(randf_range(-6, 6), randf_range(-2, 2))
	var w: float = font_size * 4.0
	var h: float = float(font_size) + 6.0
	label.size = Vector2(w, h)
	label.position = local_pos + jitter - Vector2(w * 0.5, h + 18.0)

	parent.add_child(label)

	# 动画：并行（位移 + 淡出）
	var tw: Tween = label.create_tween().set_parallel(true)
	tw.tween_property(label, "position:y",
		label.position.y - RISE_DISTANCE, DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(label, "modulate:a", 0.0, DURATION - FADE_DELAY).set_delay(FADE_DELAY)
	# 暴击额外：开场弹一下尺寸（scale 1.4 → 1.0）
	if big:
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2(1.4, 1.4)
		tw.tween_property(label, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT)

	# 完成后销毁
	var tree: SceneTree = parent.get_tree()
	if tree:
		tree.create_timer(DURATION + 0.05).timeout.connect(label.queue_free)
