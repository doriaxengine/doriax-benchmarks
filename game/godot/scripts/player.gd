extends RigidBody3D

var game: Node
var parameters: Dictionary = {}
var yaw = -90.0
var pitch = -22.0
var camera_focus = Vector3.ZERO
var focus_valid = false
var grounded = false
var was_grounded = false
var ground_velocity = Vector3.ZERO
var coyote = 0.0
var jump_buffer = 0.0
var jump_held = false
var jump_cut_pending = false
var hurt_timer = 1.0
var blink_timer = 0.0
var dead = false
var stomp_pending = false
var fall_speed = 0.0
var pending_respawn: Variant = null
var desired_velocity = Vector3.ZERO
var facing = Quaternion.IDENTITY

func _ready():
	yaw = float(parameters.get("cameraYaw", -90))
	pitch = float(parameters.get("cameraPitch", -22))
	facing = quaternion
	desired_velocity = linear_velocity

func _integrate_forces(state: PhysicsDirectBodyState3D):
	if pending_respawn != null:
		var destination: Vector3 = pending_respawn
		state.transform = Transform3D(Basis.IDENTITY, destination)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		pending_respawn = null
		desired_velocity = Vector3.ZERO
		return
	grounded = false
	ground_velocity = Vector3.ZERO
	for i in range(state.get_contact_count()):
		var normal = state.get_contact_local_normal(i)
		var other_velocity = state.get_contact_collider_velocity_at_position(i)
		if normal.y >= 0.64 and (state.linear_velocity - other_velocity).dot(normal) <= 1.0:
			grounded = true
			coyote = float(parameters.get("coyoteTime", 0.12))
			ground_velocity = other_velocity
	state.angular_velocity = Vector3.ZERO
	var transform_value = state.transform
	transform_value.basis = Basis(facing)
	state.transform = transform_value
	var velocity_value = state.linear_velocity
	velocity_value.x = desired_velocity.x
	velocity_value.z = desired_velocity.z
	if dead:
		state.linear_velocity = Vector3.ZERO
		return
	state.linear_velocity = velocity_value

func update_movement(dt: float):
	if game.paused or game.loading:
		return
	hurt_timer = maxf(0, hurt_timer - dt)
	if blink_timer > 0:
		blink_timer -= dt
		var model = get_node_or_null("Model")
		if model:
			model.visible = blink_timer <= 0 or fmod(blink_timer, 0.2) > 0.1
	if dead:
		gravity_scale = 0
		game.builder.play_model(self, "die", false)
		return
	var heading = Basis(Vector3.UP, deg_to_rad(yaw))
	var movement = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): movement.y += 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): movement.y -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): movement.x += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): movement.x -= 1
	var sprinting = Input.is_physical_key_pressed(KEY_SHIFT)
	var jump_pressed = Input.is_physical_key_pressed(KEY_SPACE) or game.touch_jump
	movement += game.touch_move
	sprinting = sprinting or game.touch_move.length() > 0.9
	var pads = Input.get_connected_joypads()
	if not pads.is_empty():
		var pad: int = pads[0]
		var stick = Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), -Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if absf(stick.x) > 0.2: movement.x += stick.x
		if absf(stick.y) > 0.2: movement.y += stick.y
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP): movement.y += 1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN): movement.y -= 1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT): movement.x += 1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT): movement.x -= 1
		sprinting = sprinting or Input.is_joy_button_pressed(pad, JOY_BUTTON_X)
		jump_pressed = jump_pressed or Input.is_joy_button_pressed(pad, JOY_BUTTON_A)
	var direction = (-heading.z * movement.y + heading.x * movement.x).normalized()
	var moving = movement.length() > 0.1
	if not moving: direction = Vector3.ZERO
	if coyote > 0: coyote -= dt
	fall_speed = minf(fall_speed, linear_velocity.y)
	if grounded and not was_grounded and fall_speed < -2:
		game.play_sound("Land Sound")
		game.emit_dust(global_position)
	if grounded: fall_speed = 0
	was_grounded = grounded
	if jump_pressed and not jump_held:
		jump_buffer = float(parameters.get("jumpBuffer", 0.15))
	else:
		jump_buffer = maxf(0, jump_buffer - dt)
	jump_held = jump_pressed
	var velocity_value = linear_velocity
	if stomp_pending:
		stomp_pending = false
		velocity_value.y = 7
		grounded = false
		coyote = 0
		game.emit_dust(global_position)
	if jump_cut_pending and not jump_held:
		jump_cut_pending = false
		if velocity_value.y > 0: velocity_value.y *= float(parameters.get("jumpCut", 0.45))
	var speed: float = float(parameters.get("sprintSpeed", 9.5)) if sprinting and grounded else float(parameters.get("moveSpeed", 6.5))
	var target = direction * speed + ground_velocity
	var acceleration: float = float(parameters.get("acceleration", 18)) * (1.0 if grounded else float(parameters.get("airControl", 0.55)))
	velocity_value.x = lerpf(velocity_value.x, target.x, minf(1, acceleration * dt))
	velocity_value.z = lerpf(velocity_value.z, target.z, minf(1, acceleration * dt))
	if jump_buffer > 0 and coyote > 0:
		velocity_value.y = float(parameters.get("jumpSpeed", 9))
		jump_buffer = 0
		coyote = 0
		jump_cut_pending = true
		if grounded: game.emit_dust(global_position)
		grounded = false
		game.play_sound("Jump Sound")
	desired_velocity = velocity_value
	linear_velocity = velocity_value
	if moving:
		facing = facing.slerp(Quaternion(Vector3.UP, atan2(direction.x, direction.z)), minf(1, float(parameters.get("turnSpeed", 14)) * dt))
	if global_position.y < float(parameters.get("fallDeathY", -12)):
		hurt_timer = 0
		hurt()
	var animation = "idle"
	if not grounded:
		animation = "jump" if linear_velocity.y > 0.5 else "fall"
	elif moving:
		animation = "sprint" if sprinting else "walk"
	game.builder.play_model(self, animation, animation in ["idle", "walk", "sprint"])

