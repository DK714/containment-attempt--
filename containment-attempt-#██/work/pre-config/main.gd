extends Node2D
## Single-floor prototype. All gameplay is simulated only while state == "playing".
## Meta progression deliberately has no persistence or effects in this version.

const RunData = preload("res://run_data.gd")
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
	show_menu()

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

func show_characters() -> void:
	state = "characters"
	_clear_ui()
	_label("人员档案  /  SELECT OPERATOR", Vector2(84, 74), Vector2(900, 55), 32)
	_label("目前仅开放一名收容人员。", Vector2(86, 132), Vector2(900, 35), 18, MUTED)
	_label("01 / 已授权", Vector2(111, 218), Vector2(270, 30), 17, TEAL)
	_label("回收员", Vector2(111, 354), Vector2(270, 55), 36)
	_label("E–01  /  RECLAIMER", Vector2(111, 415), Vector2(280, 35), 17, MUTED)
	_label("生命 100    自动瞄准\n\n标准回收枪，靠近零件自动拾取。\n清空房间后，选择一项强化。\n\n移动：WASD / 方向键\n冲刺：空格    暂停：Esc", Vector2(111, 463), Vector2(360, 185), 18)
	_label("02 / 未授权", Vector2(523, 218), Vector2(270, 30), 17, MUTED)
	_label("档案已封存", Vector2(523, 354), Vector2(270, 55), 30, MUTED)
	_label("后续角色预留", Vector2(523, 425), Vector2(270, 30), 18, MUTED)
	_label("03 / 未授权", Vector2(935, 218), Vector2(270, 30), 17, MUTED)
	_label("档案已封存", Vector2(935, 354), Vector2(270, 55), 30, MUTED)
	_label("后续角色预留", Vector2(935, 425), Vector2(270, 30), 18, MUTED)
	_button("以回收员开始收容", Vector2(111, 658), Vector2(326, 57), start_run)
	_button("未开放", Vector2(523, 658), Vector2(326, 57), func(): pass, MUTED, true)
	_button("未开放", Vector2(935, 658), Vector2(242, 57), func(): pass, MUTED, true)
	_button("返回", Vector2(84, 739), Vector2(125, 40), show_menu, MUTED)
	queue_redraw()

func show_meta() -> void:
	state = "meta"
	_clear_ui()
	_label("长期收容计划", Vector2(100, 125), Vector2(1080, 70), 42)
	_label("META PROGRESSION / RESERVED", Vector2(104, 205), Vector2(900, 45), 19, TEAL)
	_label("这里预留局外成长入口。\n\n当前版本每次开始都会重置属性、零件和强化。\n本页暂不提供购买、解锁或永久加成。", Vector2(104, 320), Vector2(1050, 200), 24)
	_button("返回主界面", Vector2(104, 605), Vector2(300, 60), show_menu)
	queue_redraw()

func start_run() -> void:
	attempt += 1
	stats = RunData.BASE_STATS.duplicate(true)
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
	_enter_room(Vector2i.ZERO)
	_set_notice("自动攻击 · 空格冲刺 · 靠近开放的门进入下一间", 6.0)

func _generate_floor() -> void:
	floor_rooms.clear()
	# Connected 4 × 3 floor. Layout is legible; rewards/enemies are randomized per run.
	for y in range(3):
		for x in range(4):
			var cell = Vector2i(x, y)
			var kind = "combat"
			if cell == Vector2i.ZERO:
				kind = "start"
			elif cell == Vector2i(3, 0):
				kind = "boss"
			elif cell == Vector2i(0, 1):
				kind = "supply"
			elif cell == Vector2i(2, 2):
				kind = "treasure"
			floor_rooms[cell] = {
				"kind": kind, "visited": false, "cleared": kind == "start" or kind == "supply",
				"claimed": false, "shop": [], "heal_used": false,
			}

