extends Node2D
## Single-floor prototype. All gameplay is simulated only while state == "playing".
## Meta progression deliberately has no persistence or effects in this version.

const RunData = preload("res://run_data.gd")
const ConfigDatabase = preload("res://scripts/config_database.gd")
const ARENA = Rect2(48, 140, 970, 584)
const PLAYER_RADIUS = 15.0
const TEAL = Color("6ae3c6")
const ORANGE = Color("ffb46b")
const RED = Color("f26d7d")
const INK = Color("080e15")
const PANEL = Color("101c27")
const TEXT = Color("e1edf0")
const MUTED = Color("849aa9")
const DIRECTIONS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var config_db = ConfigDatabase.new()
var selected_character_id = ""
var equipped_weapon_id = ""
var run_effects: Array = []
var owned_containment_ids: Array = []
var character_slots: Array = []
var floor_definition: Dictionary = {}
var state = "menu"
var ui: Control
var font: SystemFont
var rng = RandomNumberGenerator.new()
var clock_time = 0.0
var run_time = 0.0
var stats: Dictionary = {}
var hp = 100.0
var scrap = 0
var kills = 0
var cleared_count = 0
var upgrade_count = 0
var attempt = 0
var floor_rooms: Dictionary = {}
var current_cell = Vector2i.ZERO
var player_position = ARENA.get_center()
var last_move = Vector2.RIGHT
var weapon_direction = Vector2.RIGHT
var enemies: Array = []
var bullets: Array = []
var hostile_bullets: Array = []
var pickups: Array = []
var particles: Array = []
var float_texts: Array = []
var shoot_timer = 0.0
var invulnerability = 0.0
var dash_remaining = 0.0
var dash_cooldown = 0.0
var dash_direction = Vector2.RIGHT
var door_cooldown = 0.0
var wave = 0
var wave_timer = -1.0
var next_enemy_id = 0
var reward_choices: Array = []
var reward_source = "combat"
var notice = ""
var notice_timer = 0.0
var shake = 0.0
var shake_offset = Vector2.ZERO
var shop_reroll_cost = 6
var sounds: Dictionary = {}
var sound_players: Array = []
var sound_cursor = 0
var muted = false

func _ready() -> void:
	rng.randomize()
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Heiti SC", "Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	var theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = theme
	add_child(ui)
	_register_inputs()
	_build_sounds()
	if _load_configuration():
		show_menu()


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
	var details = _label("\n\n".join(messages), Vector2(94, 300), Vector2(1090, 320), 18)
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

func _register_inputs() -> void:
	var bindings = {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"dash": [KEY_SPACE], "pause_run": [KEY_ESCAPE], "interact": [KEY_E],
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)

func _clear_ui() -> void:
	for child in ui.get_children():
		ui.remove_child(child)
		child.queue_free()

func _label(content: String, position: Vector2, size: Vector2, font_size: int = 20, color: Color = TEXT) -> Label:
	var label = Label.new()
	label.text = content
	label.position = position
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(label)
	return label

func _button(content: String, position: Vector2, size: Vector2, callback: Callable, accent: Color = TEAL, disabled: bool = false) -> Button:
	var button = Button.new()
	button.text = content
	button.position = position
	button.size = size
	button.disabled = disabled
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	for variant in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = PANEL
		style.border_color = accent.darkened(0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 16
		style.content_margin_right = 16
		if variant == "hover" or variant == "pressed":
			style.bg_color = accent
			style.border_color = accent
		elif variant == "disabled":
			style.bg_color = Color("0c141c")
			style.border_color = Color("25323e")
		elif variant == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = accent
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(variant, style)
	button.pressed.connect(func():
		_play_sound("click")
		callback.call()
	)
	ui.add_child(button)
	return button

func _overlay() -> void:
	var tint = ColorRect.new()
	tint.position = Vector2.ZERO
	tint.size = Vector2(1280, 800)
	tint.color = Color(0.015, 0.035, 0.055, 0.94)
	tint.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(tint)

func _card_panel(position: Vector2, size: Vector2, accent: Color = TEAL) -> void:
	var panel = Panel.new()
	panel.position = position
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color("101e2b")
	style.border_color = accent.darkened(0.65)
	style.border_width_top = 3
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)

func show_menu() -> void:
	state = "menu"
	_clear_ui()
	_label("C O N T A I N M E N T   D I V I S I O N", Vector2(80, 86), Vector2(700, 30), 16, TEAL)
	_label("第██次收容", Vector2(76, 177), Vector2(740, 100), 64)
	_label("Containment Attempt #██", Vector2(82, 279), Vector2(700, 50), 28, MUTED)
	_label("警报已经响起。\n这一次，试着活着完成收容。", Vector2(84, 365), Vector2(530, 85), 22)
	_button("开始游戏  /  START", Vector2(84, 495), Vector2(330, 64), show_characters)
	_button("局外成长  /  待接入", Vector2(84, 575), Vector2(330, 52), show_meta, MUTED)
	_button("退出", Vector2(84, 641), Vector2(155, 44), func(): get_tree().quit(), MUTED)
	_button("声音：关闭" if muted else "声音：开启", Vector2(255, 641), Vector2(159, 44), func():
		muted = not muted
		show_menu()
	, MUTED)
	_label("PROTOTYPE 0.1     ·     单层设施 / 随机强化 / 无局外数值成长", Vector2(84, 742), Vector2(1040, 28), 14, MUTED)
	queue_redraw()

