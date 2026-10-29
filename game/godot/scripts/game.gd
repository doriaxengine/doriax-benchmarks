extends Node

const SceneBuilder = preload("res://scripts/scene_builder.gd")
const Benchmark = preload("res://scripts/benchmark.gd")
var builder: RefCounted
var world: Node3D
var canvas: CanvasLayer
var ui_root: Control
var camera: Camera3D
var player: RigidBody3D
var world_scopes: Array = []
var world_scope: Dictionary = {}
var hud: Dictionary = {}
var overlay: Dictionary = {}
var menus: Dictionary = {}
var loading_scope: Dictionary = {}
var sounds: Dictionary = {}
var pickups: Array = []
var portal_entries: Array = []
var score = 0
var level_start_score = 0
var lives = 3
var has_key = false
var has_checkpoint = false
var checkpoint = Vector3.ZERO
var spawn = Vector3.ZERO
var level_name = ""
var level_title = ""
var next_level = ""
var completion_bonus = 100
var paused = false
var loading = false
var finished = false
var benchmark = false
var benchmark_runner: Node
var menu_arm_timer = 0.0
var banner_timer = 0.0
var message_timer = 0.0
var best_score = 0
var coins = 0
var gems = 0
var coin_total = 0
var gem_total = 0
var touch_move = Vector2.ZERO
var touch_jump = false
var touch_points: Dictionary = {}
var stick_finger = -1
var look_finger = -1
var touch_shown = false
var touch_previous = {}
var dust_mesh: Mesh
# For the same number Godot's sun is about pi times brighter than Doriax's, so the
# authored intensity 4.0 is scaled by 0.32 (about 1 / pi) here.
# Pass --light-scale 1.0 to inspect unchanged authored directional energy.
var light_scale = 0.32
var shown_lives = -1

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The source levels disable mesh LOD. A zero threshold also disables it here.
	get_viewport().mesh_lod_threshold = 0.0
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/source.json"))
	builder = SceneBuilder.new(self, data)
	canvas = CanvasLayer.new()
	add_child(canvas)
	ui_root = Control.new()
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui_root)
	var save = ConfigFile.new()
	if save.load("user://lostslime.cfg") == OK:
		best_score = int(save.get_value("score", "best", 0))
	var args = OS.get_cmdline_user_args()
	benchmark = "--bench" in args
	var initial = "Intro Scene"
	for i in range(args.size() - 1):
		if args[i] == "--level": initial = args[i + 1]
		if args[i] == "--light-scale": light_scale = float(args[i + 1])
	load_level_now(initial)
	if benchmark:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		benchmark_runner = Node.new()
		benchmark_runner.set_script(Benchmark)
		benchmark_runner.game = self
		add_child(benchmark_runner)
	if "--smoke-test" in args:
		call_deferred("smoke_test")

func load_level_now(scene_name: String):
	get_tree().paused = false
	paused = false
	finished = false
	has_key = false
	has_checkpoint = false
	coins = 0
	gems = 0
	coin_total = 0
	gem_total = 0
	shown_lives = -1
	touch_move = Vector2.ZERO
	touch_jump = false
	if world:
		stop_audio(world)
		world.free()
	stop_audio(ui_root)
	for child in ui_root.get_children(): child.free()
	world_scopes.clear()
	builder.scopes.clear()
	sounds.clear()
	pickups.clear()
	portal_entries.clear()
	hud = {}
	overlay = {}
	menus.clear()
	player = null
	camera = null
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world_scope = builder.build_scene(scene_name, world)
	world_scopes.append(world_scope)
	if scene_name.begins_with("Level "):
		level_name = scene_name
		for entry in world_scope.scripts:
			if entry["class"] == "LevelController":
				level_title = str(entry.properties.get("levelTitle", scene_name))
				next_level = str(entry.properties.get("nextScene", ""))
				completion_bonus = int(entry.properties.get("completionBonus", 100))
				var spawn_node: Node3D = world_scope.ids.get(int(entry.properties.get("spawnPoint", 0)))
				spawn = spawn_node.global_position if spawn_node else player.global_position
		if player: player.respawn(spawn)
		hud = builder.build_scene("HUD Scene", ui_root)
		for menu_name in ["Pause Scene", "Game Over Scene", "Win Scene"]:
			menus[menu_name] = builder.build_scene(menu_name, ui_root)
			menus[menu_name].root.visible = false
		banner_timer = 3.0
		show_banner()
		initialize_entities()
		play_sound("Music")
		update_hud()
		set_touch_visible(touch_shown)
	else:
		level_name = ""
		overlay = builder.build_scene("Title Menu", ui_root)
		prepare_menu(overlay)
	menu_arm_timer = 0

