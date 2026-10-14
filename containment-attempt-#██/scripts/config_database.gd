extends RefCounted
## Versioned JSON tables with stable IDs. Invalid configuration blocks new runs.

const ROOT = "res://configs/"
const TABLE_FIELDS = {
	"stats": {"type": "string", "default": "number", "min": "number", "max": "number"},
	"weapon_categories": {},
	"weapons": {"enabled": "bool", "category_id": "string", "behavior": "string", "description": "string", "effects": "array"},
	"characters": {"enabled": "bool", "code": "string", "english_name": "string", "description": "string", "base_stats": "object", "starting_weapon_id": "string", "buff_weapons": "array", "debuff_weapons": "array", "forbidden_weapon_categories": "array"},
	"upgrades": {"enabled": "bool", "description": "string", "tag": "string", "effects": "array", "price": "number", "heal_on_apply": "number"},
	"rewards": {"enabled": "bool", "kind": "string"},
	"reward_pools": {"entries": "array"},
	"monsters": {"enabled": "bool", "behavior": "string", "visual": "string", "stats": "object", "scaling": "object", "attack": "object", "drop_reward_id": "string"},
	"containments": {"enabled": "bool", "kind": "string", "code": "string", "risk_class": "string", "description": "string", "effects": "array", "heal_on_apply": "number"},
	"rooms": {"kind": "string", "title": "string", "map_symbol": "string", "cleared_on_entry": "bool", "lock_until_clear": "bool"},
	"floors": {"start_position": "array", "cells": "array"},
}
var tables: Dictionary = {}
var settings: Dictionary = {}
var errors: Array[String] = []

func load_all() -> bool:
	tables.clear()
	settings.clear()
	errors.clear()
	var manifest = _read("manifest.json")
	if not _fields(manifest, {"tables": "object", "settings": "string"}, "manifest.json"):
		return false
	for table in TABLE_FIELDS:
		if not manifest.tables.has(table) or not manifest.tables[table] is String:
			errors.append("manifest.json: 缺少配置表路径 %s" % table)
	if not errors.is_empty(): return false
	for table in manifest.tables:
		if not manifest.tables[table] is String:
			errors.append("manifest.json: %s 的文件路径必须是字符串" % table)
			continue
		var file: String = manifest.tables[table]
		var document = _read(file)
		var index: Dictionary = {}
		if _fields(document, {"items": "array"}, file):
			for record in document.items:
				var fields = TABLE_FIELDS.get(table, {}).duplicate()
				fields.merge({"id": "string", "name": "string"})
				if not _object(record, file) or not _fields(record, fields, file):
					continue
				if record.id.is_empty() or index.has(record.id):
					errors.append("%s: 空编号或重复编号 %s" % [file, record.id])
					continue
				index[record.id] = record
		tables[table] = index
	settings = _read(manifest.settings)
	if not errors.is_empty(): return false
	_validate()
	return errors.is_empty()

func _read(filename: String) -> Dictionary:
	if filename.contains("..") or filename.contains(":") or not filename.ends_with(".json"):
		errors.append("非法配置路径：%s" % filename)
		return {}
	var file = FileAccess.open(ROOT + filename, FileAccess.READ)
	if file == null:
		errors.append("无法读取 %s（错误 %d）" % [filename, FileAccess.get_open_error()])
		return {}
	var parser = JSON.new()
	var code = parser.parse(file.get_as_text())
	file.close()
	if code != OK:
		errors.append("%s 第 %d 行：%s" % [filename, parser.get_error_line() + 1, parser.get_error_message()])
		return {}
	if not parser.data is Dictionary:
		errors.append("%s 根节点必须是对象" % filename)
		return {}
	var data: Dictionary = parser.data
	if data.get("schema_version", 0) != 1:
		errors.append("%s: 当前只支持 schema_version=1" % filename)
	return data

func _type(value: Variant, expected: String) -> bool:
	match expected:
		"string": return value is String
		"object": return value is Dictionary
		"array": return value is Array
		"bool": return value is bool
		"number": return (value is int or value is float) and is_finite(float(value))
	return false

func _fields(data: Dictionary, fields: Dictionary, context: String) -> bool:
	var valid = true
	for field in fields:
		if not data.has(field) or not _type(data[field], fields[field]):
			errors.append("%s: %s 必须为 %s" % [context, field, fields[field]])
			valid = false
	return valid

func _object(value: Variant, context: String) -> bool:
	if value is Dictionary: return true
	errors.append("%s: 每项记录必须是对象" % context)
	return false

func _number(data: Dictionary, key: String, context: String, minimum: float = 0.0, integer: bool = false) -> bool:
	if not _fields(data, {key: "number"}, context): return false
	var value = float(data[key])
	if value < minimum or (integer and value != floorf(value)):
		errors.append("%s: %s 必须 >= %s%s" % [context, key, minimum, " 且为整数" if integer else ""])
		return false
	return true

