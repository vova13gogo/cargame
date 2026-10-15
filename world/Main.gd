## Main.gd - Scene root for Stage 1. Wires everything together in code so the
## .tscn file stays tiny (just this script on a Node3D). Responsibilities:
##  - create WorldEnvironment + DirectionalLight3D and hand them to DayNight
##  - spawn the streamed world, the player (on safe land) and the HUD
extends Node3D

@export var start_in_plains: bool = true    ## false = random surface spot


func _ready() -> void:
	# --- environment ----------------------------------------------------------
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	add_child(we)

	# --- sun -------------------------------------------------------------------
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = false          # flat style: no realistic shadows
	add_child(sun)

	DayNightManager.world_env = we
	DayNightManager.sun_light = sun

	# --- world -----------------------------------------------------------------
	var world := WorldManager.new()
	world.name = "World"
	add_child(world)

	# --- player ------------------------------------------------------------------
	var player := _make_player()
	add_child(player)
	player.global_position = _find_spawn_point()

	# --- UI ------------------------------------------------------------------------
	var hud := HUD.new()
	hud.name = "HUD"
	add_child(hud)


## Deterministic-ish spawn: prefer plains center, fall back to any dry cell.
func _find_spawn_point() -> Vector3:
	if start_in_plains:
		var p := Terrain.norm_to_world_pos(0.25, 0.67)   # middle of plains rect
		# Nudge until we find dry, gentle ground around the plains center.
		for r in range(0, 40):
			for i in range(8):
				var ang := i * TAU / 8.0
				var x := p.x + cos(ang) * r * 2.0
				var z := p.z + sin(ang) * r * 2.0
				var h := Terrain.get_height(x, z)
				if h > GameState.water_level + 1.5 and Terrain.get_normal(x, z).y > 0.9:
					return Vector3(x, h + 2.0, z)
		return Vector3(p.x, Terrain.get_height(p.x, p.z) + 2.0, p.z)
	# Random surface point.
	var rng := GameState.make_rng(99)
	for attempt in 200:
		var x := rng.randf_range(-190, 190)
		var z := rng.randf_range(-190, 190)
		var h := Terrain.get_height(x, z)
		if h > GameState.water_level + 1.0:
			return Vector3(x, h + 2.0, z)
	return Vector3(0, 20, 0)


## Build the player scene entirely in code: CharacterBody3D + capsule collider
## + camera pivot. No Player.tscn needed, nothing can go missing.
func _make_player() -> Player:
	var p := Player.new()
	p.name = "Player"

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 2.0
	shape.shape = cap
	p.add_child(shape)

	var visual := Node3D.new()
	visual.name = "BodyVisual"
	p.add_child(visual)

	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	pivot.position = Vector3(0, 1.4, 0)
	p.add_child(pivot)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 1.6, 5.2)     # third-person orbit distance
	cam.fov = 70.0
	cam.far = 800.0
	cam.current = true
	pivot.add_child(cam)
	return p
