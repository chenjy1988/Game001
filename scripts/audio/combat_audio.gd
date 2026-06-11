extends Node

const Synth = preload("res://scripts/audio/audio_synth.gd")
##
## CombatAudio — 战斗程序化音效（creating-godot-procedural-audio）
##
## 事件语义（本游戏固定）：
##   miss      — 短促风声（未命中）
##   armor     — 金属钝击（破甲 / 格挡感）
##   damage    — 低沉重击 + 噪声（见血）
##   crit      — damage + 高音金属亮峰
##   blocked   — 沉闷盾击
##   death     — 下行尾音（倒下）
##   footstep  — 步行落脚（每格一步）
##
## 无头模式（OS.has_feature("headless")）跳过播放，单测不受影响。

const MIX_RATE: int = 22050
const POOL_SIZE: int = 10

const FOOTSTEP_VOLUME_DB: float = -5.5

var _enabled: bool = true
var _rng := RandomNumberGenerator.new()
var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}  ## event_id -> AudioStreamWAV
var _step_toggle: bool = false


func _ready() -> void:
	_rng.randomize()
	_enabled = not OS.has_feature("headless")
	if not _enabled:
		return
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		p.volume_db = -4.0
		add_child(p)
		_players.append(p)


func play_miss() -> void:
	_play("miss")


func play_armor_hit() -> void:
	_play("armor")


func play_damage(intensity: float = 1.0) -> void:
	_play("damage", clampf(intensity, 0.5, 1.5))


func play_crit() -> void:
	_play("crit")


func play_blocked() -> void:
	_play("blocked")


func play_death() -> void:
	_play("death")


func play_footstep(weight: int = 0) -> void:
	_step_toggle = not _step_toggle
	var heaviness: float = clampf(float(weight) / 30.0, 0.25, 1.0)
	var side: float = 1.05 if _step_toggle else 0.94
	var pitch: float = side * lerpf(1.06, 0.90, heaviness) * _rng.randf_range(0.985, 1.015)
	var tier: float = roundf(heaviness * 4.0) / 4.0  # 0.25 步进缓存
	_play("footstep", tier, FOOTSTEP_VOLUME_DB, pitch)


func _play(event_id: String, intensity: float = 1.0, volume_db: float = -4.0, pitch: float = -1.0) -> void:
	if not _enabled:
		return
	var cache_key := "%s_%.2f" % [event_id, intensity]
	if not _cache.has(cache_key):
		var samples := _generate(event_id, intensity)
		if samples.is_empty():
			return
		_cache[cache_key] = Synth.samples_to_wav(samples, MIX_RATE)
	var stream: AudioStreamWAV = _cache[cache_key]
	var player := _get_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch if pitch > 0.0 else _rng.randf_range(0.97, 1.03)
	player.play()


func _get_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0] if not _players.is_empty() else null


func _generate(event_id: String, intensity: float) -> PackedFloat32Array:
	match event_id:
		"miss":
			return _gen_noise_burst(0.07, 0.35, 800.0)
		"armor":
			return _gen_metal_ping(0.12, 320.0 * intensity, 0.55)
		"damage":
			return _gen_impact(0.16, 140.0 * intensity, 0.75)
		"crit":
			var base := _gen_impact(0.14, 130.0, 0.7)
			var ring := _gen_metal_ping(0.10, 620.0, 0.45)
			return _mix_samples(base, ring, 0.65)
		"blocked":
			return _gen_impact(0.10, 200.0, 0.5)
		"death":
			return _gen_fall(0.38)
		"footstep":
			return _gen_footstep(intensity)
		_:
			return PackedFloat32Array()


func _gen_noise_burst(duration: float, amp: float, _bright_hz: float) -> PackedFloat32Array:
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var env := Synth.sfx_envelope(t, duration, 0.05, 0.55)
		out[i] = Synth.noise(_rng) * env * amp
	return out


func _gen_metal_ping(duration: float, freq: float, amp: float) -> PackedFloat32Array:
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var env := Synth.sfx_envelope(t, duration, 0.02, 0.5)
		var phase := t * freq
		var tri := Synth.triangle(phase) * 0.7
		var nse := Synth.noise(_rng) * 0.15
		out[i] = (tri + nse) * env * amp
	return out


func _gen_impact(duration: float, freq: float, amp: float) -> PackedFloat32Array:
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var env := Synth.sfx_envelope(t, duration, 0.01, 0.55)
		var body := Synth.sine(t * freq) * 0.55
		var crack := Synth.noise(_rng) * 0.45
		out[i] = (body + crack) * env * amp
	return out


func _gen_fall(duration: float) -> PackedFloat32Array:
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var f0 := 280.0
	var f1 := 70.0
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var env := Synth.sfx_envelope(t, duration, 0.08, 0.6)
		var k := t / duration
		var freq := lerpf(f0, f1, k * k)
		var body := Synth.sine(t * freq) * 0.5
		var nse := Synth.noise(_rng) * 0.25 * (1.0 - k)
		out[i] = (body + nse) * env * 0.85
	return out


func _gen_footstep(heaviness: float) -> PackedFloat32Array:
	# 尘土草地脚步：短促鞋跟 + 低频落脚 + 沙沙尾音；heaviness 越高越沉
	var duration: float = lerpf(0.050, 0.082, heaviness)
	var low_hz: float = lerpf(125.0, 72.0, heaviness)
	var n := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var click_len := 0.009
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var env := Synth.sfx_envelope(t, duration, 0.008, 0.70)
		var sample := 0.0
		# 鞋跟/甲片轻响
		if t < click_len:
			var k := 1.0 - t / click_len
			sample += Synth.noise(_rng) * k * lerpf(0.28, 0.42, heaviness)
			sample += Synth.triangle(t * lerpf(900.0, 520.0, heaviness)) * k * 0.12
		# 脚掌着地
		var thud_decay: float = exp(-t * lerpf(22.0, 14.0, heaviness))
		sample += Synth.sine(t * low_hz) * thud_decay * lerpf(0.38, 0.62, heaviness)
		# 尘土摩擦
		var grit: float = Synth.noise(_rng) * absf(Synth.sine(t * 280.0)) * 0.20
		sample += grit * env * (1.0 - t / duration)
		out[i] = clampf(sample * 0.68, -1.0, 1.0)
	return out


func _mix_samples(a: PackedFloat32Array, b: PackedFloat32Array, b_gain: float) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var av: float = a[i] if i < a.size() else 0.0
		var bv: float = b[i] if i < b.size() else 0.0
		out[i] = clampf(av + bv * b_gain, -1.0, 1.0)
	return out