func _ref(table: String, id: Variant, context: String) -> bool:
	if not id is String or not tables.get(table, {}).has(id):
		errors.append("%s: 找不到 %s 编号 %s" % [context, table, str(id)])
		return false
	return true

func _effects(effects: Array, context: String) -> void:
	for effect in effects:
		if not effect is Dictionary or not _fields(effect, {"stat": "string", "op": "string", "value": "number"}, context):
			errors.append("%s: effects 每项须为 stat/op/value 对象" % context)
			continue
		_ref("stats", effect.stat, context)
		if effect.op not in ["add", "multiply"] or (effect.op == "multiply" and effect.value <= 0):
			errors.append("%s: 仅支持 add 或正数 multiply" % context)
		if effect.has("cap"): _number(effect, "cap", context)

func _validate() -> void:
	for item in records("stats"):
		if item.type not in ["int", "float"] or item.min > item.max or item.default < item.min or item.default > item.max:
			errors.append("stats/%s: 类型或 min/default/max 不合法" % item.id)
		if item.type == "int" and (item.default != floorf(item.default) or item.min != floorf(item.min) or item.max != floorf(item.max)):
			errors.append("stats/%s: int 属性的默认值和边界必须为整数" % item.id)
	for key in ["max_hp", "damage", "fire_interval", "speed", "projectiles", "pierce", "armor", "magnet", "range", "bullet_speed", "spread_angle", "dash_speed", "dash_duration", "dash_cooldown"]:
		_ref("stats", key, "必需属性")
	for key in ["max_hp", "damage", "fire_interval", "speed", "projectiles", "range", "bullet_speed", "dash_duration", "dash_cooldown"]:
		if tables.stats.has(key) and tables.stats[key].min <= 0:
			errors.append("stats/%s.min 必须 > 0" % key)
	if tables.stats.has("armor") and tables.stats.armor.max >= 1:
		errors.append("stats/armor.max 必须 < 1")
	for table in ["weapons", "upgrades", "containments"]:
		for item in records(table):
			_effects(item.effects, table + "/" + item.id)
			if item.has("heal_on_apply"): _number(item, "heal_on_apply", item.id)
			if item.has("price"): _number(item, "price", item.id, 0, true)
	for item in records("weapons"):
		_ref("weapon_categories", item.category_id, item.id)
		if item.behavior != "projectile_auto": errors.append("%s: 未实现的武器行为" % item.id)
	for item in records("characters"):
		var seen: Array = []
		for key in item.base_stats:
			if _ref("stats", key, item.id) and _number(item.base_stats, key, item.id, float(get_record("stats", key).min)):
				var definition = get_record("stats", key)
				if item.base_stats[key] < definition.min or item.base_stats[key] > definition.max:
					errors.append("%s: 属性 %s 超出范围" % [item.id, key])
				if definition.type == "int" and item.base_stats[key] != floorf(item.base_stats[key]):
					errors.append("%s: 属性 %s 必须为整数" % [item.id, key])
		for group in ["buff_weapons", "debuff_weapons"]:
			for rule in item[group]:
				if not _object(rule, item.id) or not _fields(rule, {"category_id": "string", "effects": "array"}, item.id): continue
				_ref("weapon_categories", rule.category_id, item.id)
				_effects(rule.effects, item.id)
				if rule.category_id in seen: errors.append("%s: buff/debuff 品类重复或冲突" % item.id)
				seen.append(rule.category_id)
		for id in item.forbidden_weapon_categories:
			_ref("weapon_categories", id, item.id)
			if id in seen: errors.append("%s: 禁用品类不能同时配置 buff/debuff" % item.id)
		if _ref("weapons", item.starting_weapon_id, item.id):
			var weapon = get_record("weapons", item.starting_weapon_id)
			if not weapon.enabled or weapon.category_id in item.forbidden_weapon_categories:
				errors.append("%s: 初始武器未开放或被禁止" % item.id)
	for item in records("containments"):
		if item.kind == "hostile":
			if _ref("monsters", item.get("monster_id", ""), item.id) and not get_record("monsters", item.monster_id).enabled:
				errors.append("%s: 收容对象引用的怪物未开放" % item.id)
		elif item.kind == "artifact": _fields(item, {"tag": "string", "unique": "bool"}, item.id)
		else: errors.append("%s: 未实现的收容物种类" % item.id)
	for item in records("rewards"):
		match item.kind:
			"upgrade": _ref("upgrades", item.get("upgrade_id", ""), item.id)
			"weapon": _ref("weapons", item.get("weapon_id", ""), item.id)
			"containment":
				if _ref("containments", item.get("containment_id", ""), item.id) and get_record("containments", item.containment_id).kind != "artifact":
					errors.append("%s: 只能奖励 artifact 收容物" % item.id)
			"scrap", "heal": _number(item, "amount", item.id, 0.001)
			_: errors.append("%s: 未实现的奖励种类" % item.id)
		if item.has("price"): _number(item, "price", item.id, 0, true)
	for item in records("reward_pools"):
		var seen: Array = []
		for entry in item.entries:
			if not _object(entry, item.id) or not _fields(entry, {"reward_id": "string", "weight": "number"}, item.id): continue
			_ref("rewards", entry.reward_id, item.id)
			_number(entry, "weight", item.id, 0.000001)
			if entry.reward_id in seen: errors.append("%s: 重复奖励编号" % item.id)
			seen.append(entry.reward_id)
	for item in records("monsters"):
		if item.behavior not in ["chaser", "shooter", "boss_radial_charge"] or item.visual not in ["chaser", "shooter", "tank", "boss"]:
			errors.append("%s: 未实现的怪物行为或外观" % item.id)
		for key in ["hp", "radius", "speed", "contact_damage"]: _number(item.stats, key, item.id, 0.001)
		for key in ["hp_per_clear", "speed_per_clear"]: _number(item.scaling, key, item.id)
		var fields: Array = []
		if item.behavior == "shooter": fields = ["approach_distance", "retreat_distance", "interval", "bullet_speed", "damage"]
		if item.behavior == "boss_radial_charge": fields = ["initial_interval", "phase_threshold", "bullet_count", "enraged_bullet_count", "interval", "enraged_interval", "bullet_speed", "damage", "charge_warning", "charge_duration", "charge_speed"]
		for key in fields: _number(item.attack, key, item.id, 0.001)
		if item.behavior == "boss_radial_charge":
			_number(item.attack, "bullet_count", item.id, 1, true)
			_number(item.attack, "enraged_bullet_count", item.id, 1, true)
			if _type(item.attack.get("phase_threshold"), "number") and item.attack.phase_threshold >= 1:
				errors.append("%s: phase_threshold 必须在 0 到 1 之间" % item.id)
		if _ref("rewards", item.drop_reward_id, item.id) and get_record("rewards", item.drop_reward_id).kind != "scrap":
			errors.append("%s: 当前怪物掉落只支持 scrap" % item.id)
	for item in records("rooms"): _validate_room(item)
	# Floor validation consumes room fields, so stop if the content is malformed.
	if not errors.is_empty(): return
	for item in records("floors"): _validate_floor(item)
	if _fields(settings, {"default_character_id": "string", "default_floor_id": "string", "combat": "object"}, "balance.json"):
		if _ref("characters", settings.default_character_id, "默认角色") and not get_record("characters", settings.default_character_id).enabled:
			errors.append("默认角色必须已开放")
		_ref("floors", settings.default_floor_id, "默认楼层")
		for key in ["entry_invulnerability", "hit_invulnerability", "door_cooldown", "door_trigger_distance", "spawn_margin", "spawn_min_distance", "spawn_position_attempts", "enemy_initial_attack_min", "enemy_initial_attack_max", "hostile_bullet_lifetime", "pickup_radius", "pickup_speed"]:
			_number(settings.combat, key, "balance.combat", 0.001)
		_number(settings.combat, "spawn_position_attempts", "balance.combat", 1, true)