func _enter_room(cell: Vector2i, from_direction: Vector2i = Vector2i.ZERO) -> void:
	current_cell = cell
	var room: Dictionary = floor_rooms[cell]
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
	invulnerability = 1.0
	door_cooldown = 0.9
	dash_remaining = 0.0
	wave = 0
	wave_timer = -1.0
	state = "playing"
	_clear_ui()
	if room.kind == "combat" and not room.cleared:
		wave_timer = 0.7
		_set_notice("区域封锁 · 清除两波异常体", 2.5)
	elif room.kind == "boss" and not room.cleared:
		_spawn_enemy("boss", ARENA.get_center() + Vector2(185, 0))
		_set_notice("核心收容程序已启动", 3.0)
	elif room.kind == "treasure" and not room.claimed:
		room.cleared = true
		_show_rewards("treasure")
	elif room.kind == "supply":
		show_shop()
	queue_redraw()

func _room_locked() -> bool:
	var room: Dictionary = floor_rooms[current_cell]
	return not room.cleared and (room.kind == "combat" or room.kind == "boss")

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
		dash_remaining = 0.17
		dash_cooldown = 1.4
		_play_sound("dash")
	if dash_remaining > 0.0:
		dash_remaining -= delta
		player_position += dash_direction * 690.0 * delta
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
	var count = 5 + mini(cleared_count, 5) + wave
	for index in range(count):
		var spawn = Vector2.ZERO
		for tries in range(24):
			spawn = Vector2(rng.randf_range(ARENA.position.x + 55, ARENA.end.x - 55), rng.randf_range(ARENA.position.y + 55, ARENA.end.y - 55))
			if spawn.distance_to(player_position) > 240:
				break
		var kind = "chaser"
		if index % 5 == 3:
			kind = "shooter"
		elif index % 5 == 4:
			kind = "tank"
		_spawn_enemy(kind, spawn)
	_set_notice("异常体入侵 / %d–2" % wave, 1.8)

func _spawn_enemy(kind: String, position: Vector2) -> void:
	next_enemy_id += 1
	var enemy = {
		"id": next_enemy_id, "kind": kind, "pos": position,
		"hp": 28.0 + cleared_count * 4.0, "max_hp": 28.0 + cleared_count * 4.0,
		"radius": 16.0, "speed": 80.0 + cleared_count * 4,
		"cooldown": rng.randf_range(1.0, 2.5), "flash": 0.0,
		"charge_timer": 0.0, "charge_dir": Vector2.ZERO, "charge_left": 0.0,
	}
	if kind == "tank":
		enemy.hp *= 2.7
		enemy.radius = 24.0
		enemy.speed *= 0.52
	elif kind == "shooter":
		enemy.speed *= 0.68
	elif kind == "boss":
		enemy.hp = 760.0 + cleared_count * 55.0
		enemy.radius = 43.0
		enemy.speed = 50.0
		enemy.cooldown = 1.6
	enemy.max_hp = enemy.hp
	enemies.append(enemy)
	_emit_particles(position, RED, 12)

func _tick_enemies(delta: float) -> void:
	for enemy in enemies:
		enemy.flash = maxf(0.0, float(enemy.flash) - delta)
		enemy.cooldown -= delta
		var toward: Vector2 = player_position - Vector2(enemy.pos)
		var direction = toward.normalized()
		if enemy.kind == "boss":
			_tick_boss(enemy, direction, delta)
		elif enemy.kind == "shooter":
			if toward.length() > 285:
				enemy.pos += direction * float(enemy.speed) * delta
			elif toward.length() < 165:
				enemy.pos -= direction * float(enemy.speed) * delta
			if enemy.cooldown <= 0.0:
				_hostile_fire(enemy.pos, direction, 190.0, 11.0)
				enemy.cooldown = 2.5
		else:
			enemy.pos += direction * float(enemy.speed) * delta
		enemy.pos.x = clampf(enemy.pos.x, ARENA.position.x + enemy.radius, ARENA.end.x - enemy.radius)
		enemy.pos.y = clampf(enemy.pos.y, ARENA.position.y + enemy.radius, ARENA.end.y - enemy.radius)
		if player_position.distance_to(enemy.pos) < PLAYER_RADIUS + float(enemy.radius):
			_damage_player(20.0 if enemy.kind == "boss" else 13.0)
			if state != "playing":
				return