func initialize_entities():
	for scope in world_scopes:
		for entry in scope.scripts:
			match entry["class"]:
				"Collectible":
					pickups.append(entry)
					if entry.properties.get("kind", "coin") == "coin": coin_total += 1
					if entry.properties.get("kind", "coin") == "gem": gem_total += 1
				"ExitPortal": portal_entries.append(entry)

func _process(dt: float):
	menu_arm_timer += dt
	if not paused and not loading and not hud.is_empty():
		banner_timer -= dt
		var banner: Control = hud.names.get("Banner")
		if banner: banner.modulate.a = clampf(minf(3.0 - banner_timer, banner_timer) / 0.4, 0, 1)
		message_timer -= dt
		var message: Control = hud.names.get("Message")
		if message:
			message.visible = message_timer > 0
			message.modulate.a = clampf(message_timer / 0.4, 0, 1)
		for entry in portal_entries:
			if not entry.node.get_meta("opened", false) and has_key:
				entry.node.set_meta("opened", true)
				play_sound("Portal Sound")
				show_message("The portal is open!")
				var lock = entry.scope.ids.get(int(entry.properties.get("lock", 0)))
				if lock: lock.visible = false
				var star: Node = entry.scope.ids.get(163)
				if star: set_mesh_tint(star, Color.WHITE)
				SceneBuilder.start_action(entry.scope, int(entry.properties.get("openAnimation", 0)))
				var spin = entry.scope.actions.get(int(entry.properties.get("starSpin", 0)))
				if spin is AnimationPlayer: spin.speed_scale = float(entry.properties.get("openSpinSpeed", 4))
			if has_key and not finished and player in entry.node.get_overlapping_bodies():
				finish_level(true)
		update_hud()
		update_touch()

func on_sensor(body: Node3D, sensor: Area3D):
	if body != player or player.dead or paused or finished or loading:
		return
	var entry: Dictionary = sensor.get_meta("behavior", {})
	var p: Dictionary = entry.get("properties", {})
	match str(entry.get("class", "")):
		"Collectible":
			if sensor.get_meta("collected", false): return
			sensor.set_meta("collected", true)
			sensor.visible = false
			sensor.set_deferred("monitoring", false)
			match str(p.get("kind", "coin")):
				"key":
					has_key = true
					play_sound("Key Sound")
				"gem":
					gems += 1
					score += int(p.get("scoreValue", 100))
					play_sound("Gem Sound")
				_:
					coins += 1
					score += int(p.get("scoreValue", 10))
					play_sound("Coin Sound")
		"Checkpoint":
			if sensor.get_meta("reached", false): return
			sensor.set_meta("reached", true)
			has_checkpoint = true
			checkpoint = sensor.global_position + Vector3(0, 0.3, 0)
			show_message("Checkpoint!")
			play_sound("Checkpoint Sound")
			SceneBuilder.start_action(entry.scope, int(p.get("reachAnimation", 0)))
			set_mesh_tint(sensor, Color.WHITE)
		"ExitPortal":
			if has_key:
				finish_level(true)
			elif float(sensor.get_meta("locked_until", 0.0)) < Time.get_ticks_msec() / 1000.0:
				sensor.set_meta("locked_until", Time.get_ticks_msec() / 1000.0 + 2.0)
				play_sound("Locked Sound")
				show_message("Find the key first!")
		"Hazard": player.hurt()
		"Enemy":
			if sensor.get_meta("squashed", false): return
			if player.linear_velocity.y < 0 and player.global_position.y > sensor.global_position.y + float(p.get("stompHeight", 0.35)):
				sensor.set_meta("squashed", true)
				for action in entry.scope.actions.values():
					if action is AnimationPlayer: action.stop(true)
				var visual: Node3D = entry.scope.names.get("Visual")
				if visual: visual.scale *= Vector3(1.3, 0.3, 1.3)
				player.stomp_pending = true
				score += int(p.get("scoreValue", 50))
				play_sound("Squash Sound")
				get_tree().create_timer(0.5, false).timeout.connect(func(): if is_instance_valid(sensor): sensor.visible = false)
			else:
				player.hurt()

