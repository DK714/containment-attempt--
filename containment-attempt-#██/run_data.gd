extends RefCounted
## Configuration-driven rules. JSON contains data, never executable code.

static func apply_effects(stats: Dictionary, effects: Array) -> void:
	for effect in effects:
		var key: String = effect.stat
		# A positive upgrade already at its own cap must never reduce a better stat.
		var increases = (effect.op == "add" and effect.value >= 0) or (effect.op == "multiply" and effect.value >= 1)
		if increases and effect.has("cap") and float(stats[key]) >= float(effect.cap):
			continue
		if effect.op == "multiply":
			stats[key] = float(stats[key]) * float(effect.value)
		else:
			stats[key] = float(stats[key]) + float(effect.value)
		if effect.has("cap"):
			stats[key] = minf(float(stats[key]), float(effect.cap))

static func can_equip(db, character_id: String, weapon_id: String) -> bool:
	var character = db.get_record("characters", character_id)
	var weapon = db.get_record("weapons", weapon_id)
	return not weapon.is_empty() and weapon.get("enabled", false) and weapon.category_id not in character.get("forbidden_weapon_categories", [])

static func build_stats(db, character_id: String, weapon_id: String, run_effects: Array) -> Dictionary:
	var result: Dictionary = db.default_stats()
	var character = db.get_record("characters", character_id)
	result.merge(character.base_stats, true)
	var weapon = db.get_record("weapons", weapon_id)
	apply_effects(result, weapon.effects)
	for rule in character.buff_weapons + character.debuff_weapons:
		if rule.category_id == weapon.category_id:
			apply_effects(result, rule.effects)
	apply_effects(result, run_effects)
	db.clamp_stats(result)
	return result

static func resolve_reward(db, reward_id: String) -> Dictionary:
	var reward = db.get_record("rewards", reward_id)
	if reward.is_empty() or not reward.get("enabled", false): return {}
	var item: Dictionary = {}
	match reward.kind:
		"upgrade":
			item = db.get_record("upgrades", reward.upgrade_id)
			if not item.get("enabled", false): return {}
			item.content_key = "upgrade:" + reward.upgrade_id
		"weapon":
			item = db.get_record("weapons", reward.weapon_id)
			if not item.get("enabled", false): return {}
			item.content_key = "weapon:" + reward.weapon_id
			item.tag = "更换武器"
		"containment":
			item = db.get_record("containments", reward.containment_id)
			if not item.get("enabled", false): return {}
			item.content_key = "containment:" + reward.containment_id
		"heal", "scrap":
			item = reward.duplicate(true)
			item.content_key = reward.kind + ":" + str(reward.amount)
			item.tag = "医疗" if reward.kind == "heal" else "零件"
			item.description = "恢复 %d 点生命" % int(reward.amount) if reward.kind == "heal" else "获得 %d 个零件" % int(reward.amount)
		_: return {}
	item.content_id = item.id
	item.id = reward.id
	item.kind = reward.kind
	item.price = int(reward.get("price", item.get("price", 0)))
	item.name = reward.get("name", item.name)
	if reward.has("description"): item.description = reward.description
	return item

static func eligible(db, item: Dictionary, stats: Dictionary, hp: float, character_id: String, weapon_id: String, owned: Array) -> bool:
	if item.is_empty(): return false
	match item.kind:
		"weapon": return item.content_id != weapon_id and can_equip(db, character_id, item.content_id)
		"heal": return hp < float(stats.max_hp)
		"scrap": return true
		"containment":
			if item.get("unique", true) and item.content_id in owned: return false
	var changed = stats.duplicate(true)
	apply_effects(changed, item.get("effects", []))
	db.clamp_stats(changed)
	for key in changed:
		if not is_equal_approx(float(changed[key]), float(stats[key])): return true
	return float(item.get("heal_on_apply", 0)) > 0 and hp < float(stats.max_hp)

static func roll_choices(db, stats: Dictionary, rng: RandomNumberGenerator, pool_id: String, character_id: String, weapon_id: String, owned: Array, hp: float, count: int = 3) -> Array:
	var pool = db.get_record("reward_pools", pool_id)
	var candidates: Array = []
	for entry in pool.get("entries", []):
		var item = resolve_reward(db, entry.reward_id)
		if eligible(db, item, stats, hp, character_id, weapon_id, owned):
			candidates.append({"item": item, "weight": float(entry.weight)})
	var choices: Array = []
	while not candidates.is_empty() and choices.size() < count:
		var total = 0.0
		for entry in candidates: total += entry.weight
		var roll = rng.randf() * total
		var picked = candidates.size() - 1
		for index in range(candidates.size()):
			roll -= float(candidates[index].weight)
			if roll <= 0:
				picked = index
				break
		var selected: Dictionary = candidates[picked].item
		choices.append(selected)
		# Different reward records pointing at the same content never occupy two cards.
		for index in range(candidates.size() - 1, -1, -1):
			if candidates[index].item.content_key == selected.content_key:
				candidates.remove_at(index)
	return choices