func _tick_boss(enemy: Dictionary, direction: Vector2, delta: float) -> void:
	if enemy.charge_left > 0.0:
		enemy.charge_left -= delta
		enemy.pos += Vector2(enemy.charge_dir) * 430.0 * delta
	elif enemy.charge_timer > 0.0:
		enemy.charge_timer -= delta
		if enemy.charge_timer <= 0.0:
			enemy.charge_left = 0.5
			_play_sound("alarm")
	else:
		enemy.pos += direction * float(enemy.speed) * delta
		if enemy.cooldown <= 0.0:
			var angle = direction.angle()
			var count = 10 if enemy.hp > enemy.max_hp * 0.5 else 14
			for index in range(count):
				_hostile_fire(enemy.pos, Vector2.from_angle(angle + TAU * index / count), 155.0, 15.0)
			enemy.cooldown = 2.8 if count == 10 else 2.0
			enemy.charge_timer = 0.85
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
		var angle = aim + (float(index) - float(count - 1) / 2.0) * 0.15
		bullets.append({
			"pos": player_position, "velocity": Vector2.from_angle(angle) * 610.0,
			"life": float(stats.range) / 610.0, "damage": float(stats.damage),
			"pierce": int(stats.pierce), "hit_ids": [],
		})
	shoot_timer = float(stats.fire_interval)
	_play_sound("shoot")

func _hostile_fire(position: Vector2, direction: Vector2, speed: float, damage: float) -> void:
	hostile_bullets.append({"pos": position, "velocity": direction * speed, "damage": damage, "life": 7.0})

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
	var amount = 3 if enemy.kind == "tank" else 2
	if enemy.kind == "boss":
		amount = 30
	pickups.append({"pos": Vector2(enemy.pos), "amount": amount})
	_emit_particles(enemy.pos, ORANGE if enemy.kind == "boss" else RED, 18)
	shake = maxf(shake, 2.0 if enemy.kind != "boss" else 7.0)
	enemies.remove_at(index)
	_play_sound("kill")

func _damage_player(amount: float) -> void:
	if invulnerability > 0.0 or dash_remaining > 0.0 or state != "playing":
		return
	var damage = maxf(1.0, amount * (1.0 - float(stats.armor)))
	hp = maxf(0.0, hp - damage)
	invulnerability = 0.75
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
		if distance < 25:
			scrap += int(item.amount)
			pickups.remove_at(index)
			_play_sound("pickup")
		elif distance < float(stats.magnet):
			item.pos = Vector2(item.pos).move_toward(player_position, 340.0 * delta)

func _collect_all_scrap() -> void:
	for item in pickups:
		scrap += int(item.amount)
	pickups.clear()

func _check_room_completion() -> void:
	var room: Dictionary = floor_rooms[current_cell]
	if room.cleared or not enemies.is_empty() or wave_timer >= 0.0:
		return
	if room.kind == "combat":
		if wave < 2:
			wave_timer = 1.5
			_set_notice("第一波已清除 · 下一波即将出现", 1.5)
		else:
			room.cleared = true
			cleared_count += 1
			_collect_all_scrap()
			scrap += 8
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
		if player_position.distance_to(_door_position(direction)) < 39:
			if floor_rooms[destination].kind == "boss" and cleared_count < 4:
				_set_notice("核心门禁：还需清除 %d 间战斗房" % (4 - cleared_count), 2.0)
				door_cooldown = 1.0
				return
			_enter_room(destination, direction)
			return

func _show_rewards(source: String) -> void:
	state = "reward"
	reward_source = source
	reward_choices = RunData.roll_choices(stats, rng)
	_clear_ui()
	_overlay()
	var title = "区域已净化 · 选择一项强化" if source == "combat" else "发现封存物资 · 选择一项强化"
	_label(title, Vector2(110, 108), Vector2(1080, 60), 34)
	_label("三选一，仅对本次收容生效。" if source == "combat" else "探索奖励：免费领取一次，返回此房间不会重复获得。", Vector2(114, 171), Vector2(1040, 40), 18, TEAL)
	for index in range(reward_choices.size()):
		var item: Dictionary = reward_choices[index]
		var x = 110.0 + index * 360.0
		_card_panel(Vector2(x, 242), Vector2(330, 414))
		_label("0%d / %s" % [index + 1, item.tag], Vector2(x + 24, 270), Vector2(280, 40), 17, TEAL)
		_label(item.name, Vector2(x + 24, 335), Vector2(282, 65), 30)
		_label(item.description, Vector2(x + 24, 427), Vector2(280, 130), 20)
		_button("应用强化", Vector2(x + 24, 574), Vector2(282, 60), func(): _choose_reward(index))
	_label("强化后房门开放；走向门口继续探索。", Vector2(114, 700), Vector2(1000, 40), 17, MUTED)