func _process(dt: float):
	if game.paused or game.loading:
		return
	# Match the original PlayerController::onUpdate cadence. Contacts and gravity
	# still use the engine's fixed physics steps; input/blending/camera run per frame.
	update_movement(dt)
	var pads = Input.get_connected_joypads()
	if not pads.is_empty():
		var look = Vector2(Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X), Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_Y))
		if absf(look.x) > 0.2: yaw -= look.x * 130 * dt
		if absf(look.y) > 0.2: pitch += look.y * 130 * dt
	if Input.is_physical_key_pressed(KEY_Q): yaw += 90 * dt
	if Input.is_physical_key_pressed(KEY_E): yaw -= 90 * dt
	pitch = clampf(pitch, -70, 5)
	if not focus_valid:
		camera_focus = global_position
		focus_valid = true
	else:
		camera_focus = camera_focus.lerp(global_position, 1 - exp(-float(parameters.get("cameraLag", 7)) * dt))
	if game.camera:
		var camera_rotation = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0), EULER_ORDER_YXZ)
		var target = camera_focus + Vector3(0, float(parameters.get("lookHeight", 1)), 0)
		game.camera.global_position = target + camera_rotation.z * float(parameters.get("cameraDistance", 9))
		game.camera.look_at(target, Vector3.UP)

func look_by(delta: Vector2):
	yaw -= delta.x * float(parameters.get("mouseSensitivity", 0.25))
	pitch -= delta.y * float(parameters.get("mouseSensitivity", 0.25))
	pitch = clampf(pitch, -70, 5)

func hurt():
	if dead or hurt_timer > 0 or game.finished:
		return
	hurt_timer = 1
	blink_timer = 1.2
	game.play_sound("Hurt Sound")
	game.lives -= 1
	if game.lives <= 0:
		dead = true
		game.finish_level(false)
	else:
		respawn(game.checkpoint if game.has_checkpoint else game.spawn)

func respawn(destination: Vector3):
	pending_respawn = destination
	dead = false
	gravity_scale = 1
	coyote = 0
	jump_buffer = 0
	grounded = false
	hurt_timer = 1
	focus_valid = false
