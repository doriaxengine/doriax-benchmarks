extends Node
# Mirrors doriax/main.cpp. Only the camera moves, on the same path in both engines.

var world: Dictionary
var scene_name: String
var camera2d: Camera2D
var camera3d: Camera3D
var objects := 0
var warmup: float
var duration: float
var freeze_at := -1.0
var ready_usec := 0
var previous_usec := 0
var measure_usec := 0
var finished := false
var captured := false
var frame_ms: Array[float] = []
var draws: Array[int] = []
var primitives: Array[int] = []

func env_value(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback

func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _ready() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/scenes.json"))
	scene_name = env_value("BENCH_SCENE", "crowd")
	assert(spec.has(scene_name), "Unknown scene: " + scene_name)
	world = spec[scene_name]
	warmup = float(env_value("BENCH_WARMUP", "3"))
	duration = float(env_value("BENCH_DURATION", "20"))
	if env_value("BENCH_FREEZE_AT", "") != "":
		freeze_at = float(env_value("BENCH_FREEZE_AT", ""))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var bg: Array = world.background
	RenderingServer.set_default_clear_color(Color(bg[0], bg[1], bg[2], 1))
	if scene_name == "crowd":
		build_crowd()
	else:
		build_island()
	place_camera(0)
	ready_usec = Time.get_ticks_usec()
	print("BENCH_READY ", RenderingServer.get_video_adapter_name())

func build_crowd() -> void:
	camera2d = Camera2D.new()
	camera2d.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(camera2d)
	camera2d.make_current()
	var atlas := load("res://shared/" + world.atlas) as Texture2D
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	var frames: Array = world.frames
	for s in world.sprites:
		var sprite := Sprite2D.new()
		sprite.texture = atlas
		sprite.material = material
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.region_enabled = true
		var f: Array = frames[int(s[3])]
		sprite.region_rect = Rect2(f[0], f[1], f[2], f[3])
		sprite.scale = Vector2.ONE * float(s[2]) / float(f[2])
		sprite.position = Vector2(s[0], s[1])
		add_child(sprite)
		objects += 1

func build_island() -> void:
	var c: Dictionary = world.camera
	camera3d = Camera3D.new()
	camera3d.fov = c.yfov
	camera3d.near = c.near
	camera3d.far = c.far
	add_child(camera3d)
	camera3d.make_current()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	var bg: Array = world.background
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(bg[0], bg[1], bg[2], 1)
	var a: Dictionary = world.ambient
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(a.color[0], a.color[1], a.color[2])
	environment.environment.ambient_light_energy = a.intensity
	environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(environment)
	var l: Dictionary = world.light
	var light := DirectionalLight3D.new()
	add_child(light)
	var direction := v3(l.direction).normalized()
	light.look_at_from_position(Vector3.ZERO, direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	light.light_color = Color(l.color[0], l.color[1], l.color[2])
	# Godot's light energy is Doriax's intensity / pi (the Lost Slime 3D port uses --light-scale 0.32 too)
	light.light_energy = l.intensity / PI
	light.shadow_enabled = false
	var scenes := {}
	for m in world.models:
		if not scenes.has(m[0]):
			scenes[m[0]] = load("res://shared/%s.glb" % m[0]) as PackedScene
		var node := (scenes[m[0]] as PackedScene).instantiate() as Node3D
		for child in node.find_children("*", "GeometryInstance3D"):
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.position = Vector3(m[1], m[2], m[3])
		node.quaternion = Quaternion(Vector3.UP, deg_to_rad(m[4]))
		node.scale = Vector3.ONE * float(m[5])
		objects += 1

func place_camera(t: float) -> void:
	if freeze_at >= 0: t = freeze_at
	var c: Dictionary = world.camera
	if scene_name == "crowd":
		var w := TAU * t / float(c.period)
		camera2d.position = Vector2(c.center[0] + c.amplitude[0] * sin(c.freq[0] * w),
			c.center[1] + c.amplitude[1] * sin(c.freq[1] * w))
	else:
		var a := deg_to_rad(float(c.start_deg) + float(c.deg_per_s) * t)
		camera3d.position = Vector3(c.radius * cos(a), c.height, c.radius * sin(a))
		camera3d.look_at(v3(c.target), Vector3.UP)

func _process(_delta: float) -> void:
	if finished: return
	var now := Time.get_ticks_usec()
	var elapsed := (now - ready_usec) / 1000000.0
	if elapsed < warmup:
		if env_value("BENCH_CAPTURE", "0") == "1" and elapsed > warmup / 2 and not captured:
			captured = true
			print("BENCH_CAPTURE_WINDOW ", DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE))
		place_camera(0)
		return
	if measure_usec == 0:
		measure_usec = now
		previous_usec = now
		place_camera(0)
		print("BENCH_MEASURE_BEGIN %.6f" % Time.get_unix_time_from_system())
		return
	frame_ms.append((now - previous_usec) / 1000.0)
	previous_usec = now
	draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	primitives.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var measured := (now - measure_usec) / 1000000.0
	if measured < duration:
		place_camera(measured)
		return
	finished = true
	print("BENCH_MEASURE_END")
	var report := {"engine": "Godot", "version": Engine.get_version_info(), "scene": scene_name, "objects": objects,
		"resolution": [get_viewport().size.x, get_viewport().size.y], "gpu": RenderingServer.get_video_adapter_name(),
		"warmup_seconds": warmup, "duration_seconds": measured, "frames": frame_ms.size(), "frame_ms": frame_ms,
		"draw_calls": draws, "primitives": primitives, "debug_build": OS.is_debug_build(),
		"renderer": RenderingServer.get_current_rendering_method()}
	var file := FileAccess.open(env_value("BENCH_OUTPUT", "user://scenes.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
