extends Node
##
## CombatPalette — 战斗视觉反馈色板（directing-game-visuals）
##
## 角色分工：
##   ally / enemy     — 阵营识别（TopBar 边框、单位本体）
##   accent_gold      — 选中、路径、正向强调
##   warning_amber    — ZoC / 借机攻击警示
##   damage_*         — 命中反馈（飘字、闪屏、受击染色）
##   armor_hit        — 破甲 / 格挡火花
##   miss_neutral     — 未命中

# ── 阵营 ──
var ally: Color = Color(0.15, 0.55, 0.85)
var ally_bright: Color = Color(0.40, 0.78, 1.00)
var ally_glow: Color = Color(0.45, 0.75, 1.00)
var enemy: Color = Color(0.82, 0.18, 0.18)
var enemy_bright: Color = Color(1.00, 0.40, 0.40)
var enemy_glow: Color = Color(1.00, 0.45, 0.40)

# ── 战术强调 ──
var accent_gold: Color = Color(0.95, 0.78, 0.30)
var warning_amber: Color = Color(0.95, 0.55, 0.25)
var round_divider: Color = Color(0.85, 0.69, 0.22)
var turn_boost: Color = Color(0.20, 0.90, 0.35)

# ── 战斗反馈 ──
var damage_hp: Color = Color(0.92, 0.28, 0.26)
var damage_crit: Color = Color(1.00, 0.85, 0.30)
var armor_hit: Color = Color(0.70, 0.85, 1.00)
var miss_neutral: Color = Color(0.75, 0.73, 0.60)
var hit_flash_white: Color = Color(2.2, 2.2, 2.2)
var hit_flash_damage: Color = Color(2.0, 0.55, 0.50)
var hit_flash_crit: Color = Color(2.4, 0.70, 0.35)
var hit_flash_miss: Color = Color(1.35, 1.35, 1.40)

# ── 六角格高亮（预乘 alpha）──
var hex_hover: Color = Color(0.95, 0.78, 0.30, 0.22)
var hex_move: Color = Color(0.22, 0.52, 0.82, 0.40)
var hex_attack: Color = Color(0.88, 0.26, 0.24, 0.50)
var hex_attack_edge: Color = Color(0.92, 0.32, 0.28, 0.50)
var hex_attack_target: Color = Color(0.92, 0.22, 0.18, 0.88)    ## BB 风：可攻击敌方小红标
var hex_attack_marker: Color = Color(0.58, 0.58, 0.62, 0.50)    ## BB 风：射程内其他格小灰标
var hex_path: Color = Color(0.95, 0.78, 0.30, 0.85)
var hex_zoc: Color = Color(0.95, 0.55, 0.25, 0.16)
var hex_oa: Color = Color(0.98, 0.42, 0.22, 0.92)
var hex_selected: Color = Color(0.95, 0.90, 0.78, 0.95)
var hex_selected_glow: Color = Color(1.00, 0.95, 0.75, 0.10)

# ── 全屏闪 ──
var screen_flash_crit: Color = Color(1.00, 0.25, 0.20, 0.35)
var screen_flash_heavy: Color = Color(1.00, 0.40, 0.38, 0.18)


func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