func finish_level(won: bool):
	if finished: return
	finished = true
	if won: score += completion_bonus
	var delay: float = (1.0 if next_level == "" else 0.8) if won else 1.6
	var music: AudioStreamPlayer = sounds.get("Music")
	if music: create_tween().tween_property(music, "volume_db", -60.0, delay)
	await get_tree().create_timer(delay, false).timeout
	if won and next_level != "":
		level_start_score = score
		change_level(next_level)
	else:
		record_score()
		show_overlay("Win Scene" if won else "Game Over Scene")

func show_overlay(scene_name: String):
	if not overlay.is_empty(): overlay.root.visible = false
	overlay = menus.get(scene_name, {})
	if overlay.is_empty(): overlay = builder.build_scene(scene_name, ui_root)
	overlay.root.visible = true
	set_paused(true)
	prepare_menu(overlay)
	menu_arm_timer = 0

func prepare_menu(scope: Dictionary):
	for entry in scope.scripts:
		if entry["class"] != "MenuController": continue
		var p: Dictionary = entry.properties
		var score_text = scope.ids.get(int(p.get("scoreText", 0)))
		var best_text = scope.ids.get(int(p.get("bestText", 0)))
		if score_text: score_text.text = str(score)
		if best_text: best_text.text = "Best " + str(best_score)
		if str(p.get("jingle", "")) != "": play_sound(str(p.jingle))
		if touch_shown:
			var help_text = scope.ids.get(int(p.get("helpText", 0)))
			if help_text and p.get("touchHelp", "") != "": help_text.text = str(p.touchHelp)
	var credits = scope.names.get("Credits Text")
	if credits: credits.text = "Made with Godot Engine"

func set_paused(value: bool):
	paused = value
	get_tree().paused = value
	var music: AudioStreamPlayer = sounds.get("Music")
	if music: music.stream_paused = value

func menu_action(action: String, target: String = "Level One"):
	if loading: return
	play_sound("Click Sound")
	match action:
		"play":
			score = 0
			level_start_score = 0
			lives = 3
			change_level(target)
		"retry":
			lives = 3
			score = level_start_score
			change_level(level_name if level_name != "" else target)
		"menu": change_level("Intro Scene")
		"resume":
			if not overlay.is_empty(): overlay.root.visible = false
			overlay = {}
			set_paused(false)
		"quit": get_tree().quit()

func change_level(scene_name: String):
	if loading: return
	loading = true
	get_tree().paused = false
	loading_scope = builder.build_scene("Loading Scene", ui_root)
	var title = loading_scope.names.get("Title Text")
	if title: title.text = scene_name if scene_name.begins_with("Level ") else ""
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	load_level_now(scene_name)
	loading = false

func _unhandled_input(event: InputEvent):
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		touch_shown = true
		set_touch_visible(true)
		if event is InputEventScreenTouch:
			if event.pressed: touch_points[event.index] = event.position
			else:
				touch_points.erase(event.index)
				touch_previous.erase(event.index)
				if stick_finger == event.index: stick_finger = -1
				if look_finger == event.index: look_finger = -1
		else:
			touch_points[event.index] = event.position
		return
	if event is InputEventKey and event.pressed:
		touch_shown = false
		set_touch_visible(false)
	if event is InputEventMouseMotion and player and not paused and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		player.look_by(event.relative)
	var confirm = false
	var escape = false
	var pause_pressed = false
	if event is InputEventKey and event.pressed and not event.echo:
		confirm = event.physical_keycode in [KEY_ENTER, KEY_SPACE]
		escape = event.physical_keycode == KEY_ESCAPE
		pause_pressed = event.physical_keycode in [KEY_ESCAPE, KEY_P]
	if event is InputEventJoypadButton and event.pressed:
		confirm = event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START]
		escape = event.button_index == JOY_BUTTON_B
		pause_pressed = event.button_index == JOY_BUTTON_START
	if loading: return
	if not overlay.is_empty() and menu_arm_timer > 0.3:
		for entry in overlay.scripts:
			if entry["class"] != "MenuController": continue
			var p: Dictionary = entry.properties
			if confirm: menu_action(str(p.get("primaryAction", "")), str(p.get("primaryScene", "Level One")))
			elif escape: menu_action(str(p.get("escapeAction", "")), str(p.get("escapeScene", "Intro Scene")))
	elif pause_pressed and level_name != "" and not finished:
		show_overlay("Pause Scene")