func show_characters(page: int = 0) -> void:
	if not _load_configuration(): return
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
		var details = "生命 %d · 移速 %d\n初始武器：%s\n\n%s" % [int(preview.max_hp), int(preview.speed), weapon.name, character.description]
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

func show_meta() -> void:
	state = "meta"
	_clear_ui()
	_label("长期收容计划", Vector2(100, 125), Vector2(1080, 70), 42)
	_label("META PROGRESSION / RESERVED", Vector2(104, 205), Vector2(900, 45), 19, TEAL)
	_label("这里预留局外成长入口。\n\n当前版本每次开始都会重置属性、零件和强化。\n本页暂不提供购买、解锁或永久加成。", Vector2(104, 320), Vector2(1050, 200), 24)
	_button("返回主界面", Vector2(104, 605), Vector2(300, 60), show_menu)
	queue_redraw()

func start_run() -> void:
	# Read once per new attempt; editing files never mutates a running battle.
	if not _load_configuration(): return
	attempt += 1
	run_effects.clear()
	owned_containment_ids.clear()
	equipped_weapon_id = config_db.get_record("characters", selected_character_id).starting_weapon_id
	stats = RunData.build_stats(config_db, selected_character_id, equipped_weapon_id, run_effects)
	hp = float(stats.max_hp)
	scrap = 0
	kills = 0
	cleared_count = 0
	upgrade_count = 0
	run_time = 0.0
	enemies.clear()
	bullets.clear()
	hostile_bullets.clear()
	pickups.clear()
	particles.clear()
	float_texts.clear()
	shoot_timer = 0.25
	last_move = Vector2.RIGHT
	weapon_direction = Vector2.RIGHT
	invulnerability = 0.0
	dash_remaining = 0.0
	dash_cooldown = 0.0
	next_enemy_id = 0
	shake = 0.0
	reward_choices.clear()
	shop_reroll_cost = 6
	_generate_floor()
	var start: Array = floor_definition.start_position
	_enter_room(Vector2i(int(start[0]), int(start[1])))
	_set_notice("自动攻击 · 空格冲刺 · 靠近开放的门进入下一间", 6.0)

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

func _enter_room(cell: Vector2i, from_direction: Vector2i = Vector2i.ZERO) -> void:
	current_cell = cell
	var room: Dictionary = floor_rooms[cell]
	var definition = _room_config(cell)
	room.visited = true
	enemies.clear()
	bullets.clear()
	hostile_bullets.clear()
	_collect_all_scrap()
	particles.clear()
	float_texts.clear()
	player_position = ARENA.get_center()
	if from_direction != Vector2i.ZERO:
		player_position = ARENA.get_center() - Vector2(from_direction) * Vector2(ARENA.size.x * 0.5 - 75, ARENA.size.y * 0.5 - 75)
	invulnerability = float(config_db.settings.combat.entry_invulnerability)
	door_cooldown = float(config_db.settings.combat.door_cooldown)
	dash_remaining = 0.0
	wave = 0
	wave_timer = -1.0
	state = "playing"
	_clear_ui()
	if room.kind == "combat" and not room.cleared:
		wave_timer = float(definition.waves.initial_delay)
		_set_notice("区域封锁 · 清除 %d 波异常体" % int(definition.waves.count), 2.5)
	elif room.kind == "boss" and not room.cleared:
		var containment = config_db.get_record("containments", definition.containment_id)
		_spawn_enemy(containment.monster_id, ARENA.get_center() + Vector2(185, 0))
		_set_notice("核心收容程序已启动", 3.0)
	elif room.kind == "treasure" and not room.claimed:
		room.cleared = true
		_show_rewards("treasure")
	elif room.kind == "supply":
		show_shop()
	queue_redraw()

func _room_locked() -> bool:
	return not floor_rooms[current_cell].cleared and bool(_room_config(current_cell).lock_until_clear)

func _door_position(direction: Vector2i) -> Vector2:
	return ARENA.get_center() + Vector2(direction) * ARENA.size * 0.5

