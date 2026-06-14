extends RefCounted
class_name AbilityResult
##
## AbilityResult — use_ability() 统一返回字典的键名（避免魔法字符串散落）
##

const OK := "ok"
const REASON := "reason"
const ABILITY_ID := "ability_id"
const KIND := "kind"
const TARGETS := "targets"              ## Array[Unit]
const EFFECTS_APPLIED := "effects_applied"  ## Array[AbilityEffectSpec]
const DAMAGE_RESULTS := "damage_results"    ## Array[Dictionary]（HYBRID / 多段）
const PRIMARY := "primary"              ## 主伤害结果（ATTACK 兼容旧 UI）


static func fail(reason: String, ability_id: String = "") -> Dictionary:
	return {OK: false, REASON: reason, ABILITY_ID: ability_id}


static func success(ability_id: String, kind: int, payload: Dictionary = {}) -> Dictionary:
	var r: Dictionary = {OK: true, ABILITY_ID: ability_id, KIND: kind}
	r.merge(payload, true)
	return r