func update_touch():
	if not touch_shown or paused or hud.is_empty():
		touch_move = Vector2.ZERO
		touch_jump = false
		return
	var stick: Control = hud.names.get("Touch Stick")
	var jump: Control = hud.names.get("Touch Jump")
	var pause_button: Control = hud.names.get("Touch Pause")
	var center = stick.global_position + stick.size / 2
	var ratio = get_viewport().get_visible_rect().size / Vector2(1280, 720)
	var radius = stick.size.x * 0.4
	var movement = Vector2.ZERO
	touch_jump = false
	for id in touch_points:
		var point: Vector2 = touch_points[id] / ratio
		if id == stick_finger or (stick_finger < 0 and point.distance_to(center) <= stick.size.x * 0.6):
			stick_finger = int(id)
			movement = (point - center).limit_length(radius)
		elif Rect2(jump.global_position, jump.size).grow(12).has_point(point):
			touch_jump = true
		elif Rect2(pause_button.global_position, pause_button.size).grow(12).has_point(point):
			show_overlay("Pause Scene")
		elif player:
			if id == look_finger and touch_previous.has(id): player.look_by(point - touch_previous[id])
			elif look_finger < 0: look_finger = int(id)
		touch_previous[id] = point
	touch_move = Vector2(movement.x, -movement.y) / radius
	var knob: Control = hud.names.get("Stick Knob")
	if knob: knob.position = Vector2(60, 60) + movement

func set_touch_visible(value: bool):
	if hud.is_empty(): return
	for key in ["Touch Stick", "Touch Jump", "Touch Pause"]:
		var control = hud.names.get(key)
		if control: control.visible = value

func show_banner():
	var label: Label = hud.names.get("Banner Text")
	if label:
		label.text = level_title
		label.position.x = (460.0 - label.get_minimum_size().x) / 2.0
	var banner: Control = hud.names.get("Banner")
	if banner: banner.visible = true

func show_message(text: String):
	if hud.is_empty(): return
	var label: Label = hud.names.get("Message Text")
	if label:
		label.text = text
		label.position.x = (440.0 - label.get_minimum_size().x) / 2.0
	message_timer = 2.5

func update_hud():
	if hud.is_empty(): return
	if shown_lives != lives:
		for i in range(1, 4):
			var heart = hud.names.get("Heart " + str(i))
			if heart: heart.texture = load("res://assets/ui/heart.png" if i <= lives else "res://assets/ui/heart_empty.png")
		shown_lives = lives
	for pair in [["Coin Text", str(coins) + "/" + str(coin_total)], ["Gem Text", str(gems) + "/" + str(gem_total)], ["Score Text", str(score)]]:
		var label = hud.names.get(pair[0])
		if label and label.text != pair[1]: label.text = pair[1]
	var key = hud.names.get("Key Icon")
	if key: key.modulate.a = 1.0 if has_key else 0.3

func play_sound(name_of_sound: String):
	var sound: AudioStreamPlayer = sounds.get(name_of_sound)
	if sound and is_instance_valid(sound):
		sound.stop()
		sound.play()

func stop_audio(root: Node):
	if root is AudioStreamPlayer:
		root.stop()
		root.stream = null
	for child in root.get_children(): stop_audio(child)

func _exit_tree():
	stop_audio(self)

func record_score():
	if "--smoke-test" in OS.get_cmdline_user_args(): return
	if score <= best_score: return
	best_score = score
	var save = ConfigFile.new()
	save.set_value("score", "best", best_score)
	save.save("user://lostslime.cfg")

