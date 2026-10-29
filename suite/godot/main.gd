extends Node
# Mirrors doriax/main.cpp. Motion time is measured separately.

var spec: Dictionary
var workload: Dictionary
var objects: Array[Node] = []
var bases: Array[Vector3] = []
var phases: Array[float] = []
var base_rotation: Quaternion
var multimesh: MultiMesh
var warmup: float
var duration: float
var freeze := false
var ready_usec := 0
var previous_usec := 0
var measure_usec := 0
var finished := false
var captured := false
var script_accum := 0.0
var frame_ms: Array[float] = []
var script_ms: Array[float] = []
var draws: Array[int] = []
var primitives: Array[int] = []

func env_value(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback

func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _ready() -> void:
	spec = JSON.parse_string(FileAccess.get_file_as_string("res://shared/workloads.json"))
	var selected := env_value("BENCH_CASE", "sprites_static_3000")
	for item in spec.cases:
		if item.id == selected: workload = item
	assert(not workload.is_empty(), "Unknown case: " + selected)
	warmup = float(env_value("BENCH_WARMUP", "3"))
	duration = float(env_value("BENCH_DURATION", "8"))
	freeze = env_value("BENCH_FREEZE", "0") == "1"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.set_default_clear_color(Color(spec.background[0], spec.background[1], spec.background[2], 1))
	var q: Array = spec.cube_rotation
	base_rotation = Quaternion(q[0], q[1], q[2], q[3])
	var count := int(workload.count)
	if workload.kind == "sprites":
		var textures: Array[Texture2D] = []
		for i in range(int(workload.textures)):
			textures.append(load("res://shared/sprite%d.png" % i) as Texture2D)
		var sprite_material := CanvasItemMaterial.new()
		sprite_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		sprite_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
		for i in range(count):
			var sprite := Sprite2D.new()
			sprite.texture = textures[i % textures.size()]
			sprite.material = sprite_material
			sprite.centered = true
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			var p: Array = spec.sprites[i]
			bases.append(Vector3(p[0], p[1], 0))
			phases.append(p[2])
			sprite.position = Vector2(p[0], p[1])
			add_child(sprite)
			objects.append(sprite)
	else:
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = spec.camera.ortho_height
		camera.near = spec.camera.near
		camera.far = spec.camera.far
		add_child(camera)
		camera.position = v3(spec.camera.position)
		camera.look_at(v3(spec.camera.target))
		camera.make_current()
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(spec.background[0], spec.background[1], spec.background[2], 1)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
		environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		add_child(environment)
		if workload.lit:
			var light := DirectionalLight3D.new()
			add_child(light)
			var direction := v3(spec.light.direction).normalized()
			light.look_at_from_position(Vector3.ZERO, direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
			light.light_color = Color(spec.light.color[0], spec.light.color[1], spec.light.color[2])
			# Doriax divides intensity by pi, Godot multiplies directional energy by pi
			light.light_energy = spec.light.energy / PI
			light.shadow_enabled = false
		var mesh: Mesh
		var model: PackedScene
		if workload.kind == "models":
			model = load("res://shared/key.glb") as PackedScene
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE * float(spec.cube_size)
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if workload.lit else BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color(spec.cube_color[0], spec.cube_color[1], spec.cube_color[2], 1)
			material.metallic = 0.0
			material.roughness = 1.0
			box.material = material
			mesh = box
		if workload.instanced:
			multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = mesh
			multimesh.instance_count = count
			for i in range(count):
				multimesh.set_instance_transform(i, Transform3D(Basis(base_rotation), v3(spec.cubes[i])))
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = multimesh
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
		else:
			for i in range(count):
				var node: Node3D
				if model:
					node = model.instantiate()
					node.scale = Vector3.ONE * float(spec.model_scale)
					for child in node.find_children("*", "GeometryInstance3D"):
						child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				else:
					var cube := MeshInstance3D.new()
					cube.mesh = mesh
					cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					node = cube
				var p: Array = spec.cubes[i]
				add_child(node)
				node.position = Vector3(p[0], p[1], p[2])
				node.quaternion = base_rotation
				bases.append(node.position)
				phases.append(p[3])
				objects.append(node)
	move_objects(0)
	ready_usec = Time.get_ticks_usec()
	print("BENCH_READY ", RenderingServer.get_video_adapter_name())

func move_objects(t: float) -> void:
	if not workload.moving: return
	var start := Time.get_ticks_usec()
	var speed := float(spec.motion.angular_speed)
	if workload.kind == "sprites":
		var ax := float(spec.motion.x_amplitude)
		var ay := float(spec.motion.y_amplitude)
		for i in range(objects.size()):
			var sprite := objects[i] as Sprite2D
			sprite.position = Vector2(bases[i].x + ax * sin(speed * t + phases[i]), bases[i].y + ay * cos(speed * t + phases[i]))
	else:
		for i in range(objects.size()):
			var angle := speed * t + phases[i]
			(objects[i] as Node3D).quaternion = base_rotation * Quaternion(0, sin(angle * 0.5), 0, cos(angle * 0.5))
	script_accum += (Time.get_ticks_usec() - start) / 1000.0

func positions() -> Array:
	var result := []
	for object in objects:
		var p: Vector3
		if workload.kind == "sprites":
			p = Vector3(object.position.x, object.position.y, 0)
		else:
			p = object.position
		result.append([p.x, p.y, p.z])
	return result

func rotations() -> Array:
	var result := []
	if workload.kind == "sprites" or objects.is_empty(): return result
	for i in [0, objects.size() / 2, objects.size() - 1]:
		var q: Quaternion = objects[i].quaternion
		result.append([q.x, q.y, q.z, q.w])
	return result

func resources() -> Dictionary:
	var result := {"debug_build": OS.is_debug_build(), "objects": objects.size(),
		"msaa": get_viewport().msaa_3d, "renderer": RenderingServer.get_current_rendering_method()}
	if workload.kind == "sprites":
		var textures := {}
		for object in objects:
			textures[object.texture.get_rid().get_id()] = true
		result["textures"] = textures.size()
	return result

func _process(_delta: float) -> void:
	if finished: return
	var now := Time.get_ticks_usec()
	var elapsed := (now - ready_usec) / 1000000.0
	if elapsed < warmup:
		if env_value("BENCH_CAPTURE", "0") == "1" and elapsed > warmup / 2 and not captured:
			captured = true
			print("BENCH_CAPTURE_WINDOW ", DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE))
		move_objects(0 if freeze else elapsed)
		return
	if measure_usec == 0:
		measure_usec = now
		previous_usec = now
		script_accum = 0
		move_objects(0)
		print("BENCH_MEASURE_BEGIN")
		return
	frame_ms.append((now - previous_usec) / 1000.0)
	script_ms.append(script_accum)
	script_accum = 0
	previous_usec = now
	draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	primitives.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var measured := (now - measure_usec) / 1000000.0
	if measured < duration:
		move_objects(0 if freeze else measured)
		return
	finished = true
	print("BENCH_MEASURE_END")
	var count := multimesh.instance_count if multimesh else objects.size()
	var report := {"engine": "Godot", "version": Engine.get_version_info(), "case": workload.id, "count": count,
		"resolution": [get_viewport().size.x, get_viewport().size.y], "gpu": RenderingServer.get_video_adapter_name(),
		"warmup_seconds": warmup, "duration_seconds": measured, "frames": frame_ms.size(), "frame_ms": frame_ms,
		"script_ms": script_ms, "draw_calls": draws, "primitives": primitives}
	move_objects(0)
	report.positions_t0 = positions()
	report.rotations_t0 = rotations()
	move_objects(1)
	report.positions_t1 = positions()
	report.rotations_t1 = rotations()
	report.resources = resources()
	var file := FileAccess.open(env_value("BENCH_OUTPUT", "user://bench.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