func _process(delta: float) -> void:
	clock_time += delta
	if state == "playing":
		run_time += delta
		_tick_run(delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_run"):
		if state == "playing":
			show_pause()
		elif state == "paused":
			_resume_run()
	elif event.is_action_pressed("interact") and state == "playing":
		if floor_rooms[current_cell].kind == "supply":
			show_shop()

func _tick_run(delta: float) -> void:
	invulnerability = maxf(0.0, invulnerability - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	door_cooldown = maxf(0.0, door_cooldown - delta)
	notice_timer = maxf(0.0, notice_timer - delta)
	shake = maxf(0.0, shake - delta * 20.0)
	shake_offset = Vector2(rng.randf_range(-shake, shake), rng.randf_range(-shake, shake))
	var movement = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if movement.length_squared() > 0.01:
		last_move = movement.normalized()
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0:
		dash_direction = last_move
		dash_remaining = float(stats.dash_duration)
		dash_cooldown = float(stats.dash_cooldown)
		_play_sound("dash")
	if dash_remaining > 0.0:
		dash_remaining -= delta
		player_position += dash_direction * float(stats.dash_speed) * delta
		_emit_particles(player_position, TEAL, 2)
	else:
		player_position += movement * float(stats.speed) * delta
	player_position.x = clampf(player_position.x, ARENA.position.x + PLAYER_RADIUS, ARENA.end.x - PLAYER_RADIUS)
	player_position.y = clampf(player_position.y, ARENA.position.y + PLAYER_RADIUS, ARENA.end.y - PLAYER_RADIUS)
	if wave_timer >= 0.0:
		wave_timer -= delta
		if wave_timer < 0.0:
			_spawn_wave()
	_tick_enemies(delta)
	if state != "playing":
		return
	shoot_timer -= delta
	if shoot_timer <= 0.0 and not enemies.is_empty():
		_auto_fire()
	_tick_bullets(delta)
	if state != "playing":
		return
	_tick_pickups(delta)
	_tick_effects(delta)
	_check_room_completion()
	if state == "playing":
		_check_doors()

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

func _tick_enemies(delta: float) -> void:
	for enemy in enemies:
		enemy.flash = maxf(0.0, float(enemy.flash) - delta)
		enemy.cooldown -= delta
		var toward: Vector2 = player_position - Vector2(enemy.pos)
		var direction = toward.normalized()
		if enemy.behavior == "boss_radial_charge":
			_tick_boss(enemy, direction, delta)
		elif enemy.behavior == "shooter":
			if toward.length() > float(enemy.attack.approach_distance):
				enemy.pos += direction * float(enemy.speed) * delta
			elif toward.length() < float(enemy.attack.retreat_distance):
				enemy.pos -= direction * float(enemy.speed) * delta
			if enemy.cooldown <= 0.0:
				_hostile_fire(enemy.pos, direction, float(enemy.attack.bullet_speed), float(enemy.attack.damage))
				enemy.cooldown = float(enemy.attack.interval)
		else:
			enemy.pos += direction * float(enemy.speed) * delta
		enemy.pos.x = clampf(enemy.pos.x, ARENA.position.x + enemy.radius, ARENA.end.x - enemy.radius)
		enemy.pos.y = clampf(enemy.pos.y, ARENA.position.y + enemy.radius, ARENA.end.y - enemy.radius)
		if player_position.distance_to(enemy.pos) < PLAYER_RADIUS + float(enemy.radius):
			_damage_player(float(enemy.contact_damage))
			if state != "playing":
				return

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

func _auto_fire() -> void:
	var target: Dictionary = {}
	var best_distance = float(stats.range)
	for enemy in enemies:
		var distance = player_position.distance_to(enemy.pos)
		if distance < best_distance:
			best_distance = distance
			target = enemy
	if target.is_empty():
		shoot_timer = 0.1
		return
	var aim = (Vector2(target.pos) - player_position).angle()
	weapon_direction = Vector2.from_angle(aim)
	var count = int(stats.projectiles)
	for index in range(count):
		var angle = aim + (float(index) - float(count - 1) / 2.0) * float(stats.spread_angle)
		bullets.append({
			"pos": player_position, "velocity": Vector2.from_angle(angle) * float(stats.bullet_speed),
			"life": float(stats.range) / float(stats.bullet_speed), "damage": float(stats.damage),
			"pierce": int(stats.pierce), "hit_ids": [],
		})
	shoot_timer = float(stats.fire_interval)
	_play_sound("shoot")

func _hostile_fire(position: Vector2, direction: Vector2, speed: float, damage: float) -> void:
	hostile_bullets.append({"pos": position, "velocity": direction * speed, "damage": damage, "life": float(config_db.settings.combat.hostile_bullet_lifetime)})

func _tick_bullets(delta: float) -> void:
	for index in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[index]
		var old_position: Vector2 = bullet.pos
		bullet.pos += Vector2(bullet.velocity) * delta
		bullet.life -= delta
		var remove = bullet.life <= 0.0 or not ARENA.grow(25).has_point(bullet.pos)
		if not remove:
			for enemy_index in range(enemies.size() - 1, -1, -1):
				var enemy: Dictionary = enemies[enemy_index]
				if int(enemy.id) in bullet.hit_ids:
					continue
				var closest = Geometry2D.get_closest_point_to_segment(enemy.pos, old_position, bullet.pos)
				if closest.distance_to(enemy.pos) <= float(enemy.radius) + 4.0:
					bullet.hit_ids.append(int(enemy.id))
					enemy.hp -= float(bullet.damage)
					enemy.flash = 0.10
					_emit_particles(bullet.pos, TEAL, 4)
					float_texts.append({"pos": Vector2(enemy.pos) - Vector2(0, 25), "text": str(int(bullet.damage)), "life": 0.65, "color": TEAL})
					if enemy.hp <= 0.0:
						_kill_enemy(enemy_index)
					if int(bullet.pierce) <= 0:
						remove = true
						break
					bullet.pierce -= 1
		if remove:
			bullets.remove_at(index)
	for index in range(hostile_bullets.size() - 1, -1, -1):
		var bullet: Dictionary = hostile_bullets[index]
		var old_position: Vector2 = bullet.pos
		bullet.pos += Vector2(bullet.velocity) * delta
		bullet.life -= delta
		var closest = Geometry2D.get_closest_point_to_segment(player_position, old_position, bullet.pos)
		if closest.distance_to(player_position) <= PLAYER_RADIUS + 5.0:
			var damage = float(bullet.damage)
			hostile_bullets.remove_at(index)
			_damage_player(damage)
			if state != "playing":
				return
		elif bullet.life <= 0 or not ARENA.grow(25).has_point(bullet.pos):
			hostile_bullets.remove_at(index)

func _kill_enemy(index: int) -> void:
	var enemy: Dictionary = enemies[index]
	kills += 1
	var drop = RunData.resolve_reward(config_db, enemy.drop_reward_id)
	if not drop.is_empty(): pickups.append({"pos": Vector2(enemy.pos), "amount": int(drop.amount)})
	_emit_particles(enemy.pos, ORANGE if enemy.kind == "boss" else RED, 18)
	shake = maxf(shake, 2.0 if enemy.kind != "boss" else 7.0)
	enemies.remove_at(index)
	_play_sound("kill")

func _damage_player(amount: float) -> void:
	if invulnerability > 0.0 or dash_remaining > 0.0 or state != "playing":
		return
	var damage = maxf(1.0, amount * (1.0 - float(stats.armor)))
	hp = maxf(0.0, hp - damage)
	invulnerability = float(config_db.settings.combat.hit_invulnerability)
	shake = 7.0
	_emit_particles(player_position, RED, 22)
	float_texts.append({"pos": player_position - Vector2(0, 35), "text": "−%d" % int(damage), "life": 0.8, "color": RED})
	_play_sound("hurt")
	if hp <= 0.0:
		show_result(false)

func _tick_pickups(delta: float) -> void:
	for index in range(pickups.size() - 1, -1, -1):
		var item: Dictionary = pickups[index]
		var distance = player_position.distance_to(item.pos)
		if distance < float(config_db.settings.combat.pickup_radius):
			scrap += int(item.amount)
			pickups.remove_at(index)
			_play_sound("pickup")
		elif distance < float(stats.magnet):
			item.pos = Vector2(item.pos).move_toward(player_position, float(config_db.settings.combat.pickup_speed) * delta)

func _collect_all_scrap() -> void:
	for item in pickups:
		scrap += int(item.amount)
	pickups.clear()

func _check_room_completion() -> void:
	var room: Dictionary = floor_rooms[current_cell]
	if room.cleared or not enemies.is_empty() or wave_timer >= 0.0:
		return
	if room.kind == "combat":
		var definition = _room_config(current_cell)
		if wave < int(definition.waves.count):
			wave_timer = float(definition.waves.between_delay)
			_set_notice("本波已清除 · 下一波即将出现", wave_timer)
		else:
			room.cleared = true
			cleared_count += 1
			_collect_all_scrap()
			_apply_reward(RunData.resolve_reward(config_db, definition.clear_reward_id), false)
			hostile_bullets.clear()
			bullets.clear()
			_play_sound("clear")
			_show_rewards("combat")
	elif room.kind == "boss":
		room.cleared = true
		_collect_all_scrap()
		show_result(true)

func _check_doors() -> void:
	if _room_locked() or door_cooldown > 0.0:
		return
	for direction in DIRECTIONS:
		var destination: Vector2i = current_cell + direction
		if not floor_rooms.has(destination):
			continue
		if player_position.distance_to(_door_position(direction)) < float(config_db.settings.combat.door_trigger_distance):
			if floor_rooms[destination].kind == "boss" and cleared_count < int(_room_config(destination).required_combat_clears):
				_set_notice("核心门禁：还需清除 %d 间战斗房" % (int(_room_config(destination).required_combat_clears) - cleared_count), 2.0)
				door_cooldown = 1.0
				return
			_enter_room(destination, direction)
			return

func _show_rewards(source: String) -> void:
	state = "reward"
	reward_source = source
	var definition = _room_config(current_cell)
	reward_choices = _roll_pool(definition.choice_pool_id, int(definition.choice_count))
	_clear_ui()
	_overlay()
	var title = "区域已净化 · 选择一项奖励" if source == "combat" else "发现封存物资 · 选择一项奖励"
	_label(title, Vector2(110, 108), Vector2(1080, 60), 34)
	_label("选择一项，仅对本次收容生效。" if source == "combat" else "探索奖励：免费领取一次，返回此房间不会重复获得。", Vector2(114, 171), Vector2(1040, 40), 18, TEAL)
	for index in range(reward_choices.size()):
		var item: Dictionary = reward_choices[index]
		var x = 110.0 + index * 360.0
		_card_panel(Vector2(x, 242), Vector2(330, 414))
		_label("0%d / %s" % [index + 1, item.tag], Vector2(x + 24, 270), Vector2(280, 40), 17, TEAL)
		_label(item.name, Vector2(x + 24, 335), Vector2(282, 65), 30)
		var description = _label(item.description, Vector2(x + 24, 427), Vector2(280, 130), 20)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_button("装备武器" if item.kind == "weapon" else "领取奖励", Vector2(x + 24, 574), Vector2(282, 60), _choose_reward.bind(index))
	if reward_choices.is_empty():
		_label("当前奖励池没有可用物资。", Vector2(114, 340), Vector2(1000, 50), 24, MUTED)
		_button("继续探索", Vector2(114, 540), Vector2(300, 60), _finish_reward)
	_label("领取后房门开放；走向门口继续探索。", Vector2(114, 700), Vector2(1000, 40), 17, MUTED)

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

func _reroll_shop() -> void:
	if state != "shop" or scrap < shop_reroll_cost: return
	var room: Dictionary = floor_rooms[current_cell]
	var shop: Dictionary = _room_config(current_cell).shop
	scrap -= shop_reroll_cost
	room.reroll_cost += int(shop.reroll_increment)
	room.shop = _roll_pool(shop.pool_id, int(shop.slots))
	room.shop_generated = true
	show_shop()

func _leave_shop() -> void:
	state = "playing"
	_clear_ui()
	door_cooldown = 0.5
	_set_notice("补给终端待机 · 按 E 打开", 3.0)

func show_pause() -> void:
	state = "paused"
	_clear_ui()
	_overlay()
	_label("收容暂缓", Vector2(460, 185), Vector2(480, 75), 46)
	_label("暂停期间，战斗与计时均停止。", Vector2(425, 280), Vector2(560, 45), 21, MUTED)
	_button("继续收容", Vector2(460, 373), Vector2(360, 62), _resume_run)
	_button("声音：关闭" if muted else "声音：开启", Vector2(460, 456), Vector2(360, 52), func():
		muted = not muted
		show_pause()
	, MUTED)
	_button("放弃本次收容", Vector2(460, 532), Vector2(360, 52), show_abandon_confirmation, RED)

func show_abandon_confirmation() -> void:
	_clear_ui()
	_overlay()
	_label("放弃本次收容？", Vector2(430, 245), Vector2(640, 65), 38)
	_label("本局强化和零件将被清空。", Vector2(430, 330), Vector2(600, 40), 21, MUTED)
	_button("返回暂停页", Vector2(430, 430), Vector2(260, 58), show_pause)
	_button("确认放弃", Vector2(715, 430), Vector2(220, 58), show_menu, RED)

func _resume_run() -> void:
	state = "playing"
	_clear_ui()

func show_result(won: bool) -> void:
	state = "victory" if won else "defeat"
	_clear_ui()
	_overlay()
	var accent = TEAL if won else RED
	_label("ATTEMPT CLOSED / 本次记录已封存", Vector2(110, 105), Vector2(1100, 40), 18, accent)
	_label("收容完成" if won else "收容失败", Vector2(105, 197), Vector2(1050, 90), 62, accent)
	_label("异常核心已关闭。回收员撤离。" if won else "生命体征丢失。下一次会有所不同。", Vector2(112, 300), Vector2(1000, 50), 24)
	_label("存活时间\n%s" % _format_time(run_time), Vector2(114, 407), Vector2(240, 95), 24)
	_label("清除异常体\n%03d" % kills, Vector2(384, 407), Vector2(240, 95), 24)
	_label("战斗房 / 强化\n%d / %d" % [cleared_count, upgrade_count], Vector2(654, 407), Vector2(270, 95), 24)
	_label("剩余零件\n%03d" % scrap, Vector2(951, 407), Vector2(220, 95), 24)
	_button("再尝试一次", Vector2(114, 588), Vector2(300, 63), start_run, accent)
	_button("重新选人", Vector2(439, 588), Vector2(260, 63), show_characters, MUTED)
	_button("返回主界面", Vector2(724, 588), Vector2(260, 63), show_menu, MUTED)
	_label("当前没有局外永久加成，每次重新开始都使用基础属性。", Vector2(114, 701), Vector2(1100, 38), 18, MUTED)
	_play_sound("clear" if won else "alarm")

func _set_notice(content: String, duration: float = 2.5) -> void:
	notice = content
	notice_timer = duration

func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]

func _emit_particles(position: Vector2, color: Color, count: int) -> void:
	for index in range(count):
		particles.append({"pos": position, "velocity": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(35, 160), "life": rng.randf_range(0.18, 0.5), "color": color})
	# Prevent decorative effects from accumulating indefinitely during a long run.
	while particles.size() > 500:
		particles.pop_front()

func _tick_effects(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var item: Dictionary = particles[index]
		item.pos += Vector2(item.velocity) * delta
		item.life -= delta
		if item.life <= 0.0:
			particles.remove_at(index)
	for index in range(float_texts.size() - 1, -1, -1):
		float_texts[index].pos.y -= 34 * delta
		float_texts[index].life -= delta
		if float_texts[index].life <= 0:
			float_texts.remove_at(index)

func _draw() -> void:
	if font == null:
		return
	draw_rect(Rect2(0, 0, 1280, 800), INK)
	_draw_background()
	if state in ["menu", "characters", "meta", "config_error"]:
		_draw_menu_art()
	elif not floor_rooms.is_empty():
		_draw_game()
	if state == "reward" or state == "shop":
		# UI tint is above the arena; card bodies are UI controls as well.
		pass

func _draw_background() -> void:
	for x in range(0, 1281, 40):
		draw_line(Vector2(x, 0), Vector2(x, 800), Color(0.15, 0.25, 0.32, 0.14))
	for y in range(0, 801, 40):
		draw_line(Vector2(0, y), Vector2(1280, y), Color(0.15, 0.25, 0.32, 0.14))
	draw_line(Vector2(48, 45), Vector2(1232, 45), Color("243541"), 1)
	draw_circle(Vector2(1227, 26), 3, TEAL if sin(clock_time * 2) > 0 else TEAL.darkened(0.6))
	_text("FACILITY 09   /   LOCAL SESSION", Vector2(48, 31), 13, MUTED)

func _draw_menu_art() -> void:
	if state == "menu":
		var center = Vector2(916, 386)
		for radius in [90, 135, 185]:
			draw_arc(center, radius, clock_time * 0.12, clock_time * 0.12 + TAU * 0.82, 90, Color(TEAL, 0.20), 1.5)
		for index in range(4):
			var angle = index * PI / 2 + clock_time * 0.08
			var position = center + Vector2.from_angle(angle) * 153
			draw_rect(Rect2(position - Vector2(11, 11), Vector2(22, 22)), ORANGE, false, 2)
		_draw_operator(center, 4.0)
		_text("E—01", center + Vector2(-34, 254), 22, TEAL)
		_text("STATUS: AWAITING ATTEMPT", Vector2(790, 686), 14, MUTED)
	elif state == "characters":
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

func _text(content: String, position: Vector2, font_size: int = 18, color: Color = TEXT) -> void:
	draw_string(font, position, content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_game() -> void:
	var room: Dictionary = floor_rooms[current_cell]
	var definition = _room_config(current_cell)
	_text("第██次收容", Vector2(48, 92), 30)
	_text("%s    [%d,%d]" % [definition.title, current_cell.x + 1, current_cell.y + 1], Vector2(48, 121), 16, MUTED)
	_text("ATTEMPT %02d    %s" % [attempt, _format_time(run_time)], Vector2(815, 92), 17, TEAL)
	_text("%s / %s" % [config_db.get_record("characters", selected_character_id).name, config_db.get_record("weapons", equipped_weapon_id).name], Vector2(815, 121), 14, MUTED)
	draw_rect(ARENA, Color("101c25"))
	for x in range(int(ARENA.position.x), int(ARENA.end.x), 48):
		for y in range(int(ARENA.position.y), int(ARENA.end.y), 48):
			draw_circle(Vector2(x + 24, y + 24), 1, Color("28404c"))
	draw_rect(ARENA, Color("3b5360"), false, 3)
	_draw_floor_markings(room)
	_draw_doors()
	for item in pickups:
		var p: Vector2 = item.pos
		draw_circle(p, 10, Color(ORANGE, 0.08))
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)]), ORANGE)
	for bullet in bullets:
		var p: Vector2 = bullet.pos
		draw_line(p - Vector2(bullet.velocity).normalized() * 15, p, TEAL, 3.0)
		draw_circle(p, 3.5, TEXT)
	for bullet in hostile_bullets:
		draw_circle(bullet.pos, 8, Color(RED, 0.13))
		draw_circle(bullet.pos, 5, RED)
	for enemy in enemies:
		_draw_enemy(enemy)
	for particle in particles:
		draw_circle(particle.pos, 2, Color(particle.color, clampf(particle.life * 2, 0, 1)))
	if invulnerability <= 0.0 or int(clock_time * 16) % 2 == 0:
		_draw_operator(player_position + shake_offset, 1.0)
	if dash_remaining > 0:
		draw_arc(player_position, 24, 0, TAU, 24, TEAL, 2)
	for item in float_texts:
		_text(item.text, item.pos, 16, Color(item.color, minf(1, item.life * 2)))
	_draw_hud()
	if notice_timer > 0.0:
		draw_rect(Rect2(210, 680, 652, 34), Color(INK, 0.88))
		_text(notice, Vector2(226, 703), 17, TEAL)
	_text("WASD / 方向键：移动    空格：冲刺（无敌）    自动攻击    Esc：暂停", Vector2(48, 767), 16, MUTED)

