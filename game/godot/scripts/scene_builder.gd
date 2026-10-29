extends RefCounted

const Player = preload("res://scripts/player.gd")
var game: Node
var source: Dictionary
var material_cache: Dictionary = {}
var model_cache: Dictionary = {}
var scopes: Array = []

func _init(owner_game: Node, data: Dictionary):
	game = owner_game
	source = data

static func v3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func quat(value: Array) -> Quaternion:
	return Quaternion(float(value[1]), float(value[2]), float(value[3]), float(value[0])).normalized()

static func color(value: Array, srgb: bool = false) -> Color:
	var result = Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)
	return result.linear_to_srgb() if srgb else result

func build_scene(scene_name: String, parent: Node) -> Dictionary:
	var data: Dictionary = source.scenes[scene_name]
	var ui: bool = data.get("sceneType", "") == "scene_ui"
	# UI scenes in the source use scene_2d as well as scene_ui.
	ui = ui or scene_name in ["Title Menu", "HUD Scene", "Pause Scene", "Win Scene", "Game Over Scene", "Loading Scene"]
	var scope = build_scope(data.get("entities", []), parent, scene_name, ui)
	if not ui:
		setup_environment(data, scope)
	return scope

func build_scope(entities: Array, parent: Node, scope_name: String, ui: bool) -> Dictionary:
	var root: Node = Control.new() if ui else Node3D.new()
	root.name = scope_name
	if ui:
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var scope = {"root": root, "ids": {}, "names": {}, "scripts": [], "actions": {}, "entities": entities, "ui": ui}
	scopes.append(scope)
	for entity in entities:
		build_entity(entity, root, scope)
	build_animations(scope)
	return scope