func _choose_reward(index: int) -> void:
	if state != "reward" or index < 0 or index >= reward_choices.size():
		return
	var item: Dictionary = reward_choices[index]
	_apply_upgrade(item)
	floor_rooms[current_cell].claimed = true
	reward_choices.clear()
	state = "playing"
	_clear_ui()
	door_cooldown = 0.4
	_set_notice("已应用：%s · 房门开放" % item.name, 3.0)
	_play_sound("upgrade")

func _apply_upgrade(item: Dictionary) -> void:
	RunData.apply_upgrade(stats, item)
	if item.id == "hp":
		hp = minf(float(stats.max_hp), hp + 20.0)
	upgrade_count += 1

func show_shop() -> void:
	state = "shop"
	_clear_ui()
	_overlay()
	var room: Dictionary = floor_rooms[current_cell]
	if room.shop.is_empty():
		room.shop = RunData.roll_choices(stats, rng)
	_label("补给站  /  SUPPLY TERMINAL", Vector2(110, 88), Vector2(1040, 60), 34)
	_label("零件 %03d    ·    生命 %d / %d" % [scrap, ceili(hp), int(stats.max_hp)], Vector2(114, 156), Vector2(1000, 38), 22, ORANGE)
	_label("消灭异常体回收零件；刷新会生成新货架，购买和刷新都消耗本局零件。", Vector2(114, 203), Vector2(1100, 35), 17, MUTED)
	for index in range(room.shop.size()):
		var item: Dictionary = room.shop[index]
		var x = 110.0 + index * 360.0
		_card_panel(Vector2(x, 256), Vector2(330, 364), ORANGE)
		var sold = bool(item.get("sold", false))
		var capped = item.has("cap") and float(stats[item.stat]) >= float(item.cap) - 0.001
		_label("物资 %02d / %s" % [index + 1, item.tag], Vector2(x + 24, 285), Vector2(282, 30), 17, TEAL)
		_label(item.name, Vector2(x + 24, 344), Vector2(282, 55), 30)
		_label(item.description, Vector2(x + 24, 420), Vector2(282, 110), 19)
		var caption = "已购买" if sold else ("已达上限" if capped else "购买 · %d 零件" % int(item.price))
		_button(caption, Vector2(x + 24, 550), Vector2(282, 54), func(): _buy_item(index), ORANGE, sold or capped or scrap < int(item.price))
	var healing_disabled = room.heal_used or hp >= float(stats.max_hp) or scrap < 12
	_button("医疗已用" if room.heal_used else "应急医疗 +35 HP · 12 零件", Vector2(114, 643), Vector2(354, 50), _buy_heal, ORANGE, healing_disabled)
	_button("刷新物资 · %d 零件" % shop_reroll_cost, Vector2(488, 643), Vector2(295, 50), _reroll_shop, MUTED, scrap < shop_reroll_cost)
	_button("继续探索", Vector2(881, 643), Vector2(270, 50), _leave_shop)
	_label("离开后可返回；站内按 E 再次打开终端。", Vector2(114, 719), Vector2(1000, 35), 16, MUTED)

func _buy_item(index: int) -> void:
	if state != "shop":
		return
	var offers: Array = floor_rooms[current_cell].shop
	if index < 0 or index >= offers.size():
		return
	var item: Dictionary = offers[index]
	if item.get("sold", false) or scrap < int(item.price):
		return
	if item.has("cap") and float(stats[item.stat]) >= float(item.cap) - 0.001:
		return
	scrap -= int(item.price)
	_apply_upgrade(item)
	item.sold = true
	_play_sound("upgrade")
	show_shop()

func _buy_heal() -> void:
	var room: Dictionary = floor_rooms[current_cell]
	if state != "shop" or room.heal_used or scrap < 12 or hp >= float(stats.max_hp):
		return
	scrap -= 12
	hp = minf(float(stats.max_hp), hp + 35)
	room.heal_used = true
	_play_sound("upgrade")
	show_shop()