func _draw_floor_markings(room: Dictionary) -> void:
	var center = ARENA.get_center()
	draw_arc(center, 96, 0, TAU, 64, Color(TEAL, 0.05), 2)
	draw_line(center - Vector2(120, 0), center + Vector2(120, 0), Color(TEAL, 0.05))
	draw_line(center - Vector2(0, 120), center + Vector2(0, 120), Color(TEAL, 0.05))
	if room.kind == "supply":
		draw_rect(Rect2(center - Vector2(43, 36), Vector2(86, 72)), Color("1a333a"))
		draw_rect(Rect2(center - Vector2(43, 36), Vector2(86, 72)), TEAL, false, 2)
		_text("E / 补给", center + Vector2(-37, 63), 16, TEAL)
	elif room.kind == "treasure":
		draw_rect(Rect2(center - Vector2(33, 24), Vector2(66, 48)), ORANGE.darkened(0.65), false, 2)
		_text("已回收", center + Vector2(-29, 54), 15, MUTED)
	elif room.kind == "start":
		_text("ENTRY / 回收入口", center + Vector2(-85, 103), 17, MUTED)

func _draw_doors() -> void:
	for direction in DIRECTIONS:
		var destination: Vector2i = current_cell + direction
		if not floor_rooms.has(destination):
			continue
		var locked = _room_locked()
		var is_boss = floor_rooms[destination].kind == "boss"
		if is_boss and cleared_count < int(_room_config(destination).required_combat_clears):
			locked = true
		var p = _door_position(direction)
		var horizontal = direction.x != 0
		var size = Vector2(18, 82) if horizontal else Vector2(82, 18)
		var color = RED if locked else (ORANGE if is_boss else TEAL)
		draw_rect(Rect2(p - size * 0.5, size), color.darkened(0.60))
		draw_rect(Rect2(p - size * 0.5, size), color, false, 2)
		if locked:
			for index in range(3):
				var offset = (index - 1) * 22.0
				if horizontal:
					draw_line(p + Vector2(-8, offset - 7), p + Vector2(8, offset + 7), color, 2)
				else:
					draw_line(p + Vector2(offset - 7, -8), p + Vector2(offset + 7, 8), color, 2)
		else:
			var inward = p - Vector2(direction) * 23
			var side = Vector2(-direction.y, direction.x) * 6
			draw_line(inward - side, inward + Vector2(direction) * 7, color, 2)
			draw_line(inward + side, inward + Vector2(direction) * 7, color, 2)