func build_entity(entity: Dictionary, parent: Node, scope: Dictionary):
	var c: Dictionary = entity.get("components", {})
	if c.has("bone") or c.has("action") or c.has("sky") or c.has("fog"):
		return
	var node: Node
	var script_entries: Array = c.get("script", {}).get("scripts", [])
	var player: bool = script_entries.any(func(s): return s.get("className", "") == "PlayerController")
	if c.has("sound"):
		node = AudioStreamPlayer.new()
	elif scope.ui:
		node = make_control(c)
	elif player:
		node = RigidBody3D.new()
		node.set_script(Player)
		node.game = game
		node.parameters = properties(script_entries[0])
		game.player = node
	elif c.has("body3d"):
		var body: Dictionary = c.body3d
		if body.get("sensor", false):
			node = Area3D.new()
			node.collision_layer = 2
			node.collision_mask = 4
		elif body.get("type", "static") == "kinematic":
			node = AnimatableBody3D.new()
			node.sync_to_physics = true
		else:
			node = StaticBody3D.new()
	elif c.has("camera"):
		node = Camera3D.new()
	elif c.has("light"):
		node = DirectionalLight3D.new()
	elif c.has("sound"):
		node = AudioStreamPlayer.new()
	else:
		node = Node3D.new()
	node.name = str(entity.get("name", "Entity")).replace("/", "_")
	parent.add_child(node)
	scope.ids[int(entity.get("entity", 0))] = node
	scope.names[node.name] = node
	node.set_meta("source_id", int(entity.get("entity", 0)))
	var t: Dictionary = c.get("transform", {})
	if node is Node3D:
		node.position = v3(t.get("position", [0, 0, 0]))
		node.quaternion = quat(t.get("rotation", [1, 0, 0, 0]))
		node.scale = v3(t.get("scale", [1, 1, 1]))
		node.visible = t.get("visible", true)
	if node is Control:
		var p: Array = t.get("position", [0, 0, 0])
		node.position = Vector2(float(p[0]), float(p[1]))
		var layout: Dictionary = c.get("uilayout", {})
		node.size = Vector2(float(layout.get("width", 0)), float(layout.get("height", 0)))
		node.visible = t.get("visible", true)
		node.pivot_offset = node.size * 0.5
	if c.has("model") and not c.has("instancedmesh"):
		var model_path: String = "res://assets/" + c.model.filename
		if not model_cache.has(model_path):
			model_cache[model_path] = load(model_path)
		var packed: PackedScene = model_cache[model_path]
		if packed:
			var model: Node3D = packed.instantiate()
			model.name = "Model"
			node.add_child(model)
			configure_meshes(model, c.get("mesh", {}))
			var animation = find_animation_player(model)
			if animation:
				node.set_meta("model_animation", animation)
				play_model(node, "idle", true)
	if c.has("body3d"):
		add_shapes(node, c.body3d)
		if node is RigidBody3D:
			node.collision_layer = 4
			node.collision_mask = 1
			node.lock_rotation = true
			node.can_sleep = false
			node.contact_monitor = true
			node.max_contacts_reported = 16
			node.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
			node.linear_damp = 0.0
			var physics_material = PhysicsMaterial.new()
			physics_material.friction = 0.0
			node.physics_material_override = physics_material
	if node is Camera3D:
		var camera: Dictionary = c.camera
		node.fov = rad_to_deg(float(camera.get("yfov", 0.8)))
		node.near = float(camera.get("nearClip", 0.2))
		node.far = float(camera.get("farClip", 400.0))
		node.look_at(v3(camera.get("target", [0, 0, 0])), Vector3.UP)
		node.current = true
		game.camera = node
	if node is DirectionalLight3D:
		var light: Dictionary = c.light
		node.light_color = color(light.get("color", [1, 1, 1]), true)
		node.light_energy = float(light.get("intensity", 4)) * game.light_scale
		node.shadow_enabled = light.get("shadows", true)
		node.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(light.get("numShadowCascades", 4)) > 1 else DirectionalLight3D.SHADOW_ORTHOGONAL
		node.directional_shadow_max_distance = float(light.get("range", 200))
		node.shadow_bias = 0.03
		node.look_at_from_position(Vector3.ZERO, v3(light.get("direction", [-0.31, -0.8, -0.52])), Vector3.UP)
	if node is AudioStreamPlayer:
		var sound: Dictionary = c.sound
		node.stream = load("res://assets/" + sound.filename)
		node.volume_db = linear_to_db(float(sound.get("volume", 1)))
		if sound.get("looping", false) and node.stream is AudioStreamOggVorbis:
			node.stream = node.stream.duplicate()
			node.stream.loop = true
		if sound.get("state", "stopped") == "playing":
			node.play()
		game.sounds[node.name] = node
	for script_data in script_entries:
		var entry = {"node": node, "class": script_data.get("className", ""), "properties": properties(script_data), "scope": scope}
		scope.scripts.append(entry)
		node.set_meta("behavior", entry)
		if node is Area3D:
			node.body_entered.connect(game.on_sensor.bind(node))
	if c.has("bundle"):
		var name_in_bundle: String = c.bundle.path.get_file().get_basename()
		var data: Dictionary = source.bundles[name_in_bundle]
		var members: Array = data.get("members", []) if data.get("type", "") == "EntityBundle" else [data]
		var instance = build_scope(members, node, name_in_bundle, false)
		game.world_scopes.append(instance)
	for child in entity.get("children", []):
		build_entity(child, node, scope)

