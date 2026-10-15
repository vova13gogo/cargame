## Player.gd - Third-person character controller (Stage 1)
##
## CharacterBody3D with WASD movement, mouse-look camera, jump and sprint.
## Ground following uses the shared Terrain sampler (analytic height) instead
## of physics raycasts: this is cheaper, deterministic and works even before
## chunk collision exists. Physics collision still keeps us out of props.
##
## The visual body is built entirely from primitives in code (bean body, dot
## eyes) so no asset files are needed.
class_name Player
extends CharacterBody3D

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 9.5
@export var jump_velocity: float = 7.0
@export var gravity_scale: float = 1.8          # snappy arcade gravity
@export var mouse_sensitivity: float = 0.0025
@export var swim_bob: float = 0.4               # how deep we sit in water

var health: float = 100.0                        # used by Stage 2+ systems
var _cam_pivot_y: float = 1.6                    # camera target height on body
var _grounded: bool = false                      # analytic terrain contact flag


@onready var cam_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var body_visual: Node3D = $BodyVisual


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_avatar()


## Mouse look: yaw rotates the whole body, pitch rotates the camera pivot.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		cam_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		cam_pivot.rotation.x = clampf(cam_pivot.rotation.x, -1.2, 0.7)
	if event.is_action_pressed("toggle_camera"):
		toggle_camera_view()


var _first_person := false
func toggle_camera_view() -> void:
	_first_person = not _first_person
	camera.position = Vector3(0, 0.1, 0.1) if _first_person else Vector3(0, 1.6, 5.2)


func _physics_process(delta: float) -> void:
	# --- input direction relative to camera yaw -----------------------------
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir.length_squared() > 0.01:
		# Face the movement direction when walking (classic over-the-shoulder
		# feel); mouse still controls the camera freely.
		var want := atan2(input_dir.x, input_dir.y) + rotation.y
		rotation.y = lerp_angle(rotation.y, want, minf(1.0, 14.0 * delta))
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# --- horizontal movement --------------------------------------------------
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target := dir * speed
	# Acceleration feel: quick start, quick stop (arcade).
	velocity.x = lerp(velocity.x, target.x, 12.0 * delta)
	velocity.z = lerp(velocity.z, target.z, 12.0 * delta)

	# --- jump -----------------------------------------------------------------
	# Grounded is decided by the analytic check below, so cache it first frame.
	if Input.is_action_just_pressed("jump") and _grounded:
		velocity.y = jump_velocity

	# --- analytic terrain follow ---------------------------------------------
	# The ground is a pure height function, so instead of trusting trimesh
	# collision (which only exists for loaded chunks) we resolve the vertical
	# position ourselves: below ground => stand; above ground => free fall.
	var h := Terrain.get_height(global_position.x, global_position.z)
	var feet_y := global_position.y - 1.0        # capsule origin is center
	_grounded = false
	if feet_y <= h + 0.05:
		global_position.y = h + 1.0              # put feet exactly on terrain
		velocity.y = 0.0
		_grounded = true
	else:
		velocity.y -= 9.8 * gravity_scale * delta
		if velocity.y < -40.0:
			velocity.y = -40.0                   # terminal velocity
	move_and_slide()

	# --- shallow-water slow-down ----------------------------------------------
	if global_position.y < GameState.water_level:
		velocity.x *= 0.85
		velocity.z *= 0.85
		velocity.y = maxf(velocity.y, -1.5)     # buoyancy-ish float

	_animate_walk(delta, input_dir.length())


# ---------------------------------------------------------------------------
# Procedural flat-style avatar: bean body, dot eyes, tiny propeller hat.
# Built once in code; no scenes or textures required.
# ---------------------------------------------------------------------------
func _build_avatar() -> void:
	var skin := Color(1.0, 0.85, 0.70)
	var shirt := Color(0.98, 0.45, 0.25)      # cheerful orange mechanic shirt
	var pants := Color(0.25, 0.35, 0.60)

	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.35
	torso_mesh.height = 0.95
	var torso := MeshInstance3D.new()
	torso.mesh = torso_mesh
	torso.material_override = FlatStyle.mat(shirt)
	torso.position = Vector3(0, 0.15, 0)
	body_visual.add_child(torso)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.32
	head_mesh.height = 0.62
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = FlatStyle.mat(skin)
	head.position = Vector3(0, 0.85, 0)
	body_visual.add_child(head)

	# Dot eyes (two tiny black spheres) - Dumb-Ways style, no faces beyond that.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.045
	eye_mesh.height = 0.09
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = FlatStyle.mat(Color(0.1, 0.1, 0.12))
		eye.position = Vector3(0.11 * side, 0.9, -0.28)
		body_visual.add_child(eye)

	# Legs: two short capsules.
	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = 0.12
	leg_mesh.height = 0.5
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.mesh = leg_mesh
		leg.material_override = FlatStyle.mat(pants)
		leg.position = Vector3(0.16 * side, -0.62, 0)
		body_visual.add_child(leg)

	# Arms: thin capsules attached to shoulders.
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.09
	arm_mesh.height = 0.55
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.name = "ArmL" if side < 0 else "ArmR"
		arm.mesh = arm_mesh
		arm.material_override = FlatStyle.mat(shirt.darkened(0.1))
		arm.position = Vector3(0.42 * side, 0.25, 0)
		body_visual.add_child(arm)

	# Tiny wrench on the back - hints the player is a mechanic.
	var wrench_handle := BoxMesh.new()
	wrench_handle.size = Vector3(0.07, 0.5, 0.07)
	var wh := MeshInstance3D.new()
	wh.mesh = wrench_handle
	wh.material_override = FlatStyle.mat(Color(0.55, 0.58, 0.62))
	wh.position = Vector3(0.2, 0.3, 0.3)
	wh.rotation_degrees = Vector3(0, 0, 25)
	body_visual.add_child(wh)


## Simple procedural limb swing while moving (no animation files needed).
func _animate_walk(delta: float, move_amount: float) -> void:
	var legs := [body_visual.get_node_or_null("LegL"), body_visual.get_node_or_null("LegR")]
	var arms := [body_visual.get_node_or_null("ArmL"), body_visual.get_node_or_null("ArmR")]
	if legs[0] == null:
		return
	_walk_phase += delta * (6.0 if move_amount > 0.1 else 1.5)
	var swing := sin(_walk_phase * 4.0) * minf(move_amount, 1.0) * 0.6
	legs[0].rotation.x = swing
	legs[1].rotation.x = -swing
	arms[0].rotation.x = -swing * 0.7
	arms[1].rotation.x = swing * 0.7
	# Gentle idle bob.
	body_visual.position.y = 0.0 + absf(sin(_walk_phase * 4.0)) * 0.05 * move_amount


var _walk_phase: float = 0.0