func _reroll_shop() -> void:
	if state != "shop" or scrap < shop_reroll_cost:
		return
	scrap -= shop_reroll_cost
	shop_reroll_cost += 3
	floor_rooms[current_cell].shop = RunData.roll_choices(stats, rng)
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
	if state in ["menu", "characters", "meta"]:
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
		for index in range(3):
			var x = 85.0 + index * 412.0
			draw_rect(Rect2(x, 192, 374 if index < 2 else 326, 534), PANEL)
			draw_rect(Rect2(x, 192, 374 if index < 2 else 326, 534), TEAL.darkened(0.65) if index == 0 else Color("2a3540"), false, 1)
			if index == 0:
				_draw_operator(Vector2(266, 295), 2.2)
			else:
				draw_circle(Vector2(x + 174, 298), 37, Color("1d2934"))
				draw_rect(Rect2(x + 163, 283, 22, 24), MUTED.darkened(0.55), false, 2)
				draw_arc(Vector2(x + 174, 283), 9, PI, TAU, 20, MUTED.darkened(0.55), 2)

func _text(content: String, position: Vector2, font_size: int = 18, color: Color = TEXT) -> void:
	draw_string(font, position, content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_game() -> void:
	var room: Dictionary = floor_rooms[current_cell]
	var titles = {"start": "入口 / 安全区域", "combat": "隔离室 / 清除异常体", "supply": "补给站 / 回收终端", "treasure": "封存仓 / 探索奖励", "boss": "收容核心 / 最终区域"}
	_text("第██次收容", Vector2(48, 92), 30)
	_text("%s    [%d,%d]" % [titles[room.kind], current_cell.x + 1, current_cell.y + 1], Vector2(48, 121), 16, MUTED)
	_text("ATTEMPT %02d    %s" % [attempt, _format_time(run_time)], Vector2(815, 92), 17, TEAL)
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
		if is_boss and cleared_count < 4:
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
			var end = p + Vector2(enemy.charge_dir) * 230
			draw_line(p, end, Color(RED, 0.35), 18)
			draw_line(p, end, RED, 2)
		var bar = Rect2(235, 159, 596, 12)
		draw_rect(bar, Color("342432"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * maxf(0, enemy.hp / enemy.max_hp), bar.size.y)), RED)
		_text("异常核心", Vector2(477, 192), 17, RED)
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
	_text("核心门禁  %d / 4" % mini(cleared_count, 4), Vector2(1056, 503), 16, ORANGE)
	_text("伤害     %.0f" % float(stats.damage), Vector2(1056, 550), 16)
	_text("射速     %.1f / 秒" % (1.0 / float(stats.fire_interval)), Vector2(1056, 577), 16)
	_text("弹数     %d" % int(stats.projectiles), Vector2(1056, 604), 16)
	_text("穿透     %d" % int(stats.pierce), Vector2(1056, 631), 16)
	_text("减伤     %d%%" % roundi(float(stats.armor) * 100), Vector2(1056, 658), 16)
	_text("强化     %d 项" % upgrade_count, Vector2(1056, 691), 16, TEAL)

func _draw_minimap(origin: Vector2) -> void:
	for cell in floor_rooms:
		var room: Dictionary = floor_rooms[cell]
		var visible = bool(room.visited)
		for direction in DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			if floor_rooms.has(neighbor) and floor_rooms[neighbor].visited:
				visible = true
		if not visible:
			continue
		var p = origin + Vector2(cell) * Vector2(39, 37)
		var color = Color("273c47")
		if room.visited:
			color = Color("45626a") if room.cleared else RED.darkened(0.65)
		draw_rect(Rect2(p, Vector2(31, 26)), color)
		if cell == current_cell:
			draw_rect(Rect2(p, Vector2(31, 26)), TEAL, false, 2)
		if room.visited or room.kind == "boss":
			var symbol = {"start": "S", "combat": "·", "supply": "+", "treasure": "?", "boss": "!"}[room.kind]
			_text(symbol, p + Vector2(10, 19), 16, ORANGE if room.kind == "boss" else TEXT)

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
