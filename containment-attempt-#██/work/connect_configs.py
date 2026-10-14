"""Source migration only; does not import Godot or run tests."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
path = root / "main.gd"
source = path.read_text(encoding="utf-8")

def function(name, body):
    global source
    start = source.index("func " + name + "(")
    end = source.find("\nfunc ", start + 1)
    if end == -1:
        end = len(source)
    source = source[:start] + body.strip() + "\n" + source[end:]

source = source.replace('const RunData = preload("res://run_data.gd")', 'const RunData = preload("res://run_data.gd")\nconst ConfigDatabase = preload("res://scripts/config_database.gd")')
source = source.replace('var state = "menu"', '''var config_db = ConfigDatabase.new()
var selected_character_id = ""
var equipped_weapon_id = ""
var run_effects: Array = []
var owned_containment_ids: Array = []
var character_slots: Array = []
var floor_definition: Dictionary = {}
var state = "menu"''')
source = source.replace('\t_build_sounds()\n\tshow_menu()', '\t_build_sounds()\n\tif _load_configuration():\n\t\tshow_menu()', 1)
addition = '''
func _load_configuration() -> bool:
	if config_db.load_all():
		var character = config_db.get_record("characters", selected_character_id)
		if character.is_empty() or not character.enabled:
			selected_character_id = config_db.settings.default_character_id
		return true
	state = "config_error"
	_clear_ui()
	_label("配置读取失败", Vector2(90, 115), Vector2(1100, 70), 42, RED)
	_label("请修正下列配置后重试；不会使用一份不完整的配置开始游戏。", Vector2(94, 205), Vector2(1100, 60), 20, MUTED)
	var messages = PackedStringArray(config_db.errors.slice(0, 8))
	var details = _label("\\n\\n".join(messages), Vector2(94, 300), Vector2(1090, 320), 18)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for message in config_db.errors:
		push_error(message)
	_button("修改后重试", Vector2(94, 672), Vector2(300, 60), func():
		if _load_configuration(): show_menu()
	)
	return false

func _room_config(cell: Vector2i) -> Dictionary:
	return config_db.get_record("rooms", floor_rooms[cell].definition_id)

func _boss_requirement() -> int:
	for cell in floor_rooms:
		var definition = _room_config(cell)
		if definition.kind == "boss": return int(definition.required_combat_clears)
	return 0

func _roll_pool(pool_id: String, count: int = 3) -> Array:
	return RunData.roll_choices(config_db, stats, rng, pool_id, selected_character_id, equipped_weapon_id, owned_containment_ids, hp, count)

func _rebuild_stats() -> void:
	stats = RunData.build_stats(config_db, selected_character_id, equipped_weapon_id, run_effects)
	hp = minf(hp, float(stats.max_hp))
'''
source = source.replace('\nfunc _register_inputs()', '\n' + addition + '\nfunc _register_inputs()', 1)

function("show_characters", '''
func show_characters(page: int = 0) -> void:
	state = "characters"
	_clear_ui()
	var characters = config_db.records("characters")
	var pages = maxi(1, ceili(float(characters.size()) / 3.0))
	page = clampi(page, 0, pages - 1)
	character_slots = characters.slice(page * 3, page * 3 + 3)
	_label("人员档案 / SELECT OPERATOR", Vector2(84, 74), Vector2(1000, 55), 32)
	_label("选择已授权角色；角色和初始武器来自配置。", Vector2(86, 132), Vector2(1050, 35), 18, MUTED)
	for index in range(character_slots.size()):
		var character: Dictionary = character_slots[index]
		var x = 110.0 + index * 400.0
		var enabled = bool(character.enabled)
		var preview = RunData.build_stats(config_db, character.id, character.starting_weapon_id, [])
		var weapon = config_db.get_record("weapons", character.starting_weapon_id)
		_label("%s / %s" % [character.code, "已授权" if enabled else "未授权"], Vector2(x, 218), Vector2(285, 30), 17, TEAL if enabled else MUTED)
		_label(character.name, Vector2(x, 354), Vector2(295, 55), 34, TEXT if enabled else MUTED)
		_label(character.english_name, Vector2(x, 415), Vector2(295, 35), 17, MUTED)
		var details = "生命 %d · 移速 %d\\n初始武器：%s\\n\\n%s" % [int(preview.max_hp), int(preview.speed), weapon.name, character.description]
		var description = _label(details, Vector2(x, 464), Vector2(295, 162), 17, TEXT if enabled else MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_button("以%s开始" % character.name if enabled else "未开放", Vector2(x, 658), Vector2(300, 57), _start_character.bind(character.id), TEAL, not enabled)
	_button("返回", Vector2(84, 739), Vector2(125, 40), show_menu, MUTED)
	if pages > 1:
		_button("上一页", Vector2(770, 739), Vector2(120, 40), show_characters.bind(page - 1), MUTED, page == 0)
		_button("下一页", Vector2(1030, 739), Vector2(120, 40), show_characters.bind(page + 1), MUTED, page == pages - 1)
		_label("%d / %d" % [page + 1, pages], Vector2(924, 744), Vector2(100, 30), 18, MUTED)
	queue_redraw()

func _start_character(character_id: String) -> void:
	selected_character_id = character_id
	start_run()
''')
source = source.replace('func start_run() -> void:\n\tattempt += 1\n\tstats = RunData.BASE_STATS.duplicate(true)', '''func start_run() -> void:
	# Read once per new attempt; editing files never mutates a running battle.
	if not _load_configuration(): return
	attempt += 1
	run_effects.clear()
	owned_containment_ids.clear()
	equipped_weapon_id = config_db.get_record("characters", selected_character_id).starting_weapon_id
	stats = RunData.build_stats(config_db, selected_character_id, equipped_weapon_id, run_effects)''')
source = source.replace('\t_enter_room(Vector2i.ZERO)', '\tvar start: Array = floor_definition.start_position\n\t_enter_room(Vector2i(int(start[0]), int(start[1])))', 1)

function("_generate_floor", '''
func _generate_floor() -> void:
	floor_rooms.clear()
	floor_definition = config_db.get_record("floors", config_db.settings.default_floor_id)
	for entry in floor_definition.cells:
		var cell = Vector2i(int(entry.position[0]), int(entry.position[1]))
		var definition = config_db.get_record("rooms", entry.room_id)
		floor_rooms[cell] = {
			"definition_id": definition.id, "kind": definition.kind, "visited": false,
			"cleared": bool(definition.cleared_on_entry), "claimed": false,
			"shop": [], "shop_generated": false, "medical_uses": 0,
			"reroll_cost": int(definition.get("shop", {}).get("reroll_cost", 0)),
		}
''')
source = source.replace('\tvar room: Dictionary = floor_rooms[cell]\n\troom.visited', '\tvar room: Dictionary = floor_rooms[cell]\n\tvar definition = _room_config(cell)\n\troom.visited', 1)
source = source.replace('\tinvulnerability = 1.0\n\tdoor_cooldown = 0.9', '\tinvulnerability = float(config_db.settings.combat.entry_invulnerability)\n\tdoor_cooldown = float(config_db.settings.combat.door_cooldown)', 1)
source = source.replace('\t\twave_timer = 0.7\n\t\t_set_notice("区域封锁 · 清除两波异常体", 2.5)', '\t\twave_timer = float(definition.waves.initial_delay)\n\t\t_set_notice("区域封锁 · 清除 %d 波异常体" % int(definition.waves.count), 2.5)', 1)
source = source.replace('\t\t_spawn_enemy("boss", ARENA.get_center() + Vector2(185, 0))', '\t\tvar containment = config_db.get_record("containments", definition.containment_id)\n\t\t_spawn_enemy(containment.monster_id, ARENA.get_center() + Vector2(185, 0))', 1)
function("_room_locked", '''
func _room_locked() -> bool:
	return not floor_rooms[current_cell].cleared and bool(_room_config(current_cell).lock_until_clear)
''')
source = source.replace('\t\tdash_remaining = 0.17\n\t\tdash_cooldown = 1.4', '\t\tdash_remaining = float(stats.dash_duration)\n\t\tdash_cooldown = float(stats.dash_cooldown)')
source = source.replace('dash_direction * 690.0 * delta', 'dash_direction * float(stats.dash_speed) * delta')

function("_spawn_wave", '''
func _spawn_wave() -> void:
	wave += 1
	var waves: Dictionary = _room_config(current_cell).waves
	var combat: Dictionary = config_db.settings.combat
	var count = int(waves.base_count) + mini(cleared_count, int(waves.clear_bonus_cap)) * int(waves.extra_per_clear) + wave * int(waves.extra_per_wave)
	var cycle: Array = waves.monster_cycle
	for index in range(count):
		var spawn = Vector2.ZERO
		for tries in range(int(combat.spawn_position_attempts)):
			spawn = Vector2(rng.randf_range(ARENA.position.x + combat.spawn_margin, ARENA.end.x - combat.spawn_margin), rng.randf_range(ARENA.position.y + combat.spawn_margin, ARENA.end.y - combat.spawn_margin))
			if spawn.distance_to(player_position) > float(combat.spawn_min_distance): break
		_spawn_enemy(cycle[index % cycle.size()], spawn)
	_set_notice("异常体入侵 / %d–%d" % [wave, int(waves.count)], 1.8)
''')
function("_spawn_enemy", '''
func _spawn_enemy(monster_id: String, position: Vector2) -> void:
	next_enemy_id += 1
	var definition = config_db.get_record("monsters", monster_id)
	var health = float(definition.stats.hp) + cleared_count * float(definition.scaling.hp_per_clear)
	var initial_cooldown = rng.randf_range(float(config_db.settings.combat.enemy_initial_attack_min), float(config_db.settings.combat.enemy_initial_attack_max))
	if definition.behavior == "boss_radial_charge": initial_cooldown = float(definition.attack.initial_interval)
	var enemy = {
		"id": next_enemy_id, "config_id": monster_id, "kind": definition.visual,
		"behavior": definition.behavior, "name": definition.name,
		"pos": position, "hp": health, "max_hp": health,
		"radius": float(definition.stats.radius),
		"speed": float(definition.stats.speed) + cleared_count * float(definition.scaling.speed_per_clear),
		"contact_damage": float(definition.stats.contact_damage), "attack": definition.attack,
		"drop_reward_id": definition.drop_reward_id,
		"cooldown": initial_cooldown, "flash": 0.0,
		"charge_timer": 0.0, "charge_dir": Vector2.ZERO, "charge_left": 0.0,
	}
	enemies.append(enemy)
	_emit_particles(position, RED, 12)
''')
source = source.replace('if enemy.kind == "boss":\n\t\t\t_tick_boss', 'if enemy.behavior == "boss_radial_charge":\n\t\t\t_tick_boss', 1)
source = source.replace('elif enemy.kind == "shooter":\n\t\t\tif toward.length() > 285:', 'elif enemy.behavior == "shooter":\n\t\t\tif toward.length() > float(enemy.attack.approach_distance):', 1)
source = source.replace('elif toward.length() < 165:', 'elif toward.length() < float(enemy.attack.retreat_distance):', 1)
source = source.replace('_hostile_fire(enemy.pos, direction, 190.0, 11.0)\n\t\t\t\tenemy.cooldown = 2.5', '_hostile_fire(enemy.pos, direction, float(enemy.attack.bullet_speed), float(enemy.attack.damage))\n\t\t\t\tenemy.cooldown = float(enemy.attack.interval)', 1)
source = source.replace('_damage_player(20.0 if enemy.kind == "boss" else 13.0)', '_damage_player(float(enemy.contact_damage))', 1)
function("_tick_boss", '''
func _tick_boss(enemy: Dictionary, direction: Vector2, delta: float) -> void:
	var attack: Dictionary = enemy.attack
	if enemy.charge_left > 0.0:
		enemy.charge_left -= delta
		enemy.pos += Vector2(enemy.charge_dir) * float(attack.charge_speed) * delta
	elif enemy.charge_timer > 0.0:
		enemy.charge_timer -= delta
		if enemy.charge_timer <= 0.0:
			enemy.charge_left = float(attack.charge_duration)
			_play_sound("alarm")
	else:
		enemy.pos += direction * float(enemy.speed) * delta
		if enemy.cooldown <= 0.0:
			var enraged = enemy.hp <= enemy.max_hp * float(attack.phase_threshold)
			var count = int(attack.enraged_bullet_count if enraged else attack.bullet_count)
			for index in range(count):
				_hostile_fire(enemy.pos, Vector2.from_angle(direction.angle() + TAU * index / count), float(attack.bullet_speed), float(attack.damage))
			enemy.cooldown = float(attack.enraged_interval if enraged else attack.interval)
			enemy.charge_timer = float(attack.charge_warning)
			enemy.charge_dir = direction
''')
source = source.replace('* 0.15\n\t\tbullets.append', '* float(stats.spread_angle)\n\t\tbullets.append', 1)
source = source.replace('Vector2.from_angle(angle) * 610.0', 'Vector2.from_angle(angle) * float(stats.bullet_speed)', 1)
source = source.replace('float(stats.range) / 610.0', 'float(stats.range) / float(stats.bullet_speed)', 1)
source = source.replace('"life": 7.0})', '"life": float(config_db.settings.combat.hostile_bullet_lifetime)})', 1)
function("_kill_enemy", '''
func _kill_enemy(index: int) -> void:
	var enemy: Dictionary = enemies[index]
	kills += 1
	var drop = RunData.resolve_reward(config_db, enemy.drop_reward_id)
	if not drop.is_empty(): pickups.append({"pos": Vector2(enemy.pos), "amount": int(drop.amount)})
	_emit_particles(enemy.pos, ORANGE if enemy.kind == "boss" else RED, 18)
	shake = maxf(shake, 2.0 if enemy.kind != "boss" else 7.0)
	enemies.remove_at(index)
	_play_sound("kill")
''')
source = source.replace('\tinvulnerability = 0.75', '\tinvulnerability = float(config_db.settings.combat.hit_invulnerability)', 1)
source = source.replace('if distance < 25:', 'if distance < float(config_db.settings.combat.pickup_radius):', 1)
source = source.replace('340.0 * delta)', 'float(config_db.settings.combat.pickup_speed) * delta)', 1)
source = source.replace('\t\tif wave < 2:\n\t\t\twave_timer = 1.5\n\t\t\t_set_notice("第一波已清除 · 下一波即将出现", 1.5)', '\t\tvar definition = _room_config(current_cell)\n\t\tif wave < int(definition.waves.count):\n\t\t\twave_timer = float(definition.waves.between_delay)\n\t\t\t_set_notice("本波已清除 · 下一波即将出现", wave_timer)', 1)
source = source.replace('\t\t\tscrap += 8', '\t\t\t_apply_reward(RunData.resolve_reward(config_db, definition.clear_reward_id), false)', 1)
source = source.replace('player_position.distance_to(_door_position(direction)) < 39:', 'player_position.distance_to(_door_position(direction)) < float(config_db.settings.combat.door_trigger_distance):', 1)
source = source.replace('if floor_rooms[destination].kind == "boss" and cleared_count < 4:', 'if floor_rooms[destination].kind == "boss" and cleared_count < int(_room_config(destination).required_combat_clears):', 1)
source = source.replace('(4 - cleared_count)', '(int(_room_config(destination).required_combat_clears) - cleared_count)', 1)
source = source.replace('\treward_choices = RunData.roll_choices(stats, rng)', '\tvar definition = _room_config(current_cell)\n\treward_choices = _roll_pool(definition.choice_pool_id, int(definition.choice_count))', 1)
source = source.replace('区域已净化 · 选择一项强化', '区域已净化 · 选择一项奖励')
source = source.replace('发现封存物资 · 选择一项强化', '发现封存物资 · 选择一项奖励')
source = source.replace('\t\t_button("应用强化",', '\t\t_button("装备武器" if item.kind == "weapon" else "领取奖励",', 1)
source = source.replace('\t_label("强化后房门开放；走向门口继续探索。"', '\tif reward_choices.is_empty():\n\t\t_label("当前奖励池没有可用物资。", Vector2(114, 340), Vector2(1000, 50), 24, MUTED)\n\t\t_button("继续探索", Vector2(114, 540), Vector2(300, 60), _finish_reward)\n\t_label("领取后房门开放；走向门口继续探索。"', 1)
function("_choose_reward", '''
func _choose_reward(index: int) -> void:
	if state != "reward" or index < 0 or index >= reward_choices.size(): return
	var item: Dictionary = reward_choices[index]
	if not _apply_reward(item): return
	_finish_reward()
	_set_notice("已领取：%s · 房门开放" % item.name, 3.0)
	_play_sound("upgrade")

func _finish_reward() -> void:
	floor_rooms[current_cell].claimed = true
	reward_choices.clear()
	state = "playing"
	_clear_ui()
	door_cooldown = 0.4
''')
function("_apply_upgrade", '''
func _apply_reward(item: Dictionary, count_upgrade: bool = true) -> bool:
	if item.is_empty(): return false
	match item.kind:
		"scrap": scrap += int(item.amount)
		"heal": hp = minf(float(stats.max_hp), hp + float(item.amount))
		"weapon":
			if not RunData.can_equip(config_db, selected_character_id, item.content_id): return false
			equipped_weapon_id = item.content_id
			_rebuild_stats()
		"upgrade", "containment":
			if item.kind == "containment":
				if item.get("unique", true) and item.content_id in owned_containment_ids: return false
				if item.content_id not in owned_containment_ids: owned_containment_ids.append(item.content_id)
			run_effects.append_array(item.get("effects", []).duplicate(true))
			_rebuild_stats()
			hp = minf(float(stats.max_hp), hp + float(item.get("heal_on_apply", 0)))
			if count_upgrade: upgrade_count += 1
	return true
''')

function("show_shop", '''
func show_shop() -> void:
	state = "shop"
	_clear_ui()
	_overlay()
	var room: Dictionary = floor_rooms[current_cell]
	var shop: Dictionary = _room_config(current_cell).shop
	if not room.shop_generated:
		room.shop = _roll_pool(shop.pool_id, int(shop.slots))
		room.shop_generated = true
	shop_reroll_cost = int(room.reroll_cost)
	var medical = RunData.resolve_reward(config_db, shop.medical_reward_id)
	_label("补给站 / SUPPLY TERMINAL", Vector2(110, 88), Vector2(1040, 60), 34)
	_label("零件 %03d · 生命 %d / %d" % [scrap, ceili(hp), int(stats.max_hp)], Vector2(114, 156), Vector2(1000, 38), 22, ORANGE)
	_label("购买和刷新消耗本局零件；武器会根据角色品类规则筛选。", Vector2(114, 203), Vector2(1100, 35), 17, MUTED)
	for index in range(room.shop.size()):
		var item: Dictionary = room.shop[index]
		var x = 110.0 + index * 360.0
		_card_panel(Vector2(x, 256), Vector2(330, 364), ORANGE)
		var sold = bool(item.get("sold", false))
		var usable = RunData.eligible(config_db, item, stats, hp, selected_character_id, equipped_weapon_id, owned_containment_ids)
		_label("物资 %02d / %s" % [index + 1, item.tag], Vector2(x + 24, 285), Vector2(282, 30), 17, TEAL)
		_label(item.name, Vector2(x + 24, 344), Vector2(282, 55), 30)
		var description = _label(item.description, Vector2(x + 24, 420), Vector2(282, 110), 19)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var caption = "已购买" if sold else ("当前不可用" if not usable else "购买 · %d 零件" % int(item.price))
		_button(caption, Vector2(x + 24, 550), Vector2(282, 54), _buy_item.bind(index), ORANGE, sold or not usable or scrap < int(item.price))
	if room.shop.is_empty(): _label("当前物资池没有可用奖励。", Vector2(114, 350), Vector2(1000, 70), 24, MUTED)
	var medical_used = int(room.medical_uses) >= int(shop.medical_uses)
	if not medical.is_empty():
		var caption = "医疗已用" if medical_used else "%s +%d HP · %d 零件" % [medical.name, int(medical.amount), int(medical.price)]
		_button(caption, Vector2(114, 643), Vector2(354, 50), _buy_heal, ORANGE, medical_used or hp >= float(stats.max_hp) or scrap < int(medical.price))
	_button("刷新物资 · %d 零件" % shop_reroll_cost, Vector2(488, 643), Vector2(295, 50), _reroll_shop, MUTED, scrap < shop_reroll_cost)
	_button("继续探索", Vector2(881, 643), Vector2(270, 50), _leave_shop)
	_label("离开后可返回；站内按 E 再次打开终端。", Vector2(114, 719), Vector2(1000, 35), 16, MUTED)
''')
function("_buy_item", '''
func _buy_item(index: int) -> void:
	if state != "shop": return
	var offers: Array = floor_rooms[current_cell].shop
	if index < 0 or index >= offers.size(): return
	var item: Dictionary = offers[index]
	if item.get("sold", false) or scrap < int(item.price): return
	if not RunData.eligible(config_db, item, stats, hp, selected_character_id, equipped_weapon_id, owned_containment_ids): return
	if not _apply_reward(item): return
	scrap -= int(item.price)
	item.sold = true
	_play_sound("upgrade")
	show_shop()
''')
function("_buy_heal", '''
func _buy_heal() -> void:
	if state != "shop": return
	var room: Dictionary = floor_rooms[current_cell]
	var shop: Dictionary = _room_config(current_cell).shop
	var item = RunData.resolve_reward(config_db, shop.medical_reward_id)
	if item.is_empty() or int(room.medical_uses) >= int(shop.medical_uses) or scrap < int(item.price) or hp >= float(stats.max_hp): return
	scrap -= int(item.price)
	_apply_reward(item, false)
	room.medical_uses += 1
	_play_sound("upgrade")
	show_shop()
''')
function("_reroll_shop", '''
func _reroll_shop() -> void:
	if state != "shop" or scrap < shop_reroll_cost: return
	var room: Dictionary = floor_rooms[current_cell]
	var shop: Dictionary = _room_config(current_cell).shop
	scrap -= shop_reroll_cost
	room.reroll_cost += int(shop.reroll_increment)
	room.shop = _roll_pool(shop.pool_id, int(shop.slots))
	room.shop_generated = true
	show_shop()
''')

# Keep the hand-drawn art; only character card content and layout become dynamic.
start = source.index('\telif state == "characters":', source.index('func _draw_menu_art'))
end = source.index('\nfunc _text', start)
source = source[:start] + '''	elif state == "characters":
		for index in range(character_slots.size()):
			var x = 85.0 + index * 400.0
			var enabled = bool(character_slots[index].enabled)
			draw_rect(Rect2(x, 192, 350, 534), PANEL)
			draw_rect(Rect2(x, 192, 350, 534), TEAL.darkened(0.65) if enabled else Color("2a3540"), false, 1)
			if enabled:
				_draw_operator(Vector2(x + 175, 295), 2.2)
			else:
				draw_circle(Vector2(x + 175, 298), 37, Color("1d2934"))
				draw_rect(Rect2(x + 164, 283, 22, 24), MUTED.darkened(0.55), false, 2)
				draw_arc(Vector2(x + 175, 283), 9, PI, TAU, 20, MUTED.darkened(0.55), 2)
''' + source[end:]
source = source.replace('\tvar titles = {"start": "入口 / 安全区域", "combat": "隔离室 / 清除异常体", "supply": "补给站 / 回收终端", "treasure": "封存仓 / 探索奖励", "boss": "收容核心 / 最终区域"}', '\tvar definition = _room_config(current_cell)')
source = source.replace('[titles[room.kind], current_cell.x + 1, current_cell.y + 1]', '[definition.title, current_cell.x + 1, current_cell.y + 1]')
source = source.replace('\tdraw_rect(ARENA, Color("101c25"))', '\t_text("%s / %s" % [config_db.get_record("characters", selected_character_id).name, config_db.get_record("weapons", equipped_weapon_id).name], Vector2(815, 121), 14, MUTED)\n\tdraw_rect(ARENA, Color("101c25"))', 1)
source = source.replace('if is_boss and cleared_count < 4:', 'if is_boss and cleared_count < int(_room_config(destination).required_combat_clears):', 1)
source = source.replace('var end = p + Vector2(enemy.charge_dir) * 230', 'var end = p + Vector2(enemy.charge_dir) * float(enemy.attack.charge_speed) * float(enemy.attack.charge_duration)')
source = source.replace('_text("异常核心", Vector2(477, 192)', '_text(enemy.name, Vector2(477, 192)', 1)
source = source.replace('"核心门禁  %d / 4" % mini(cleared_count, 4)', '"核心门禁  %d / %d" % [mini(cleared_count, _boss_requirement()), _boss_requirement()]', 1)
function("_draw_minimap", '''
func _draw_minimap(origin: Vector2) -> void:
	var low = Vector2i(100000, 100000)
	var high = Vector2i(-100000, -100000)
	for cell in floor_rooms:
		low.x = mini(low.x, cell.x)
		low.y = mini(low.y, cell.y)
		high.x = maxi(high.x, cell.x)
		high.y = maxi(high.y, cell.y)
	var step = minf(39.0, minf(160.0 / float(high.x - low.x + 1), 108.0 / float(high.y - low.y + 1)))
	var size = Vector2(step - 6, step - 9)
	for cell in floor_rooms:
		var room: Dictionary = floor_rooms[cell]
		var visible = bool(room.visited)
		for direction in DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			if floor_rooms.has(neighbor) and floor_rooms[neighbor].visited: visible = true
		if not visible: continue
		var p = origin + Vector2(cell - low) * step
		var color = Color("273c47")
		if room.visited: color = Color("45626a") if room.cleared else RED.darkened(0.65)
		draw_rect(Rect2(p, size), color)
		if cell == current_cell: draw_rect(Rect2(p, size), TEAL, false, 2)
		if step >= 20 and (room.visited or room.kind == "boss"):
			var symbol: String = _room_config(cell).map_symbol
			_text(symbol, p + Vector2(8, size.y - 5), 14, ORANGE if room.kind == "boss" else TEXT)
''')
path.write_text(source, encoding="utf-8")
