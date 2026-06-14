extends RefCounted
class_name AbilityEnums
##
## AbilityEnums — 能力目标 / 类型 / 效果极性（职业技能扩展用）
##

enum Targeting {
	NONE,              ## 无目标（全场规则、被动开关）
	SELF,              ## 仅自身（吐纳、先发制人）
	SINGLE_ALLY,       ## 单体友军（战吼、包扎）
	SINGLE_ENEMY,      ## 单体敌军（普攻、涂毒、眩晕）
	SINGLE_ANY,        ## 任意存活单位（极少用）
	ALL_ALLIES,        ## 全体友军（鼓舞；范围由子类 filter）
	ALL_ENEMIES,       ## 全体敌军（恐惧光环）
	ALLIES_IN_RANGE,   ## 范围内友军
	ENEMIES_IN_RANGE,  ## 范围内敌军（AOE debuff）
}

enum Kind {
	ATTACK,            ## 走 DamageSystem（普攻、处决）
	BUFF,              ## 仅施加友方增益
	DEBUFF,            ## 仅施加敌方减益
	UTILITY,           ## 位移 / 资源 / 回合序（不发 Effect）
	HYBRID,            ## 攻击 + 效果（涂毒、碎甲附带眩晕）
}

enum EffectPolarity {
	BUFF,
	DEBUFF,
	NEUTRAL,           ## 标记类、破绽（双方可读）
}
