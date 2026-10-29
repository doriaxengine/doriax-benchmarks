extends Node

var game: Node
var warmup = 5.0
var duration = 20.0
var output = "user://benchmark.json"
var screenshot = ""
var trace: Array = []
var started_usec = 0
var previous_usec = 0
var measured_start = 0
var frame_ms: Array = []
var draws: Array = []
var primitives: Array = []
var gpu_ms: Array = []
var renderer_cpu_ms: Array = []
var finished = false
var captured = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--duration": duration = float(args[i + 1])
			"--warmup": warmup = float(args[i + 1])
			"--output": output = args[i + 1]
			"--screenshot": screenshot = args[i + 1]
	var routes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://benchmark/routes.json"))
	trace = routes[game.level_name]
	started_usec = Time.get_ticks_usec()
	previous_usec = started_usec
	print("BENCH_READY ", OS.get_process_id(), " ", RenderingServer.get_video_adapter_name(), " ", game.level_name)

func _process(_delta: float):
	if finished or not game.camera: return
	var now = Time.get_ticks_usec()
	var elapsed = (now - started_usec) / 1000000.0
	var progress = clampf((elapsed - warmup) / duration, 0, 1) if elapsed >= warmup else clampf(elapsed / warmup, 0, 1)
	set_camera(progress)
	if elapsed < warmup:
		if screenshot != "" and not captured and progress > 0.5:
			captured = true
			capture.call_deferred()
		previous_usec = now
		return
	if measured_start == 0:
		measured_start = now
		previous_usec = now
		print("BENCH_MEASURE_BEGIN")
		return
	frame_ms.append((now - previous_usec) / 1000.0)
	previous_usec = now
	draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	primitives.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if elapsed >= warmup + duration:
		finished = true
		var report = {"engine": "Godot", "version": Engine.get_version_info(), "scene": game.level_name,
			"directional_light_energy_scale": game.light_scale,
			"renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(),
			"resolution": [1280, 720], "warmup_seconds": warmup, "duration_seconds": (now - measured_start) / 1000000.0,
			"frames": frame_ms.size(), "frame_ms": frame_ms, "draw_calls": draws, "primitives": primitives,
			"gpu_render_ms": gpu_ms, "renderer_cpu_ms": renderer_cpu_ms,
			"render_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)}
		var file = FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report))
		print("BENCH_MEASURE_END ", frame_ms.size(), " frames")
		game.stop_audio(game)
		await get_tree().create_timer(0.2).timeout
		get_tree().quit()

func set_camera(progress: float):
	var segment = progress * (trace.size() - 1)
	var index = mini(int(segment), trace.size() - 2)
	var focus = game.builder.v3(trace[index]).lerp(game.builder.v3(trace[index + 1]), segment - index)
	var yaw = deg_to_rad(-90 + 25 * sin(progress * TAU))
	var pitch = deg_to_rad(-22)
	var rotation_value = Basis.from_euler(Vector3(pitch, yaw, 0), EULER_ORDER_YXZ)
	var target = focus + Vector3(0, 1, 0)
	game.camera.global_position = target + rotation_value.z * 9
	game.camera.look_at(target, Vector3.UP)

func capture():
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(screenshot)
