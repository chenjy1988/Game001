extends RefCounted
##
## Procedural audio primitives (from creating-godot-procedural-audio skill).

static func push_sample(playback: AudioStreamGeneratorPlayback, sample: float) -> bool:
	var v := clampf(sample, -1.0, 1.0)
	return playback.push_frame(Vector2(v, v))


static func sfx_envelope(t: float, duration: float, attack_ratio: float = 0.1, release_ratio: float = 0.45) -> float:
	if duration <= 0.0:
		return 0.0
	var attack_time: float = maxf(0.001, duration * attack_ratio)
	var release_time: float = maxf(0.001, duration * release_ratio)
	if t < attack_time:
		return t / attack_time
	if t > duration - release_time:
		return max(0.0, (duration - t) / release_time)
	return 1.0


static func sine(phase: float) -> float:
	return sin(phase * TAU)


static func square(phase: float, duty: float = 0.5) -> float:
	return 1.0 if fmod(phase, 1.0) < duty else -1.0


static func triangle(phase: float) -> float:
	var t := fmod(phase, 1.0)
	return 4.0 * absf(t - 0.5) - 1.0


static func noise(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(-1.0, 1.0)


static func samples_to_wav(samples: PackedFloat32Array, mix_rate: int = 22050) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var s: int = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	wav.data = data
	return wav