func _draw_operator(position: Vector2, scale_factor: float) -> void:
	var r = 14 * scale_factor
	draw_circle(position + Vector2(0, 4) * scale_factor, r + 5 * scale_factor, Color(0, 0, 0, 0.22))
	draw_circle(position, r, Color("213e4a"))
	draw_arc(position, r, 0, TAU, 32, TEAL, 2 * scale_factor)
	draw_rect(Rect2(position - Vector2(8, 6) * scale_factor, Vector2(16, 6) * scale_factor), TEAL)
	draw_line(position + Vector2(-6, 9) * scale_factor, position + Vector2(6, 9) * scale_factor, MUTED, 2 * scale_factor)
	if scale_factor == 1.0:
		draw_line(position + weapon_direction * 10, position + weapon_direction * 23, TEXT, 4)

func _draw_enemy(enemy: Dictionary) -> void:
	var p: Vector2 = enemy.pos
	var r = float(enemy.radius)
	var color = ORANGE if enemy.kind == "shooter" else RED
	if enemy.flash > 0:
		color = TEXT
	if enemy.kind == "tank":
		draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), Color("482735"))
		draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), color, false, 2)
	elif enemy.kind == "shooter":
		var points = PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, r * 0.8), p + Vector2(-r, r * 0.8)])
		draw_colored_polygon(points, color.darkened(0.7))
		points.append(points[0])
		draw_polyline(points, color, 2)
	else:
		draw_circle(p, r, Color("482735"))
		draw_arc(p, r, 0, TAU, 32, color, 2)
		draw_line(p - Vector2(6, 4), p + Vector2(6, 4), color, 2)
		draw_line(p - Vector2(6, -4), p + Vector2(6, -4), color, 2)
	if enemy.kind == "boss":
		draw_arc(p, r + 10, clock_time, clock_time + TAU * 0.8, 40, ORANGE, 3)
		if enemy.charge_timer > 0:
			var end = p + Vector2(enemy.charge_dir) * float(enemy.attack.charge_speed) * float(enemy.attack.charge_duration)
			draw_line(p, end, Color(RED, 0.35), 18)
			draw_line(p, end, RED, 2)
		var bar = Rect2(235, 159, 596, 12)
		draw_rect(bar, Color("342432"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * maxf(0, enemy.hp / enemy.max_hp), bar.size.y)), RED)
		_text(enemy.name, Vector2(477, 192), 17, RED)
	elif enemy.hp < enemy.max_hp:
		draw_rect(Rect2(p + Vector2(-r, -r - 9), Vector2(r * 2, 3)), Color("352737"))
		draw_rect(Rect2(p + Vector2(-r, -r - 9), Vector2(r * 2 * maxf(0, enemy.hp / enemy.max_hp), 3)), color)

