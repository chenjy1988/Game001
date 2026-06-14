extends RefCounted
class_name AbilityEffectSpec

const _Enums = preload("res://scripts/core/abilities/AbilityEnums.gd")
##
## AbilityEffectSpec — 能力施加的战斗效果描述（声明式，不含结算逻辑）
##
## I0 CombatEffectContainer 落地后，由 EffectDB.create_from_spec() 实例化 CombatEffect。
## 能力只负责「对谁、挂什么、持续多久」；数值 fold 在容器内完成。
##

var effect_id: String = ""           ## 对齐 data/effects.json / EffectDB
var display_name: String = ""
var polarity: int = _Enums.EffectPolarity.DEBUFF
var target = null                    ## Unit：效果承载单位（可敌可友）
var source = null                    ## Unit：施加者（DoT 来源、UI 归因）
var turns: int = 1                   ## 回合数；-1 = 战斗结束或子类自定
var stacks: int = 1
var refresh_if_exists: bool = true   ## 非 stacking 时刷新持续时间
var params: Dictionary = {}          ## 覆写模板字段（如 dot 倍率）


static func buff(effect_id: String, target, source, turns: int = 1):
	var s := new()
	s.effect_id = effect_id
	s.polarity = _Enums.EffectPolarity.BUFF
	s.target = target
	s.source = source
	s.turns = turns
	return s


static func debuff(effect_id: String, target, source, turns: int = 1):
	var s := new()
	s.effect_id = effect_id
	s.polarity = _Enums.EffectPolarity.DEBUFF
	s.target = target
	s.source = source
	s.turns = turns
	return s


## 从 JSON 字典构造（数据驱动技能用）
##   cfg = {
##     "type": "buff" | "debuff" | "neutral",
##     "id":   "<effect_id>",        # 必填
##     "duration": 2,                # 默认 1
##     "stacks": 1,                  # 默认 1
##     "params": { ... },            # 透传给 CombatEffect
##   }
static func from_dict(cfg: Dictionary, target, source):
	var s := new()
	s.effect_id = String(cfg.get("id", ""))
	s.target = target
	s.source = source
	s.turns = int(cfg.get("duration", 1))
	s.stacks = int(cfg.get("stacks", 1))
	s.refresh_if_exists = bool(cfg.get("refresh", true))
	s.params = cfg.get("params", {}) if cfg.get("params") is Dictionary else {}
	var ty: String = String(cfg.get("type", "debuff")).to_lower()
	match ty:
		"buff":    s.polarity = _Enums.EffectPolarity.BUFF
		"neutral": s.polarity = _Enums.EffectPolarity.NEUTRAL
		_:         s.polarity = _Enums.EffectPolarity.DEBUFF
	return s