func emit_dust(at: Vector3):
	if not dust_mesh:
		var packed: PackedScene = load("res://assets/models/dust.glb")
		if not packed: return
		var model = packed.instantiate()
		var meshes = model.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty(): dust_mesh = meshes[0].mesh
		model.free()
	if not dust_mesh: return
	var dust = CPUParticles3D.new()
	dust.mesh = dust_mesh
	dust.amount = 10
	dust.lifetime = 0.5
	dust.one_shot = true
	dust.explosiveness = 1
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.25, 0.05, 0.25)
	dust.direction = Vector3.UP
	dust.spread = 80
	dust.initial_velocity_min = 0.8
	dust.initial_velocity_max = 1.8
	dust.gravity = Vector3.ZERO
	dust.scale_amount_min = 0.32
	dust.scale_amount_max = 0.32
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	dust.scale_amount_curve = curve
	world.add_child(dust)
	dust.global_position = at + Vector3(0, 0.1, 0)
	dust.emitting = true
	get_tree().create_timer(0.6, false).timeout.connect(dust.queue_free)

func set_mesh_tint(node: Node, tint: Color):
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var original = node.get_active_material(i)
			if original is StandardMaterial3D:
				var material = original.duplicate()
				material.albedo_color = tint
				node.set_surface_override_material(i, material)
	for child in node.get_children(): set_mesh_tint(child, tint)

func smoke_test():
	# Exercise the real gameplay entry points and physics scenes, without saving a score.
	for scene_name in ["Level One", "Level Two"]:
		lives = 3
		load_level_now(scene_name)
		await get_tree().create_timer(0.4).timeout
		assert(player != null and camera != null and not pickups.is_empty())
		var movement_start = player.global_position
		var key_event = InputEventKey.new()
		key_event.physical_keycode = KEY_D
		key_event.pressed = true
		Input.parse_input_event(key_event.duplicate())
		await get_tree().create_timer(0.2).timeout
		key_event.pressed = false
		Input.parse_input_event(key_event.duplicate())
		assert(player.global_position.distance_to(movement_start) > 0.15)
		var jump_start = player.global_position.y
		key_event.physical_keycode = KEY_SPACE
		key_event.pressed = true
		Input.parse_input_event(key_event.duplicate())
		await get_tree().create_timer(0.12).timeout
		key_event.pressed = false
		Input.parse_input_event(key_event.duplicate())
		assert(player.global_position.y > jump_start + 0.2)
		assert(coin_total == (16 if scene_name == "Level One" else 11))
		assert(gem_total == 2)
		var initial_score = score
		var coin = pickups.filter(func(e): return e.properties.get("kind", "coin") == "coin")[0]
		on_sensor(player, coin.node)
		assert(coins == 1 and score == initial_score + 10)
		on_sensor(player, coin.node)
		assert(coins == 1)
		var key = pickups.filter(func(e): return e.properties.get("kind", "coin") == "key")[0]
		on_sensor(player, key.node)
		assert(has_key)
		for scope in world_scopes:
			for entry in scope.scripts:
				if entry["class"] == "Checkpoint":
					on_sensor(player, entry.node)
					assert(has_checkpoint and checkpoint.y > 0)
		player.hurt_timer = 0
		var before_lives = lives
		player.hurt()
		assert(lives == before_lives - 1)
		show_overlay("Pause Scene")
		assert(paused)
		menu_action("resume")
		assert(not paused)
		await get_tree().create_timer(0.2).timeout
		assert(player.global_position.distance_to(checkpoint) < 0.65, str(player.global_position) + " != checkpoint " + str(checkpoint))
		print("SMOKE PASS: ", scene_name, " movement, jump, pickups, key, checkpoints, hurt/respawn, pause/resume")
	for menu in ["Game Over Scene", "Win Scene"]:
		show_overlay(menu)
		await get_tree().process_frame
		assert(not overlay.is_empty())
		menu_action("resume")
	print("SMOKE PASS: result screens")
	lives = 3
	load_level_now("Level One")
	await get_tree().create_timer(0.1).timeout
	var first_key = pickups.filter(func(e): return e.properties.get("kind", "coin") == "key")[0]
	on_sensor(player, first_key.node)
	on_sensor(player, portal_entries[0].node)
	assert(finished)
	await get_tree().create_timer(1.6).timeout
	assert(level_name == "Level Two" and not loading)
	var second_key = pickups.filter(func(e): return e.properties.get("kind", "coin") == "key")[0]
	on_sensor(player, second_key.node)
	on_sensor(player, portal_entries[0].node)
	await get_tree().create_timer(1.3).timeout
	assert(paused and overlay.root.name == "Win Scene")
	menu_action("resume")
	print("SMOKE PASS: loading, Level One -> Level Two -> victory")
	stop_audio(self)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