func make_control(c: Dictionary) -> Control:
	var node: Control
	var ui: Dictionary = c.get("ui", {})
	var image: Dictionary = c.get("image", {})
	var texture_data: Dictionary = ui.get("texture", {}) if ui.get("texture") != null else {}
	var texture_path: String = texture_data.get("path", "")
	if c.has("text"):
		node = Label.new()
		node.text = str(c.text.get("text", ""))
		node.add_theme_font_override("font", load("res://assets/" + c.text.get("font", ["fonts/Sniglet-Regular.ttf"])[0]))
		# FontStash uses ascent-to-descent pixel height; Godot sizes the em square.
		var font_scale = 0.8733624454 if "TitanOne" in c.text.get("font", [""])[0] else 0.8032128514
		node.add_theme_font_size_override("font_size", roundi(float(c.text.get("fontSize", 24)) * font_scale))
		node.add_theme_color_override("font_color", color(ui.get("color", [1, 1, 1, 1]), true))
		node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif c.has("button"):
		node = TextureButton.new()
		node.ignore_texture_size = true
		node.stretch_mode = TextureButton.STRETCH_SCALE
		for state in ["Normal", "Hovered", "Pressed", "Disabled"]:
			var button_texture: Dictionary = c.button.get("texture" + state, {})
			if button_texture.has("path"):
				node.set("texture_" + ("hover" if state == "Hovered" else state.to_lower()), load("res://assets/" + button_texture.path))
		node.mouse_entered.connect(func(): node.create_tween().tween_property(node, "scale", Vector2.ONE * float(c.button.get("scaleHovered", 1.06)), 0.1))
		node.mouse_exited.connect(func(): node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.1))
		node.pressed.connect(func():
			var behavior = node.get_meta("behavior", {})
			var p: Dictionary = behavior.get("properties", {})
			game.menu_action(str(p.get("action", "")), str(p.get("targetScene", "Level One")))
		)
	elif texture_path != "":
		if int(image.get("patchMarginLeft", 0)) > 0:
			node = NinePatchRect.new()
			node.texture = load("res://assets/" + texture_path)
			for side in ["left", "right", "top", "bottom"]:
				node.set("patch_margin_" + side, int(image.get("patchMargin" + side.capitalize(), 0)))
		else:
			node = TextureRect.new()
			node.texture = load("res://assets/" + texture_path)
			node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			node.stretch_mode = TextureRect.STRETCH_SCALE
		node.modulate = color(ui.get("color", [1, 1, 1, 1]), true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif c.has("ui"):
		node = ColorRect.new()
		node.color = color(ui.get("color", [0, 0, 0, 0]), true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		node = Control.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func add_shapes(node: Node, body: Dictionary):
	for data in body.get("shapes", []):
		var collision = CollisionShape3D.new()
		var shape: Shape3D
		match str(data.get("type", "box")):
			"sphere":
				shape = SphereShape3D.new()
				shape.radius = float(data.get("radius", 0.5))
			"capsule":
				shape = CapsuleShape3D.new()
				shape.radius = float(data.get("radius", 0.28))
				shape.height = 2.0 * (shape.radius + float(data.get("halfHeight", 0.18)))
			_:
				shape = BoxShape3D.new()
				shape.size = Vector3(float(data.get("width", 1)), float(data.get("height", 1)), float(data.get("depth", 1)))
		collision.shape = shape
		collision.position = v3(data.get("position", [0, 0, 0]))
		collision.quaternion = quat(data.get("rotation", [1, 0, 0, 0]))
		node.add_child(collision)

func configure_meshes(root: Node, settings: Dictionary):
	if root is MeshInstance3D:
		root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if settings.get("castShadows", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.visibility_range_end = 0.0
		var submeshes: Array = settings.get("submeshes", []) if settings.get("submeshes") != null else []
		for i in range(mini(submeshes.size(), root.mesh.get_surface_count())):
			var sub: Dictionary = submeshes[i]
			if int(sub.get("overrideFields", 0)) & 1:
				var factor: Array = sub.get("material", {}).get("baseColorFactor", [1, 1, 1, 1])
				var key = str(root.mesh.get_rid()) + ":" + str(i) + ":" + str(factor)
				if not material_cache.has(key):
					var original = root.mesh.surface_get_material(i)
					var material: StandardMaterial3D = original.duplicate() if original is StandardMaterial3D else StandardMaterial3D.new()
					material.albedo_color = color(factor, true)
					material_cache[key] = material
				root.set_surface_override_material(i, material_cache[key])
	for child in root.get_children():
		configure_meshes(child, settings)

func setup_environment(data: Dictionary, scope: Dictionary):
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = color(data.get("scene", {}).get("backgroundColor", [0.67, 0.78, 0.94, 1]))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = color(data.get("scene", {}).get("globalIlluminationColor", [0.95, 0.97, 1]), true)
	environment.ambient_light_energy = float(data.get("scene", {}).get("globalIlluminationIntensity", 0.4))
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	for entity in data.get("entities", []):
		var c: Dictionary = entity.get("components", {})
		if c.has("sky"):
			var sky_texture: Texture2D = load("res://assets/" + c.sky.texture.path)
			var image = sky_texture.get_image()
			if image.is_compressed(): image.decompress()
			var tile: int = image.get_width() / 4
			var faces: Array[Image] = []
			for point in [Vector2i(2, 1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 2), Vector2i(1, 1), Vector2i(3, 1)]:
				var face = image.get_region(Rect2i(point * tile, Vector2i(tile, tile)))
				face.generate_mipmaps()
				faces.append(face)
			var cube = Cubemap.new()
			cube.create_from_images(faces)
			var shader = Shader.new()
			shader.code = "shader_type sky; uniform samplerCube original_sky: source_color, filter_linear_mipmap; void sky(){COLOR=texture(original_sky, EYEDIR).rgb;}"
			var material = ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("original_sky", cube)
			var sky = Sky.new()
			sky.sky_material = material
			environment.sky = sky
			environment.background_mode = Environment.BG_SKY
		if c.has("fog"):
			environment.fog_enabled = true
			environment.fog_mode = Environment.FOG_MODE_DEPTH
			environment.fog_light_color = color(c.fog.color, true)
			environment.fog_depth_begin = float(c.fog.get("linearStart", 16))
			environment.fog_depth_end = float(c.fog.get("linearEnd", 70))
			environment.fog_depth_curve = 1.0
			environment.fog_sky_affect = 0.0
	var world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	scope.root.add_child(world_environment)

static func properties(script_data: Dictionary) -> Dictionary:
	var values = {}
	for property in script_data.get("properties", []):
		values[property.name] = property.get("value")
	return values

static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = find_animation_player(child)
		if result:
			return result
	return null

static func play_model(node: Node, animation_name: String, loop: bool):
	var player: AnimationPlayer = node.get_meta("model_animation", null)
	if not player:
		return
	for key in player.get_animation_list():
		if str(key).get_file().to_lower() == animation_name:
			player.get_animation(key).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			if player.current_animation != key:
				player.play(key, 0.12)
			return

func build_animations(scope: Dictionary):
	var raw = {}
	collect_actions(scope.entities, raw)
	for id in raw:
		var data: Dictionary = raw[id]
		var c: Dictionary = data.components
		var target: Node = scope.ids.get(int(c.action.get("target", 0)))
		if not target or c.has("animation"):
			continue
		var animation = make_animation(c, target, scope.root)
		if not animation:
			continue
		var player = AnimationPlayer.new()
		player.name = str(data.name).validate_node_name() + str(id)
		scope.root.add_child(player)
		var library = AnimationLibrary.new()
		library.add_animation("action", animation)
		player.add_animation_library("", library)
		if target is AnimatableBody3D or target is Area3D:
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		scope.actions[int(id)] = player
		player.speed_scale = float(c.action.get("speed", 1))
		if c.action.get("state", "Stopped") == "Running":
			player.play("action")
			player.seek(randf() * animation.length if c.action.get("randomStart", false) else float(c.action.get("startOffset", 0)), true)
	for id in raw:
		var c: Dictionary = raw[id].components
		if c.has("animation"):
			var children: Array = []
			for action in c.animation.get("actions", []):
				var player = scope.actions.get(int(action.action))
				if player is AnimationPlayer:
					children.append(player)
			if not children.is_empty():
				scope.actions[int(id)] = children
				if c.action.get("state", "Stopped") == "Running":
					for child in children:
						if c.animation.get("loop", false): child.get_animation("action").loop_mode = Animation.LOOP_LINEAR
						child.play("action")

func collect_actions(entities: Array, result: Dictionary):
	for entity in entities:
		if entity.get("components", {}).has("action"):
			result[int(entity.entity)] = entity
		collect_actions(entity.get("children", []), result)

func make_animation(c: Dictionary, target: Node, root: Node) -> Animation:
	var animation = Animation.new()
	var path = str(root.get_path_to(target))
	var timed: Dictionary = c.get("timedaction", {})
	var keyframes: Dictionary = c.get("keyframetracks", {})
	var duration: float = float(timed.get("duration", 0.0))
	var times: Array = keyframes.get("times", [])
	var ping_pong: bool = timed.get("pingPong", false)
	if not times.is_empty():
		duration = float(times[-1])
	if duration <= 0:
		return null
	animation.length = duration * (2 if ping_pong else 1)
	animation.loop_mode = Animation.LOOP_LINEAR if timed.get("loop", keyframes.get("loop", false)) else Animation.LOOP_NONE
	for component in ["positionaction", "rotationaction", "scaleaction", "alphaaction", "coloraction", "translatetracks", "rotatetracks", "scaletracks"]:
		if not c.has(component):
			continue
		var property_name: String = "position"
		if "rotat" in component:
			property_name = "quaternion"
		elif "scale" in component:
			property_name = "scale"
		elif component == "alphaaction":
			if not target is CanvasItem: continue
			property_name = "modulate:a"
		elif component == "coloraction":
			# Color changes target imported mesh material copies.
			continue
		var track = animation.add_track(Animation.TYPE_VALUE)
		var target_property = "rotation" if target is Control and property_name == "quaternion" else property_name
		animation.track_set_path(track, NodePath(path + ":" + target_property))
		var settings: Dictionary = c[component]
		if component.ends_with("tracks"):
			for i in range(times.size()):
				var value: Variant = quat(settings["values"][i]) if property_name == "quaternion" else v3(settings["values"][i])
				if target is Control:
					value = value.get_euler().z if value is Quaternion else Vector2(value.x, value.y)
				animation.track_insert_key(track, float(times[i]), value)
		else:
			var steps = maxi(2, int(animation.length * 30))
			for i in range(steps + 1):
				var time = animation.length * float(i) / steps
				var ratio = time / duration
				if ping_pong and ratio > 1: ratio = 2 - ratio
				ratio = easing(ratio, str(timed.get("function", "LINEAR")))
				var value: Variant
				if property_name == "position":
					var a = v3(settings.startPosition)
					var b = v3(settings.endPosition)
					value = a.lerp(b, ratio)
				elif property_name == "quaternion":
					value = quat(settings.startRotation) * Quaternion(v3(settings.axis).normalized(), deg_to_rad(float(settings.angle)) * ratio) if settings.get("spin", false) else quat(settings.startRotation).slerp(quat(settings.endRotation), ratio)
				elif property_name == "scale":
					value = v3(settings.startScale).lerp(v3(settings.endScale), ratio)
				else:
					value = lerpf(float(settings.startAlpha), float(settings.endAlpha), ratio)
				if target is Control and value is Vector3: value = Vector2(value.x, value.y)
				if target is Control and value is Quaternion: value = value.get_euler().z
				animation.track_insert_key(track, time, value)
	return animation if animation.get_track_count() > 0 else null

static func easing(t: float, function: String) -> float:
	match function:
		"SINE_IN_OUT": return -(cos(PI * t) - 1.0) / 2.0
		"SINE_OUT": return sin(t * PI / 2.0)
		"QUAD_OUT": return 1.0 - (1.0 - t) * (1.0 - t)
		"QUAD_IN_OUT": return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2) / 2.0
	return t

static func start_action(scope: Dictionary, id: int):
	var action = scope.actions.get(id)
	if action is Array:
		for child in action:
			child.stop()
			child.play("action")
	elif action is AnimationPlayer:
		action.stop()
		action.play("action")