func _validate_room(item: Dictionary) -> void:
	if item.kind not in ["start", "combat", "treasure", "supply", "boss"]: errors.append("%s: 未实现的房型" % item.id)
	if item.kind in ["combat", "boss"] and item.cleared_on_entry:
		errors.append("%s: 战斗/核心房不能设为进入时已清除" % item.id)
	if item.kind in ["combat", "treasure"]:
		_ref("reward_pools", item.get("choice_pool_id", ""), item.id)
		if _number(item, "choice_count", item.id, 1, true) and item.choice_count > 3: errors.append("%s: 当前选择界面最多 3 项" % item.id)
	if item.kind == "combat":
		if not _fields(item, {"waves": "object", "clear_reward_id": "string"}, item.id): return
		for key in ["count", "base_count"]: _number(item.waves, key, item.id, 1, true)
		for key in ["extra_per_wave", "extra_per_clear", "clear_bonus_cap"]: _number(item.waves, key, item.id, 0, true)
		for key in ["initial_delay", "between_delay"]: _number(item.waves, key, item.id, 0.001)
		if _fields(item.waves, {"monster_cycle": "array"}, item.id):
			if item.waves.monster_cycle.is_empty(): errors.append("%s: 刷怪循环不能为空" % item.id)
			for id in item.waves.monster_cycle:
				if _ref("monsters", id, item.id) and not get_record("monsters", id).enabled: errors.append("%s: 刷怪循环含未开放怪物" % item.id)
		if _ref("rewards", item.clear_reward_id, item.id) and get_record("rewards", item.clear_reward_id).kind not in ["scrap", "heal"]:
			errors.append("%s: 清房即时奖励仅支持 scrap/heal" % item.id)
	elif item.kind == "supply":
		if not _fields(item, {"shop": "object"}, item.id): return
		_ref("reward_pools", item.shop.get("pool_id", ""), item.id)
		for key in ["slots", "medical_uses"]: _number(item.shop, key, item.id, 1, true)
		if _type(item.shop.get("slots"), "number") and item.shop.slots > 3:
			errors.append("%s: 当前补给界面最多 3 栏" % item.id)
		for key in ["reroll_cost", "reroll_increment"]: _number(item.shop, key, item.id, 0, true)
		if _ref("rewards", item.shop.get("medical_reward_id", ""), item.id) and get_record("rewards", item.shop.medical_reward_id).kind != "heal":
			errors.append("%s: 医疗须引用 heal 奖励" % item.id)
	elif item.kind == "boss":
		_number(item, "required_combat_clears", item.id, 0, true)
		if _ref("containments", item.get("containment_id", ""), item.id):
			var obj = get_record("containments", item.containment_id)
			if obj.kind != "hostile" or not obj.enabled: errors.append("%s: 核心房须引用开放的 hostile 收容物" % item.id)