func _draw_hud() -> void:
	draw_rect(Rect2(1040, 140, 192, 584), PANEL)
	_text("生命体征", Vector2(1056, 172), 17, MUTED)
	_text("%d / %d" % [ceili(hp), int(stats.max_hp)], Vector2(1056, 207), 27, TEAL if hp > stats.max_hp * 0.3 else RED)
	draw_rect(Rect2(1056, 220, 160, 8), Color("293941"))
	draw_rect(Rect2(1056, 220, 160 * hp / float(stats.max_hp), 8), TEAL if hp > stats.max_hp * 0.3 else RED)
	_text("零件  %03d" % scrap, Vector2(1056, 270), 23, ORANGE)
	_text("冲刺就绪" if dash_cooldown <= 0.0 else "冲刺冷却 %.1fs" % dash_cooldown, Vector2(1056, 304), 16, TEAL if dash_cooldown <= 0.0 else MUTED)
	_text("设施导航", Vector2(1056, 354), 17, MUTED)
	_draw_minimap(Vector2(1063, 373))
	_text("核心门禁  %d / %d" % [mini(cleared_count, _boss_requirement()), _boss_requirement()], Vector2(1056, 503), 16, ORANGE)
	_text("伤害     %.0f" % float(stats.damage), Vector2(1056, 550), 16)
	_text("射速     %.1f / 秒" % (1.0 / float(stats.fire_interval)), Vector2(1056, 577), 16)
	_text("弹数     %d" % int(stats.projectiles), Vector2(1056, 604), 16)
	_text("穿透     %d" % int(stats.pierce), Vector2(1056, 631), 16)
	_text("减伤     %d%%" % roundi(float(stats.armor) * 100), Vector2(1056, 658), 16)
	_text("强化     %d 项" % upgrade_count, Vector2(1056, 691), 16, TEAL)

