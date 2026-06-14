extends RefCounted
class_name AbilityLibrary
##
## AbilityLibrary.gd — 能力注册表（数据驱动）
##
## 加载顺序：
##   1) 注册必要的 .gd 子类实例（如 BasicAttack —— 走 DamageSystem 完整管线）
##   2) 从 data/abilities.json 加载所有数据驱动技能（GenericAbility）
##   3) 按 id 索引；外部统一通过 get(id) 获取实例
##
## 加新技能：
##   - 多数情况：在 data/abilities.json 增加一段 JSON，零代码改动
##   - 特殊情况（命中回调、复杂 can_use、自定义 targeting）：写 .gd 子类，
##     在 _register_native() 中显式注册
##

const _BasicAttack    = preload("res://scripts/core/abilities/BasicAttack.gd")
const _GenericAbility = preload("res://scripts/core/abilities/GenericAbility.gd")
const _Qiaoshou       = preload("res://scripts/core/abilities/Qiaoshou.gd")

const ABILITIES_JSON_PATH := "res://data/abilities.json"

static var _by_id: Dictionary = {}
static var _initialized: bool = false


# ──────────── 公共 API ────────────

## 通用获取入口：先按 id 查表（含 .gd 子类与 JSON 技能）
## 注：方法名 get_by_id 而非 get，避免与 Object.get() 冲突
static func get_by_id(ability_id: String):
	_ensure_loaded()
	return _by_id.get(ability_id, null)


## 已实装能力快捷访问（兼容旧调用点）
static func basic_attack():
	_ensure_loaded()
	return _by_id.get("basic_attack", null)


static func tuizhuang():
	_ensure_loaded()
	return _by_id.get("tui_zhuang", null)


static func huanwei():
	_ensure_loaded()
	return _by_id.get("huan_wei", null)


static func chaofeng():
	_ensure_loaded()
	return _by_id.get("chao_feng", null)


static func yixing():
	_ensure_loaded()
	return _by_id.get("yi_xing", null)


static func zhenfenjunxin():
	_ensure_loaded()
	return _by_id.get("zhen_fen_jun_xin", null)


static func qiaoshou():
	_ensure_loaded()
	return _by_id.get("qiao_shou", null)


static func baoza():
	_ensure_loaded()
	return _by_id.get("bao_za", null)


static func baoza_jingjin():
	_ensure_loaded()
	return _by_id.get("bao_za_jing_jin", null)


## 列出全部能力（单测 / 调试用）
static func all() -> Array:
	_ensure_loaded()
	return _by_id.values()


## 按 id 列表（调试 / UI 列表）
static func ids() -> Array:
	_ensure_loaded()
	return _by_id.keys()


## 测试 / 热重载用：清空缓存重新装载
static func reload() -> void:
	_by_id.clear()
	_initialized = false
	_ensure_loaded()


# ──────────── 内部加载 ────────────

static func _ensure_loaded() -> void:
	if _initialized:
		return
	_initialized = true
	_register_native()
	_load_from_json(ABILITIES_JSON_PATH)


## 显式注册的 .gd 子类（无法 JSON 化的特殊技能）
static func _register_native() -> void:
	# BasicAttack 走 DamageSystem 完整管线，必须 .gd
	var ba = _BasicAttack.new()
	if ba.id == "":
		ba.id = "basic_attack"
	_by_id[ba.id] = ba

	# 巧手（§5.4）：武器切换，自定义 apply()
	var qs = _Qiaoshou.new()
	_by_id[qs.id] = qs

	# 包扎 / 包扎·精进 均为 JSON 数据驱动（GenericAbility）


## 加载 JSON 技能配置
static func _load_from_json(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("[AbilityLibrary] abilities.json not found: %s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[AbilityLibrary] cannot open: %s" % path)
		return
	var text: String = f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[AbilityLibrary] invalid JSON root in %s" % path)
		return

	var loaded: int = 0
	for k in parsed.keys():
		if String(k).begins_with("_"):
			continue  # 注释字段
		var cfg = parsed[k]
		if not (cfg is Dictionary):
			continue
		# id 兜底：若 JSON 内未填，用键名
		if not cfg.has("id"):
			cfg["id"] = String(k)
		var ab = _GenericAbility.from_dict(cfg)
		if ab == null or ab.id == "":
			continue
		# 注意：JSON 可以覆盖 native 注册（如热重载迭代 BasicAttack 配置）
		_by_id[ab.id] = ab
		loaded += 1

	if loaded > 0:
		print("[AbilityLibrary] loaded %d JSON abilities from %s" % [loaded, path])