func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _type(value[0], "number") and _type(value[1], "number") and value[0] == floorf(value[0]) and value[1] == floorf(value[1])

func _validate_floor(item: Dictionary) -> void:
	if not _position(item.start_position):
		errors.append("%s: 起点必须为 [整数, 整数]" % item.id)
		return
	var cells: Dictionary = {}
	var combats = 0
	var bosses = 0
	for entry in item.cells:
		if not entry is Dictionary or not _fields(entry, {"position": "array", "room_id": "string"}, item.id) or not _position(entry.position):
			errors.append("%s: 房间坐标须为 [整数, 整数]" % item.id)
			continue
		var cell = Vector2i(int(entry.position[0]), int(entry.position[1]))
		if cells.has(cell): errors.append("%s: 重复坐标 %s" % [item.id, cell])
		cells[cell] = entry.room_id
		if _ref("rooms", entry.room_id, item.id):
			var room = get_record("rooms", entry.room_id)
			if room.kind == "combat": combats += 1
			if room.kind == "boss": bosses += 1
	var start = Vector2i(int(item.start_position[0]), int(item.start_position[1]))
	if not cells.has(start) or bosses != 1:
		errors.append("%s: 起点必须有房间，当前一层须恰好一个核心房" % item.id)
		return
	if get_record("rooms", cells[start]).get("kind", "") != "start":
		errors.append("%s: 起点须引用 start 房型" % item.id)
	var seen: Dictionary = {start: true}
	var pending: Array = [start]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next = cell + direction
			if cells.has(next) and not seen.has(next):
				seen[next] = true
				pending.append(next)
	if seen.size() != cells.size(): errors.append("%s: 所有房间必须连通" % item.id)
	for room_id in cells.values():
		var room = get_record("rooms", room_id)
		if room.get("kind", "") == "boss" and room.required_combat_clears > combats:
			errors.append("%s: 核心门禁要求超过战斗房数量" % item.id)
	# Ensure the core door does not hide the rooms needed to unlock that very door.
	var accessible: Dictionary = {start: true}
	var frontier: Array = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next = cell + direction
			if cells.has(next) and not accessible.has(next) and get_record("rooms", cells[next]).get("kind", "") != "boss":
				accessible[next] = true
				frontier.append(next)
	var accessible_combats = 0
	for cell in accessible:
		if get_record("rooms", cells[cell]).get("kind", "") == "combat": accessible_combats += 1
	for room_id in cells.values():
		var room = get_record("rooms", room_id)
		if room.get("kind", "") == "boss" and room.required_combat_clears > accessible_combats:
			errors.append("%s: 门禁前能到达的战斗房不足，地图将无法通关" % item.id)

func get_record(table: String, id: String) -> Dictionary:
	return tables.get(table, {}).get(id, {}).duplicate(true)

func records(table: String) -> Array:
	return tables.get(table, {}).values()

func default_stats() -> Dictionary:
	var result: Dictionary = {}
	for item in records("stats"):
		result[item.id] = int(item.default) if item.type == "int" else float(item.default)
	return result

func clamp_stats(stats: Dictionary) -> void:
	for item in records("stats"):
		var value = clampf(float(stats.get(item.id, item.default)), float(item.min), float(item.max))
		stats[item.id] = int(value) if item.type == "int" else value
