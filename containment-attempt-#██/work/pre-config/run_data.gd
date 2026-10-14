extends RefCounted
## All balancing values and run upgrades live here, separate from presentation.

const BASE_STATS = {
	"max_hp": 100.0, "damage": 12.0, "fire_interval": 0.52,
	"speed": 235.0, "projectiles": 1, "pierce": 0,
	"armor": 0.0, "magnet": 92.0, "range": 690.0,
}

const UPGRADES = [
	{"id": "damage", "name": "高压弹头", "tag": "伤害", "description": "弹丸伤害 +25%", "stat": "damage", "mode": "multiply", "value": 1.25, "price": 28},
	{"id": "rate", "name": "快速循环", "tag": "射速", "description": "攻击间隔缩短 15%", "stat": "fire_interval", "mode": "multiply", "value": 0.85, "price": 30},
	{"id": "multi", "name": "分裂协议", "tag": "弹数", "description": "每次攻击额外发射 1 枚弹丸\n最多 5 枚；形成扇形弹道", "stat": "projectiles", "mode": "add", "value": 1, "cap": 5, "price": 40},
	{"id": "pierce", "name": "贯穿许可", "tag": "穿透", "description": "弹丸可额外穿过 1 个敌人\n最多额外穿过 3 个敌人", "stat": "pierce", "mode": "add", "value": 1, "cap": 3, "price": 32},
	{"id": "hp", "name": "应急组织", "tag": "生命", "description": "生命上限 +20\n同时恢复 20 点生命", "stat": "max_hp", "mode": "add", "value": 20.0, "price": 26},
	{"id": "armor", "name": "复合外壳", "tag": "防御", "description": "伤害减免 +8 个百分点\n最多减免 48%", "stat": "armor", "mode": "add", "value": 0.08, "cap": 0.48, "price": 30},
	{"id": "speed", "name": "轻量骨架", "tag": "移动", "description": "移动速度 +12%\n上限 400", "stat": "speed", "mode": "multiply", "value": 1.12, "cap": 400.0, "price": 24},
	{"id": "magnet", "name": "磁场回收", "tag": "回收", "description": "零件吸取范围 +60\n上限 330", "stat": "magnet", "mode": "add", "value": 60.0, "cap": 330.0, "price": 20},
]

static func available_upgrades(stats: Dictionary) -> Array:
	var result: Array = []
	for item in UPGRADES:
		if item.has("cap") and float(stats[item.stat]) >= float(item.cap) - 0.001:
			continue
		result.append(item.duplicate(true))
	return result

static func roll_choices(stats: Dictionary, rng: RandomNumberGenerator, count: int = 3) -> Array:
	var pool = available_upgrades(stats)
	var choices: Array = []
	while not pool.is_empty() and choices.size() < count:
		var index = rng.randi_range(0, pool.size() - 1)
		choices.append(pool.pop_at(index))
	return choices

static func apply_upgrade(stats: Dictionary, item: Dictionary) -> void:
	var key: String = item.stat
	if item.mode == "multiply":
		stats[key] = float(stats[key]) * float(item.value)
	else:
		stats[key] = float(stats[key]) + float(item.value)
	if item.has("cap"):
		stats[key] = minf(float(stats[key]), float(item.cap))
	if key == "projectiles" or key == "pierce":
		stats[key] = int(stats[key])
	stats.fire_interval = maxf(0.12, float(stats.fire_interval))