func _draw_minimap(origin: Vector2) -> void:
	var low = Vector2i(100000, 100000)
	var high = Vector2i(-100000, -100000)
	for cell in floor_rooms:
		low.x = mini(low.x, cell.x)
		low.y = mini(low.y, cell.y)
		high.x = maxi(high.x, cell.x)
		high.y = maxi(high.y, cell.y)
	var step = minf(39.0, minf(160.0 / float(high.x - low.x + 1), 108.0 / float(high.y - low.y + 1)))
	var size = Vector2(maxf(1.0, step - 6), maxf(1.0, step - 9))
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

func _build_sounds() -> void:
	# Short original synthesized effects; no downloaded assets or audio dependencies.
	var definitions = {
		"shoot": [540.0, 0.045, 0.12], "kill": [150.0, 0.09, 0.18],
		"hurt": [75.0, 0.15, 0.22], "pickup": [960.0, 0.04, 0.07],
		"dash": [280.0, 0.09, 0.12], "upgrade": [720.0, 0.19, 0.14],
		"clear": [460.0, 0.22, 0.15], "click": [610.0, 0.035, 0.08],
		"alarm": [110.0, 0.25, 0.18],
	}
	for name in definitions:
		var definition: Array = definitions[name]
		var frequency = float(definition[0])
		var duration = float(definition[1])
		var amplitude = float(definition[2])
		var data = PackedByteArray()
		var sample_rate = 22050
		var sample_count = int(duration * sample_rate)
		data.resize(sample_count * 2)
		for index in range(sample_count):
			var t = float(index) / sample_rate
			var progress = float(index) / sample_count
			var envelope = (1.0 - progress) * minf(1.0, progress * 30)
			var chirp = 1.0 + progress * (0.7 if name == "upgrade" or name == "clear" else -0.5)
			var sample = sin(TAU * frequency * chirp * t) * amplitude * envelope
			data.encode_s16(index * 2, int(sample * 32767))
		var stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = sample_rate
		stream.data = data
		sounds[name] = stream
	for index in range(12):
		var player = AudioStreamPlayer.new()
		player.volume_db = -7.0
		add_child(player)
		sound_players.append(player)

func _play_sound(name: String) -> void:
	if muted or not sounds.has(name) or sound_players.is_empty():
		return
	var player: AudioStreamPlayer = sound_players[sound_cursor % sound_players.size()]
	sound_cursor += 1
	player.stream = sounds[name]
	player.play()
